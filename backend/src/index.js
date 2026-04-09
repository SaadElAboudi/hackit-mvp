// import { deleteLesson } from "./utils/persistence.js";
// Deprecated persistence import removed. Use Mongoose models instead.
import { randomBytes } from 'crypto';

import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import mongoose from 'mongoose';
import morgan from 'morgan';

import { getFeatureFlags } from './config/featureFlags.js';
import lessonsRouter from './routes/lessons.js';
import projectsRouter from './routes/projects.js';
import { attachWebSocketServer } from './services/threadRooms.js';
import { validateFeedbackPayload, validateSearchPayload, validateTtvPayload } from './middleware/validation.js';
import { getChapters, extractDesiredChapters } from './services/chapters.js';
import { getTranscript } from './services/transcript.js';
import { searchYouTube as originalSearchYouTube } from './services/youtube.js';
import { buildObservabilitySnapshot, evaluateAlerts, observeExternal, observeHttp, observeQualityEvent, observeTtvEvent } from './utils/observability.js';
import { userIdMiddleware } from './utils/userIdMiddleware.js';

// Avoid importing yt-search at module load on Node<20 to prevent undici File init crash
const dynamicImport = (moduleName) => Function('m', 'return import(m)')(moduleName);

dotenv.config({ quiet: true });

const featureFlags = getFeatureFlags();



const app = express();
// CORS middleware at the very top
// Restrict CORS in production, allow all in dev
app.use(cors({
  origin: process.env.NODE_ENV === 'production'
    ? [process.env.FRONTEND_ORIGIN || 'https://yourfrontend.com']
    : true,
  credentials: true
}));
app.use(express.json({ limit: process.env.JSON_BODY_LIMIT || '1mb' }));
app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on('finish', () => {
    const resolvedPath = req.route?.path ? `${req.baseUrl || ''}${req.route.path}` : req.path;
    const routeKey = `${req.method} ${resolvedPath}`;
    observeHttp({ key: routeKey, durationMs: Date.now() - startedAt, statusCode: res.statusCode });
  });
  next();
});
// Rate limiter with Redis support (distributed) and in-memory fallback
const rateLimit = {};
const REDIS_URL = process.env.REDIS_URL;
let redisClient = null;
let redisReady = false;

async function initRedisRateLimiter() {
  if (!REDIS_URL || process.env.NODE_ENV === 'test' || redisReady || redisClient) return;
  try {
    const { createClient } = await dynamicImport('redis');
    redisClient = createClient({ url: REDIS_URL });
    redisClient.on('error', (err) => {
      redisReady = false;
      console.warn('Redis rate limiter unavailable:', err?.message || err);
    });
    await redisClient.connect();
    redisReady = true;
  } catch (err) {
    redisClient = null;
    redisReady = false;
    if (process.env.NODE_ENV !== 'test') {
      console.warn('Redis rate limiter disabled, fallback to memory:', err?.message || err);
    }
  }
}

await initRedisRateLimiter();

async function simpleRateLimit(key, maxPerMinute = 30) {
  if (redisReady && redisClient) {
    try {
      const bucket = Math.floor(Date.now() / 60000);
      const redisKey = `ratelimit:${key}:${bucket}`;
      const current = await redisClient.incr(redisKey);
      if (current === 1) {
        await redisClient.expire(redisKey, 60);
      }
      return current <= maxPerMinute;
    } catch (err) {
      redisReady = false;
      console.warn('Redis rate limiting failed, using memory fallback:', err?.message || err);
    }
  }

  const now = Date.now();
  if (!rateLimit[key]) rateLimit[key] = [];
  rateLimit[key] = rateLimit[key].filter((ts) => now - ts < 60000);
  if (rateLimit[key].length >= maxPerMinute) return false;
  rateLimit[key].push(now);
  return true;
}
// Enable concise logging in all non-test environments
if (process.env.NODE_ENV && process.env.NODE_ENV !== "test") {
  app.use(morgan("dev"));
}
app.get('/api/me', (req, res) => {
  return res.json({
    ok: true,
    auth: 'disabled',
    user: {
      id: req.headers['x-user-id'] || 'anonymous',
      isAnonymous: true,
    },
  });
});

function buildGuestAuthSuccessUrl(req) {
  const frontendOrigin = (process.env.FRONTEND_ORIGIN || '').trim().replace(/\/$/, '');
  const fallbackOrigin = `${req.protocol}://${req.get('host')}`;
  const base = frontendOrigin || fallbackOrigin;
  const userId = randomBytes(8).toString('hex');
  return `${base}/auth-success?userId=${userId}&mode=guest`;
}

// Compatibility endpoints: legacy login buttons may still call Google OAuth routes.
// The app currently runs in no-auth mode, so we redirect to guest success instead.
app.get('/auth/google/status', (_req, res) => {
  return res.json({
    enabled: false,
    mode: 'guest-only',
    reason: 'Authentication is disabled in this deployment',
  });
});

app.get('/auth/google', (req, res) => {
  return res.redirect(302, buildGuestAuthSuccessUrl(req));
});

app.get('/auth/google/callback', (req, res) => {
  return res.redirect(302, buildGuestAuthSuccessUrl(req));
});

app.get('/api/feature-flags', (_req, res) => {
  return res.json({ ok: true, flags: featureFlags });
});

const USE_GEMINI_ENV = (process.env.USE_GEMINI || "false") === "true";
const USE_GEMINI_REFORMULATION = (process.env.USE_GEMINI_REFORMULATION || "false") === "true";
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "models/gemini-2.0-flash-lite";
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "20000");
let GEMINI_OPERATIONAL = true; // set to false after first hard failure
// Circuit breaker state for Gemini
const FAILURE_WINDOW_MS = Number(process.env.GEMINI_FAILURE_WINDOW_MS || '120000'); // 2 minutes
const BREAKER_OPEN_MS = Number(process.env.GEMINI_BREAKER_OPEN_MS || '300000'); // 5 minutes
let GEMINI_FAILURE_TIMESTAMPS = []; // array of ms since epoch
let GEMINI_BREAKER_UNTIL = 0; // timestamp ms when breaker closes
const START_TIME = Date.now();
const APP_VERSION = process.env.APP_VERSION || process.env.npm_package_version || '1.0.0';
const MAX_QUERY_LEN = Number(process.env.MAX_QUERY_LEN || 500);
const MAX_STREAM_QUERY_LEN = Number(process.env.MAX_STREAM_QUERY_LEN || 500);
const TAVILY_API_KEY = process.env.TAVILY_API_KEY || '';

function makeMockResponse() {
  return {
    title: "Mock: Comment structurer un plan de projet efficace",
    steps: [
      "Définir l'objectif SMART et les critères de succès du projet.",
      "Identifier les parties prenantes et clarifier leurs rôles.",
      "Décomposer le projet en phases, jalons et livrables clés.",
      "Estimer la charge, allouer les ressources et identifier les dépendances.",
      "Mettre en place un suivi régulier avec des points de décision clairs.",
    ],
    videoUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    source: "mock"
  };
}

/**
 * Fetches up to 3 web snippets from Tavily for a given query.
 * Returns [] gracefully if TAVILY_API_KEY is not set or the call fails.
 */
async function fetchWebSnippets(query) {
  if (!TAVILY_API_KEY) return [];
  try {
    const resp = await axios.post(
      'https://api.tavily.com/search',
      {
        api_key: TAVILY_API_KEY,
        query: String(query).slice(0, 200),
        search_depth: 'basic',
        max_results: 3,
        include_answer: false,
        include_raw_content: false,
      },
      { timeout: 3000 }
    );
    const results = resp.data?.results || [];
    return results
      .map(r => `${r.title}: ${r.snippet || String(r.content || '').slice(0, 200)}`)
      .filter(Boolean)
      .slice(0, 3);
  } catch (err) {
    console.warn('[Tavily] web search failed:', err.message);
    return [];
  }
}

function heuristicSummary({ desiredSteps, mode, query } = {}) {
  // Mode-aware local summary when Gemini is disabled/unavailable — personalised with query topic
  const topic = extractTopicFromQuery(query);
  const T = topic ? `"${topic}"` : 'ce sujet';
  const bases = {
    cadrer: [
      `Analyser le brief ${T} et identifier les zones d'ambiguïté prioritaires.`,
      `Formaliser les livrables attendus, les critères de succès et les contraintes pour ${T}.`,
      `Aligner les parties prenantes sur le périmètre et les responsabilités autour de ${T}.`,
      `Documenter les hypothèses, risques et dépendances clés liés à ${T}.`,
      `Valider le cadrage avec le client et déclencher la production de ${T}.`,
    ],
    communiquer: [
      `Clarifier le message central à délivrer sur ${T} et définir l'audience cible.`,
      `Structurer le contenu en : contexte, valeur ajoutée et call to action pour ${T}.`,
      `Sélectionner le canal et le timing optimaux pour maximiser l'impact de ${T}.`,
      `Rédiger, faire relire et valider le message avant diffusion.`,
      `Diffuser, mesurer les retours et planifier le suivi de ${T}.`,
    ],
    audit: [
      `Inventorier les artéfacts et critères d'évaluation disponibles pour ${T}.`,
      `Diagnostiquer les écarts critiques entre l'état actuel et les objectifs de ${T}.`,
      `Trier les problèmes par criticité : bloquant / à corriger / à surveiller.`,
      `Traiter les quick wins à fort impact pour ${T} en priorité.`,
      `Rédiger la synthèse d'audit avec un plan d'action priorisé.`,
    ],
    produire: [
      `Valider le périmètre et les spécifications de ${T} avant de démarrer.`,
      `Décomposer ${T} en tâches unitaires avec priorité et dépendances claires.`,
      `Exécuter les tâches critiques de ${T} en commençant par les bloquantes.`,
      `Conduire une revue qualité et corriger les écarts avant livraison.`,
      `Livrer ${T}, recueillir le feedback client et documenter les apprentissages.`,
    ],
  };
  const base = bases[mode] || bases.produire;
  const extras = [
    `Documenter les décisions prises sur ${T} pour faciliter le suivi.`,
    "Anticiper les risques résiduels et préparer un plan B.",
    "Planifier la prochaine itération en tenant compte des retours.",
    "Partager les apprentissages avec l'équipe pour améliorer le processus.",
  ];
  if (Number.isInteger(desiredSteps) && desiredSteps > 0) {
    if (desiredSteps <= base.length) {
      return base.slice(0, desiredSteps).join("\n");
    }
    const out = base.slice();
    let i = 0;
    while (out.length < desiredSteps) {
      out.push(extras[i % extras.length]);
      i++;
    }
    return out.join("\n");
  }
  return base.join("\n");
}

function getSummaryConfig(summaryLength = 'standard') {
  switch (summaryLength) {
    case 'tldr':
      return { stepsTarget: 3 };
    case 'deep':
      return { stepsTarget: 8 };
    default:
      return { stepsTarget: 5 };
  }
}

function detectDeliveryModeFromQuery(query) {
  const q = String(query || '').toLowerCase();
  // Explicit mode override (backward-compatible)
  if (/\bmode[\s:]+cadrer\b/.test(q)) return 'cadrer';
  if (/\bmode[\s:]+produire\b/.test(q)) return 'produire';
  if (/\bmode[\s:]+communiquer\b/.test(q)) return 'communiquer';
  if (/\bmode[\s:]+audit\b/.test(q)) return 'audit';
  // Semantic signals — order: most specific first
  if (/audit|diagnostic|revue|r[ée]vision|v[ée]rification|analyser|contr[ôo]le|bilan/.test(q)) return 'audit';
  if (/pr[ée]senter|pr[ée]sentation|reporting|compte.?rendu|\bcr\b|pitch|email|communiquer|communication|message|annoncer/.test(q)) return 'communiquer';
  if (/cadrer|cadrage|\bbrief\b|p[eé]rim[eè]tre|scope|d[eé]finir|clarifier|\bcontexte\b/.test(q)) return 'cadrer';
  return 'produire';
}

function normalizeDeliveryContext(raw = {}) {
  const normalize = (v) => {
    const s = String(v ?? '').trim();
    return s ? s.slice(0, 80) : null;
  };
  return {
    clientType: normalize(raw.clientType),
    budget: normalize(raw.budget),
    deadline: normalize(raw.deadline),
    maturity: normalize(raw.maturity),
    strategyKey: normalize(raw.strategyKey), // 'rapide' | 'equilibre' | 'ambitieux'
    webSnippets: Array.isArray(raw.webSnippets) ? raw.webSnippets.slice(0, 3) : [],
  };
}

function contextNotes(context = {}) {
  const notes = [];
  if (context.clientType) notes.push(`Type client: ${context.clientType}`);
  if (context.budget) notes.push(`Budget: ${context.budget}`);
  if (context.deadline) notes.push(`Deadline: ${context.deadline}`);
  if (context.maturity) notes.push(`Maturite: ${context.maturity}`);
  return notes;
}

function extractTopicFromQuery(query) {
  return String(query || '')
    .replace(/\bmode[\s:]*(cadrer|produire|communiquer|audit)\b/gi, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 100);
}

function classifyImpactLabel(actionText = '', mode = 'produire') {
  const t = String(actionText || '').toLowerCase();
  if (/bloquant|critique|urgent|risque|incident|deadline|client/.test(t)) return 'élevé';
  if (/validation|revue|qualit|test|mesure|suivi/.test(t)) return 'moyen';
  if (mode === 'audit' && /quick win|correct/.test(t)) return 'élevé';
  return 'moyen';
}

function classifyEffortLabel(actionText = '', mode = 'produire') {
  const t = String(actionText || '').toLowerCase();
  if (/atelier|refonte|migration|impl[eé]ment|stabilisation|structurant/.test(t)) return 'élevé';
  if (/validation|revue|message|compte.?rendu|relance/.test(t)) return 'faible';
  if (mode === 'audit' && /diagnostic/.test(t)) return 'moyen';
  return 'moyen';
}

function actionPriorityScore({ impactLabel, effortLabel }) {
  const impact = impactLabel === 'élevé' ? 3 : impactLabel === 'moyen' ? 2 : 1;
  const effortPenalty = effortLabel === 'élevé' ? 3 : effortLabel === 'moyen' ? 2 : 1;
  return (impact * 30) - (effortPenalty * 12);
}

function buildActionMatrix(nextActions = [], mode = 'produire') {
  const normalized = (Array.isArray(nextActions) ? nextActions : [])
    .map((a) => String(a || '').trim())
    .filter(Boolean);

  const ranked = normalized.map((action) => {
    const impact = classifyImpactLabel(action, mode);
    const effort = classifyEffortLabel(action, mode);
    const score = actionPriorityScore({ impactLabel: impact, effortLabel: effort });
    return { action, impact, effort, score };
  }).sort((a, b) => b.score - a.score);

  return ranked.map((item, index) => (
    `${index + 1}. ${item.action} (impact: ${item.impact}, effort: ${item.effort}, score: ${item.score})`
  ));
}

function buildQualityAssessment({ mode, objective, scope, risks, nextActions, timeline, dependencies, acceptanceCriteria, clientMessage }) {
  const checks = [
    { label: 'Objectif explicite', ok: Array.isArray(objective) && objective.length > 0 },
    { label: 'Périmètre défini', ok: Array.isArray(scope) && scope.length > 0 },
    { label: 'Risques identifiés', ok: Array.isArray(risks) && risks.length > 0 },
    { label: 'Actions concrètes', ok: Array.isArray(nextActions) && nextActions.length >= 2 },
    { label: 'Timeline présente', ok: Array.isArray(timeline) && timeline.length >= 2 },
    { label: 'Dépendances explicites', ok: Array.isArray(dependencies) && dependencies.length > 0 },
    { label: 'Critères d’acceptation', ok: Array.isArray(acceptanceCriteria) && acceptanceCriteria.length >= 2 },
    { label: 'Message client prêt', ok: Array.isArray(clientMessage) && clientMessage.length >= 2 },
  ];

  const passed = checks.filter((c) => c.ok).length;
  const coherenceScore = Math.round((passed / checks.length) * 100);
  const coherenceChecks = checks.filter((c) => c.ok).map((c) => `OK: ${c.label}`);
  const coherenceIssues = checks.filter((c) => !c.ok).map((c) => `À renforcer: ${c.label}`);

  const baseImpactByMode = { cadrer: 68, produire: 76, communiquer: 64, audit: 82 };
  const impactScore = Math.min(
    100,
    (baseImpactByMode[mode] || 72)
    + Math.min((Array.isArray(nextActions) ? nextActions.length : 0), 4) * 4
    + Math.min((Array.isArray(acceptanceCriteria) ? acceptanceCriteria.length : 0), 4) * 3
  );

  const baseEffortByMode = { cadrer: 34, produire: 58, communiquer: 28, audit: 72 };
  const effortScore = Math.min(
    100,
    (baseEffortByMode[mode] || 50) + Math.min((Array.isArray(dependencies) ? dependencies.length : 0), 4) * 4
  );

  const overall = Math.round((impactScore * 0.45) + ((100 - effortScore) * 0.2) + (coherenceScore * 0.35));
  const priorityIndex = Math.round((impactScore * 0.6) - (effortScore * 0.25) + (coherenceScore * 0.2));
  const priority = priorityIndex >= 65 ? 'haute' : priorityIndex >= 45 ? 'moyenne' : 'basse';

  const qualitySummary = [
    `Score global: ${overall}/100`,
    `Impact estimé: ${impactScore}/100`,
    `Effort estimé: ${effortScore}/100`,
    `Cohérence: ${coherenceScore}/100`,
    `Priorité recommandée: ${priority}`,
  ];

  return {
    quality: {
      overall,
      impactScore,
      effortScore,
      coherenceScore,
      priority,
    },
    qualitySummary,
    coherenceChecks,
    coherenceIssues,
  };
}

function buildStrategyVariants({ mode, context }) {
  const ctx = normalizeDeliveryContext(context);
  const hasDeadline = !!(ctx.deadline || ctx.budget);
  const effortFromCtx = (base) => ctx.deadline ? `Pour: ${ctx.deadline}` : base;

  const byMode = {
    cadrer: [
      {
        key: 'rapide', emoji: '⚡', label: 'Cadrage flash',
        description: 'Alignement rapide en 1 réunion, scope minimal, décisions sur hypothèses. Pour débloquer une équipe immédiatement sans attendre une note complète.',
        estimatedGains: ['Équipe débloquée sous 24h', 'Décision prise sans délai', 'Zéro doc superflue'],
        risks: ['Hypothèses non validées', 'Réajustements probables dès J3'],
        effort: effortFromCtx('~4h'),
        recommended: hasDeadline,
      },
      {
        key: 'equilibre', emoji: '⚖️', label: 'Cadrage structuré',
        description: 'Scope MECE, livrables précis, risques tracés, GO/NO-GO formalisé. Le standard consultant pour 80 % des missions de cadrage.',
        estimatedGains: ['Périmètre documenté MECE', 'Risques P0/P1 identifiés', 'GO/NO-GO formalisé'],
        risks: ['1–2 ateliers requis', 'Légèrement plus long'],
        effort: '~1–2j',
        recommended: !hasDeadline,
      },
      {
        key: 'ambitieux', emoji: '🚀', label: 'Cadrage complet',
        description: 'Note exhaustive, hypothèses structurantes validées, grille de décision, alignement C-level. Pour projets stratégiques ou transformations.',
        estimatedGains: ['Documentation réutilisable', 'Alignement C-level', 'Hypothèses validées'],
        risks: ['3–5 jours minimum', ctx.budget ? `Potentiellement hors budget: ${ctx.budget}` : 'Ressources senior requises'],
        effort: '~3–5j',
        recommended: false,
      },
    ],
    produire: [
      {
        key: 'rapide', emoji: '⚡', label: 'MVP 48h',
        description: 'MUST only, zéro perfectionnisme. Premier livrable sous 24h, feedback client dès J+2. Dette technique à planifier après coup.',
        estimatedGains: ['First commit sous 24h', 'Feedback réel dès J+2', 'Coût technique minimal'],
        risks: ['Dette technique à planifier', 'SHOULD non couverts'],
        effort: effortFromCtx('~0.5–1j'),
        recommended: hasDeadline,
      },
      {
        key: 'equilibre', emoji: '⚖️', label: 'Livraison maîtrisée',
        description: 'MUST + SHOULD couverts, tests essentiels inclus, qualité suffisante pour la production. Standard livraison pour satisfaire un client exigeant.',
        estimatedGains: ['Qualité production', 'Tests de base inclus', 'Client satisfait'],
        risks: ['Validation intermédiaire requise'],
        effort: '~1–2j',
        recommended: !hasDeadline,
      },
      {
        key: 'ambitieux', emoji: '🚀', label: 'Livraison complète',
        description: 'Tous MoSCoW couverts, doc exhaustive, critères de done stricts, zéro dette. Livrable production-ready et maintenable à long terme.',
        estimatedGains: ['Zéro dette technique', 'Documentation complète', 'Score qualité > 9/10'],
        risks: ['Délai ×2–3', ctx.budget ? `Potentiellement hors budget: ${ctx.budget}` : 'Risque de surqualité'],
        effort: '~3–5j',
        recommended: false,
      },
    ],
    communiquer: [
      {
        key: 'rapide', emoji: '⚡', label: 'Message direct',
        description: 'Bottom-line en 3 phrases, une seule action demandée. Taux de réponse maximal. Pour décision urgente ou validation rapide dans la journée.',
        estimatedGains: ['Lu en 30 secondes', 'Taux de réponse élevé', 'Décision dès J+1'],
        risks: ['Pas adapté aux sujets complexes', 'Risque de manque de contexte'],
        effort: effortFromCtx('~30 min'),
        recommended: hasDeadline,
      },
      {
        key: 'equilibre', emoji: '⚖️', label: 'Communication structurée',
        description: 'Pyramid Principle complète : conclusion + arguments + faits. Standard pour communications executives, directement envoyable sans retouche.',
        estimatedGains: ['Arguments tracés', 'Compris à tous niveaux', 'Ton professionnel'],
        risks: ['Peut sembler formel dans contextes informels'],
        effort: '~1h',
        recommended: !hasDeadline,
      },
      {
        key: 'ambitieux', emoji: '🚀', label: 'Campagne complète',
        description: 'Email + points de discussion + FAQ anticipée. Multi-audience, tous canaux. Pour sujets critiques ou validation en comité de direction.',
        estimatedGains: ['Tous canaux couverts', 'Multi-audience adapté', 'Objections anticipées'],
        risks: ['Surproduction si urgence simple', ctx.budget ? `Hors budget: ${ctx.budget}` : 'Effort ×3'],
        effort: '~4h–1j',
        recommended: false,
      },
    ],
    audit: [
      {
        key: 'rapide', emoji: '⚡', label: 'Verdict flash',
        description: 'P0 identifiés + 3 quick wins actionnables en 1h. Pour premier diagnostic ou réunion dans 2h qui nécessite des faits précis immédiatement.',
        estimatedGains: ['Priorités claires sous 1h', '3 quick wins immédiats', 'Verdict communicable'],
        risks: ['Causes racines non analysées', 'P1/P2 non couverts'],
        effort: effortFromCtx('~2–4h'),
        recommended: hasDeadline,
      },
      {
        key: 'equilibre', emoji: '⚖️', label: 'Audit structuré 7j',
        description: 'P0/P1/P2 complets, analyse causes racines, plan 7 jours et KPIs de succès. Le livrable standard partageable à un client ou à la direction.',
        estimatedGains: ['Diagnostic exhaustif', "Plan d'action priorisé", 'KPIs de suivi définis'],
        risks: ["2–3 jours d'analyse", 'Données internes requises'],
        effort: '~2–3j',
        recommended: !hasDeadline,
      },
      {
        key: 'ambitieux', emoji: '🚀', label: 'Audit approfondi',
        description: 'Score maturité par axe, benchmarks sectoriels, roadmap 30/60/90j + recommandations stratégiques. Rapport partageable au C-level.',
        estimatedGains: ['Rapport 10+ pages', 'Benchmarks sectoriels', 'Roadmap 90 jours'],
        risks: ['4–5 jours minimum', ctx.budget ? `Hors budget: ${ctx.budget}` : 'Données externes requises'],
        effort: '~4–5j',
        recommended: false,
      },
    ],
  };

  return byMode[mode] || byMode.produire;
}

// Builds a Gemini prompt that generates a COMPLETE professional deliverable (not just 5 bullets).
// The output becomes the readyToSend document directly.
function buildGeminiPromptForMode({ mode, query, context, videoTitle }) {
  const ctx = normalizeDeliveryContext(context);
  const ctxHint = [
    ctx.clientType ? `Client : ${ctx.clientType}` : '',
    ctx.budget    ? `Budget : ${ctx.budget}` : '',
    ctx.deadline  ? `Deadline : ${ctx.deadline}` : '',
    ctx.maturity  ? `Maturité : ${ctx.maturity}` : '',
  ].filter(Boolean).join(' | ');
  const ctxLine = ctxHint ? `\nContexte additionnel : ${ctxHint}` : '';
  const refLine = videoTitle ? `\nRéférence vidéo : "${videoTitle}"` : '';
  const webLine = ctx.webSnippets && ctx.webSnippets.length > 0
    ? `\nSources web récentes :\n${ctx.webSnippets.map((s, i) => `${i + 1}. ${s}`).join('\n')}`
    : '';
  const strategyHint = ctx.strategyKey === 'rapide'
    ? '\nMODE RAPIDE CHOISI : Périmètre minimal, livrable opérationnel en 24–48h. Priorise l\'essentiel absolu, coupe tout ce qui n\'est pas strictement nécessaire.'
    : ctx.strategyKey === 'ambitieux'
    ? '\nMODE AMBITIEUX CHOISI : Périmètre exhaustif, documentation complète, aucun compromis sur le détail. Rends ce livrable réutilisable à long terme et partageable C-level.'
    : '';

  // Core mandate present in all modes: fill every placeholder, be specific, be opinionated.
  const fillRule = `
RÈGLES ABSOLUES (non-négociables) :
1. Remplace CHAQUE placeholder entre crochets par du contenu réel et spécifique déduit du brief. Zéro crochet [...] dans la réponse finale.
2. Si une information est absente du brief, déduis une valeur plausible et professionnelle — ne laisse pas de blanc.
3. Prends position. Un bon consultant ne dit pas "il faudrait peut-être" — il dit "faites X car Y".
4. Sois précis : dates, chiffres, noms de livrables, durées estimées.
5. L'INSIGHT CLÉ doit être non-évident — quelque chose que le client n'aurait pas vu seul.`;

  switch (mode) {

    // ─── COMMUNIQUER — Pyramid Principle + Executive communication ───────────
    case 'communiquer':
      return `Tu es un expert en communication executive, formé à la Pyramid Principle de Barbara Minto, avec 12 ans d'expérience en conseil stratégique.${ctxLine}${refLine}${webLine}${strategyHint}
Brief client : "${query}"
${fillRule}

Rédige un email de communication professionnelle qui applique la Pyramid Principle : conclusion d'abord, arguments ensuite, détails en dernier. Directement envoyable, zéro retouche.

═══════════════════════════════════════════════
OBJET : [objet email — 7 mots max — indique la décision ou l'action attendue, pas juste le sujet]

[STATUT : 🟢 EN BONNE VOIE | 🟡 POINT D'ATTENTION | 🔴 DÉCISION URGENTE — choisis le plus honnête]

Bonjour,

BOTTOM LINE (conclusion en premier — style executive)
[1 phrase maximale, directe : la décision, le résultat ou l'action requise. Ex: "Le projet est prêt à démarrer — je vous demande une validation avant vendredi 17h."]

CE QUE CELA SIGNIFIE POUR VOUS
• [conséquence concrète 1 pour le client — impact business, délai ou risque]
• [conséquence concrète 2 — chiffre ou date si possible]
• [opportunité ou risque si aucune action n'est prise]

FAITS QUI APPUIENT CETTE CONCLUSION
1. [fait 1 — observable, mesurable, déduit du brief]
2. [fait 2 — développement récent ou point technique clé]
3. [fait 3 — s'il est pertinent ; sinon omets-le]

CE QUE J'ATTENDS DE VOUS
→ Action : [une seule action — validation / décision / signature / retour]
→ Pour le : [date précise — déduite du contexte ou estimée de façon réaliste]
→ Format : [email / call 15 min / signature — ce qui est le plus simple pour vous]

PROCHAINE ÉTAPE DE MA PART
Dès réception de votre retour : [action concrète et délai — ex: "je lance X sous 24h"]

INSIGHT CLÉ — CE QUE LA PLUPART RATENT
[1–2 phrases non-évidentes sur ce type de communication. Ex: "Les emails qui obtiennent une réponse posent une seule question, pas plusieurs. En multipliant les demandes, on réduit le taux de réponse de 60%."]

Je reste disponible pour un point de 15 min — [proposition de créneau plausible déduit du contexte].

Cordialement
═══════════════════════════════════════════════
RÈGLES : Pyramid Principle. Bottom line en premier. Une seule action demandée. 28–35 lignes.`;

    // ─── CADRER — MECE decomposition + Answer First (Bain/BCG) ───────────────
    case 'cadrer':
      return `Tu es un principal dans un cabinet de stratégie top-3, expert en cadrage de missions complexes. Tu appliques la décomposition MECE et l'Answer First.${ctxLine}${refLine}${webLine}${strategyHint}
Brief client : "${query}"
${fillRule}

Rédige une note de cadrage de niveau senior, directement transmissible. Commence par l'Answer First — ta lecture enrichie du problème AVANT la décomposition. Ce qui distingue cette note d'un simple template : elle révèle quelque chose que le client n'avait pas formulé.

═══════════════════════════════════════════════
NOTE DE CADRAGE — [TITRE EN MAJUSCULES — PRÉCIS, ≤ 9 MOTS, DÉRIVÉ DU BRIEF]

DIAGNOSTIC — CE QUE CE BRIEF RÉVÈLE VRAIMENT
[2–3 lignes. Quel est le vrai enjeu derrière le brief littéral ? Qu'est-ce qui crée la pression sur ce projet ? Ex: "En surface, le client veut X. En réalité, le risque est Y car Z. Si ce n'est pas traité dans les prochaines semaines, le coût sera D fois plus élevé."]

ANSWER FIRST — MA RECOMMANDATION
[Ta position claire. Commence par "Je recommande de..." ou "Le vrai levier ici est...". Pas de conditionnel. Opinioné et justifié en 1–2 phrases.]

OBJECTIF SMART
• Résultat attendu : [quoi exactement — livrable ou décision, pas un processus]
• Mesure de succès : [KPI concret ou critère binaire observable]
• Délai réaliste : [estimation basée sur la complexité du brief]
• Validé par : [qui prend la décision finale]

PÉRIMÈTRE (MECE — exhaustif sans chevauchement)
✅ In scope : [éléments clairement à traiter — spécifiques au brief, 2–3 items]
❌ Out of scope : [ce qu'on ne touche PAS — et pourquoi c'est une distraction]
❓ À décider avant J1 : [question non tranchée qui bloque le démarrage si non résolue]

HYPOTHÈSES STRUCTURANTES
• H1 (critique) : [présupposé qui tient tout le plan — si faux, le projet change entièrement]
• H2 (importante) : [autre présupposé — si faux, on ajuste le périmètre]
• ⚠ Invalider immédiatement si : [condition précise qui nécessite de revoir H1]

LIVRABLES (format précis)
1. [livrable principal — format : "note 3p / slide deck 8p / tableau Excel"] → Validé par : [qui]
2. [livrable secondaire ou checkpoint intermédiaire]

QUESTIONS CLÉS (MECE — couvrent tout l'espace du problème)
Axe 1 — [dimension principale] : [question fondamentale à répondre]
Axe 2 — [dimension risque/faisabilité] : [question bloquante si non répondue]
Axe 3 — [dimension parties prenantes] : [qui doit être aligné et sur quoi]

RISQUES & DÉPENDANCES
🔴 [risque P0 — conséquence concrète si non traité avant J1]
🟡 [risque P1 — impact délai ou qualité — mitigation proposée]
🔗 [dépendance critique : ce qui doit être en place AVANT de démarrer]

PROCHAINES ÉTAPES
J0–J1 : [action très concrète — qui, quoi, sortie attendue]
J1–J2 : [validation ou atelier — participants, format, durée estimée]
J2–J3 : [livraison note de cadrage + GO / NO-GO décision]

CRITÈRES GO / NO-GO
→ GO si : [condition précise — ce qui doit être vrai pour démarrer sereinement]
→ NO-GO si : [signal d'alarme qui justifie de stopper et reprendre le brief]

INSIGHT CLÉ — L'ERREUR CLASSIQUE SUR CE TYPE DE MISSION
[2–3 phrases sur ce que les équipes ratent systématiquement dans ce type de cadrage. Pas une évidence — quelque chose que seul un expert expérimenté verrait.]
═══════════════════════════════════════════════
RÈGLES : Answer First. MECE. Aucun placeholder non rempli. 45–55 lignes.`;

    // ─── AUDIT — Maturity scoring + Root cause + P0/P1/P2 ───────────────────
    case 'audit':
      return `Tu es un auditeur senior avec 12 ans d'expérience en diagnostics organisationnels et techniques. Tu uses une grille de maturité à 5 niveaux et l'analyse des causes racines.${ctxLine}${refLine}${webLine}${strategyHint}
Brief client : "${query}"
${fillRule}

Rédige un rapport d'audit flash de niveau partner, directement partageable. Verdict clair dès la première ligne. Le client doit comprendre en 30 secondes si la situation est grave et quoi faire d'abord.

═══════════════════════════════════════════════
RAPPORT D'AUDIT — [TITRE EN MAJUSCULES DÉRIVÉ DU BRIEF]

VERDICT GLOBAL : [X,X/10] | [🔴 CRITIQUE / 🟡 DÉGRADÉ / 🟢 VIABLE / 🔵 MATURE]
[1 phrase de verdict direct et honnête. Ex: "La situation est viable à court terme mais structurellement fragile sur 3 axes — sans intervention dans les 30 jours, le risque devient élevé."]

DIAGNOSTIC PAR CRITICITÉ
━━ 🔴 P0 — BLOQUANT (traitement sous 48h) ━━
• [problème critique 1 — conséquence concrète et chiffrée si non corrigé sous 48h]
• [problème critique 2 si pertinent — sinon omets ce bullet]

━━ 🟡 P1 — IMPORTANT (traiter dans les 7 jours) ━━
• [point à corriger 1 — impact sur qualité / délai / budget si ignoré]
• [point à corriger 2]

━━ 🟢 P2 — OPTIMISATION (effort < 4h, gain immédiat) ━━
• [amélioration rapide 1 — résultat estimé : gain de X% ou Y jours]
• [amélioration rapide 2]

ANALYSE DES CAUSES RACINES
→ Cause primaire : [le vrai facteur à l'origine des problèmes P0/P1 — souvent organisationnel ou de gouvernance, pas technique]
→ Cause aggravante : [facteur qui amplifie la cause primaire]
→ Signal ignoré : [indicateur qui était visible et n'a pas été traité — ce que tout le monde avait remarqué sans agir]

QUICK WINS TOP 3 (impact élevé, effort < 4h chacun)
1. [action 1] → Résultat : [spécifique] | Délai : [X heures/jours]
2. [action 2] → Résultat : [spécifique] | Délai : [X heures/jours]
3. [action 3] → Résultat : [spécifique] | Délai : [X heures/jours]

SCORE DE MATURITÉ PAR AXE
• [Axe 1 pertinent au brief] : [X/5] — [justification en une phrase]
• [Axe 2] : [X/5] — [justification]
• [Axe 3] : [X/5] — [justification]
Niveau global : [1-Initiale / 2-Reproductible / 3-Définie / 4-Gérée / 5-Optimisée]

PLAN D'ACTION PRIORISÉ
J0–J1 : [P0 — action précise, responsable, livrable attendu]
J2–J3 : [Quick wins P2 + démarrage P1 — objectif mesurable]
J4–J5 : [P1 structurants — milestone]
J6–J7 : [Rapport final + validation corrections — format livraison]

ROADMAP DE REMÉDIATION
• 30j : [objectif mesurable de stabilisation — indicateur de succès]
• 60j : [consolidation — premier KPI amélioré, chiffre cible]
• 90j : [clôture audit — condition binaire de validation définitive]

INSIGHT CLÉ — CE QUE L'ÉQUIPE N'A PAS VU
[2–3 phrases. L'observation non-évidente. La vraie cause n'est souvent pas là où on la cherche. Qu'est-ce qu'un expert extérieur verrait immédiatement que l'équipe interne rate par proximité ?]

RECOMMANDATION FERME
→ [Verdict sans hedging : que faire EN PREMIER, dans quel ordre exact, et pourquoi cet ordre-là et pas un autre]
═══════════════════════════════════════════════
RÈGLES : Verdict dès la 1ère ligne. Chiffres précis. Causes racines identifiées. 48–58 lignes.`;

    // ─── PRODUIRE — Critical path + MoSCoW + Definition of Done ─────────────
    default: // produire
      return `Tu es un partner d'un cabinet de conseil avec 15 ans d'expérience en gestion de projets complexes et livraison client.${ctxLine}${refLine}${webLine}${strategyHint}
Brief client : "${query}"
${fillRule}

Rédige un plan de livraison de niveau partner, directement transmissible au client. Commence par le diagnostic — montre que tu comprends le vrai problème. Sois opinioné et prêt à défendre ta recommandation.

═══════════════════════════════════════════════
PLAN DE LIVRAISON — [TITRE PRÉCIS DÉRIVÉ DU BRIEF — ≤ 10 MOTS]

DIAGNOSTIC RAPIDE
Problème réel : [en 1 phrase : l'enjeu réel sous le brief littéral. Ex: "Vous cherchez à livrer X, mais le vrai risque est Y — si non adressé, le coût sera Z."]
Hypothèse directrice : [l'hypothèse centrale qui structure tout le plan — si elle est fausse, le plan change]
⚠ Signal d'alarme : [le point que la plupart des équipes ratent dans ce type de mission]

RECOMMANDATION FERME
[1–2 phrases sans hedging. Prends position. Ex: "Ne commencez pas par A — commencez par B, car B débloque A et réduit le risque de X de 40%."]

PRIORISATION MoSCoW
🔴 MUST — sans ça, le livrable est incomplet ou le projet échoue
• [tâche must 1 — livrée par qui, quand, critère de done binaire]
• [tâche must 2 — même format]

🟠 SHOULD — fort ROI, traiter si le temps le permet
• [tâche should 1 — impact estimé si incluse vs. si reportée]
• [tâche should 2]

🟡 COULD — bonus, reporter si contrainte de temps ou budget
• [tâche could — pourquoi c'est tentant mais pas critique maintenant]

CHEMIN CRITIQUE & DÉPENDANCES
[tâche bloquante A] → [tâche bloquante B] → [livrable final]
⚠ Prérequis non-négociable avant J0 : [ce qui doit être en place pour démarrer]
⚠ Risque de blocage si : [condition d'arrêt — quand escalader]

TIMELINE RÉALISTE
• J0 : [démarrage — action précise, pas "initialisation" mais "X fait Y pour livrer Z"]
• J1–J2 : [exécution MUST #1 et #2 — responsable nommé]
• J3 : [checkpoint qualité — critère go/no-go]
• J4 : [livraison finale + recueil feedback structuré]
⏱ Charge totale estimée : [X à Y jours·homme — basé sur les MUST ci-dessus]

DEFINITION OF DONE (non-négociable)
☑ [critère 1 — observable, binaire, pas d'interprétation possible]
☑ [critère 2 — mesurable avec un chiffre ou livrable tangible]
☑ [critère 3 — validé par qui, selon quels critères]

RISQUES & MITIGATIONS
🔴 [risque 1 — probabilité estimée] → mitigation : [action concrète, responsable désigné]
🟡 [risque 2 — impact si matérialisé] → mitigation : [action préventive à engager maintenant]

INSIGHT CLÉ — CE QUE SEUL UN EXPERT VERRAIT
[2–3 phrases non-évidentes sur ce type de mission. Ce que les équipes ratent. La décision contre-intuitive qui fait la différence entre un projet qui dérive et un qui livre.]

PROCHAINE ACTION DANS LES 2H
→ [Une action très concrète à faire maintenant pour démarrer du bon pied — précise, nommée, pas générique]
═══════════════════════════════════════════════
RÈGLES : Diagnostic d'abord. Recommandation opinionée. Zéro placeholder. 45–55 lignes.`;
  }
}

function buildReadyToSend({ mode, query, title, objective, nextActions, timeline, acceptanceCriteria }) {
  const topic = extractTopicFromQuery(query) || String(title || '').trim().slice(0, 80);
  const T = topic || 'ce sujet';
  const lines = [];
  switch (mode) {
    case 'communiquer': {
      lines.push(`Objet : ${T}`, '');
      lines.push('Bonjour,', '');
      lines.push(`Suite à notre échange, voici la synthèse sur : ${T}.`, '');
      if (objective.length) lines.push(`• Objectif : ${objective[0]}`, '');
      if (nextActions.length) {
        lines.push('Points clés :');
        nextActions.slice(0, 3).forEach((a, i) => lines.push(`${i + 1}. ${a}`));
        lines.push('');
      }
      if (timeline.length) {
        lines.push(`🗓 ${timeline[0]}`);
        if (timeline[1]) lines.push(`🗓 ${timeline[1]}`);
        lines.push('');
      }
      lines.push('Merci de confirmer votre validation ou de me faire part de vos ajustements.');
      lines.push('', 'Cordialement');
      break;
    }
    case 'cadrer': {
      lines.push('NOTE DE CADRAGE', '─────────────────────────────', T.toUpperCase(), '');
      lines.push('Objectif');
      objective.forEach((o) => lines.push(`• ${o}`));
      lines.push('');
      lines.push('Livrables & critères de succès');
      acceptanceCriteria.slice(0, 3).forEach((a) => lines.push(`☑ ${a}`));
      lines.push('');
      lines.push('Prochaines étapes');
      nextActions.slice(0, 3).forEach((a, i) => lines.push(`${i + 1}. ${a}`));
      lines.push('');
      lines.push('Timeline');
      timeline.slice(0, 3).forEach((t) => lines.push(`• ${t}`));
      break;
    }
    case 'audit': {
      lines.push("SYNTHÈSE D'AUDIT", '─────────────────────────────', T.toUpperCase(), '');
      lines.push('Points diagnostiqués');
      objective.forEach((o) => lines.push(`• ${o}`));
      lines.push('');
      lines.push('Quick wins prioritaires');
      nextActions.slice(0, 3).forEach((a, i) => lines.push(`${i + 1}. ${a}`));
      lines.push('');
      lines.push("Plan d'action");
      timeline.slice(0, 4).forEach((t) => lines.push(`• ${t}`));
      lines.push('');
      lines.push('Critères de clôture');
      acceptanceCriteria.slice(0, 2).forEach((a) => lines.push(`☑ ${a}`));
      break;
    }
    default: { // produire
      lines.push('PLAN DE LIVRAISON', '─────────────────────────────', T.toUpperCase(), '');
      lines.push('Objectif');
      objective.forEach((o) => lines.push(`• ${o}`));
      lines.push('');
      lines.push('Tâches prioritaires');
      nextActions.slice(0, 4).forEach((a, i) => lines.push(`${i + 1}. ${a}`));
      lines.push('');
      lines.push('Timeline');
      timeline.slice(0, 3).forEach((t) => lines.push(`• ${t}`));
      lines.push('');
      lines.push("Critères d'acceptation");
      acceptanceCriteria.slice(0, 2).forEach((a) => lines.push(`☑ ${a}`));
      break;
    }
  }
  return lines.join('\n');
}

/**
 * Builds a structured trust card explaining why the plan is valid,
 * what assumptions it rests on, and its confidence level.
 * If geminiDoc is provided, enriches with extracted hypothesis + insight.
 */
function buildTrustCard({ mode, context = {}, risks = [], query, geminiDoc = null }) {
  const ctx = normalizeDeliveryContext(context);

  const assumptionsByMode = {
    cadrer: [
      'Les parties prenantes sont disponibles et alignées sur les objectifs du cadrage.',
      'Le périmètre reste modifiable — aucune décision irréversible n\'a été prise.',
      'Le budget et le calendrier sont encore en cours de définition.',
    ],
    produire: [
      'Le périmètre et les critères d\'acceptance sont partagés et validés par le client.',
      'Les ressources nécessaires (temps, accès, outils) sont disponibles.',
      'Un point de feedback intermédiaire est planifié avant la livraison finale.',
    ],
    communiquer: [
      'L\'audience cible est identifiée et son contexte est connu de l\'émetteur.',
      'Le message central est validé en interne avant envoi.',
      'Le délai de réponse attendu est réaliste pour l\'audience visée.',
    ],
    audit: [
      'L\'accès aux données, outils et interlocuteurs clés est garanti.',
      'Le commanditaire de l\'audit est aligné sur les objectifs et la méthode.',
      'Les équipes auditées joueront le jeu de la transparence.',
    ],
  };

  const limitsByMode = {
    cadrer: 'Ce cadrage est un point de départ — toute hypothèse non vérifiée doit être levée avant le lancement du projet.',
    produire: 'Ce plan ne garantit pas la qualité finale sans un point de feedback intermédiaire avec le client.',
    communiquer: 'L\'impact réel du message dépend de la relation préexistante avec l\'audience et du moment d\'envoi.',
    audit: 'Les recommandations reposent sur les informations disponibles — des éléments non communiqués peuvent modifier les priorités.',
  };

  const whyThisPlanByMode = {
    cadrer: 'Méthode MECE + Answer First pour structurer le périmètre sans ambiguïté.',
    produire: 'Méthode MoSCoW + chemin critique pour maximiser la livraison de valeur dans les délais.',
    communiquer: 'Pyramid Principle (Barbara Minto) pour une communication executive qui respecte le temps des décideurs.',
    audit: 'Grille de maturité à 5 niveaux + analyse causes racines pour des diagnostics actionnables.',
  };

  // Confidence: based on context richness
  const contextScore = [ctx.clientType, ctx.budget, ctx.deadline, ctx.maturity].filter(Boolean).length;
  let confidence = contextScore >= 2 ? 'élevé' : contextScore >= 1 ? 'moyen' : 'faible';

  let assumptions = (assumptionsByMode[mode] || assumptionsByMode.produire).slice(0, 3);
  let keyInsight = null;

  // Enrich with Gemini doc extraction
  if (geminiDoc) {
    const hypoMatch = geminiDoc.match(/Hypoth[eè]se directrice\s*:\s*(.{10,200})/i);
    if (hypoMatch) {
      const extracted = hypoMatch[1].trim().replace(/^\[|\]$/g, '');
      if (extracted.length > 10 && !extracted.includes('[')) {
        assumptions = [extracted, ...assumptions.slice(1)];
      }
    }
    const insightMatch = geminiDoc.match(/INSIGHT CL[EÉ][^\n]*\n([^\n\[]{20,300})/i);
    if (insightMatch) keyInsight = insightMatch[1].trim();
    // Degrade confidence if alarm signals detected in deliverable
    if (/signal d.alarme|risque critique|bloquant/i.test(geminiDoc) && confidence === 'élevé') {
      confidence = 'moyen';
    }
  }

  return {
    confidence,
    whyThisPlan: whyThisPlanByMode[mode] || whyThisPlanByMode.produire,
    assumptions,
    limits: limitsByMode[mode] || limitsByMode.produire,
    ...(keyInsight ? { keyInsight } : {}),
  };
}

function buildDeliveryPlan({ mode, query, title, steps, context, geminiDeliverable = null }) {
  const ctx = normalizeDeliveryContext(context);
  const items = Array.isArray(steps) ? steps.filter(Boolean).map((s) => String(s).trim()).filter(Boolean) : [];
  const pick = (from, count) => items.slice(from, from + count);

  const topic = String(query || title || '').replace(/\bmode\s*(cadrer|produire|communiquer|audit)\b/gi, '').trim().slice(0, 120);
  const fallbackObjective = topic
    ? `Transformer "${topic}" en livrable concret et actionnable.`
    : 'Produire un livrable concret à partir du brief client.';

  const objective = pick(0, 1).length ? pick(0, 1) : [fallbackObjective];
  const scope = pick(1, 2).length ? pick(1, 2) : [
    `Périmètre : ${topic.slice(0, 80) || 'à définir avec le client'}`,
    "Points d'entrée et de sortie à valider avant démarrage.",
  ];
  const ctxLines = contextNotes(ctx);
  const risksByMode = {
    cadrer: ['Manque de clarté sur les livrables attendus.', 'Parties prenantes non encore alignées.'],
    produire: ["Risque de dérive du périmètre en cours d'exécution.", 'Dépendances techniques ou humaines non identifiées.'],
    communiquer: ["Message mal calibré par rapport à l'audience cible.", 'Timing inadapté ou canal de diffusion sous-optimal.'],
    audit: ['Accès incomplet aux données ou artéfacts du projet.', 'Sous-estimation de la dette technique ou organisationnelle.'],
  };
  const risks = [
    ...(pick(3, 2).length ? pick(3, 2) : (risksByMode[mode] || risksByMode.produire)),
    ...(ctx.deadline ? [`Risque de glissement si la deadline (${ctx.deadline}) n'est pas verrouillee.`] : []),
    ...(ctx.budget ? [`Contrainte budgetaire explicite a respecter: ${ctx.budget}.`] : []),
  ];
  const nextActions = pick(5, 3).length ? pick(5, 3) : items.slice(0, Math.min(3, items.length));

  const timelineByMode = {
    cadrer: [
      'H0 : lecture du brief et formulation des questions clés',
      'J1 : atelier de cadrage avec les parties prenantes',
      'J2 : livraison du document de périmètre validé',
    ],
    produire: [
      'J0 : démarrage, setup et validation du périmètre',
      'J1–J2 : exécution des tâches critiques',
      'J3 : revue qualité et ajustements',
      'J4 : livraison finale et feedback client',
    ],
    communiquer: [
      'J0 : rédaction et validation du message en interne',
      'J1 : envoi ou publication sur le canal cible',
      'J2–J3 : suivi des retours et relances si nécessaire',
    ],
    audit: [
      'J0 : diagnostic rapide et tri par criticité',
      'J1–J2 : corrections des quick wins',
      'J3–J5 : traitement des points structurants',
      'J7 : bilan final, rapport et plan de suivi',
    ],
  };
  const timeline = [
    ...(timelineByMode[mode] || timelineByMode.produire),
    ...(ctx.deadline ? [`Cadence adaptee a la deadline client: ${ctx.deadline}.`] : []),
  ];

  const effortByMode = {
    cadrer: ['Complexité : faible à moyenne', 'Charge estimée : 2 à 4 heures', 'Contrainte principale : disponibilité des parties prenantes'],
    produire: ['Complexité : variable selon le périmètre', 'Charge estimée : 0,5 à 2 jours', 'Contrainte principale : clarté des spécifications'],
    communiquer: ['Complexité : faible', 'Charge estimée : 1 à 4 heures', "Contrainte principale : alignement sur le message et l'audience"],
    audit: ['Complexité : élevée', 'Charge estimée : 1 à 5 jours', 'Contrainte principale : accès aux données et disponibilité des interlocuteurs'],
  };
  const effort = [
    ...(effortByMode[mode] || effortByMode.produire),
    ...(ctx.budget ? [`Budget cible: ${ctx.budget}.`] : []),
    ...(ctx.maturity ? [`Niveau de maturite pris en compte: ${ctx.maturity}.`] : []),
  ];

  const dependenciesByMode = {
    cadrer: ['Brief client disponible et partagé', 'Accès aux parties prenantes clés', 'Historique et contexte projet communiqués'],
    produire: ['Périmètre validé par le client', 'Accès aux ressources et outils nécessaires', 'Point de feedback intermédiaire planifié'],
    communiquer: ['Validation interne du message avant envoi', 'Liste des destinataires définie', 'Deadline de communication fixée'],
    audit: ['Accès aux artéfacts, données et code du projet', "Temps alloué pour l'analyse approfondie", 'Interlocuteur technique disponible pour clarifications'],
  };
  const dependencies = [
    ...(dependenciesByMode[mode] || dependenciesByMode.produire),
    ...ctxLines,
  ].filter(Boolean);

  const acceptanceCriteriaByMode = {
    cadrer: [
      'Le périmètre est défini, écrit et validé par le client.',
      'Les hypothèses et incertitudes majeures sont levées.',
      "L'équipe est alignée sur les priorités et la prochaine étape.",
    ],
    produire: [
      'Le livrable couvre le périmètre validé sans régression.',
      'Les risques majeurs sont traités ou documentés.',
      "Le client peut valider et passer à l'étape suivante.",
    ],
    communiquer: [
      "Le message est compris et bien reçu par l'audience cible.",
      'Les prochaines étapes sont claires pour toutes les parties.',
      'Un retour ou accusé de réception est obtenu.',
    ],
    audit: [
      'Les risques critiques sont identifiés, priorisés et documentés.',
      'Les quick wins sont livrés et mesurables.',
      "Le plan d'action 7 jours est formalisé et approuvé.",
    ],
  };
  const acceptanceCriteria = [
    ...(acceptanceCriteriaByMode[mode] || acceptanceCriteriaByMode.produire),
    ...(ctx.deadline ? [`Le planning respecte la deadline: ${ctx.deadline}.`] : []),
    ...(ctx.budget ? [`La proposition respecte le cadre budgetaire: ${ctx.budget}.`] : []),
    ...(ctx.maturity ? [`Le niveau de complexite reste adapte a une maturite ${ctx.maturity}.`] : []),
  ];

  let clientMessage = [];
  if (mode === 'communiquer') {
    clientMessage = items.length ? items : [
      `Bonjour, voici l'avancement sur "${title || topic}".`,
      'Les prochaines actions sont planifiées — je vous propose un point de validation rapide.',
      'Pouvez-vous confirmer la priorité et la deadline cible ?',
    ];
  } else {
    clientMessage = [
      `Bonjour, voici le plan de livraison proposé pour "${title || topic}".`,
      'Je partage les priorités, risques et prochaines actions pour alignement.',
      'Merci de valider le périmètre et la priorité des tâches.',
    ];
  }

  const actionMatrix = buildActionMatrix(nextActions, mode);
  const strategyVariants = buildStrategyVariants({ mode, context });
  const qualityAssessment = buildQualityAssessment({
    mode,
    objective,
    scope,
    risks,
    nextActions,
    timeline,
    dependencies,
    acceptanceCriteria,
    clientMessage,
  });

  const modeNames = { cadrer: 'Cadrage', produire: 'Production', communiquer: 'Communication', audit: 'Audit' };
  const bsTopic = extractTopicFromQuery(query) || String(title || '').trim().slice(0, 60);
  const briefSummary = `${modeNames[mode] || 'Plan'} pour "${bsTopic}". ${nextActions.length} actions prioritaires identifiées.`;
  const readyToSend = geminiDeliverable || buildReadyToSend({ mode, query, title, objective, nextActions, timeline, acceptanceCriteria });
  const trustCard = buildTrustCard({ mode, context: ctx, risks, query, geminiDoc: geminiDeliverable });

  return {
    mode,
    context: ctx,
    objective,
    scope,
    risks,
    nextActions,
    timeline,
    effort,
    dependencies,
    acceptanceCriteria,
    clientMessage,
    actionMatrix,
    strategyVariants,
    briefSummary,
    readyToSend,
    trustCard,
    ...qualityAssessment,
  };
}

function annotateSource(source, mode = 'real') {
  return {
    source,
    resultMode: mode,
    badges: [mode.toUpperCase()],
  };
}

function extractDesiredSteps(text) {
  try {
    const s = String(text || '').toLowerCase();
    // Patterns like: "en 7 étapes", "7 étapes", "7 etapes", "7 steps", "en 3 points"
    const m = s.match(/(?:en\s+)?(\d{1,3})\s*(?:étapes?|etapes?|steps?|points?)/i);
    if (m) {
      const n = parseInt(m[1], 10);
      if (Number.isFinite(n) && n > 0) return n;
    }
  } catch (_) { /* ignore */ }
  return null;
}

function extractYouTubeVideoId(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes('youtu.be')) {
      return u.pathname.replace('/', '').split('?')[0];
    }
    if (u.searchParams.has('v')) return u.searchParams.get('v');
    // Fallback for embed URLs
    const parts = u.pathname.split('/');
    const idx = parts.indexOf('embed');
    if (idx !== -1 && parts[idx + 1]) return parts[idx + 1];
  } catch (_) { /* ignore */ }
  return null;
}

function normalizeQueryInput(raw, maxLen = MAX_QUERY_LEN) {
  const query = String(raw || '').trim();
  if (!query) return { ok: false, status: 400, error: 'query is required' };
  if (query.length > maxLen) {
    return { ok: false, status: 413, error: `query is too long (max ${maxLen} chars)` };
  }
  return { ok: true, value: query };
}

function withTimestamp(url, startSec) {
  try {
    const u = new URL(url);
    // Add t=STARTS seconds as query parameter; keep existing params
    u.searchParams.set('t', String(Math.max(0, Math.floor(startSec))));
    return u.toString();
  } catch (_) {
    return url;
  }
}

async function buildCitations({ videoId, videoTitle, videoUrl, max = 3 }) {
  try {
    const { transcript } = await getTranscript(videoId, videoTitle);
    const items = (transcript || []).slice(0, max);
    return items.map((seg) => ({
      url: withTimestamp(videoUrl, seg.startSec || 0),
      startSec: Math.max(0, Math.floor(seg.startSec || 0)),
      endSec: Math.max(0, Math.floor((seg.startSec || 0) + 25)),
      quote: String(seg.text || '').slice(0, 140)
    }));
  } catch (_) {
    return [];
  }
}

// Allow overriding YouTube search implementation in tests without affecting production import binding.
let searchYouTube = originalSearchYouTube;
export function setSearchYouTube(fn) {
  if (typeof fn === 'function') {
    searchYouTube = fn;
  } else {
    throw new Error('setSearchYouTube expects a function');
  }
}

async function generateWithGemini(prompt, maxOutputTokens = 256, options = {}) {
  const currentModel = options.model || GEMINI_MODEL;
  const allowModelFallback = options.allowModelFallback !== false;
  if (!GEMINI_API_KEY) throw new Error("GEMINI_API_KEY missing");
  // Use v1 generateContent endpoint for modern models; fall back to legacy if needed.
  const isLegacy = /bison|text-bison/i.test(currentModel);
  const baseUrl = isLegacy
    ? `https://generativelanguage.googleapis.com/v1beta2/${currentModel}:generateText?key=${GEMINI_API_KEY}`
    : `https://generativelanguage.googleapis.com/v1/${currentModel}:generateContent?key=${GEMINI_API_KEY}`;


  const body = isLegacy
    ? { prompt: { text: prompt }, maxOutputTokens, temperature: 0.2 }
    : {
      contents: [
        { role: "user", parts: [{ text: prompt }] }
      ],
      generationConfig: { maxOutputTokens, temperature: 0.2 },
      safetySettings: [
        { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
        { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
        { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
        { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
      ]
    };

  try {
    const resp = await axios.post(baseUrl, body, { headers: { "Content-Type": "application/json" }, timeout: GEMINI_TIMEOUT_MS });
    if (isLegacy) {
      const txt = resp.data?.candidates?.[0]?.output;
      if (!txt) throw new Error("Empty Gemini legacy output");
      return txt.trim();
    } else {
      const block = resp.data?.promptFeedback?.blockReason;
      if (block && block !== "BLOCK_NONE") {
        throw new Error(`Gemini blocked content: ${block}`);
      }
      const parts = resp.data?.candidates?.[0]?.content?.parts || [];
      let txt = parts.map(p => p?.text).filter(Boolean).join("\n").trim();
      if (!txt) txt = (resp.data?.candidates?.[0]?.text || "").trim();
      if (!txt) txt = (resp.data?.candidates?.[0]?.output || "").trim();
      if (!txt) throw new Error("Empty Gemini response");
      // success resets failure counters and closes breaker
      GEMINI_OPERATIONAL = true;
      GEMINI_FAILURE_TIMESTAMPS = [];
      GEMINI_BREAKER_UNTIL = 0;
      observeExternal('gemini', 'success');
      return txt;
    }
  } catch (error) {
    const status = error?.response?.status;
    const message = error?.response?.data?.error?.message || error.message;
    // On timeout or network abort, throw a concise timeout error
    if (error?.code === 'ECONNABORTED' || /timeout/i.test(message || '')) {
      GEMINI_OPERATIONAL = false;
      // record failure and possibly open breaker
      const now = Date.now();
      GEMINI_FAILURE_TIMESTAMPS = GEMINI_FAILURE_TIMESTAMPS.filter(ts => now - ts <= FAILURE_WINDOW_MS);
      GEMINI_FAILURE_TIMESTAMPS.push(now);
      if (GEMINI_FAILURE_TIMESTAMPS.length >= 3) {
        GEMINI_BREAKER_UNTIL = Math.max(GEMINI_BREAKER_UNTIL, now + BREAKER_OPEN_MS);
      }
      observeExternal('gemini', 'timeout');
      throw new Error(`Gemini timeout after ${GEMINI_TIMEOUT_MS}ms`);
    }
    // If NOT_FOUND: try a known accessible lite model explicitly once
    if (
      status === 404 &&
      allowModelFallback &&
      currentModel !== 'models/gemini-2.0-flash-lite' &&
      currentModel !== 'models/gemini-2.0-flash-lite-001'
    ) {
      return await generateWithGemini(prompt, maxOutputTokens, {
        model: 'models/gemini-2.0-flash-lite',
        allowModelFallback: false,
      });
    }
    observeExternal('gemini', 'error');
    if (status === 404) {
      // mark non-operational and record failure
      GEMINI_OPERATIONAL = false;
      const now = Date.now();
      GEMINI_FAILURE_TIMESTAMPS = GEMINI_FAILURE_TIMESTAMPS.filter(ts => now - ts <= FAILURE_WINDOW_MS);
      GEMINI_FAILURE_TIMESTAMPS.push(now);
      if (GEMINI_FAILURE_TIMESTAMPS.length >= 3) {
        GEMINI_BREAKER_UNTIL = Math.max(GEMINI_BREAKER_UNTIL, now + BREAKER_OPEN_MS);
      }
    }
    throw new Error(message || "Gemini generation failed");
  }
}

app.get("/health", (_req, res) => {
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  const mock = (process.env.MOCK_MODE || mockDefault) === "true";
  res.json({
    ok: true,
    mode: mock ? 'MOCK' : 'REAL',
    mock,
    uptimeSeconds: Math.round((Date.now() - START_TIME) / 1000),
    version: APP_VERSION,
    projectId: process.env.PROJECT_ID || null,
    youtubeApi: Boolean(process.env.YT_API_KEY),
    gemini: {
      enabled: USE_GEMINI_ENV,
      model: GEMINI_MODEL,
      hasKey: Boolean(GEMINI_API_KEY),
      timeoutMs: GEMINI_TIMEOUT_MS,
      operational: GEMINI_OPERATIONAL,
      breakerActive: Date.now() < GEMINI_BREAKER_UNTIL,
      retryAt: GEMINI_BREAKER_UNTIL || null,
    }
  });
});

// Extended health with dynamic Gemini state
app.get("/health/extended", (_req, res) => {
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  const mock = (process.env.MOCK_MODE || mockDefault) === "true";
  res.json({
    ok: true,
    mode: mock ? 'MOCK' : 'REAL',
    mock,
    uptimeSeconds: Math.round((Date.now() - START_TIME) / 1000),
    version: APP_VERSION,
    timestamp: new Date().toISOString(),
    projectId: process.env.PROJECT_ID || null,
    youtube: { hasKey: Boolean(process.env.YT_API_KEY) },
    gemini: {
      configured: (process.env.USE_GEMINI || "false") === "true",
      hasKey: Boolean(GEMINI_API_KEY),
      model: GEMINI_MODEL,
      timeoutMs: GEMINI_TIMEOUT_MS,
      operational: GEMINI_OPERATIONAL,
      breakerActive: Date.now() < GEMINI_BREAKER_UNTIL,
      retryAt: GEMINI_BREAKER_UNTIL || null,
    }
  });
});
app.get("/health/observability", (_req, res) => {
  const snapshot = buildObservabilitySnapshot();
  const alerts = evaluateAlerts(snapshot);
  res.json({ ok: true, snapshot, alerts });
});

app.post('/api/search/feedback', async (req, res) => {
  let payload;
  try {
    payload = validateFeedbackPayload(req.body || {});
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload' });
  }
  const { requestId, clicked, completed, rating } = payload;
  observeQualityEvent({ requestId, clicked, completed, rating });
  return res.json({ ok: true });
});

app.post('/api/analytics/ttv', async (req, res) => {
  let payload;
  try {
    payload = validateTtvPayload(req.body || {});
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload' });
  }
  const { requestId, ttvMs } = payload;
  observeTtvEvent({ requestId, ttvMs });
  return res.json({ ok: true });
});

app.get('/api/recommendations', userIdMiddleware, async (req, res) => {
  try {
    const Lesson = (await import('./models/lesson.js')).default;
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized user context' });
    const history = await Lesson.find({ userId }).sort({ lastViewedAt: -1, updatedAt: -1 }).limit(20).lean();
    const seedWords = new Set();
    history.forEach((l) => String(l.title || '').toLowerCase().split(/\W+/).filter((w) => w.length > 3).forEach((w) => seedWords.add(w)));
    const candidates = await Lesson.find({ userId: { $ne: userId } }).sort({ favorite: -1, views: -1, createdAt: -1 }).limit(100).lean();
    const scored = candidates.map((l) => {
      const words = String(l.title || '').toLowerCase().split(/\W+/);
      const overlap = words.filter((w) => seedWords.has(w)).length;
      const score = overlap * 3 + (l.favorite ? 2 : 0) + Math.min(5, Math.floor((l.views || 0) / 10));
      return { ...l, score };
    }).sort((a, b) => b.score - a.score).slice(0, 10);
    return res.json({ items: scored });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to build recommendations', detail: e?.message || 'Unknown error' });
  }
});


app.post("/api/search", async (req, res) => {
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!(await simpleRateLimit(`search:${ip}`, 20))) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  let query;
  let summaryLength;
  let useGeminiOverride;
  let requestContext;
  try {
    ({ query, summaryLength, useGemini: useGeminiOverride, context: requestContext } = validateSearchPayload(req.body || {}));
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload' });
  }
  const summaryConfig = getSummaryConfig(featureFlags.multiLengthSummary ? summaryLength : 'standard');
  const deliveryMode = detectDeliveryModeFromQuery(query);
  const requestId = randomBytes(8).toString('hex');

  // Dev mock mode: quick responses without keys. Default mock false if YT_API_KEY exists.
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    const mock = makeMockResponse();
    const steps = Array.isArray(mock.steps) ? mock.steps : [];
    const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
    const citations = await buildCitations({ videoId: vid, videoTitle: mock.title, videoUrl: mock.videoUrl, max: 3 });
    const desiredChapters = extractDesiredChapters(query);
    const chapters = (await getChapters(vid, mock.title, { desired: desiredChapters })).chapters;
    const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: mock.title, steps, context: requestContext });
    return res.json({
      ...mock,
      steps,
      ...annotateSource(mock.source, 'mock'),
      citations,
      chapters,
      deliveryPlan,
      requestId,
      summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
    });
  }

  try {
    let searchTerm = query;
    const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
    const useGemini = USE_GEMINI_ENV && !breakerActive && (useGeminiOverride !== false);
    let reformulationTimedOut = false;
    if (useGemini && USE_GEMINI_REFORMULATION) {
      const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
      try {
        let reform = await generateWithGemini(reformPrompt, 32);
        reform = String(reform)
          .split(/\r?\n/)[0]
          .replace(/^[-*•\s>"]+/, "")
          .replace(/["`]+/g, "")
          .trim();
        if (!reform || reform.length > 80) {
          searchTerm = query;
        } else {
          searchTerm = reform;
        }
      } catch (e) {
        console.warn("Gemini reformulation failed:", e.message);
        if (/timeout/i.test(e.message || "")) {
          reformulationTimedOut = true;
        }
        searchTerm = query;
      }
    }

    let videoTitle, videoUrl, source, videoId;
    try {
      const video = await searchYouTube(searchTerm);
      videoTitle = video.title;
      videoUrl = video.url;
      source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
      observeExternal('youtube', 'success');
    } catch (videoErr) {
      console.warn("Video search failed:", videoErr.message);
      if (videoErr.code === "YOUTUBE_NO_RESULTS" && searchTerm !== query) {
        console.log("Retrying YouTube search with original query after no results for reformulated term.");
        try {
          const retryVideo = await searchYouTube(query);
          videoTitle = retryVideo.title;
          videoUrl = retryVideo.url;
          videoId = retryVideo.videoId || extractYouTubeVideoId(retryVideo.url);
          source = retryVideo.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
          console.log("Recovered video via original query.");
        } catch (retryErr) {
          console.warn("Retry with original query also failed:", retryErr.message);
          if ((process.env.ALLOW_FALLBACK || "true") === "true") {
            observeExternal('youtube', 'fallback');
            return res.json({ ...makeMockResponse(), source: "mock-fallback" });
          }
          throw retryErr;
        }
      } else {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          observeExternal('youtube', 'fallback');
          return res.json({ ...makeMockResponse(), source: "mock-fallback" });
        }
        throw videoErr;
      }
    }

    let summaryText = "";
    let geminiDeliverablePost = null;
    const attemptGeminiSummary = useGemini && !reformulationTimedOut;
    const desiredSteps = extractDesiredSteps(query) || summaryConfig.stepsTarget;
    if (attemptGeminiSummary) {
      // Récupère le transcript YouTube
      let transcriptText = "";
      try {
        const { transcript } = await getTranscript(videoId, videoTitle);
        transcriptText = Array.isArray(transcript) ? transcript.map(seg => seg.text).join(" ") : "";
      } catch (e) {
        console.warn("Transcript fetch failed, fallback to title only:", e.message);
      }
      // Utilise le transcript comme input Gemini si disponible
      const summaryPrompt = transcriptText
        ? `Tu es un consultant expert. Génère un plan d'action en ${desiredSteps || 5} étapes concrètes et numérotées pour : "${query}"\n\nTranscription de référence :\n${transcriptText.slice(0, 1200)}\n\nRègles : une étape par ligne numérotée, concrète et directement actionnable, adaptée au brief décrit.`
        : null;
      const webSnippets = await fetchWebSnippets(query);
      try {
        // Always try to generate the full deliverable document first
        const deliverablePrompt = buildGeminiPromptForMode({ mode: deliveryMode, query, context: { ...requestContext, webSnippets }, videoTitle });
        const fullDoc = await generateWithGemini(deliverablePrompt, 1200);
        geminiDeliverablePost = fullDoc.trim();
        // If we also have a transcript, use it to extract numbered steps for plan sections
        if (summaryPrompt) {
          const stepsOnly = await generateWithGemini(summaryPrompt, 300);
          summaryText = stepsOnly;
        } else {
          const numberedLines = fullDoc.split('\n').map(l => l.trim()).filter(l => /^\d+[\.\)]\s/.test(l)).map(l => l.replace(/^\d+[\.\)]\s*/, ''));
          summaryText = numberedLines.length >= 2 ? numberedLines.join('\n') : heuristicSummary({ desiredSteps, mode: deliveryMode, query });
        }
      } catch (e) {
        console.warn("Gemini summary failed:", e.message);
        summaryText = heuristicSummary({ desiredSteps, mode: deliveryMode, query });
      }
    } else {
      summaryText = heuristicSummary({ desiredSteps, mode: deliveryMode, query });
    }

    const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
    const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: videoTitle, steps, context: requestContext, geminiDeliverable: geminiDeliverablePost ?? null });
    const vid = videoId || extractYouTubeVideoId(videoUrl);
    const citations = vid ? await buildCitations({ videoId: vid, videoTitle, videoUrl, max: 3 }) : [];
    const desiredChapters = extractDesiredChapters(query);
    const chapters = vid ? (await getChapters(vid, videoTitle, { desired: desiredChapters })).chapters : [];
    return res.json({
      title: videoTitle,
      steps,
      videoUrl,
      ...annotateSource(source, 'real'),
      citations,
      chapters,
      deliveryPlan,
      requestId,
      summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
    });
  } catch (err) {
    console.error("Search error:", err?.response?.data || err.message || err);
    const statusCode = err?.status || err?.response?.status || 500;
    const detail = err?.message || "Unexpected error";
    return res.status(statusCode).json({ error: statusCode === 404 ? "Not found" : "Internal server error", detail });
  }
});

// Server-Sent Events streaming endpoint for progressive UI updates
// Usage: GET /api/search/stream?query=...
app.get("/api/search/stream", async (req, res) => {
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!(await simpleRateLimit(`stream:${ip}`, 10))) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  const validation = normalizeQueryInput(req.query.query, MAX_STREAM_QUERY_LEN);
  if (!validation.ok) return res.status(validation.status).json({ error: validation.error });
  const query = validation.value;
  const requestContext = normalizeDeliveryContext(req.query || {});
  const deliveryMode = detectDeliveryModeFromQuery(query);

  // Set SSE headers
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  const clientState = { closed: false };
  req.on('close', () => {
    clientState.closed = true;
  });

  const writeEvent = (obj) => {
    if (clientState.closed || res.writableEnded || res.destroyed) return;
    try {
      res.write(`data: ${JSON.stringify(obj)}\n\n`);
    } catch (e) {
      // client likely disconnected
      clientState.closed = true;
      return;
    }
  };

  const end = () => {
    if (res.writableEnded || res.destroyed) return;
    try {
      res.end();
    } catch (_) {
      return;
    }
  };

  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    // Stream mock in small chunks
    const mock = makeMockResponse();
    const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: mock.title, steps: mock.steps || [], context: requestContext });
    writeEvent({ type: "meta", title: mock.title, videoUrl: mock.videoUrl, source: mock.source, deliveryMode });
    const steps = mock.steps || [];
    let idx = 0;
    const interval = setInterval(() => {
      if (idx < steps.length) {
        writeEvent({ type: "partial", step: steps[idx] });
        idx++;
      } else {
        clearInterval(interval);
        // final event with citations and chapters
        (async () => {
          try {
            if (clientState.closed) return;
            const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
            const citations = await buildCitations({ videoId: vid, videoTitle: mock.title, videoUrl: mock.videoUrl, max: 3 });
            const desiredChapters = extractDesiredChapters(query);
            const chapters = (await getChapters(vid, mock.title, { desired: desiredChapters })).chapters;
            writeEvent({ type: 'final', citations, chapters, deliveryPlan });
            writeEvent({ type: 'done' });
          } catch (err) {
            writeEvent({ type: 'error', error: 'Internal server error', detail: err?.message || 'Unexpected error' });
          } finally {
            end();
          }
        })();
      }
    }, 220);
    req.on("close", () => clearInterval(interval));
    return;
  }

  (async () => {
    try {
      let searchTerm = query;
      const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
      const useGemini = USE_GEMINI_ENV && !breakerActive && (req.query?.useGemini !== "false");
      let reformulationTimedOut = false;
      if (useGemini && USE_GEMINI_REFORMULATION) {
        const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
        try {
          let reform = await generateWithGemini(reformPrompt, 32);
          reform = String(reform)
            .split(/\r?\n/)[0]
            .replace(/^[-*•\s>"]+/, "")
            .replace(/["`]+/g, "")
            .trim();
          if (reform && reform.length <= 80) searchTerm = reform;
        } catch (e) {
          if (/timeout/i.test(e.message || "")) reformulationTimedOut = true;
          console.warn("Gemini reformulation (stream) failed:", e.message);
        }
      }

      // Search video first and emit meta
      let videoTitle, videoUrl, source, videoId;
      try {
        const video = await searchYouTube(searchTerm);
        videoTitle = video.title;
        videoUrl = video.url;
        source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
        observeExternal('youtube', 'success');
      } catch (videoErr) {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          const mock = makeMockResponse();
          observeExternal('youtube', 'fallback');
          writeEvent({ type: "meta", title: mock.title, videoUrl: mock.videoUrl, source: "mock-fallback" });
          for (const s of mock.steps) {
            writeEvent({ type: "partial", step: s });
            await new Promise(r => setTimeout(r, 180));
          }
          writeEvent({ type: "done" });
          return end();
        }
        throw videoErr;
      }

      writeEvent({ type: "meta", title: videoTitle, videoUrl, source, deliveryMode });

      // Summarize and stream steps one by one (Gemini returns full text; we simulate token streaming)
      let summaryText = "";
      let geminiDeliverable = null;
      const attemptGeminiSummary = useGemini && !reformulationTimedOut;
      const desiredSteps = extractDesiredSteps(query);
      const webSnippets = await fetchWebSnippets(query);
      if (attemptGeminiSummary) {
        const deliverablePrompt = buildGeminiPromptForMode({ mode: deliveryMode, query, context: { ...requestContext, webSnippets }, videoTitle });
        try {
          const fullDoc = await generateWithGemini(deliverablePrompt, 1200);
          geminiDeliverable = fullDoc.trim();
          // Extract numbered lines as steps so the plan sections are populated
          const numberedLines = fullDoc.split('\n').map(l => l.trim()).filter(l => /^\d+[\.\)]\s/.test(l)).map(l => l.replace(/^\d+[\.\)]\s*/, ''));
          summaryText = numberedLines.length >= 2
            ? numberedLines.join('\n')
            : heuristicSummary({ desiredSteps, mode: deliveryMode, query });
        } catch (e) {
          console.warn("Gemini deliverable (stream) failed:", e.message);
          summaryText = heuristicSummary({ desiredSteps, mode: deliveryMode, query });
        }
      } else {
        summaryText = heuristicSummary({ desiredSteps, mode: deliveryMode, query });
      }

      const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
      const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: videoTitle, steps, context: requestContext, geminiDeliverable });
      for (const s of steps) {
        if (clientState.closed) return end();
        writeEvent({ type: "partial", step: s });
        await new Promise(r => setTimeout(r, 160));
      }
      if (clientState.closed) return end();
      const vid = videoId || extractYouTubeVideoId(videoUrl);
      const citations = vid ? await buildCitations({ videoId: vid, videoTitle, videoUrl, max: 3 }) : [];
      const desiredChapters = extractDesiredChapters(query);
      const chapters = vid ? (await getChapters(vid, videoTitle, { desired: desiredChapters })).chapters : [];
      writeEvent({ type: "final", citations, chapters, deliveryPlan });
      writeEvent({ type: "done" });
      end();
    } catch (err) {
      console.error("Stream error:", err?.message || err);
      // Standardize error shape with /api/search endpoint: error + detail
      writeEvent({ type: "error", error: "Internal server error", detail: err?.message || "Unexpected error" });
      end();
    }
  })();
});

// Refine stream endpoint: /api/refine/stream?query=...&followUp=...&existingDoc=...&mode=...
// Allows iterative improvement of an existing deliverable without re-running YouTube search.
app.get("/api/refine/stream", (req, res) => {
  const queryValidated = normalizeQueryInput(String(req.query.query || ''), MAX_QUERY_LEN);
  const followUpValidated = normalizeQueryInput(String(req.query.followUp || ''), MAX_QUERY_LEN);
  if (!queryValidated.ok) return res.status(queryValidated.status).json({ error: queryValidated.error });
  if (!followUpValidated.ok) return res.status(followUpValidated.status).json({ error: followUpValidated.error });

  const query = queryValidated.value;
  const followUp = followUpValidated.value;
  const existingDoc = String(req.query.existingDoc || '').slice(0, 3000);
  const mode = String(req.query.mode || 'produire');

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  const clientState = { closed: false };
  req.on('close', () => { clientState.closed = true; });

  const writeEvent = (obj) => {
    if (clientState.closed || res.writableEnded || res.destroyed) return;
    try { res.write(`data: ${JSON.stringify(obj)}\n\n`); } catch (_) { clientState.closed = true; }
  };
  const end = () => {
    if (res.writableEnded || res.destroyed) return;
    try { res.end(); } catch (_) {}
  };

  (async () => {
    try {
      const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
      const useGemini = USE_GEMINI_ENV && !breakerActive;

      writeEvent({ type: "meta", title: query, videoUrl: "", source: "refine", deliveryMode: mode });

      let refinedDoc = "";
      if (useGemini && existingDoc.trim().length > 0) {
        // Refine prompt: acts like a senior consultant receiving client feedback.
        // Step 1: analyse WHAT type of request this is (detail / challenge / reframe / pivot).
        // Step 2: respond accordingly — don't just append text, restructure if needed.
        const refinePrompt = `Tu es un partner de cabinet de conseil qui vient de livrer un document à un client.

BRIEF ORIGINAL : "${query}"

LIVRABLE ACTUEL :
${existingDoc}

LE CLIENT RÉPOND : "${followUp}"

ANALYSE D'ABORD (ne l'écris pas dans la réponse, c'est ton raisonnement interne) :
- S'agit-il d'une demande de détail supplémentaire ? → Développe spécifiquement ce point.
- D'une remise en question d'hypothèse ? → Mets l'hypothèse à jour et recadre le plan.
- D'un changement de priorité ou de périmètre ? → Réorganise le document autour du nouveau focus.
- D'une demande de simplification ? → Réduis et densifie.
- D'un ajout de section manquante ? → Intègre-la à l'endroit logique.
- D'un désaccord sur le diagnostic ? → Défends ta position OU révise si le client a raison.

RÈGLES ABSOLUES :
1. Produis directement le document RÉVISÉ — pas de commentaire sur le feedback, pas de "j'ai modifié X".
2. Conserve la structure et le format du document original — sauf si le feedback demande une réorganisation.
3. Zéro placeholder non rempli. Sois encore plus précis que la version initiale.
4. Si le client challenge une de tes recommandations, prends position : soit tu la défends avec un argument nouveau, soit tu la révises avec un meilleur raisonnement.
5. Le document final doit être encore meilleur que l'original — pas juste différent.`;
        try {
          refinedDoc = (await generateWithGemini(refinePrompt, 1200)).trim();
        } catch (e) {
          console.warn("Gemini refine failed:", e.message);
        }
      }

      if (!refinedDoc) {
        const fallbackPrompt = buildGeminiPromptForMode({ mode, query: `${query}. ${followUp}`, context: {}, videoTitle: query });
        if (useGemini) {
          try {
            refinedDoc = (await generateWithGemini(fallbackPrompt, 1200)).trim();
          } catch (e) {
            console.warn("Gemini refine fallback failed:", e.message);
          }
        }
      }

      if (!refinedDoc) {
        refinedDoc = buildReadyToSend({ mode, query: `${query}. ${followUp}`, title: query, objective: [], nextActions: [], timeline: [], acceptanceCriteria: [] });
      }

      const numberedLines = refinedDoc.split('\n').map(l => l.trim()).filter(l => /^\d+[\.\)]\s/.test(l)).map(l => l.replace(/^\d+[\.\)]\s*/, ''));
      const steps = numberedLines.length >= 2 ? numberedLines : heuristicSummary({ mode, query: `${query}. ${followUp}` }).split('\n').filter(Boolean);

      const deliveryPlan = buildDeliveryPlan({ mode, query, title: query, steps, context: {}, geminiDeliverable: refinedDoc });

      for (const s of steps) {
        if (clientState.closed) return end();
        writeEvent({ type: "partial", step: s });
        await new Promise(r => setTimeout(r, 120));
      }

      writeEvent({ type: "final", citations: [], chapters: [], deliveryPlan });
      writeEvent({ type: "done" });
      end();
    } catch (err) {
      console.error("Refine stream error:", err?.message || err);
      writeEvent({ type: "error", error: "Internal server error", detail: err?.message || "Unexpected error" });
      end();
    }
  })();
});

// Challenge (Devil's Advocate) stream endpoint: /api/challenge/stream?deliverable=...&query=...&mode=...
// Streams a structured critique of an existing deliverable.
app.get("/api/challenge/stream", (req, res) => {
  const queryValidated = normalizeQueryInput(String(req.query.query || ''), MAX_QUERY_LEN);
  if (!queryValidated.ok) return res.status(queryValidated.status).json({ error: queryValidated.error });
  const query = queryValidated.value;
  const deliverable = String(req.query.deliverable || '').slice(0, 2500);
  const mode = String(req.query.mode || 'produire');

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  const clientState = { closed: false };
  req.on('close', () => { clientState.closed = true; });

  const writeEvent = (obj) => {
    if (clientState.closed || res.writableEnded || res.destroyed) return;
    try { res.write(`data: ${JSON.stringify(obj)}\n\n`); } catch (_) { clientState.closed = true; }
  };
  const end = () => {
    if (res.writableEnded || res.destroyed) return;
    try { res.end(); } catch (_) {}
  };

  (async () => {
    try {
      const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
      const useGemini = USE_GEMINI_ENV && !breakerActive;

      writeEvent({ type: "meta", title: query, videoUrl: "", source: "challenge", deliveryMode: mode });

      const challengePrompt = `Tu es un associé senior d'un cabinet de conseil (McKinsey/BCG/Bain).
Un consultant junior vient de te soumettre ce livrable pour validation avant envoi client.
Ton rôle : jouer l'avocat du diable. Trouver ce qui ne tient pas avant que le client le trouve.

BRIEF ORIGINAL : "${query}"
MODE : ${mode}

LIVRABLE SOUMIS :
${deliverable}

INSTRUCTIONS :
- Ne juge pas la forme, juge le FOND et la solidité des recommandations.
- Sois direct et sans ménagement — c'est une relecture interne, pas un feedback client.
- Les failles doivent être spécifiques au livrable, pas génériques.
- Chaque ligne doit commencer par le numéro et l'emoji correspondant.

FORMAT OBLIGATOIRE (exactement 8 lignes numérotées, pas plus, pas moins) :
1. 🔴 FAILLE 1 — [titre court] : [explication 1-2 phrases. Pourquoi c'est fatal si le client creuse.]
2. 🔴 FAILLE 2 — [titre court] : [explication spécifique au livrable]
3. 🔴 FAILLE 3 — [titre court] : [explication]
4. ⚠️ HYPOTHÈSE 1 — [titre] : [ce qui est supposé vrai mais non vérifié. Ce qui pourrait invalider tout le plan.]
5. ⚠️ HYPOTHÈSE 2 — [titre] : [idem, deuxième hypothèse critique]
6. 💬 OBJECTION CFO : [la question EXACTE que le CFO va poser en salle. Formule-la comme une vraie question agressive, avec des chiffres si possible.]
7. ✅ CE QUI TIENT : [ce qu'on garderait tel quel sans modification. 1 phrase précise.]
8. ⚡ CORRECTION PRIORITAIRE : [la seule chose à corriger dans les 30 minutes pour que ce livrable soit défendable. 1 phrase d'action concrète.]`;

      let critiqueText = "";
      if (useGemini && deliverable.trim().length > 50) {
        try {
          critiqueText = (await generateWithGemini(challengePrompt, 900)).trim();
        } catch (e) {
          console.warn("Gemini challenge failed:", e.message);
        }
      }

      if (!critiqueText) {
        critiqueText = [
          `1. 🔴 FAILLE 1 — Périmètre flou : Les frontières du livrable ne sont pas clairement délimitées, ce qui expose à un scope creep immédiat.`,
          `2. 🔴 FAILLE 2 — Hypothèses non chiffrées : Les recommandations manquent de données quantitatives pour être défendables face au comité.`,
          `3. 🔴 FAILLE 3 — Timeline irréaliste : Les délais proposés ne prennent pas en compte les contraintes organisationnelles habituelles.`,
          `4. ⚠️ HYPOTHÈSE 1 — Alignement équipe : On suppose que les équipes sont disponibles et alignées — c'est rarement le cas.`,
          `5. ⚠️ HYPOTHÈSE 2 — Budget validé : On suppose que le budget est déjà arbitré. Il ne l'est probablement pas.`,
          `6. 💬 OBJECTION CFO : "Vous me dites que ça coûte X et ça dure Y mois — mais quel est le ROI précis et sur quelle base de calcul ?"`,
          `7. ✅ CE QUI TIENT : La structure en phases logiques et la priorisation des actions immédiates sont solides.`,
          `8. ⚡ CORRECTION PRIORITAIRE : Ajouter un tableau ROI chiffré avec hypothèses explicitées avant toute présentation au décideur.`,
        ].join('\n');
      }

      const lines = critiqueText.split('\n').map(l => l.trim()).filter(l => /^\d+[.)\s]/.test(l) || l.startsWith('🔴') || l.startsWith('⚠️') || l.startsWith('💬') || l.startsWith('✅') || l.startsWith('⚡'));
      const critLines = lines.length >= 4 ? lines : critiqueText.split('\n').map(l => l.trim()).filter(Boolean);

      for (const line of critLines) {
        if (clientState.closed) return end();
        writeEvent({ type: "partial", step: line });
        await new Promise(r => setTimeout(r, 100));
      }

      writeEvent({ type: "final", citations: [], chapters: [], deliveryPlan: {} });
      writeEvent({ type: "done" });
      end();
    } catch (err) {
      console.error("Challenge stream error:", err?.message || err);
      writeEvent({ type: "error", error: "Internal server error", detail: err?.message || "Unexpected error" });
      end();
    }
  })();
});

// Transcript endpoint: /api/transcript?videoId=...&title=...
app.get("/api/transcript", async (req, res) => {
  const videoId = String(req.query.videoId || '').trim();
  const title = String(req.query.title || '').trim();
  if (!videoId) return res.status(400).json({ error: 'videoId is required' });
  try {
    const { transcript, cache } = await getTranscript(videoId, title);
    // Optional key takeaways and quiz fields
    const keyTakeaways = transcript ? transcript.slice(0, 3).map(seg => seg.text) : [];
    const quiz = transcript ? [{ question: 'What is the first step?', answer: transcript[0]?.text }] : [];
    res.setHeader('X-Cache', cache);
    return res.json({ videoId, transcript, cached: cache === 'HIT', keyTakeaways, quiz });
  } catch (e) {
    return res.status(500).json({
      error: 'Transcript fetch failed', detail: e?.message || 'Unknown error', suggestedActions: [
        { label: 'Retry', action: '/api/transcript' },
        { label: 'Request help', action: '/support' }
      ]
    });
  }
});

// Chapters endpoint: /api/chapters?videoId=...&title=...
app.get("/api/chapters", async (req, res) => {
  const videoId = String(req.query.videoId || '').trim();
  const title = String(req.query.title || '').trim();
  const desired = req.query.desired ? parseInt(String(req.query.desired), 10) : undefined;
  if (!videoId) return res.status(400).json({ error: 'videoId is required' });
  try {
    const { chapters, cache } = await getChapters(videoId, title, { desired });
    // Optional key takeaways and quiz fields
    const keyTakeaways = chapters ? chapters.slice(0, 3).map(ch => ch.title) : [];
    const quiz = chapters ? [{ question: 'What is the main chapter?', answer: chapters[0]?.title }] : [];
    res.setHeader('X-Cache', cache);
    return res.json({ videoId, chapters, cached: cache === 'HIT', desired: Number.isFinite(desired) ? desired : null, keyTakeaways, quiz });
  } catch (e) {
    return res.status(500).json({
      error: 'Chapterization failed', detail: e?.message || 'Unknown error', suggestedActions: [
        { label: 'Retry', action: '/api/chapters' },
        { label: 'Request help', action: '/support' }
      ]
    });
  }
});

export function createApp() {
  return app;
}

// Start server in all non-test environments.
// Tests set NODE_ENV='test' in test/_setup.mjs before importing this module.
const isDirectRun = process.env.NODE_ENV !== 'test';
let server = null;

if (isDirectRun) {
  const PORT = process.env.PORT || 3000;
  server = app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Project: ${process.env.PROJECT_ID || 'unknown'}`);
    console.log(`Mock mode: ${(process.env.MOCK_MODE || 'true') === 'true' ? 'enabled' : 'disabled'}`);
    console.log(`Gemini: ${USE_GEMINI_ENV ? `enabled (${GEMINI_MODEL}, timeout=${GEMINI_TIMEOUT_MS}ms)` : 'disabled'}`);
    console.log(`YouTube API key: ${process.env.YT_API_KEY ? 'present' : 'missing'}`);
  });

  // Attach WebSocket server for real-time thread collaboration
  attachWebSocketServer(server);

  server.on('error', (err) => {
    console.error('Server listen error:', err?.message || err);
  });
}

// Connect to MongoDB only if an explicit Atlas URI is provided.
// Skipped in tests (NODE_ENV=test) and when no URI is configured,
// to prevent localhost connection attempts that crash the process after
// the serverSelectionTimeout expires (unhandled buffered-command rejections).
const mongoUri = process.env.MONGODB_URI || '';
const shouldConnectMongo =
  process.env.NODE_ENV !== 'test' &&
  mongoUri.length > 0 &&
  !mongoUri.includes('localhost') &&
  !mongoUri.includes('127.0.0.1');

if (shouldConnectMongo) {
  mongoose.connect(mongoUri, { bufferCommands: false })
    .then(() => {
      console.log('MongoDB connected');
    })
    .catch((err) => {
      console.error('MongoDB connection error:', err?.message || err);
    });
} else if (process.env.NODE_ENV !== 'test') {
  console.warn('MongoDB: no MONGODB_URI configured — lessons persistence disabled.');
}

// ============ LESSON GENERATION & PERSISTENCE ============
// POST /api/generateLesson { query } (userId via middleware)
app.post("/api/generateLesson", userIdMiddleware, async (req, res) => {
  console.log('[POST /api/generateLesson] Authorization:', req.headers.authorization, 'userId:', req.userId);
  const validation = normalizeQueryInput(req.body?.query, MAX_QUERY_LEN);
  if (!validation.ok) return res.status(validation.status).json({ error: validation.error });
  const query = validation.value;
  const userId = req.userId;
  if (!userId) return res.status(400).json({ error: 'query and userId are required' });

  try {
    // 1) Find a video for the query (reuse same logic as /api/search)
    let searchTerm = query;
    const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
    const useGemini = USE_GEMINI_ENV && !breakerActive && (req.body?.useGemini !== false);
    let reformulationTimedOut = false;
    if (useGemini && USE_GEMINI_REFORMULATION) {
      const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
      try {
        let reform = await generateWithGemini(reformPrompt, 32);
        reform = String(reform)
          .split(/\r?\n/)[0]
          .replace(/^[-*•\s>"]+/, "")
          .replace(/["`]+/g, "")
          .trim();
        if (reform && reform.length <= 80) searchTerm = reform;
      } catch (e) {
        if (/timeout/i.test(e.message || "")) reformulationTimedOut = true;
        console.warn("Gemini reformulation (generateLesson) failed:", e.message);
      }
    }

    let videoTitle, videoUrl;
    try {
      const video = await searchYouTube(searchTerm);
      videoTitle = video.title;
      videoUrl = video.url;
    } catch (e) {
      console.warn("Video search (generateLesson) failed:", e.message);
      if ((process.env.ALLOW_FALLBACK || "true") === "true") {
        const mock = makeMockResponse();
        videoTitle = mock.title; videoUrl = mock.videoUrl;
      } else {
        throw e;
      }
    }

    // 2) Summarize into steps and summary text
    let summaryText = "";
    const desiredSteps = extractDesiredSteps(query);
    const attemptGeminiSummary = useGemini && !reformulationTimedOut;
    if (attemptGeminiSummary) {
      const summaryPrompt = desiredSteps
        ? `Résume cette vidéo YouTube en ${desiredSteps} étapes claires: ${videoTitle}`
        : `Résume cette vidéo YouTube en étapes claires: ${videoTitle}`;
      try {
        summaryText = await generateWithGemini(summaryPrompt, 300);
      } catch (e) {
        console.warn("Gemini summary (generateLesson) failed:", e.message);
        summaryText = heuristicSummary({ desiredSteps });
      }
    } else {
      summaryText = heuristicSummary({ desiredSteps });
    }
    const steps = String(summaryText).split("\n").map(s => s.trim()).filter(Boolean);

    // 3) Persist lesson
    // Use Mongoose Lesson model directly
    const Lesson = (await import('./models/lesson.js')).default;
    const User = (await import('./models/User.js')).default;
    const mongoose = (await import('mongoose')).default;
    const lesson = await Lesson.create({ userId, title: videoTitle, steps, videoUrl, summary: summaryText });
    if (mongoose.Types.ObjectId.isValid(userId)) {
      await User.findByIdAndUpdate(userId, { $push: { savedLessons: lesson._id } });
    }
    // 4) Shape response
    return res.json({
      id: lesson._id?.toString() ?? '',
      userId: lesson.userId?.toString() ?? '',
      title: lesson.title?.toString() ?? '',
      summary: lesson.summary?.toString() ?? '',
      steps: Array.isArray(lesson.steps) ? lesson.steps.map(s => s?.toString() ?? '') : [],
      videoUrl: lesson.videoUrl?.toString() ?? '',
      favorite: !!lesson.favorite,
      views: typeof lesson.views === 'number' ? lesson.views : 0,
      createdAt: lesson.createdAt?.toISOString?.() ?? new Date().toISOString(),
      updatedAt: lesson.updatedAt?.toISOString?.() ?? new Date().toISOString(),
    });
  } catch (err) {
    console.error("generateLesson error:", err?.response?.data || err.message || err);
    const statusCode = err?.status || err?.response?.status || 500;
    const detail = err?.message || "Unexpected error";
    return res.status(statusCode).json({ error: statusCode === 404 ? "Not found" : "Internal server error", detail });
  }
});

// Mount lessons, projects routers.
app.use('/api/lessons', lessonsRouter);
app.use('/api/projects', projectsRouter);

app.use((req, res) => {
  return res.status(404).json({ error: 'Not found' });
});

app.use((err, _req, res, next) => {
  if (res.headersSent) return next(err);
  if (err instanceof SyntaxError && Object.prototype.hasOwnProperty.call(err, 'body')) {
    return res.status(400).json({ error: 'Invalid JSON payload' });
  }
  const status = Number(err?.status || err?.statusCode) || 500;
  const detail = err?.message || 'Unexpected error';
  return res.status(status).json({ error: status >= 500 ? 'Internal server error' : 'Request failed', detail });
});

if (isDirectRun) {
  const closeServerGracefully = (signal) => {
    console.log(`Received ${signal}, shutting down gracefully...`);
    const timeout = setTimeout(() => {
      console.error('Graceful shutdown timeout reached, forcing exit');
      process.exit(1);
    }, 10000);

    const finalize = () => {
      clearTimeout(timeout);
      process.exit(0);
    };

    Promise.resolve()
      .then(async () => {
        if (redisClient && typeof redisClient.quit === 'function') {
          await redisClient.quit();
        }
      })
      .catch(() => { })
      .finally(() => {
        if (!server) return finalize();
        server.close(() => finalize());
      });
  };

  process.on('SIGINT', () => closeServerGracefully('SIGINT'));
  process.on('SIGTERM', () => closeServerGracefully('SIGTERM'));
  process.on('unhandledRejection', (reason) => {
    console.error('Unhandled promise rejection:', reason);
  });
}
