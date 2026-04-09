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

async function persistAndBroadcastAIMessage(roomId, content) {
  const msg = await RoomMessage.create({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'text',
  });
  broadcastRoomMessage(roomId, msg.toObject());
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
    console.warn('[roomGemini] GEMINI_API_KEY not set — skipping AI response');
    await persistAndBroadcastAIMessage(
      roomId,
      "Je ne suis pas configuree (GEMINI_API_KEY manquante). Contactez l'administrateur."
    );
    return;
  }

  const now = Date.now();
  const blockedUntil = roomRetryAfterUntil.get(roomId) || 0;
  if (blockedUntil > now) {
    const waitSec = Math.max(1, Math.ceil((blockedUntil - now) / 1000));
    console.warn(`[roomGemini] cooldown active room=${roomId}, skip external call for ${waitSec}s`);
    await persistAndBroadcastAIMessage(
      roomId,
      `Quota IA temporairement depasse. Reessayez dans environ ${waitSec}s.`
    );
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
      const nextTryAt = Date.now() + retryDelayMs;
      roomRetryAfterUntil.set(roomId, nextTryAt);
      const waitSec = Math.max(1, Math.ceil(retryDelayMs / 1000));
      console.warn(`[roomGemini] 429 quota/rate-limit room=${roomId} retryIn=${waitSec}s`);
      await persistAndBroadcastAIMessage(
        roomId,
        `Je suis limitee par le quota Gemini (429). Reessayez dans environ ${waitSec}s, ou activez la facturation/augmentez le quota API.`
      );
      return;
    }

    await persistAndBroadcastAIMessage(
      roomId,
      "Desole, je n'ai pas pu repondre pour l'instant. Reessayez dans un moment."
    );
  }
}
