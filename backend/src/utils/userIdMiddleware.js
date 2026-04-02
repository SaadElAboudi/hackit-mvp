import crypto from 'crypto';

export function userIdMiddleware(req, res, next) {
  let userId = req.userId || req.header('x-user-id') || req.query.userId || req.body?.userId;

  if (!userId && req.headers.cookie) {
    try {
      const match = req.headers.cookie.match(/userId=([^;]+)/);
      if (match) userId = match[1];
    } catch (_err) {
      // ignore malformed cookie header
    }
  }

  if (!userId) {
    userId = `anon_${crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2)}`;
    req.isAnonymous = true;

    try {
      if (res.cookie) {
        res.cookie('userId', userId, { maxAge: 1000 * 3600 * 24 * 365, httpOnly: false, sameSite: 'lax' });
      } else {
        res.setHeader('Set-Cookie', `userId=${userId}; Path=/; Max-Age=31536000; SameSite=Lax`);
      }
    } catch (_err) {
      // ignore cookie write failure
    }
  }

  req.userId = String(userId);
  next();
}
