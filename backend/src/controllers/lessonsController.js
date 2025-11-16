
import {
    saveLesson,
    setFavorite as setFavoriteDb,
    recordView as recordViewDb,
    listLessons as listLessonsDb
} from '../utils/persistence.js';

/**
 * Create a lesson from chat data
 */
export const createLesson = async (req, res) => {
    try {
        const { userId, title, steps, videoUrl, summary } = req.body;
        if (!userId || !title || !steps || !videoUrl) {
            return res.status(400).json({
                error: "Missing required fields: userId, title, steps, videoUrl"
            });
        }
        const lesson = await saveLesson({ userId, title, steps, videoUrl, summary });
        res.status(201).json(lesson);
    } catch (error) {
        console.error("Create lesson error:", error);
        res.status(500).json({
            error: "Internal server error",
            detail: error.message
        });
    }
};

/**
 * Generate a lesson from a query
 */
export const generateLesson = async (req, res) => {
    try {
        const { query, userId } = req.body;

        if (!query || !userId) {
            return res.status(400).json({
                error: "Missing required fields: query, userId"
            });
        }

        // Check for mock mode
        const MOCK_MODE = (process.env.MOCK_MODE || "true") === "true";
        if (MOCK_MODE) {
            const lesson = {
                id: generateId(),
                userId,
                title: `Leçon: ${query}`,
                steps: [
                    "Étape 1: Préparez vos matériaux",
                    "Étape 2: Suivez les instructions",
                    "Étape 3: Vérifiez votre travail",
                    "Étape 4: Nettoyez l'espace de travail"
                ],
                videoUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                summary: "Cette leçon vous guide à travers les étapes de base.",
                favorite: false,
                views: 0,
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString()
            };

            lessons.push(lesson);
            return res.status(201).json(lesson);
        }

        // Real implementation would:
        // 1. Reformulate query
        // 2. Search YouTube
        // 3. Generate summary with Gemini
        // 4. Create lesson

        // For now, return mock data
        const lesson = {
            id: generateId(),
            userId,
            title: `Leçon générée: ${query}`,
            steps: ["Contenu en cours de génération..."],
            videoUrl: "https://example.com/video",
            summary: null,
            favorite: false,
            views: 0,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
        };

        lessons.push(lesson);
        res.status(201).json(lesson);
    } catch (error) {
        console.error("Generate lesson error:", error);
        res.status(500).json({
            error: "Internal server error",
            detail: error.message
        });
    }
};

/**
 * List lessons for a user
 */
export const listLessons = async (req, res) => {
    try {
        const { userId, favorite, sort = 'createdAt', order = 'desc', limit = 50, offset = 0 } = req.query;
        if (!userId) {
            return res.status(400).json({
                error: "Missing required parameter: userId"
            });
        }
        const lessons = await listLessonsDb({
            userId,
            favorite: favorite !== undefined ? favorite === 'true' : undefined,
            sortBy: sort,
            order,
            limit: parseInt(limit) || 50,
            offset: parseInt(offset) || 0
        });
        res.json({
            items: lessons,
            total: lessons.length,
            limit: parseInt(limit) || 50,
            offset: parseInt(offset) || 0
        });
    } catch (error) {
        console.error("List lessons error:", error);
        res.status(500).json({
            error: "Internal server error",
            detail: error.message
        });
    }
};

/**
 * Set favorite status for a lesson
 */
export const setFavorite = async (req, res) => {
    try {
        const { id } = req.params;
        const { favorite } = req.body;
        if (favorite === undefined) {
            return res.status(400).json({
                error: "Missing required field: favorite"
            });
        }
        const lesson = await setFavoriteDb(id, favorite);
        if (!lesson) {
            return res.status(404).json({ error: "Lesson not found" });
        }
        res.json(lesson);
    } catch (error) {
        console.error("Set favorite error:", error);
        res.status(500).json({
            error: "Internal server error",
            detail: error.message
        });
    }
};

/**
 * Record a view for a lesson
 */
export const recordView = async (req, res) => {
    try {
        const { id } = req.params;
        const lesson = await recordViewDb(id);
        if (!lesson) {
            return res.status(404).json({ error: "Lesson not found" });
        }
        res.json(lesson);
    } catch (error) {
        console.error("Record view error:", error);
        res.status(500).json({
            error: "Internal server error",
            detail: error.message
        });
    }
};

/**
 * Delete a lesson
 */
export const deleteLesson = async (req, res) => {
    try {
        const { id } = req.params;

        const index = lessons.findIndex(l => l.id === id);
        if (index === -1) {
            return res.status(404).json({
                error: "Lesson not found"
            });
        }

        lessons.splice(index, 1);

        res.json({ ok: true });
    } catch (error) {
        console.error("Delete lesson error:", error);
        res.status(500).json({
            error: "Internal server error",
            detail: error.message
        });
    }
};