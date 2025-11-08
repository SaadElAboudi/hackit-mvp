import OpenAI from "openai";

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export const reformulateQuestion = async (query) => {
  const prompt = `Reformule cette question en anglais pour une recherche YouTube: "${query}"`;
  const response = await client.chat.completions.create({
    model: "gpt-4.1-mini",
    messages: [{ role: "user", content: prompt }],
  });
  return response.choices[0].message.content;
};

export const generateSummary = async (videoTitle) => {
  const summaryPrompt = `Résume cette vidéo YouTube en 5 étapes claires: ${videoTitle}`;
  const response = await client.chat.completions.create({
    model: "gpt-4.1-mini",
    messages: [{ role: "user", content: summaryPrompt }],
  });
  return response.choices[0].message.content;
};