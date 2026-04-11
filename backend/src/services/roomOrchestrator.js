import Room from '../models/Room.js';
import RoomMessage from '../models/RoomMessage.js';
import RoomArtifact from '../models/RoomArtifact.js';
import ArtifactVersion from '../models/ArtifactVersion.js';
import RoomMission from '../models/RoomMission.js';
import RoomMemory from '../models/RoomMemory.js';

import { getChapters } from './chapters.js';
import { generateWithGemini } from './gemini.js';
import { getTranscript } from './transcript.js';
import {
  broadcastRoomArtifactCreated,
  broadcastRoomArtifactVersionCreated,
  broadcastRoomDecisionCreated,
  broadcastRoomMessage,
  broadcastRoomMissionStatus,
  broadcastRoomResearchAttached,
  broadcastRoomTyping,
} from './roomWS.js';
import { searchYouTube } from './youtube.js';

const MAX_CONTEXT_MESSAGES = 18;
const MAX_CONTEXT_ARTIFACTS = 3;
const MAX_CONTEXT_MEMORY = 6;

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

function buildHeuristicReply({ roomName, prompt, command }) {
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

async function tryGemini(prompt, maxOutputTokens = 900) {
  if (!process.env.GEMINI_API_KEY) return null;
  try {
    return await generateWithGemini(prompt, maxOutputTokens);
  } catch (error) {
    console.warn('[roomOrchestrator] Gemini fallback:', error?.message || error);
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
  broadcastRoomMessage(roomId, message.toObject());
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
    sourcePrompt: clip(instructions, 4000),
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

async function handleResearchCommand({ roomId, room, prompt }) {
  const query = clip(prompt || room.purpose || room.name, 400);
  const video = await searchYouTube(query, { maxResults: 3 });
  const videoUrl = video.url;
  const videoTitle = video.title;
  const videoId = video.videoId;
  const { transcript, keyTakeaways, summary } = await getTranscript(videoId, videoTitle);
  const { chapters } = await getChapters(videoId, videoTitle, { desired: 4 });
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
      chapters,
      keyTakeaways,
      why: 'Recherche collaborative déclenchée depuis le channel.',
    },
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

  const geminiText = await tryGemini(geminiPrompt, 650);
  const content = geminiText || buildHeuristicReply({ roomName: room.name, prompt: subject, command: 'decide' });

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'decision',
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
}) {
  const effectivePrompt = clip(prompt || inferFallbackPrompt(null, context.messages), 1200);
  const geminiPrompt = [
    'Tu es un collègue IA visible par tous dans un channel collaboratif.',
    'Réponds en français, de façon utile, structurée et concise.',
    command === 'doc'
      ? 'Rends un document markdown complet, avec un titre principal commençant par #.'
      : 'Rends une réponse directement exploitable dans le flux de discussion.',
    `Demande: ${effectivePrompt}`,
    formatContextForPrompt({ room, context }),
  ].join('\n\n');

  const geminiText = await tryGemini(geminiPrompt, command === 'doc' ? 1100 : 700);
  const content =
    geminiText || buildHeuristicReply({ roomName: room.name, prompt: effectivePrompt, command });

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
    });
  }

  const message = await persistRoomMessage({
    roomId,
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content,
    type: 'ai',
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
}) {
  const missionPrompt = clip(prompt || inferFallbackPrompt(null, context.messages), 2000);
  const mission = await RoomMission.create({
    roomId,
    prompt: missionPrompt,
    requestedBy: actor.userId,
    requestedByName: actor.displayName,
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

export async function triggerRoomAutomation({
  room,
  roomId,
  triggeringMessage,
  actor,
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
