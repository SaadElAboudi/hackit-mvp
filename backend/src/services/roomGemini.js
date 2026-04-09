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
    return;
  }

  // Signal that AI is "typing" so everyone sees the indicator
  broadcastRoomTyping(roomId, 'ai');

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

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

    const text =
      data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ||
      "Je n'ai pas pu générer de réponse.";

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

    broadcastRoomMessage(roomId, aiMsg.toObject());
  } catch (err) {
    console.error(
      '[roomGemini] Gemini error:',
      err?.response?.data || err?.message
    );
    // Notify the room so users know something went wrong
    const errMsg = await RoomMessage.create({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      content:
        "Désolé, je n'ai pas pu répondre pour l'instant. Réessayez dans un moment.",
      type: 'text',
    });
    broadcastRoomMessage(roomId, errMsg.toObject());
  }
}
