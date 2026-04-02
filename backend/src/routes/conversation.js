import express from "express";
import Conversation from "../models/conversation.js";

const router = express.Router();

// GET /conversations - Liste toutes les conversations
router.get("/", async (req, res) => {
    try {
        // Optionnel: filtrer par userId si stocké dans le modèle
        const conversations = await Conversation.find({}, "conversationId createdAt updatedAt");
        res.json(conversations);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// GET /conversations/:id - Récupère l'historique d'une conversation
router.get("/:id", async (req, res) => {
    try {
        const { id } = req.params;
        const conv = await Conversation.findOne({ conversationId: id });
        if (!conv) {
            return res.status(404).json({ message: "Conversation not found" });
        }
        res.json({
            conversationId: conv.conversationId,
            messages: conv.messages.map(m => ({ role: m.role, content: m.content, timestamp: m.timestamp })),
            createdAt: conv.createdAt,
            updatedAt: conv.updatedAt
        });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

export default router;
