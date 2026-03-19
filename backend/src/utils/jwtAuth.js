import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';

dotenv.config();

const JWT_SECRET = process.env.JWT_SECRET || 'dev_jwt_secret';

export function issueToken(user) {
  // Optional token generation kept for future compatibility.
  if (!user?.password || user.password === '') return null;
  return jwt.sign({ userId: user._id, email: user.email }, JWT_SECRET, { expiresIn: '7d' });
}

export function verifyToken(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (_e) {
    return null;
  }
}

function resolveUserId(req) {
  // 1) JWT (optional)
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    const payload = verifyToken(token);
    if (payload && payload.userId) {
      req.jwtUser = payload;
      return String(payload.userId);
    }
  }

  // 2) Google session (optional)
  if (req.isAuthenticated?.() && req.user) {
    return String(req.user.id || req.user._id || '');
  }

  // 3) Anonymous fallback (auth-free mode)
  return null;
}

// Backward-compatible middleware name; now permissive for auth-free development mode.
export function requireJwtAuthOrGoogle(req, _res, next) {
  const resolvedUserId = resolveUserId(req);
  if (resolvedUserId) {
    req.userId = resolvedUserId;
  }
  return next();
}

// Kept for compatibility; also permissive in current stage.
export function requireJwtAuth(req, _res, next) {
  const resolvedUserId = resolveUserId(req);
  if (resolvedUserId) {
    req.userId = resolvedUserId;
  }
  return next();
}
