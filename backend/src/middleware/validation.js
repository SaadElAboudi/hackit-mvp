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

  const summaryLength = body.summaryLength === undefined ? 'standard' : String(body.summaryLength).trim().toLowerCase();
  if (!['tldr', 'standard', 'deep'].includes(summaryLength)) {
    throw badRequest('summaryLength must be one of: tldr, standard, deep', { field: 'summaryLength' });
  }

  let maxResults;
  if (body.maxResults !== undefined) {
    maxResults = Number(body.maxResults);
    if (!Number.isInteger(maxResults) || maxResults < 1 || maxResults > 10) {
      throw badRequest('maxResults must be an integer between 1 and 10', { field: 'maxResults' });
    }
  }

  let pageToken;
  if (body.pageToken !== undefined) {
    pageToken = String(body.pageToken).trim();
    if (!pageToken) {
      pageToken = undefined;
    } else if (pageToken.length > 256) {
      throw badRequest('pageToken is too long', { field: 'pageToken', max: 256 });
    }
  }

  let tone;
  if (body.tone !== undefined) {
    tone = String(body.tone).trim().toLowerCase();
    if (!['practical', 'friendly', 'coach'].includes(tone)) {
      throw badRequest('tone must be one of: practical, friendly, coach', { field: 'tone' });
    }
  }

  let expertiseLevel;
  if (body.expertiseLevel !== undefined) {
    expertiseLevel = String(body.expertiseLevel).trim().toLowerCase();
    if (!['beginner', 'intermediate', 'advanced'].includes(expertiseLevel)) {
      throw badRequest('expertiseLevel must be one of: beginner, intermediate, advanced', { field: 'expertiseLevel' });
    }
  }

  return { query, useGemini, summaryLength, maxResults, pageToken, tone, expertiseLevel };
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
