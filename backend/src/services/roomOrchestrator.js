import Room from '../models/Room.js';
import RoomMessage from '../models/RoomMessage.js';
import RoomArtifact from '../models/RoomArtifact.js';
import ArtifactVersion from '../models/ArtifactVersion.js';
import RoomMission from '../models/RoomMission.js';
import RoomMemory from '../models/RoomMemory.js';

import { getChapters } from './chapters.js';
import { generateWithGemini, streamWithGemini } from './gemini.js';
import { getTranscript } from './transcript.js';
import { buildSlackShareText, postSlackMessage } from './slack.js';
import { createNotionPage } from './notion.js';
import {
  broadcastRoomArtifactCreated,
  broadcastRoomArtifactVersionCreated,
  broadcastRoomDecisionCreated,
  broadcastRoomMessage,
  broadcastRoomMessageChunk,
  broadcastRoomMissionStatus,
  broadcastRoomBriefSuggested,
  broadcastRoomResearchAttached,
  broadcastRoomSynthesisSuggested,
  broadcastRoomTyping,
  broadcastRoomShareResult,
  broadcastRoomNotionExported,
} from './roomWS.js';
import { searchYouTube } from './youtube.js';

const MAX_CONTEXT_MESSAGES = 18;
const MAX_CONTEXT_ARTIFACTS = 3;
const MAX_CONTEXT_MEMORY = 6;
const SYNTHESIS_TRIGGER_EVERY = Number(process.env.ROOM_SYNTHESIS_TRIGGER_EVERY || 8);
const SYNTHESIS_COOLDOWN_MS = Number(process.env.ROOM_SYNTHESIS_COOLDOWN_MS || 20 * 60 * 1000);
const BRIEF_TRIGGER_EVERY = Number(process.env.ROOM_BRIEF_TRIGGER_EVERY || 4);
const BRIEF_COOLDOWN_MS = Number(process.env.ROOM_BRIEF_COOLDOWN_MS || 30 * 60 * 1000);
const MEETING_SIGNAL_REGEX = /(r[ée]union|meeting|kick\s?off|standup|comit[ée]|call|point\s+client|rdv)/i;
const MISSION_AGENT_PROFILES = {
  auto: {
    type: 'auto',
    label: 'Agent auto',
    instruction:
      'Choisis la posture la plus utile selon la demande et rends un livrable directement exploitable.',
  },
  strategist: {
    type: 'strategist',
    label: 'Strategist',
    instruction:
      'Travaille comme un stratège produit ou business. Clarifie objectifs, arbitrages, priorités, risques et plan d’exécution.',
  },
  researcher: {
    type: 'researcher',
    label: 'Researcher',
    instruction:
      'Travaille comme un chercheur. Structure hypothèses, signaux, comparatifs, sources potentielles et zones d’incertitude.',
  },
  facilitator: {
    type: 'facilitator',
    label: 'Facilitator',
    instruction:
      'Travaille comme un facilitateur d’équipe. Prépare alignement, décisions à trancher, agenda, next steps et responsabilités.',
  },
  analyst: {
    type: 'analyst',
    label: 'Analyst',
    instruction:
      'Travaille comme un analyste. Décompose le problème, formule diagnostics, métriques, scénarios et recommandations argumentées.',
  },
  writer: {
    type: 'writer',
    label: 'Writer',
    instruction:
      'Travaille comme un rédacteur senior. Produis un document clair, structuré, prêt à partager, avec formulation précise et ton professionnel.',
  },
};

function clip(text, max = 240) {
  const value = String(text || '').trim();
  if (!value) return '';
  return value.length > max ? `${value.slice(0, max - 1)}…` : value;
}

function slugTitle(text, fallback) {
  const cleaned = clip(text, 120).replace(/^#+\s*/, '');
  return cleaned || fallback;
}

function headingTitle(text, fallback) {
  const match = String(text || '').match(/^#\s+(.+)$/m);
  return slugTitle(match?.[1], fallback);
}

function stripCommandPrefix(text, prefix) {
  return String(text || '').replace(prefix, '').trim();
}

function isDocLikePrompt(text) {
  return /r[eé]dige|document|canvas|brief|note|plan|sp[eé]c|spec|cahier|roadmap|synth[eè]se|rapport/i.test(
    String(text || '')
  );
}

function inferFallbackPrompt(triggeringMessage, recentMessages) {
  const latestHuman = [...recentMessages]
    .reverse()
    .find((msg) => !msg.isAI && String(msg.content || '').trim());
  return (
    clip(triggeringMessage?.content || '', 1000) ||
    clip(latestHuman?.content || '', 1000) ||
    'Aide l’équipe à avancer.'
  );
}

export function normalizeMissionAgentType(value = '') {
  const raw = String(value || '').trim().toLowerCase();
  return MISSION_AGENT_PROFILES[raw] ? raw : 'auto';
}

export function inferMissionAgentType(prompt = '') {
  const text = String(prompt || '').toLowerCase();
  if (!text) return 'auto';
  if (/(r[eé]union|atelier|alignement|facilit|standup|kickoff|kick-off|agenda|d[eé]cision)/i.test(text)) {
    return 'facilitator';
  }
  if (/(benchmark|research|cherche|analyse march[eé]|veille|source|comparatif|concurrent)/i.test(text)) {
    return 'researcher';
  }
  if (/(kpi|metric|m[eé]trique|funnel|data|diagnostic|analyse|chiffr|cohort|retention)/i.test(text)) {
    return 'analyst';
  }
  if (/(note|brief|r[eé]dige|document|sp[eé]c|spec|copy|announce|email|memo|pr[ée]sentation)/i.test(text)) {
    return 'writer';
  }
  if (/(go[- ]to[- ]market|gtm|roadmap|priori|strat[eé]gie|positionnement|lancement|plan)/i.test(text)) {
    return 'strategist';
  }
  return 'auto';
}

export function resolveMissionAgentProfile({ prompt = '', agentType = 'auto' } = {}) {
  const normalized = normalizeMissionAgentType(agentType);
  const resolvedType = normalized === 'auto' ? inferMissionAgentType(prompt) : normalized;
  return MISSION_AGENT_PROFILES[resolvedType] || MISSION_AGENT_PROFILES.auto;
}

export function parseRoomCommand(rawContent = '') {
  const content = String(rawContent || '').trim();
  if (!content) return { kind: 'none', prompt: '', raw: content };

  if (/^\/doc\b/i.test(content)) {
    return {
      kind: 'doc',
      prompt: stripCommandPrefix(content, /^\/doc\b/i),
      raw: content,
    };
  }
  if (/^\/mission\b/i.test(content)) {
    return {
      kind: 'mission',
      prompt: stripCommandPrefix(content, /^\/mission\b/i),
      raw: content,
    };
  }
  if (/^\/search\b/i.test(content)) {
    return {
      kind: 'search',
      prompt: stripCommandPrefix(content, /^\/search\b/i),
      raw: content,
    };
  }
  if (/^\/decide\b/i.test(content)) {
    return {
      kind: 'decide',
      prompt: stripCommandPrefix(content, /^\/decide\b/i),
      raw: content,
    };
  }
  if (/^\/brief\b/i.test(content)) {
    return {
      kind: 'brief',
      prompt: stripCommandPrefix(content, /^\/brief\b/i),
      raw: content,
    };
  }
  if (/^\/share\b/i.test(content)) {
    return {
      kind: 'share',
      prompt: stripCommandPrefix(content, /^\/share\b/i),
      raw: content,
    };
  }
  if (/@ia\b/i.test(content)) {
    return {
      kind: 'ai',
      prompt: content.replace(/@ia\b/gi, '').trim(),
      raw: content,
    };
  }

  return { kind: 'none', prompt: content, raw: content };
}

export function buildTranscriptCitations({ videoUrl, transcript = [], max = 3 }) {
  const items = Array.isArray(transcript) ? transcript.filter((entry) => entry?.text) : [];
  return items.slice(0, Math.max(1, max)).map((entry, index) => {
    const startSec = Number(entry.startSec || 0);
    const next = items[index + 1];
    const endSec = Number(next?.startSec || startSec + 30);
    const separator = String(videoUrl || '').includes('?') ? '&' : '?';
    return {
      quote: clip(entry.text, 180),
      startSec,
      endSec,
      url: `${videoUrl}${separator}t=${startSec}`,
    };
  });
}

function extractSectionList(markdown, titleRegex) {
  const text = String(markdown || '');
  const match = text.match(titleRegex);
  if (!match) return [];
  const body = match[1] || '';
  return body
    .split('\n')
    .map((line) => line.trim().replace(/^[-*]\s*/, ''))
    .filter(Boolean)
    .slice(0, 6);
}

function buildHeuristicReply({ roomName, prompt, command, missionAgentLabel = 'Agent auto' }) {
  const topic = clip(prompt || roomName, 120);
  if (command === 'doc') {
    return [
      `# ${slugTitle(topic, `Canvas ${roomName}`)}`,
      '',
      '## Contexte',
      `- Channel: ${roomName}`,
      `- Sujet: ${topic}`,
      '',
      '## Objectifs',
      '- Aligner rapidement les participants',
      '- Clarifier le livrable attendu',
      '- Poser une base révisable en équipe',
      '',
      '## Prochaine version',
      '- Compléter avec les contraintes métier',
      '- Définir les décisions à valider',
      '- Attribuer les prochaines actions',
    ].join('\n');
  }

  if (command === 'decide') {
    return [
      '# Synthèse de décision',
      '',
      '## Décisions',
      `- Avancer sur ${topic}`,
      '- Centraliser les échanges dans le channel',
      '- Valider rapidement une première version',
      '',
      '## Risques',
      '- Portée encore floue',
      '- Hypothèses non confirmées',
      '- Dépendances externes à préciser',
      '',
      '## Next steps',
      '- Confirmer le périmètre',
      '- Produire un document partageable',
      '- Revenir avec une révision après feedback',
    ].join('\n');
  }

  if (command === 'mission') {
    return [
      `# Mission IA — ${slugTitle(topic, 'Mission partagée')}`,
      '',
      `## Agent`,
      `- ${missionAgentLabel}`,
      '',
      '## Résultat',
      '- Analyse initiale produite',
      '- Plan d’action priorisé',
      '- Points à confirmer par l’équipe',
      '',
      '## Actions proposées',
      '1. Vérifier le besoin réel',
      '2. Valider le niveau de détail attendu',
      '3. Convertir ceci en artefact si besoin',
    ].join('\n');
  }

  return [
    `Je suis présent dans **${roomName}** pour aider sur **${topic}**.`,
    '',
    '- Je peux structurer la discussion',
    '- Transformer l’échange en document avec `/doc`',
    '- Synthétiser des décisions avec `/decide`',
    '- Chercher une source avec `/search`',
  ].join('\n');
}

function isCommandLike(text = '') {
  const value = String(text || '').trim();
  return /^\//.test(value) || /@ia\b/i.test(value);
}

export function buildSynthesisSuggestion({ roomName, lines = [] }) {
  const picked = (Array.isArray(lines) ? lines : [])
    .map((line) => clip(line, 180))
    .filter(Boolean)
    .slice(0, 6);
  if (!picked.length) {
    return [
      `# Suggestion de synthèse — ${roomName || 'Channel'}`,
      '',
      '## Résumé rapide',
      '- Peu de signaux exploitables détectés sur les derniers échanges.',
      '',
      '## Prochaines actions proposées',
      '- Clarifier le blocage principal',
      '- Nommer un responsable par action',
      '- Fixer une échéance de validation',
    ].join('\n');
  }
  return [
    `# Suggestion de synthèse — ${roomName || 'Channel'}`,
    '',
    '## Points saillants détectés',
    ...picked.slice(0, 4).map((line) => `- ${line}`),
    '',
    '## Prochaines actions proposées',
    '- Convertir les points validés en `/decide`',
    '- Structurer le livrable en `/doc`',
    '- Vérifier les zones d’incertitude avec `/search`',
  ].join('\n');
}

export function buildMeetingBrief({ roomName, lines = [], objective = '' }) {
  const picked = (Array.isArray(lines) ? lines : [])
    .map((line) => clip(line, 180))
    .filter(Boolean)
    .slice(0, 6);
  const focus = clip(objective || roomName || 'réunion à venir', 120);
  return [
    `# Brief automatique avant réunion — ${roomName || 'Channel'}`,
    '',
    `## Objectif du point`,
    `- ${focus}`,
    '',
    '## Points à aligner',
    ...(picked.slice(0, 4).map((line) => `- ${line}`)),
    ...(picked.length ? [] : ['- Aucun signal clair détecté, clarifier les priorités en ouverture']),
    '',
    '## Décisions à trancher',
    '- Confirmer le périmètre du livrable',
    '- Valider propriétaire et échéance par action',
    '',
    '## Questions critiques',
    '- Quel est le risque principal si on ne livre pas cette semaine ?',
    '- Quelle décision doit être prise pendant ce point ?',
    '',
    '## Prochaine étape',
    '- Convertir le résultat du point en `/decide` puis en `/doc`',
  ].join('\n');
}

async function tryGemini(prompt, maxOutputTokens = 900) {
  if (!process.env.GEMINI_API_KEY) return null;
  try {
    return await generateWithGemini(prompt, maxOutputTokens);
  } catch (error) {
    console.warn('[roomOrchestrator] Gemini fallback:', error?.message || error);
    return null;
  }
}

/**
 * Like tryGemini but streams token-by-token via WS.
 * onChunk(cumulativeText) is throttled to ~12 updates/s to avoid WS flood.
 * Returns the full text (same as tryGemini), or null if streaming fails.
 */
async function tryGeminiStreaming(prompt, roomId, tempId, maxOutputTokens = 900) {
  if (!process.env.GEMINI_API_KEY) return null;
  try {
    let lastBcast = 0;
    const text = await streamWithGemini(
      prompt,
      (cumulative) => {
        const now = Date.now();
        if (now - lastBcast >= 80) { // max ~12 WS frames/s per AI stream
          broadcastRoomMessageChunk(roomId, tempId, cumulative);
          lastBcast = now;
        }
      },
      maxOutputTokens
    );
    if (text) broadcastRoomMessageChunk(roomId, tempId, text); // final flush
    return text;
  } catch (err) {
    console.warn('[roomOrchestrator] streaming fallback:', err?.message || err);
    return null;
  }
}

async function collectRoomContext(roomId) {
  const [messages, artifacts, memories] = await Promise.all([
    RoomMessage.find({ roomId })
      .sort({ createdAt: -1 })
      .limit(MAX_CONTEXT_MESSAGES)
      .lean(),
    RoomArtifact.find({ roomId })
      .sort({ updatedAt: -1 })
      .limit(MAX_CONTEXT_ARTIFACTS)
      .lean(),
    RoomMemory.find({ roomId })
      .sort({ pinned: -1, createdAt: -1 })
      .limit(MAX_CONTEXT_MEMORY)
      .lean(),
  ]);

  const versionIds = artifacts
    .map((artifact) => artifact.currentVersionId)
    .filter(Boolean);
  const versions = versionIds.length
    ? await ArtifactVersion.find({ _id: { $in: versionIds } }).lean()
    : [];
  const versionsById = new Map(versions.map((version) => [String(version._id), version]));

  return {
    messages: messages.reverse(),
    artifacts: artifacts.map((artifact) => ({
      ...artifact,
      currentVersion: artifact.currentVersionId
        ? versionsById.get(String(artifact.currentVersionId)) || null
        : null,
    })),
    memories,
  };
}

function formatContextForPrompt({ room, context }) {
  const messages = context.messages
    .map((message) => `[${message.isAI ? 'IA' : message.senderName}]: ${clip(message.content, 500)}`)
    .join('\n');
  const artifacts = context.artifacts
    .map((artifact) => {
      const version = artifact.currentVersion;
      const content = version?.content ? clip(version.content, 500) : '';
      return `- ${artifact.title} (${artifact.kind})\n${content}`;
    })
    .join('\n');
  const memories = context.memories
    .map((memory) => `- [${memory.type}] ${clip(memory.content, 180)}`)
    .join('\n');

  return [
    `Nom du channel: ${room.name || 'Channel'}`,
    room.purpose ? `Purpose: ${room.purpose}` : '',
    room.aiDirectives ? `Directives: ${room.aiDirectives}` : '',
    messages ? `Conversation récente:\n${messages}` : '',
    artifacts ? `Artefacts partagés:\n${artifacts}` : '',
    memories ? `Mémoire du channel:\n${memories}` : '',
  ]
    .filter(Boolean)
    .join('\n\n');
}

async function touchRoom(roomId) {
  await Room.findByIdAndUpdate(roomId, {
    $set: { lastActivityAt: new Date(), updatedAt: new Date() },
  }).catch(() => undefined);
}

async function persistRoomMessage({
  roomId,
  senderId,
  senderName,
  isAI,
  content,
  type,
  documentTitle,
  data = {},
  tempId = null, // streaming placeholder ID — included in broadcast so client can replace it
}) {
  const message = await RoomMessage.create({
    roomId,
    senderId,
    senderName,
    isAI,
    content,
    type,
    documentTitle,
    data,
  });
  // Include tempId in the broadcast payload so Flutter can swap the streaming
  // placeholder (keyed by tempId) with the final persisted message.
  broadcastRoomMessage(roomId, { ...message.toObject(), tempId });
  await touchRoom(roomId);
  return message;
}

function summariseVersion(version) {
  const json = version.toObject ? version.toObject() : version;
  return {
    ...json,
    contentPreview: clip(json.content, 180),
  };
}

export async function createRoomArtifact({
  roomId,
  title,
  content,
  kind = 'canvas',
  createdBy,
  createdByName,
  sourcePrompt = '',
  sourceMessageId = null,
  isAI = false,
  senderId,
  senderName,
  status = 'draft',
  tempId = null, // streaming placeholder ID forwarded to persistRoomMessage
}) {
  const artifact = await RoomArtifact.create({
    roomId,
    title: slugTitle(title, 'Canvas partagé'),
    kind,
    status,
    createdBy,
    sourcePrompt: clip(sourcePrompt, 4000),
    sourceMessageId,
  });

  const versionCount = await ArtifactVersion.countDocuments({ artifactId: artifact._id });
  const version = await ArtifactVersion.create({
    artifactId: artifact._id,
    roomId,
    number: versionCount + 1,
    content,
    createdBy,
    sourcePrompt: clip(sourcePrompt, 4000),
    status: status === 'validated' ? 'approved' : 'draft',
  });

  artifact.currentVersionId = version._id;
  await artifact.save();

  const message = await persistRoomMessage({
    roomId,
    senderId: senderId || (isAI ? 'ai' : createdBy),
    senderName: senderName || (isAI ? 'IA' : createdByName || 'Anonyme'),
    isAI,
    content,
    type: 'artifact',
    documentTitle: artifact.title,
    tempId,
    data: {
      artifactId: artifact._id,
      artifactKind: kind,
      versionId: version._id,
      status,
      why: isAI
        ? 'Artefact généré par l’IA partagée à la demande du channel.'
        : 'Artefact partagé manuellement dans le channel.',
    },
  });

  broadcastRoomArtifactCreated(roomId, artifact.toObject(), summariseVersion(version));
  broadcastRoomArtifactVersionCreated(roomId, String(artifact._id), summariseVersion(version));
  await touchRoom(roomId);

  return { artifact, version, message };
}

export async function reviseRoomArtifact({
  room,
  artifact,
  instructions,
  changeSummary = '',
  actor,
}) {
  const currentVersion = artifact.currentVersionId
    ? await ArtifactVersion.findById(artifact.currentVersionId)
    : null;

  if (!currentVersion) {
    throw new Error('Artifact has no current version');
  }

  const context = await collectRoomContext(String(room._id || room.id));
  const prompt = [
    'Tu révises un artefact partagé dans un channel collaboratif.',
    `Titre: ${artifact.title}`,
    `Instructions: ${instructions}`,
    '',
    'Version actuelle:',
    currentVersion.content,
    '',
    formatContextForPrompt({ room, context }),
    '',
    'Rends uniquement la nouvelle version complète du document en markdown.',
  ].join('\n');

  const geminiText = await tryGemini(prompt, 1100);
  const content =
    geminiText ||
    [
      `# ${artifact.title}`,
      '',
      '## Révision',
      `- Instruction prise en compte: ${clip(instructions, 180)}`,
      '- Une nouvelle version a été préparée pour l’équipe.',
      '',
      currentVersion.content,
    ].join('\n');

  const versionCount = await ArtifactVersion.countDocuments({ artifactId: artifact._id });
  const version = await ArtifactVersion.create({
    artifactId: artifact._id,
    roomId: artifact.roomId,
    number: versionCount + 1,
    content,
    createdBy: actor.userId,
    authorName: actor.displayName || '',
    sourcePrompt: clip(instructions, 4000),
    changeSummary: String(changeSummary || '').trim().slice(0, 400),
    status: 'draft',
  });

  artifact.currentVersionId = version._id;
  artifact.updatedAt = new Date();
  await artifact.save();

  const message = await persistRoomMessage({
    roomId: String(artifact.roomId),
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'artifact',
    documentTitle: artifact.title,
    data: {
      artifactId: artifact._id,
      artifactKind: artifact.kind,
      versionId: version._id,
      why: `Révision IA demandée par ${actor.displayName || 'l’équipe'}.`,
    },
  });

  broadcastRoomArtifactVersionCreated(
    String(artifact.roomId),
    String(artifact._id),
    summariseVersion(version)
  );

  return { version, message };
}

async function persistResearchArtifact({
  roomId,
  title,
  content,
  query,
  sourceMessageId = null,
}) {
  const artifact = await RoomArtifact.create({
    roomId,
    title: slugTitle(title, 'Recherche collaborative'),
    kind: 'research',
    status: 'draft',
    createdBy: 'ai',
    sourcePrompt: clip(query, 4000),
    sourceMessageId,
  });

  const version = await ArtifactVersion.create({
    artifactId: artifact._id,
    roomId,
    number: 1,
    content,
    createdBy: 'ai',
    sourcePrompt: clip(query, 4000),
    status: 'draft',
  });

  artifact.currentVersionId = version._id;
  await artifact.save();

  broadcastRoomArtifactCreated(roomId, artifact.toObject(), summariseVersion(version));
  broadcastRoomArtifactVersionCreated(roomId, String(artifact._id), summariseVersion(version));

  return { artifact, version };
}

async function createDecisionMemories({ roomId, content, actor }) {
  const decisions = extractSectionList(
    content,
    /##\s*Décisions\s*([\s\S]*?)(?:##\s+|$)/i
  );
  const entries = decisions.slice(0, 3).map((item) => ({
    roomId,
    type: 'decision',
    content: item,
    createdBy: actor.userId,
    createdByName: actor.displayName,
    pinned: true,
  }));
  if (!entries.length) return [];
  return await RoomMemory.insertMany(entries);
}

async function createResearchMemories({ roomId, query, keyTakeaways, actor }) {
  const takeaways = Array.isArray(keyTakeaways)
    ? keyTakeaways.map((item) => clip(item, 240)).filter(Boolean)
    : [];
  const entries = takeaways.slice(0, 3).map((item) => ({
    roomId,
    type: 'fact',
    content: `[Recherche] ${query}: ${item}`,
    createdBy: actor.userId,
    createdByName: actor.displayName,
    pinned: true,
  }));
  if (!entries.length) return [];
  return await RoomMemory.insertMany(entries);
}

async function handleResearchCommand({ roomId, room, prompt }) {
  const query = clip(prompt || room.purpose || room.name, 400);
  const video = await searchYouTube(query, { maxResults: 3 });
  const videoUrl = video.url;
  const videoTitle = video.title;
  const videoId = video.videoId;
  const { transcript, keyTakeaways, summary } = await getTranscript(videoId, videoTitle);
  const { chapters } = await getChapters(videoId, videoTitle, { desired: 4 });
  const chapterLinks = (Array.isArray(chapters) ? chapters : []).map((chapter) => {
    const startSec = Number(chapter?.startSec || 0);
    const separator = String(videoUrl || '').includes('?') ? '&' : '?';
    return {
      ...chapter,
      startSec,
      url: `${videoUrl}${separator}t=${startSec}`,
    };
  });
  const citations = buildTranscriptCitations({ videoUrl, transcript, max: 3 });

  const researchPrompt = [
    'Tu es l’IA partagée d’un channel. Résume une source utile pour l’équipe.',
    `Question: ${query}`,
    `Source: ${videoTitle}`,
    `Transcript: ${transcript.map((item) => item.text).join('\n')}`,
    'Réponds en français, en 3 à 5 puces orientées action.',
  ].join('\n\n');

  const geminiText = await tryGemini(researchPrompt, 420);
  const content = [
    `# Recherche — ${videoTitle}`,
    '',
    geminiText ||
    summary ||
    `- Source identifiée pour avancer sur ${query}\n- Consultez les citations et chapitres pour le contexte\n- Utilisez /doc pour transformer ces éléments en livrable partagé`,
  ].join('\n');

  const researchArtifactContent = [
    `# Recherche collaborative — ${videoTitle}`,
    '',
    `## Requête`,
    query,
    '',
    `## Synthèse`,
    content,
    '',
    `## Source`,
    videoUrl,
  ].join('\n');

  const { artifact, version } = await persistResearchArtifact({
    roomId,
    title: `Recherche — ${videoTitle}`,
    content: researchArtifactContent,
    query,
  });

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'research',
    data: {
      query,
      videoTitle,
      videoUrl,
      source: video.source,
      alternatives: video.alternatives || [],
      citations,
      chapters: chapterLinks,
      keyTakeaways,
      artifactId: artifact._id,
      versionId: version._id,
      why: 'Recherche collaborative déclenchée depuis le channel.',
    },
  });

  // Link the research artifact to the final persisted room message for traceability.
  artifact.sourceMessageId = message._id;
  await artifact.save();

  // Keep a compact trace in room memory so future AI replies can reuse research insights.
  await createResearchMemories({
    roomId,
    query,
    keyTakeaways,
    actor: { userId: 'ai', displayName: 'IA' },
  });

  broadcastRoomResearchAttached(roomId, message.toObject());
  return { message };
}

async function handleDecisionCommand({ roomId, room, prompt, actor, context }) {
  const subject = clip(prompt || room.purpose || room.name, 300);
  const geminiPrompt = [
    'Tu es l’IA collègue d’un channel.',
    'À partir du contexte, extrais une synthèse de décision.',
    'Rends du markdown avec exactement ces sections:',
    '## Décisions',
    '## Risques',
    '## Next steps',
    '',
    `Sujet: ${subject}`,
    formatContextForPrompt({ room, context }),
  ].join('\n\n');

  const tempId = `stream_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  let geminiText = await tryGeminiStreaming(geminiPrompt, roomId, tempId, 650);
  if (!geminiText) geminiText = await tryGemini(geminiPrompt, 650);
  const content = geminiText || buildHeuristicReply({ roomName: room.name, prompt: subject, command: 'decide' });

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'decision',
    tempId,
    data: {
      why: `Synthèse de décision demandée par ${actor.displayName || 'un membre du channel'}.`,
      decisions: extractSectionList(content, /##\s*Décisions\s*([\s\S]*?)(?:##\s+|$)/i),
      risks: extractSectionList(content, /##\s*Risques\s*([\s\S]*?)(?:##\s+|$)/i),
      nextSteps: extractSectionList(content, /##\s*Next steps\s*([\s\S]*?)(?:##\s+|$)/i),
    },
  });

  await createDecisionMemories({ roomId, content, actor });
  broadcastRoomDecisionCreated(roomId, message.toObject());
  return { message };
}

async function handleConversationCommand({
  roomId,
  room,
  prompt,
  command,
  actor,
  context,
  sourceMessageId,
  modeInstruction = '',
  missionAgentLabel = 'Agent auto',
}) {
  const effectivePrompt = clip(prompt || inferFallbackPrompt(null, context.messages), 1200);
  const geminiPrompt = [
    'Tu es un collègue IA visible par tous dans un channel collaboratif.',
    'Réponds en français, de façon utile, structurée et concise.',
    modeInstruction ? `Posture spécialisée: ${modeInstruction}` : '',
    command === 'doc'
      ? 'Rends un document markdown complet, avec un titre principal commençant par #.'
      : 'Rends une réponse directement exploitable dans le flux de discussion.',
    `Demande: ${effectivePrompt}`,
    formatContextForPrompt({ room, context }),
  ].join('\n\n');

  const maxTokens = command === 'doc' ? 1100 : 700;
  const tempId = `stream_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  // Try token-by-token streaming first; degraded silently to a single-shot call
  let geminiText = await tryGeminiStreaming(geminiPrompt, roomId, tempId, maxTokens);
  if (!geminiText) geminiText = await tryGemini(geminiPrompt, maxTokens);

  const content =
    geminiText || buildHeuristicReply({
      roomName: room.name,
      prompt: effectivePrompt,
      command,
      missionAgentLabel,
    });

  const shouldCreateArtifact =
    command === 'doc' || /^#\s+/.test(String(content || '')) || isDocLikePrompt(effectivePrompt);

  if (shouldCreateArtifact) {
    return await createRoomArtifact({
      roomId,
      title: headingTitle(content, effectivePrompt || 'Canvas partagé'),
      content,
      kind: command === 'doc' ? 'canvas' : 'document',
      createdBy: actor.userId,
      createdByName: actor.displayName,
      sourcePrompt: effectivePrompt,
      sourceMessageId,
      isAI: true,
      senderId: 'ai',
      senderName: 'IA',
      tempId,
    });
  }

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'ai',
    tempId,
    data: {
      why: `Réponse IA partagée déclenchée par ${actor.displayName || 'un membre du channel'}.`,
    },
  });

  return { message };
}

async function handleMissionCommand({
  roomId,
  room,
  prompt,
  actor,
  context,
  sourceMessageId,
  agentType,
}) {
  const missionPrompt = clip(prompt || inferFallbackPrompt(null, context.messages), 2000);
  const agentProfile = resolveMissionAgentProfile({ prompt: missionPrompt, agentType });
  const mission = await RoomMission.create({
    roomId,
    prompt: missionPrompt,
    requestedBy: actor.userId,
    requestedByName: actor.displayName,
    agentType: agentProfile.type,
    agentLabel: agentProfile.label,
    status: 'queued',
  });
  broadcastRoomMissionStatus(roomId, mission.toObject());

  mission.status = 'running';
  await mission.save();
  broadcastRoomMissionStatus(roomId, mission.toObject());

  try {
    const result = await handleConversationCommand({
      roomId,
      room,
      prompt: missionPrompt,
      command: 'mission',
      actor,
      context,
      sourceMessageId,
      modeInstruction: agentProfile.instruction,
      missionAgentLabel: agentProfile.label,
    });

    mission.status = 'done';
    mission.resultMessageId = result.message?._id || null;
    mission.resultArtifactId = result.artifact?._id || null;
    mission.error = '';
    await mission.save();
    broadcastRoomMissionStatus(roomId, mission.toObject());
    return { mission, ...result };
  } catch (error) {
    mission.status = 'failed';
    mission.error = clip(error?.message || 'Mission failed', 500);
    await mission.save();
    broadcastRoomMissionStatus(roomId, mission.toObject());
    throw error;
  }
}

export async function suggestRoomSynthesisIfNeeded({ roomId, room, actor }) {
  if (process.env.ROOM_SYNTHESIS_SUGGESTIONS === 'false') {
    return { skipped: true, reason: 'disabled' };
  }

  const recent = await RoomMessage.find({ roomId }).sort({ createdAt: -1 }).limit(40).lean();
  if (!recent.length) return { skipped: true, reason: 'no_messages' };

  const lastSuggestion = recent.find(
    (msg) => msg?.type === 'system' && msg?.data?.kind === 'synthesis_suggestion'
  );
  if (lastSuggestion) {
    const ageMs = Date.now() - new Date(lastSuggestion.createdAt).getTime();
    if (ageMs < SYNTHESIS_COOLDOWN_MS) {
      return { skipped: true, reason: 'cooldown' };
    }
  }

  const cutoffTime = lastSuggestion?.createdAt ? new Date(lastSuggestion.createdAt).getTime() : 0;
  const humanSinceLastSuggestion = recent
    .filter((msg) => !msg?.isAI)
    .filter((msg) => !cutoffTime || new Date(msg.createdAt).getTime() > cutoffTime)
    .filter((msg) => !isCommandLike(msg?.content));

  if (humanSinceLastSuggestion.length < SYNTHESIS_TRIGGER_EVERY) {
    return { skipped: true, reason: 'not_enough_messages' };
  }

  const lines = humanSinceLastSuggestion
    .slice(0, 10)
    .map((msg) => String(msg.content || '').trim())
    .filter(Boolean);

  const defaultSuggestion = buildSynthesisSuggestion({ roomName: room?.name, lines });
  let suggestion = defaultSuggestion;

  if (process.env.GEMINI_API_KEY) {
    const prompt = [
      `Tu es copilote de canal. Produis une suggestion de synthèse concise en markdown pour "${room?.name || 'Channel'}".`,
      '',
      'Contraintes:',
      '- max 140 mots',
      '- sections: "Résumé", "Décisions proposées", "Actions"',
      '- concret et exécutable immédiatement',
      '',
      'Extraits récents:',
      ...lines.map((line, i) => `${i + 1}. ${line}`),
    ].join('\n');
    const gemini = await tryGemini(prompt, 320);
    if (gemini) suggestion = gemini;
  }

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    type: 'system',
    content: suggestion,
    data: {
      kind: 'synthesis_suggestion',
      source: 'auto',
      basedOnMessages: humanSinceLastSuggestion.length,
      suggestedCommands: ['/decide', '/doc'],
    },
    sourceMessageId: null,
  });

  broadcastRoomSynthesisSuggested(roomId, message.toObject());
  return { skipped: false, message };
}

async function handleBriefCommand({ roomId, room, prompt }) {
  const context = await collectRoomContext(roomId);
  const lines = context.messages
    .filter((msg) => !msg.isAI)
    .map((msg) => String(msg.content || '').trim())
    .filter(Boolean)
    .slice(-8);

  const objective = clip(prompt || room?.purpose || room?.name || 'Préparer le prochain point', 180);
  let brief = buildMeetingBrief({ roomName: room?.name, lines, objective });

  if (process.env.GEMINI_API_KEY) {
    const geminiPrompt = [
      `Tu es PM de canal. Rédige un brief pré-réunion en markdown pour "${room?.name || 'Channel'}".`,
      `Objectif: ${objective}`,
      'Contraintes: <= 180 mots, sections: Objectif / Points à aligner / Décisions / Questions / Next step.',
      '',
      'Extraits récents:',
      ...lines.map((line, i) => `${i + 1}. ${line}`),
    ].join('\n');
    const gemini = await tryGemini(geminiPrompt, 360);
    if (gemini) brief = gemini;
  }

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    type: 'system',
    content: brief,
    data: {
      kind: 'meeting_brief',
      source: 'manual',
      objective,
      suggestedCommands: ['/decide', '/doc'],
      why: 'Brief automatique déclenché avant réunion.',
    },
  });

  broadcastRoomBriefSuggested(roomId, message.toObject());
  return { message };
}

async function handleShareCommand({ roomId, room, prompt, context }) {
  const providerAndNote = String(prompt || '').trim();

  // ── Notion branch ──────────────────────────────────────────────────────────
  if (/^notion\b/i.test(providerAndNote)) {
    const notion = room?.integrations?.notion || {};
    if (!notion.enabled || !String(notion.apiToken || '').trim()) {
      const message = await persistRoomMessage({
        roomId,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        type: 'system',
        content:
          'Notion n\'est pas connecte sur ce channel. Connectez-le via POST /integrations/notion puis relancez `/share notion`.',
        data: { kind: 'notion_export', ok: false, reason: 'notion_not_connected' },
      });
      broadcastRoomNotionExported(roomId, message.toObject());
      return { message };
    }

    // Find most recent AI-generated artifact content to export
    const latestArtifact = await RoomArtifact.findOne({ roomId }).sort({ updatedAt: -1 }).lean();
    let markdown = '';
    let pageTitle = `Hackit — ${room?.name || 'Channel'}`;

    if (latestArtifact?.currentVersionId) {
      const ver = await ArtifactVersion.findById(latestArtifact.currentVersionId).lean();
      if (ver?.content) {
        markdown = ver.content;
        pageTitle = latestArtifact.title || pageTitle;
      }
    }

    if (!markdown) {
      const candidate = [...(context?.messages || [])]
        .reverse()
        .find((msg) => msg?.isAI && String(msg?.content || '').trim());
      markdown = clip(candidate?.content || room?.purpose || 'Partage depuis Hackit.', 4000);
    }

    try {
      const page = await createNotionPage({
        apiToken: notion.apiToken,
        parentPageId: notion.parentPageId,
        title: pageTitle,
        markdown,
        emoji: '\uD83D\uDCCB',
      });

      const message = await persistRoomMessage({
        roomId,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        type: 'system',
        content: `Contenu exporte vers Notion : ${page.url}`,
        data: {
          kind: 'notion_export',
          ok: true,
          pageId: page.pageId,
          url: page.url,
          title: pageTitle,
        },
      });
      broadcastRoomNotionExported(roomId, message.toObject());
      return { message };
    } catch (error) {
      const message = await persistRoomMessage({
        roomId,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        type: 'system',
        content: `Echec export Notion : ${clip(error?.message || 'erreur inconnue', 220)}`,
        data: {
          kind: 'notion_export',
          ok: false,
          reason: clip(error?.code || error?.message || 'notion_error', 120),
        },
      });
      broadcastRoomNotionExported(roomId, message.toObject());
      return { error, message };
    }
  }

  // ── Slack branch ───────────────────────────────────────────────────────────
  if (!/^slack\b/i.test(providerAndNote)) {
    const message = await persistRoomMessage({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      type: 'system',
      content:
        'Partage non supporte pour cette cible. Utilisez `/share slack` ou `/share notion`.',
      data: { kind: 'share_result', provider: 'unknown', ok: false },
    });
    return { message };
  }

  const slack = room?.integrations?.slack || {};
  if (!slack.enabled || !String(slack.botToken || '').trim()) {
    const message = await persistRoomMessage({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      type: 'system',
      content:
        'Slack n\'est pas connecte sur ce channel. Connectez-le via les endpoints integrations puis relancez `/share slack`.',
      data: { kind: 'share_result', provider: 'slack', ok: false, reason: 'slack_not_connected' },
    });
    return { message };
  }

  const note = providerAndNote.replace(/^slack\b/i, '').trim();
  const candidate = [...(context?.messages || [])]
    .reverse()
    .find((msg) => String(msg?.content || '').trim() && !isCommandLike(msg?.content));

  const summary = clip(
    candidate?.content || room?.purpose || 'Partage rapide depuis le channel Hackit.',
    1800
  );
  const text = buildSlackShareText({ roomName: room?.name, summary, note });

  try {
    const sent = await postSlackMessage({
      botToken: slack.botToken,
      channelId: slack.channelId,
      text,
    });

    const message = await persistRoomMessage({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      type: 'system',
      content: `Partage Slack envoye dans ${sent.channel} (ts: ${sent.ts}).`,
      data: {
        kind: 'share_result',
        provider: 'slack',
        ok: true,
        channel: sent.channel,
        ts: sent.ts,
      },
    });
    broadcastRoomShareResult(roomId, message.toObject());
    return { message };
  } catch (error) {
    const message = await persistRoomMessage({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      type: 'system',
      content: `Echec du partage Slack: ${clip(error?.message || 'erreur inconnue', 220)}`,
      data: {
        kind: 'share_result',
        provider: 'slack',
        ok: false,
        reason: clip(error?.code || error?.message || 'slack_error', 120),
      },
    });
    broadcastRoomShareResult(roomId, message.toObject());
    return { error, message };
  }
}

export async function suggestRoomBriefIfNeeded({ roomId, room }) {
  if (process.env.ROOM_AUTO_BRIEF === 'false') {
    return { skipped: true, reason: 'disabled' };
  }

  const recent = await RoomMessage.find({ roomId }).sort({ createdAt: -1 }).limit(40).lean();
  if (!recent.length) return { skipped: true, reason: 'no_messages' };

  const lastBrief = recent.find(
    (msg) => msg?.type === 'system' && msg?.data?.kind === 'meeting_brief'
  );
  if (lastBrief) {
    const ageMs = Date.now() - new Date(lastBrief.createdAt).getTime();
    if (ageMs < BRIEF_COOLDOWN_MS) {
      return { skipped: true, reason: 'cooldown' };
    }
  }

  const cutoffTime = lastBrief?.createdAt ? new Date(lastBrief.createdAt).getTime() : 0;
  const humanSinceLastBrief = recent
    .filter((msg) => !msg?.isAI)
    .filter((msg) => !cutoffTime || new Date(msg.createdAt).getTime() > cutoffTime)
    .filter((msg) => !isCommandLike(msg?.content));

  if (humanSinceLastBrief.length < BRIEF_TRIGGER_EVERY) {
    return { skipped: true, reason: 'not_enough_messages' };
  }

  const meetingSignals = humanSinceLastBrief
    .map((msg) => String(msg.content || '').trim())
    .filter((line) => MEETING_SIGNAL_REGEX.test(line));

  if (!meetingSignals.length) {
    return { skipped: true, reason: 'no_meeting_signal' };
  }

  const lines = humanSinceLastBrief
    .slice(0, 10)
    .map((msg) => String(msg.content || '').trim())
    .filter(Boolean);
  const objective = meetingSignals[0] || room?.purpose || 'Préparer le point à venir';
  let brief = buildMeetingBrief({ roomName: room?.name, lines, objective });

  if (process.env.GEMINI_API_KEY) {
    const prompt = [
      `Rédige un brief pré-réunion prêt à l'emploi pour "${room?.name || 'Channel'}".`,
      `Objectif détecté: ${clip(objective, 180)}`,
      'Format: markdown, <= 180 mots, sections: Objectif / Points à aligner / Décisions / Questions / Next step.',
      '',
      'Messages récents:',
      ...lines.map((line, i) => `${i + 1}. ${line}`),
    ].join('\n');
    const gemini = await tryGemini(prompt, 380);
    if (gemini) brief = gemini;
  }

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    type: 'system',
    content: brief,
    data: {
      kind: 'meeting_brief',
      source: 'auto',
      objective: clip(objective, 180),
      basedOnMessages: humanSinceLastBrief.length,
      suggestedCommands: ['/decide', '/doc'],
      why: 'Brief auto proposé avant réunion détectée dans le channel.',
    },
  });

  broadcastRoomBriefSuggested(roomId, message.toObject());
  return { skipped: false, message };
}

export async function triggerRoomAutomation({
  room,
  roomId,
  triggeringMessage,
  actor,
  options = {},
}) {
  const parsed = parseRoomCommand(triggeringMessage?.content || '');
  if (parsed.kind === 'none') return { skipped: true };

  const context = await collectRoomContext(roomId);
  const effectivePrompt = parsed.prompt || inferFallbackPrompt(triggeringMessage, context.messages);

  broadcastRoomTyping(roomId, 'ai');

  try {
    if (parsed.kind === 'search') {
      return await handleResearchCommand({
        roomId,
        room,
        prompt: effectivePrompt,
      });
    }
    if (parsed.kind === 'decide') {
      return await handleDecisionCommand({
        roomId,
        room,
        prompt: effectivePrompt,
        actor,
        context,
      });
    }
    if (parsed.kind === 'mission') {
      return await handleMissionCommand({
        roomId,
        room,
        prompt: effectivePrompt,
        actor,
        context,
        sourceMessageId: triggeringMessage?._id || null,
        agentType: options.agentType,
      });
    }
    if (parsed.kind === 'brief') {
      return await handleBriefCommand({
        roomId,
        room,
        prompt: effectivePrompt,
      });
    }
    if (parsed.kind === 'share') {
      return await handleShareCommand({
        roomId,
        room,
        prompt: effectivePrompt,
        context,
      });
    }
    return await handleConversationCommand({
      roomId,
      room,
      prompt: effectivePrompt,
      command: parsed.kind,
      actor,
      context,
      sourceMessageId: triggeringMessage?._id || null,
    });
  } catch (error) {
    const failureMessage = await persistRoomMessage({
      roomId,
      senderId: 'ai',
      senderName: 'IA',
      isAI: true,
      content: `Je n’ai pas pu terminer cette demande pour le moment.\n\nRaison: ${clip(
        error?.message || 'erreur inconnue',
        240
      )}`,
      type: 'system',
      data: {
        why: 'L’IA a rencontré une erreur en traitant la commande du channel.',
      },
    });
    return { error, message: failureMessage };
  }
}
