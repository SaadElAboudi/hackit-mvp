import axios from "axios";

/**
 * Service Gemini - Gère toutes les interactions avec l'API Gemini de Google
 */

/**
 * Generate text using Gemini API
 * @param {string} prompt - Le prompt à envoyer à Gemini
 * @param {number} maxOutputTokens - Nombre maximum de tokens dans la réponse
 * @returns {Promise<string>} - Texte généré
 */
export const generateWithGemini = async (prompt, maxOutputTokens = 256) => {
  const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
  const CONFIG_MODEL = process.env.GEMINI_MODEL || "models/gemini-1.5-flash";

  if (!GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY manquante dans les variables d'environnement");
  }

  const buildRequest = (model) => {
    const isLegacyPalm = /bison/i.test(model);
    const url = isLegacyPalm
      ? `https://generativelanguage.googleapis.com/v1beta2/${model}:generateText?key=${GEMINI_API_KEY}`
      : `https://generativelanguage.googleapis.com/v1/${model}:generateContent?key=${GEMINI_API_KEY}`;

    const body = isLegacyPalm
      ? {
        prompt: { text: prompt },
        maxOutputTokens,
        temperature: 0.2,
      }
      : {
        contents: [
          {
            role: "user",
            parts: [{ text: prompt }],
          },
        ],
        generationConfig: {
          maxOutputTokens,
          temperature: 0.2,
        },
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
  // 1) configured model
  tryModels.push(CONFIG_MODEL);
  // 2) if ends with -latest, try base name
  if (/-latest$/i.test(CONFIG_MODEL)) {
    tryModels.push(CONFIG_MODEL.replace(/-latest$/i, ""));
  }
  // 3) modern defaults
  for (const candidate of [
    "models/gemini-2.5-flash",
    "models/gemini-2.5-pro",
    "models/gemini-2.0-flash",
    "models/gemini-1.5-flash",
  ]) {
    if (!tryModels.includes(candidate)) tryModels.push(candidate);
  }
  // 4) legacy fallback if v1 model not available
  if (!tryModels.includes("models/text-bison-001")) {
    tryModels.push("models/text-bison-001");
  }

  let lastError;
  for (const model of tryModels) {
    try {
      const { url, body, parse } = buildRequest(model);
      const resp = await axios.post(url, body, {
        headers: { "Content-Type": "application/json" },
        timeout: 15000,
      });
      const text = parse(resp.data);
      if (!text) throw new Error(`Pas de contenu généré par Gemini (${model})`);
      return text;
    } catch (error) {
      lastError = error;
      const status = error?.response?.status;
      const message = error?.response?.data?.error?.message || error.message;
      const isNotFound = status === 404 || /not\s*found/i.test(message || "");
      const isBlocked = /blocked|safety/i.test(message || "") || /Contenu bloqué/.test(error?.message || "");
      // Continue on NOT_FOUND or BLOCKED; otherwise break early
      if (!isNotFound && !isBlocked) {
        console.error("Erreur API Gemini:", error?.response?.data || error.message);
        throw error;
      }
      console.warn(`Modèle indisponible ou sortie bloquée (${model}), tentative avec un autre modèle...`);
      // loop continues
    }
  }

  console.error("Erreur API Gemini:", lastError?.response?.data || lastError?.message || lastError);
  throw lastError || new Error("Échec de génération Gemini");
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

  const summaryPrompt = `Résume cette vidéo YouTube en 5 étapes claires: ${videoTitle}`;
  return await generateWithGemini(summaryPrompt, 300);
};