import express from "express";
import {
    createLesson,
    generateLesson,
    listLessons,
    setFavorite,
    recordView,
    deleteLesson
} from "../controllers/lessonsController.js";

const router = express.Router();

// GET /api/lessons - List lessons for a user
router.get("/", listLessons);

// POST /api/lessons - Create a lesson from chat
router.post("/", createLesson);

// POST /api/generateLesson - Generate a lesson from query
router.post("/generateLesson", generateLesson);

// PATCH /api/lessons/:id/favorite - Set favorite status
router.patch("/:id/favorite", setFavorite);

// POST /api/lessons/:id/view - Record a view
router.post("/:id/view", recordView);

// DELETE /api/lessons/:id - Delete a lesson
router.delete("/:id", deleteLesson);

export default router;