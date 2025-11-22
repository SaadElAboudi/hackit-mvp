// Middleware: accept JWT or Google session
export function requireJwtAuthOrGoogle(req, res, next) {
    // JWT
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.split(' ')[1];
        const payload = verifyToken(token);
        if (payload && payload.userId) {
            req.userId = payload.userId;
            req.jwtUser = payload;
            return next();
        }
    }
    // Google session
    if (req.isAuthenticated?.() && req.user) {
        req.userId = req.user.id || req.user._id;
        return next();
    }
    return res.status(401).json({ error: 'Authentication required (JWT or Google)' });
}
import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';
dotenv.config();

const JWT_SECRET = process.env.JWT_SECRET || 'dev_jwt_secret';

export function issueToken(user) {
    // Only issue token for users with password (not Google-only accounts)
    if (!user.password || user.password === '') return null;
    return jwt.sign({ userId: user._id, email: user.email }, JWT_SECRET, { expiresIn: '7d' });
}

export function verifyToken(token) {
    try {
        return jwt.verify(token, JWT_SECRET);
    } catch (e) {
        return null;
    }
}

export function requireJwtAuth(req, res, next) {
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.split(' ')[1];
        const payload = verifyToken(token);
        if (payload && payload.userId) {
            req.userId = payload.userId;
            req.jwtUser = payload;
            return next();
        }
    }
    return res.status(401).json({ error: 'Authentication required (JWT)' });
}
