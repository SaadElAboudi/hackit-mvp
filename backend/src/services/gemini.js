import axios from "axios";

/**
 * Service Gemini - Gère toutes les interactions avec l'API Gemini de Google
 */

const DEFAULT_MODEL = process.env.GEMINI_MODEL || "models/gemini-2.0-flash-lite";

const RETRYABLE_NETWORK_CODES = new Set([
  "ECONNRESET",
  "ECONNABORTED",
  "ETIMEDOUT",
  "EAI_AGAIN",
  "ENOTFOUND",
]);

const GENERIC_PHRASES = [
  "je peux vous aider",
  "voici quelques pistes",
  "en mode hors-ligne",
  "réponse générique",
  "structure générique",
  "few ideas",
  "generic response",
];

const STOPWORDS = new Set([
  "avec", "pour", "dans", "cette", "cet", "quoi", "comment", "pourquoi", "which", "what", "when", "where", "have", "will", "would", "your", "vous", "nous", "leur", "leurs", "être", "faire", "plus", "moins", "tout", "tous", "from", "that", "this", "there", "here", "est", "sont", "des", "les", "une", "the", "and", "mais", "donc", "avec", "sans", "about", "into", "over", "under", "than", "bien", "very", "just", "only", "aussi",
]);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function extractKeywords(text = "") {
  return Array.from(
    new Set(
      String(text)
        .toLowerCase()
        .replace(/[^\p{L}\p{N}\s-]/gu, " ")
        .split(/\s+/)
        .map((word) => word.trim())
        .filter((word) => word.length >= 5 && !STOPWORDS.has(word))
    )
  );
}

function looksGenericResponse(text = "", prompt = "") {
  const value = String(text || "").trim();
  if (!value) return true;

  const lower = value.toLowerCase();
  if (GENERIC_PHRASES.some((phrase) => lower.includes(phrase))) {
    return true;
  }

  const promptKeywords = extractKeywords(prompt).slice(0, 18);
  if (!promptKeywords.length) return false;

  const overlap = promptKeywords.filter((keyword) => lower.includes(keyword)).length;
  const veryShort = value.length < 140;
  const weakOverlap = overlap === 0;

  return veryShort && weakOverlap;
}

function buildSpecificityRepairPrompt({ originalPrompt, draft }) {
  return [
    "Ameliore la reponse ci-dessous.",
    "Contraintes obligatoires:",
    "- Pas de formulation generique (ex: \"voici quelques pistes\", \"je peux aider\")",
    "- Appuie-toi sur des elements concrets de la demande",
    "- Donne des propositions directement executables",
    "- Garde le meme format de sortie attendu",
    "",
    "Demande originale:",
    originalPrompt,
    "",
    "Brouillon a corriger:",
    draft,
  ].join("\n");
}

function isRetryableGeminiError(error) {
  const status = error?.response?.status;
  if (status === 429) return true;
  if (typeof status === "number" && status >= 500) return true;
  if (RETRYABLE_NETWORK_CODES.has(String(error?.code || ""))) return true;
  return false;
}

/**
 * Generate text using Gemini API
 * @param {string} prompt - Le prompt a envoyer a Gemini
 * @param {number} maxOutputTokens - Nombre maximum de tokens dans la reponse
 * @param {object} options - Options avancees (temperature, model, preferModels, systemInstruction)
 * @returns {Promise<string>} - Texte genere
 */
export const generateWithGemini = async (prompt, maxOutputTokens = 256, options = {}) => {
  const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
  const timeoutMs = Number(options.timeoutMs || process.env.GEMINI_TIMEOUT_MS || 15000);
  const temperature = Number.isFinite(options.temperature)
    ? options.temperature
    : 0.2;
  const maxAttemptsPerModel = Math.max(1, Number(options.maxAttemptsPerModel || 2));
  const allowQualityRepair = options.allowQualityRepair !== false;
  const systemInstruction = String(options.systemInstruction || "").trim();

  if (!GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY manquante dans les variables d'environnement");
  }

  const buildRequest = (model, inputPrompt) => {
    const isLegacyPalm = /bison/i.test(model);
    const url = isLegacyPalm
      ? `https://generativelanguage.googleapis.com/v1beta2/${model}:generateText?key=${GEMINI_API_KEY}`
      : `https://generativelanguage.googleapis.com/v1/${model}:generateContent?key=${GEMINI_API_KEY}`;

    const body = isLegacyPalm
      ? {
        prompt: { text: inputPrompt },
        maxOutputTokens,
        temperature,
      }
      : {
        contents: [
          {
            role: "user",
            parts: [{ text: inputPrompt }],
          },
        ],
        generationConfig: {
          maxOutputTokens,
          temperature,
        },
        ...(systemInstruction
          ? { system_instruction: { parts: [{ text: systemInstruction }] } }
          : {}),
        // Reduce unexpected safety blocks for benign prompts
        safetySettings: [
          { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_SEXUAL_CONTENT", threshold: "BLOCK_NONE" },
          { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
        ],
      };
    const parse = (data) => {
      if (/bison/i.test(model)) {
        const text = data?.candidates?.[0]?.output;
        return (text || "").trim();
      }
      // Handle potential safety blocks
      const blockReason = data?.promptFeedback?.blockReason;
      if (blockReason && blockReason !== "BLOCK_NONE") {
        throw new Error(`Contenu bloqué par la sécurité: ${blockReason}`);
      }
      // Try standard v1 shape
      const parts = data?.candidates?.[0]?.content?.parts || [];
      let text = parts.map((p) => p?.text).filter(Boolean).join("\n").trim();
      // Fallbacks for alternate shapes
      if (!text) text = (data?.candidates?.[0]?.text || "").trim();
      if (!text) text = (data?.candidates?.[0]?.output || "").trim();
      return text;
    };

    return { url, body, parse };
  };

  const tryModels = [];
  const preferred = [
    ...(Array.isArray(options.preferModels) ? options.preferModels : []),
    options.model,
    DEFAULT_MODEL,
  ]
    .map((value) => String(value || "").trim())
    .filter(Boolean);

  for (const model of preferred) {
    if (!tryModels.includes(model)) tryModels.push(model);
    if (/-latest$/i.test(model)) {
      const base = model.replace(/-latest$/i, "");
      if (!tryModels.includes(base)) tryModels.push(base);
    }
  }

  // modern defaults
  for (const candidate of [
    "models/gemini-2.5-flash",
    "models/gemini-2.5-pro",
    "models/gemini-2.0-flash",
    "models/gemini-2.0-flash-lite",
    "models/gemini-1.5-flash",
  ]) {
    if (!tryModels.includes(candidate)) tryModels.push(candidate);
  }

  // legacy fallback if v1 model not available
  if (!tryModels.includes("models/text-bison-001")) {
    tryModels.push("models/text-bison-001");
  }

  let lastError;
  for (const model of tryModels) {
    for (let attempt = 1; attempt <= maxAttemptsPerModel; attempt++) {
      try {
        const { url, body, parse } = buildRequest(model, prompt);
        const resp = await axios.post(url, body, {
          headers: { "Content-Type": "application/json" },
          timeout: timeoutMs,
        });
        const text = parse(resp.data);
        if (!text) throw new Error(`Pas de contenu genere par Gemini (${model})`);

        if (
          allowQualityRepair &&
          !options.__qualityRepairAttempt &&
          looksGenericResponse(text, prompt)
        ) {
          const repairedPrompt = buildSpecificityRepairPrompt({
            originalPrompt: prompt,
            draft: text,
          });
          try {
            const repaired = await generateWithGemini(repairedPrompt, maxOutputTokens, {
              ...options,
              model,
              allowQualityRepair: false,
              __qualityRepairAttempt: true,
              maxAttemptsPerModel: 1,
            });
            if (repaired && !looksGenericResponse(repaired, prompt)) {
              return repaired;
            }
          } catch (_) {
            // keep original response if repair pass fails
          }
        }

        return text;
      } catch (error) {
        lastError = error;
        const status = error?.response?.status;
        const message = error?.response?.data?.error?.message || error.message;
        const isNotFound = status === 404 || /not\s*found/i.test(message || "");
        const isBlocked =
          /blocked|safety/i.test(message || "") ||
          /Contenu bloqu[eé]/i.test(error?.message || "");

        if (isNotFound || isBlocked) {
          if (attempt >= maxAttemptsPerModel) {
            console.warn(`Modele indisponible ou bloque (${model}), tentative du modele suivant...`);
          }
          break;
        }

        if (attempt < maxAttemptsPerModel && isRetryableGeminiError(error)) {
          const backoff = Math.min(4000, 400 * attempt + Math.floor(Math.random() * 150));
          await sleep(backoff);
          continue;
        }

        console.error("Erreur API Gemini:", error?.response?.data || error.message);
        throw error;
      }
    }
  }

  console.error("Erreur API Gemini:", lastError?.response?.data || lastError?.message || lastError);
  throw lastError || new Error("Echec de generation Gemini");
};

/**
 * Stream text from Gemini API, calling onChunk(cumulativeText) as tokens arrive.
 * Returns the full generated text, or null on error.
 * Uses gemini-2.0-flash-lite for fast streaming; falls back to null so the
 * caller can degrade to non-streaming generateWithGemini.
 *
 * @param {string} prompt
 * @param {(cumulative: string) => void} onChunk
 * @param {number} maxOutputTokens
 * @returns {Promise<string|null>}
 */
export const streamWithGemini = async (prompt, onChunk, maxOutputTokens = 900) => {
  const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
  if (!GEMINI_API_KEY) return null;

  const model = process.env.GEMINI_STREAM_MODEL || 'models/gemini-2.0-flash-lite';
  const url =
    `https://generativelanguage.googleapis.com/v1/${model}:streamGenerateContent` +
    `?key=${GEMINI_API_KEY}&alt=sse`;

  try {
    const resp = await axios.post(
      url,
      {
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens, temperature: 0.2 },
        safetySettings: [
          { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_NONE' },
          { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_NONE' },
          { category: 'HARM_CATEGORY_SEXUAL_CONTENT', threshold: 'BLOCK_NONE' },
          { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_NONE' },
        ],
      },
      {
        headers: { 'Content-Type': 'application/json' },
        responseType: 'stream',
        timeout: 60_000,
      }
    );

    let fullText = '';
    let buffer = '';

    await new Promise((resolve, reject) => {
      resp.data.on('data', (raw) => {
        buffer += raw.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop(); // keep any partial line for the next chunk
        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const json = line.slice(6).trim();
          if (!json || json === '[DONE]') continue;
          try {
            const parsed = JSON.parse(json);
            const text = parsed?.candidates?.[0]?.content?.parts?.[0]?.text || '';
            if (text) {
              fullText += text;
              onChunk(fullText);
            }
          } catch (_) { /* malformed SSE line — skip */ }
        }
      });
      resp.data.on('end', resolve);
      resp.data.on('error', reject);
    });

    return fullText || null;
  } catch (err) {
    console.warn('[gemini] streamWithGemini error:', err?.message || err);
    return null;
  }
};

/**
 * Reformule une question pour la recherche YouTube
 * @param {string} query - Question originale de l'utilisateur
 * @returns {Promise<string>} - Question reformulée
 */
export const reformulateQuestion = async (query) => {
  const USE_GEMINI = (process.env.USE_GEMINI || "false") === "true";

  if (!USE_GEMINI) {
    return query; // Retourne la question originale si Gemini est désactivé
  }

  const prompt = `Reformule cette question en anglais pour une recherche YouTube: "${query}"`;
  return await generateWithGemini(prompt, 128);
};

/**
 * Génère un résumé à partir du titre d'une vidéo
 * @param {string} videoTitle - Titre de la vidéo
 * @returns {Promise<string>} - Résumé généré
 */
export const generateSummary = async (videoTitle) => {
  const USE_GEMINI = (process.env.USE_GEMINI || "false") === "true";

  if (!USE_GEMINI) {
    return "Résumé non disponible: activez USE_GEMINI=true dans votre fichier .env";
  }

  const summaryPrompt = `Donne uniquement les étapes principales de la vidéo YouTube: ${videoTitle}`;
  return await generateWithGemini(summaryPrompt, 80);
};