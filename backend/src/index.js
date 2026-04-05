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
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "4000");
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
  const modeLabels = {
    cadrer: { rapide: 'Cadrage express', equilibre: 'Cadrage structuré', ambitieux: 'Cadrage complet' },
    produire: { rapide: 'MVP rapide', equilibre: 'Livraison équilibrée', ambitieux: 'Livraison complète' },
    communiquer: { rapide: 'Message direct', equilibre: 'Communication structurée', ambitieux: 'Campagne complète' },
    audit: { rapide: 'Audit flash', equilibre: 'Audit structuré', ambitieux: 'Audit approfondi' },
  };
  const lbl = modeLabels[mode] || modeLabels.produire;
  return [
    {
      key: 'rapide',
      label: lbl.rapide,
      emoji: '⚡',
      description: 'Périmètre minimal, livraison en 24h–48h. Idéal si la deadline est serrée ou le budget limité.',
      estimatedGains: ['Mise en route immédiate', 'Résultat visible rapidement', 'Coût minimal'],
      risks: ['Périmètre réduit, itérations probables', 'Risque qualité si cornerscut'],
      effort: ctx.deadline ? `Adapté à: ${ctx.deadline}` : '~0.5j',
      recommended: !!(ctx.deadline || ctx.budget),
    },
    {
      key: 'equilibre',
      label: lbl.equilibre,
      emoji: '⚖️',
      description: 'Périmètre maîtrisé, qualité et vitesse en équilibre. Recommandé par défaut pour la majorité des missions.',
      estimatedGains: ['Qualité livrable suffisante', 'Risques anticipés', 'Satisfaction client'],
      risks: ['Validation intermédiaire requise', 'Légèrement plus long que le mode express'],
      effort: '~1–2j',
      recommended: !(ctx.deadline || ctx.budget),
    },
    {
      key: 'ambitieux',
      label: lbl.ambitieux,
      emoji: '🚀',
      description: 'Périmètre complet, documentation poussée, critères d\'acceptation stricts. Pour un impact maximal.',
      estimatedGains: ['Impact maximal', 'Livrables réutilisables', 'Alignement long terme'],
      risks: [
        'Délai plus long',
        ctx.budget ? `Potentiellement hors budget: ${ctx.budget}` : 'Risque de dépassement budgétaire',
      ],
      effort: '~3–5j',
      recommended: false,
    },
  ];
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

  switch (mode) {
    case 'communiquer':
      return `Tu es un consultant senior.${ctxLine}${refLine}
Brief client : "${query}"

Rédige un email professionnel directement envoyable au client, en réponse à ce brief.

FORMAT OBLIGATOIRE :
OBJET : [objet email concis et lié au brief]

Bonjour,

[Phrase d'accroche contextualisée — 2 lignes max, mentionne le sujet du brief]

[Développement en 3 points bullet courts et actionnables, spécifiques au brief]

[Call to action clair — 1 phrase qui ouvre la suite]

Cordialement,
[Prénom]

RÈGLES STRICTES : Email directement envoyable sans retouche. Zéro formule creuse. Tous les éléments doivent être spécifiques au brief, pas génériques. 15–20 lignes max.`;

    case 'cadrer':
      return `Tu es un consultant senior mandaté pour cadrer ce projet.${ctxLine}${refLine}
Brief client : "${query}"

Rédige une note de cadrage professionnelle directement transmissible au client.

FORMAT OBLIGATOIRE :
NOTE DE CADRAGE — [TITRE EN MAJUSCULES DÉRIVÉ DU BRIEF]

CONTEXTE & ENJEUX
[2–3 lignes qui résument le contexte et ce qui est en jeu pour CE brief spécifiquement]

LIVRABLES ATTENDUS
• [livrable 1 concret et mesurable]
• [livrable 2 concret et mesurable]
• [livrable 3 si pertinent]

PÉRIMÈTRE
Inclus : [éléments in-scope liés au brief]
Exclu : [éléments hors scope à clarifier]

RISQUES & DÉPENDANCES
• [risque 1 spécifique au brief]
• [risque 2 spécifique au brief]
• [dépendance clé]

PROCHAINES ÉTAPES
1. [action concrète — J0–J1]
2. [action concrète — J1–J2]
3. [action concrète — J2–J3]

RÈGLES STRICTES : Document directement transmissible. Tous les éléments font référence au brief, pas à un projet générique. 20–25 lignes.`;

    case 'audit':
      return `Tu es un auditeur senior.${ctxLine}${refLine}
Brief client : "${query}"

Rédige une synthèse d'audit flash directement partageable au client.

FORMAT OBLIGATOIRE :
SYNTHÈSE D'AUDIT — [TITRE EN MAJUSCULES DÉRIVÉ DU BRIEF]

POINTS DIAGNOSTIQUÉS
🔴 [point critique 1 — spécifique au brief]
🔴 [point critique 2 si pertinent]
🟡 [point à corriger 1]
🟡 [point à corriger 2]
🟢 [quick win identifié]

QUICK WINS PRIORITAIRES
1. [action immédiate 1 — impact élevé, effort faible — lié au brief]
2. [action immédiate 2]
3. [action immédiate 3]

PLAN D'ACTION 7 JOURS
J0–J1 : [focus spécifique]
J2–J3 : [focus spécifique]
J4–J5 : [focus spécifique]
J6–J7 : [livraison rapport]

CRITÈRES DE CLÔTURE
☑ [critère 1 mesurable et lié au brief]
☑ [critère 2 mesurable]
☑ [critère 3]

RÈGLES STRICTES : Synthèse directement partageable. Tous les éléments font référence au brief. 22–28 lignes.`;

    default: // produire
      return `Tu es un chef de projet senior.${ctxLine}${refLine}
Brief client : "${query}"

Rédige un plan de livraison professionnel directement transmissible au client.

FORMAT OBLIGATOIRE :
PLAN DE LIVRAISON — [TITRE EN MAJUSCULES DÉRIVÉ DU BRIEF]

OBJECTIF
[Objectif SMART en 1–2 lignes, directement lié au brief]

TÂCHES PRIORITAIRES
1. [tâche critique 1 — J0] ⚠ bloquante
2. [tâche 2 — J1–J2]
3. [tâche 3 — J2–J3]
4. [tâche 4 — J3–J4]

TIMELINE
• J0 : [démarrage — action concrète]
• J1–J2 : [exécution — focus]
• J3 : [revue qualité]
• J4 : [livraison finale]

CRITÈRES D'ACCEPTATION
☑ [critère 1 mesurable et lié au brief]
☑ [critère 2 mesurable]
☑ [critère 3]

RISQUES
⚠ [risque 1 spécifique au brief]
⚠ [risque 2]

RÈGLES STRICTES : Document directement transmissible. Tous les éléments font référence au brief, pas à un projet générique. 25–30 lignes.`;
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
      try {
        // Always try to generate the full deliverable document first
        const deliverablePrompt = buildGeminiPromptForMode({ mode: deliveryMode, query, context: requestContext, videoTitle });
        const fullDoc = await generateWithGemini(deliverablePrompt, 600);
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
      if (attemptGeminiSummary) {
        const deliverablePrompt = buildGeminiPromptForMode({ mode: deliveryMode, query, context: requestContext, videoTitle });
        try {
          const fullDoc = await generateWithGemini(deliverablePrompt, 600);
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

// Mount lessons and users routers.
app.use('/api/lessons', lessonsRouter);

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
