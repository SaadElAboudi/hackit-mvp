import express from "express";

import { searchQuery } from "../controllers/searchController";

const router = express.Router();

router.post("/", searchQuery);

export default router;