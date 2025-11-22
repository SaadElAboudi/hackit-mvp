import express from 'express';
import bcrypt from 'bcryptjs';
import User from '../models/User.js';
const router = express.Router();

// Inscription
router.post('/register', async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ error: 'Email et mot de passe requis.' });
    try {
        const existing = await User.findOne({ email });
        if (existing) return res.status(409).json({ error: 'Utilisateur déjà existant.' });
        const hash = await bcrypt.hash(password, 10);
        const user = new User({ email, password: hash });
        await user.save();
        res.status(201).json({ message: 'Inscription réussie.' });
    } catch (e) {
        res.status(500).json({ error: 'Erreur serveur.' });
    }
});

// Connexion
router.post('/login', async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ error: 'Email et mot de passe requis.' });
    try {
        const user = await User.findOne({ email });
        if (!user) return res.status(404).json({ error: 'Utilisateur non trouvé.' });
        // Block Google-only accounts (no password set)
        if (!user.password || user.password === '') {
            return res.status(403).json({ error: 'Connexion par mot de passe non autorisée pour ce compte.' });
        }
        const valid = await bcrypt.compare(password, user.password);
        if (!valid) return res.status(401).json({ error: 'Mot de passe incorrect.' });
        // Issue JWT token
        const { issueToken } = await import('../utils/jwtAuth.js');
        const token = issueToken(user);
        res.json({ message: 'Connexion réussie.', userId: user._id, token });
    } catch (e) {
        res.status(500).json({ error: 'Erreur serveur.' });
    }
});

// Historique
router.get('/:userId/history', async (req, res) => {
    try {
        const user = await User.findById(req.params.userId);
        if (!user) return res.status(404).json({ error: 'Utilisateur non trouvé.' });
        res.json(user.history);
    } catch (e) {
        res.status(500).json({ error: 'Erreur serveur.' });
    }
});

// Favoris
router.get('/:userId/favorites', async (req, res) => {
    try {
        const user = await User.findById(req.params.userId).populate('favorites');
        if (!user) return res.status(404).json({ error: 'Utilisateur non trouvé.' });
        res.json(user.favorites);
    } catch (e) {
        res.status(500).json({ error: 'Erreur serveur.' });
    }
});

// Leçons enregistrées
router.get('/:userId/saved-lessons', async (req, res) => {
    try {
        const user = await User.findById(req.params.userId).populate('savedLessons');
        if (!user) return res.status(404).json({ error: 'Utilisateur non trouvé.' });
        res.json(user.savedLessons);
    } catch (e) {
        res.status(500).json({ error: 'Erreur serveur.' });
    }
});

// Endpoint admin pour lister tous les utilisateurs
router.get('/all', async (req, res) => {
    try {
        const users = await User.find({}, '-password'); // Exclure le hash du mot de passe
        res.json(users);
    } catch (e) {
        res.status(500).json({ error: 'Erreur serveur.' });
    }
});

export default router;
