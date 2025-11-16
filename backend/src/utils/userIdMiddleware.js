// Simple middleware to extract userId from header or query, or generate anonymous if missing
import crypto from 'crypto';

export function userIdMiddleware(req, res, next) {
    console.log('[userIdMiddleware] headers:', req.headers);
    console.log('[userIdMiddleware] query:', req.query);
    console.log('[userIdMiddleware] body:', req.body);
    let userId = req.header('x-user-id') || req.query.userId || req.body?.userId;
    // Try to get from cookie if not present
    if (!userId && req.headers.cookie) {
        try {
            const match = req.headers.cookie.match(/userId=([^;]+)/);
            if (match) userId = match[1];
        } catch (err) {
            console.error('[userIdMiddleware] Cookie parse error:', err);
        }
    }
    if (!userId) {
        userId = 'anon_' + (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));
        req.isAnonymous = true;
        // Set cookie for future requests (httpOnly=false for SPA access)
        try {
            if (res.cookie) {
                res.cookie('userId', userId, { maxAge: 1000 * 3600 * 24 * 365, httpOnly: false, sameSite: 'lax' });
            } else {
                res.setHeader('Set-Cookie', `userId=${userId}; Path=/; Max-Age=31536000; SameSite=Lax`);
            }
        } catch (err) {
            console.error('[userIdMiddleware] Set-Cookie error:', err);
        }
    }
    console.log('[userIdMiddleware] resolved userId:', userId);
    req.userId = userId;
    next();
}
