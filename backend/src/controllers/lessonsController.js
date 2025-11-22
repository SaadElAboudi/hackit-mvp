
import Lesson from '../models/lesson.js';
import User from '../models/User.js';

// Fonction utilitaire pour mettre à jour le favoris
export async function updateFavorite(id, favorite) {
    const mongoose = require('mongoose');
    let lesson = null;
    if (mongoose.Types.ObjectId.isValid(id)) {
        lesson = await Lesson.findByIdAndUpdate(id, { favorite }, { new: true });
    }
    return lesson;
}

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
        // Create lesson in MongoDB
        const lesson = await Lesson.create({ userId, title, steps, videoUrl, summary });
        // Link lesson to user's savedLessons
        await User.findByIdAndUpdate(userId, { $push: { savedLessons: lesson._id } });
        res.status(201).json(lesson);
    } catch (error) {
        console.error("Create lesson error:", error);
        // Log full error object for debugging
        try {
            console.error("Full error:", JSON.stringify(error, Object.getOwnPropertyNames(error)));
        } catch (e) {
            console.error("Error stringification failed:", e);
        }
        res.status(500).json({
            error: "Internal server error",
            detail: error.message,
            stack: error.stack,
            name: error.name
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
        const mongoose = require('mongoose');
        let lessons = [];
        if (mongoose.Types.ObjectId.isValid(userId)) {
            // Registered user: get savedLessons
            const user = await User.findById(userId).populate({
                path: 'savedLessons',
                match: favorite !== undefined ? { favorite: favorite === 'true' } : {},
                options: {
                    sort: { [sort]: order === 'asc' ? 1 : -1 },
                    limit: parseInt(limit) || 50,
                    skip: parseInt(offset) || 0
                }
            });
            if (!user) {
                return res.status(404).json({ error: 'Utilisateur non trouvé.' });
            }
            lessons = user.savedLessons || [];
        } else {
            // Guest/anonymous: get lessons by userId field
            lessons = await Lesson.find({ userId }).sort({ [sort]: order === 'asc' ? 1 : -1 }).limit(parseInt(limit) || 50).skip(parseInt(offset) || 0);
            if (favorite !== undefined) {
                lessons = lessons.filter(l => !!l.favorite === (favorite === 'true'));
            }
        }
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
        const mongoose = require('mongoose');
        let lesson = null;
        if (mongoose.Types.ObjectId.isValid(id)) {
            lesson = await Lesson.findByIdAndUpdate(id, { favorite }, { new: true });
        }
        // Always return success, even for guest/invalid ids
        res.json({ ok: true, lesson });
    } catch (error) {
        console.error("Set favorite error:", error);
        res.json({ ok: true });
    }
};

/**
 * Record a view for a lesson
 */
export const recordView = async (req, res) => {
    try {
        const { id } = req.params;
        const lesson = await Lesson.findByIdAndUpdate(id, {
            $inc: { views: 1 },
            lastViewedAt: new Date(),
            updatedAt: new Date()
        }, { new: true });
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
        const mongoose = require('mongoose');
        // Only delete from MongoDB if id is a valid ObjectId
        if (mongoose.Types.ObjectId.isValid(id)) {
            await Lesson.findByIdAndDelete(id);
            await User.updateMany({}, { $pull: { savedLessons: id } });
        }
        // Always return success, even for guest/invalid ids
        res.json({ ok: true });
    } catch (error) {
        console.error("Delete lesson error:", error);
        res.json({ ok: true });
    }
};