/**
 * roomGemini.js — AI colleague integration for Salons rooms.
 *
 * Triggered when a room message contains "@ia" (case-insensitive).
 * The AI responds as a peer participant, posting a RoomMessage with isAI=true.
 *
 * If the AI response appears to be a structured document (starts with a
 * markdown heading), the message type is set to 'document' so the frontend
 * can render it as a challengeable deliverable.
 */

import axios from 'axios';
import RoomMessage from '../models/RoomMessage.js';
import { broadcastRoomMessage, broadcastRoomTyping } from './roomWS.js';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'models/gemini-2.0-flash-lite';
const GEMINI_TIMEOUT_MS = parseInt(process.env.GEMINI_TIMEOUT_MS || '30000', 10);
const MAX_HISTORY = 20;

// roomId -> epoch ms until next allowed Gemini request
const roomRetryAfterUntil = new Map();

function parseRetryDelayMs(errData) {
  const msg = errData?.error?.message || '';
  const m = String(msg).match(/Please retry in\s+([0-9]+(?:\.[0-9]+)?)s\.?/i);
  if (!m) return null;
  const seconds = Number(m[1]);
  if (!Number.isFinite(seconds)) return null;
  return Math.max(1000, Math.ceil(seconds * 1000));
}

async function persistAndBroadcastAIMessage(roomId, content, { isDocument = false, documentTitle } = {}) {
  const msg = await RoomMessage.create({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: isDocument ? 'document' : 'text',
    ...(documentTitle ? { documentTitle } : {}),
  });
  broadcastRoomMessage(roomId, msg.toObject());
}

// ── Local heuristic fallback ──────────────────────────────────────────────────
// Used when Gemini is unavailable (quota / API key missing / timeout).
// Reads the triggering message + room context to produce a structured,
// context-aware response. Not AI quality, but always useful.

function _capitalize(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
}

function buildHeuristicResponse(room, recentMessages) {
  // Find the last human message that mentioned @ia
  const triggerMsg = [...recentMessages]
    .reverse()
    .find((m) => !m.isAI && /@ia\b/i.test(m.content));

  const rawQuery = (triggerMsg?.content ?? '')
    .replace(/@ia\b/gi, '')
    .replace(/[?!.]+$/, '')
    .trim();

  const roomName = room.name || 'Salon';

  // ── Intent detection ────────────────────────────────────────────────────────
  const isDocRequest = /r[eé]dig|[eé]cri[st]|g[eé]n[eè]re?|cr[eé][eé]?|produ[it]s?|plan\b|rapport\b|brief\b|cahier\b|compte.rendu|note\b|fiche\b|analyse\b|synth[eè]se|livrable|template|modèle/i.test(rawQuery);
  const isBrainstorm = /id[eé]e[s]?|suggestion[s]?|approche[s]?|option[s]?|alternative[s]?|piste[s]?|propose[sz]?|brainstorm/i.test(rawQuery);
  const isQuestion = /\?/.test(rawQuery) || /^(comment|pourquoi|qu['\s]est|quoi|quand|qui|o[uù]|combien|lequel|laquelle|lesquels|expliqu|d[eé]fin|montre)/i.test(rawQuery);

  // ── Response by intent ──────────────────────────────────────────────────────
  if (isDocRequest) {
    const title = rawQuery.length > 4 ? _capitalize(rawQuery) : `Document — ${roomName}`;
    return {
      content: [
        `# ${title}`,
        '',
        `## Contexte`,
        `Salon : **${roomName}**`,
        '',
        `## Objectifs`,
        `- Définir le périmètre et les enjeux`,
        `- Identifier les parties prenantes`,
        `- Lister les livrables attendus`,
        '',
        `## Plan proposé`,
        `1. **Cadrage** — Comprendre les contraintes et critères de succès`,
        `2. **Diagnostic** — État de l'existant et points de blocage`,
        `3. **Solutions** — Options identifiées et recommandations`,
        `4. **Plan d'action** — Étapes, responsables, délais`,
        '',
        `## Prochaines étapes`,
        `- Valider ce plan avec l'équipe`,
        `- Affiner chaque section selon le contexte`,
        '',
        `> *Mode hors-ligne (quota Gemini épuisé) — structure générique à compléter. Réessayez @ia pour une version IA complète.*`,
      ].join('\n'),
      isDocument: true,
      documentTitle: title,
    };
  }

  if (isBrainstorm) {
    const topic = rawQuery
      .replace(/id[eé]e[s]?\s*(sur|pour|de|à propos)?|suggestion[s]?\s*(sur|pour)?|approche[s]?\s*(pour)?|propose[sz]?\s*/gi, '')
      .trim() || roomName;
    return {
      content: [
        `Quelques pistes sur **${topic}** :`,
        '',
        `1. **Explorer l'existant** — Recenser ce qui a déjà été tenté, identifier les écueils.`,
        `2. **Impliquer les parties prenantes** — Consulter ceux qui seront impactés en premier.`,
        `3. **Prioriser par impact/effort** — Matrice impact vs effort pour choisir par où commencer.`,
        `4. **Prototyper rapidement** — Tester une version minimale avant de généraliser.`,
        `5. **Itérer en équipe** — Cycles courts de feedback pour corriger le tir.`,
        '',
        `> *Mode hors-ligne (quota Gemini épuisé) — idées génériques. Réessayez @ia pour une génération contextuelle complète.*`,
      ].join('\n'),
      isDocument: false,
    };
  }

  if (isQuestion) {
    const topic = rawQuery
      .replace(/^(comment|pourquoi|qu['\s]est-ce|quoi|quand|qui|o[uù]|combien|expliqu[eé]r?|d[eé]finir?|montre[rz]?)\s*/i, '')
      .trim() || rawQuery;
    return {
      content: [
        `Concernant **${topic || 'votre question'}** :`,
        '',
        `- Clarifier avec l'équipe pour s'aligner sur le périmètre exact`,
        `- Identifier les sources disponibles (documents, experts, données)`,
        `- Distinguer ce qui est certain de ce qui est à valider`,
        `- Définir une hypothèse de travail pour avancer sans attendre`,
        '',
        `> *Mode hors-ligne (quota Gemini épuisé) — réponse générique. Réessayez @ia pour une analyse IA.*`,
      ].join('\n'),
      isDocument: false,
    };
  }

  // Generic acknowledgement
  const preview = rawQuery ? `*"${rawQuery.slice(0, 80)}"*` : '*(mention @ia)*';
  return {
    content: [
      `Message reçu : ${preview}`,
      '',
      `En mode hors-ligne (quota Gemini épuisé), je peux vous aider à structurer :`,
      `- **Questions clés** à résoudre en équipe`,
      `- **Plan d'action** à décomposer en tâches`,
      `- **Document** à rédiger (utilisez "@ia rédige …" pour générer un livrable)`,
      '',
      `Réessayez avec @ia dans quelques instants pour une réponse IA complète.`,
    ].join('\n'),
    isDocument: false,
  };
}

/**
 * Trigger the AI colleague to respond in a room.
 *
 * @param {object} room          - plain Room object (lean or toObject)
 * @param {Array}  recentMessages - last N room messages (already includes the triggering one)
 * @param {string} roomId        - string representation of room._id
 */
export async function triggerRoomAI(room, recentMessages, roomId) {
  if (!GEMINI_API_KEY) {
    console.warn('[roomGemini] GEMINI_API_KEY not set — using heuristic fallback');
    const fallback = buildHeuristicResponse(room, recentMessages);
    await persistAndBroadcastAIMessage(roomId, fallback.content, fallback);
    return;
  }

  const now = Date.now();
  const blockedUntil = roomRetryAfterUntil.get(roomId) || 0;
  if (blockedUntil > now) {
    const waitSec = Math.max(1, Math.ceil((blockedUntil - now) / 1000));
    console.warn(`[roomGemini] cooldown active room=${roomId} (${waitSec}s left) — using heuristic fallback`);
    const fallback = buildHeuristicResponse(room, recentMessages);
    // Append cooldown note to fallback content
    const note = `\n> *(Quota Gemini épuisé — réponse disponible dans ~${waitSec}s)*`;
    await persistAndBroadcastAIMessage(roomId, fallback.content + note, fallback);
    return;
  }

  const maskedKey = GEMINI_API_KEY.slice(0, 6) + '***' + GEMINI_API_KEY.slice(-4);
  console.log(`[roomGemini] triggerRoomAI room=${roomId} model=${GEMINI_MODEL} key=${maskedKey} historySize=${recentMessages.length}`);

  // Signal that AI is "typing" so everyone sees the indicator
  broadcastRoomTyping(roomId, 'ai');

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  console.log(`[roomGemini] POST ${geminiUrl.replace(GEMINI_API_KEY, '***')}`);

  const roomName = room.name || 'Salon';
  const directives = room.aiDirectives?.trim()
    ? `\nDirectives des membres du salon :\n${room.aiDirectives}\n`
    : '';

  const history = recentMessages
    .slice(-MAX_HISTORY)
    .map((m) => `[${m.isAI ? 'IA' : m.senderName}]: ${m.content}`)
    .join('\n');

  const systemPrompt =
    `Tu es IA, un collègue IA intégré dans un salon de discussion collaboratif nommé "${roomName}". ` +
    `Tu es un participant à part entière, au même titre que les humains. ` +
    `Tu réponds uniquement quand on t'interpelle (via @ia). Sois concis et utile. ` +
    `Si tu produis un document structuré (plan, rapport, cahier des charges, analyse, etc.), ` +
    `commence par un titre principal en markdown (ex: # Titre du document) afin qu'il soit ` +
    `reconnu comme un livrable challengeable par les membres.` +
    directives;

  const fullPrompt = `${systemPrompt}\n\nHistorique de la conversation :\n${history}`;

  try {
    const { data } = await axios.post(
      geminiUrl,
      {
        contents: [{ role: 'user', parts: [{ text: fullPrompt }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 2048 },
      },
      { timeout: GEMINI_TIMEOUT_MS }
    );

    console.log(`[roomGemini] Gemini response received — candidates: ${data?.candidates?.length ?? 0} finishReason: ${data?.candidates?.[0]?.finishReason}`);

    const text =
      data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ||
      "Je n'ai pas pu générer de réponse.";

    console.log(`[roomGemini] AI text length=${text.length} isDocument=${/^#{1,3}\s+\S/.test(text)} preview="${text.slice(0, 80).replace(/\n/g, '↵')}"`);

    // Detect document: starts with a markdown heading OR has 2+ ## sections
    const isDocument =
      /^#{1,3}\s+\S/.test(text) || (text.match(/^#{1,3} /gm) || []).length >= 2;

    const documentTitle = isDocument
      ? text.split('\n')[0].replace(/^#+\s*/, '').trim()
      : undefined;

    const aiMsg = await RoomMessage.create({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      content: text,
      type: isDocument ? 'document' : 'text',
      documentTitle,
    });

    console.log(`[roomGemini] AI message saved id=${aiMsg._id} type=${aiMsg.type}`);
    broadcastRoomMessage(roomId, aiMsg.toObject());
  } catch (err) {
    const errStatus = err?.response?.status;
    const errData = err?.response?.data;
    const errMessage = err?.message;
    const errCode = err?.code; // e.g. ECONNABORTED for timeout
    console.error('[roomGemini] GEMINI CALL FAILED:', {
      status: errStatus,
      code: errCode,
      message: errMessage,
      geminiError: errData?.error ?? errData,
    });

    // Respect server-advised retry window on quota/rate limits.
    if (errStatus === 429) {
      const retryDelayMs = parseRetryDelayMs(errData) || 45000;
      roomRetryAfterUntil.set(roomId, Date.now() + retryDelayMs);
      const waitSec = Math.max(1, Math.ceil(retryDelayMs / 1000));
      console.warn(`[roomGemini] 429 quota/rate-limit room=${roomId} retryIn=${waitSec}s — using heuristic fallback`);
      const fallback = buildHeuristicResponse(room, recentMessages);
      const note = `\n> *(Quota Gemini épuisé — réponse IA disponible dans ~${waitSec}s)*`;
      await persistAndBroadcastAIMessage(roomId, fallback.content + note, fallback);
      return;
    }

    // Timeout or other unexpected error — still give a useful heuristic response
    console.warn(`[roomGemini] non-quota error (${errCode || errStatus}) — using heuristic fallback`);
    const fallback = buildHeuristicResponse(room, recentMessages);
    const note = '\n> *(Mode hors-ligne — réponse heuristique, réessayez @ia dans un instant)*';
    await persistAndBroadcastAIMessage(roomId, fallback.content + note, fallback);
  }
}
