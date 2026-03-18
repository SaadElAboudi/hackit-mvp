function badRequest(message, details) {
  const err = new Error(message);
  err.status = 400;
  err.code = 'BAD_REQUEST';
  err.details = details;
  return err;
}

export function validateBody(validator) {
  return (req, _res, next) => {
    try {
      req.validatedBody = validator(req.body || {});
      return next();
    } catch (err) {
      return next(err);
    }
  };
}

export function validateSearchPayload(body) {
  const query = typeof body.query === 'string' ? body.query.trim() : '';
  if (!query) {
    throw badRequest('query is required', { field: 'query' });
  }
  if (query.length > 1000) {
    throw badRequest('query is too long', { field: 'query', max: 1000 });
  }

  const useGemini = body.useGemini;
  if (useGemini !== undefined && typeof useGemini !== 'boolean') {
    throw badRequest('useGemini must be a boolean', { field: 'useGemini' });
  }

  return { query, useGemini };
}

export function validateFeedbackPayload(body) {
  const requestId = body.requestId === undefined ? '' : String(body.requestId).trim();
  const clicked = Boolean(body.clicked);
  const completed = Boolean(body.completed);
  const rating = body.rating === undefined || body.rating === null ? null : Number(body.rating);

  if (rating !== null && (!Number.isFinite(rating) || rating < 1 || rating > 5)) {
    throw badRequest('rating must be between 1 and 5', { field: 'rating' });
  }

  return { requestId, clicked, completed, rating };
}

export function validateTtvPayload(body) {
  const requestId = body.requestId === undefined ? '' : String(body.requestId).trim();
  const ttvMs = Number(body.ttvMs);

  if (!Number.isFinite(ttvMs) || ttvMs < 0) {
    throw badRequest('ttvMs is required and must be >= 0', { field: 'ttvMs' });
  }

  return { requestId, ttvMs };
}
