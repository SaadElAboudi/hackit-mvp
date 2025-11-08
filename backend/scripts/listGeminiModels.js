import dotenv from 'dotenv';
dotenv.config();
import axios from 'axios';

const main = async () => {
    const key = process.env.GEMINI_API_KEY;
    if (!key) {
        console.error('GEMINI_API_KEY manquante.');
        process.exit(1);
    }
    try {
        const resp = await axios.get(`https://generativelanguage.googleapis.com/v1/models?key=${key}`);
        const models = resp.data?.models || [];
        // supportedGenerationMethods is an array of method names
        const rows = models.map(m => ({
            name: m.name,
            supportedMethods: Array.isArray(m.supportedGenerationMethods) ? m.supportedGenerationMethods : [],
            displayName: m.displayName,
            description: (m.description || '').slice(0, 80)
        }));
        console.log(JSON.stringify(rows, null, 2));
    } catch (e) {
        console.error('ListModels error:', e?.response?.data || e.message);
        process.exit(1);
    }
};

main();
