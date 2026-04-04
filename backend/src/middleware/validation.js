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

  const rawContext = body.context && typeof body.context === 'object' ? body.context : {};
  const clientType = rawContext.clientType === undefined ? '' : String(rawContext.clientType).trim();
  const budget = rawContext.budget === undefined ? '' : String(rawContext.budget).trim();
  const deadline = rawContext.deadline === undefined ? '' : String(rawContext.deadline).trim();
  const maturity = rawContext.maturity === undefined ? '' : String(rawContext.maturity).trim();

  if (clientType.length > 80) {
    throw badRequest('context.clientType is too long', { field: 'context.clientType', max: 80 });
  }
  if (budget.length > 80) {
    throw badRequest('context.budget is too long', { field: 'context.budget', max: 80 });
  }
  if (deadline.length > 80) {
    throw badRequest('context.deadline is too long', { field: 'context.deadline', max: 80 });
  }
  if (maturity.length > 80) {
    throw badRequest('context.maturity is too long', { field: 'context.maturity', max: 80 });
  }

  const context = {
    clientType: clientType || null,
    budget: budget || null,
    deadline: deadline || null,
    maturity: maturity || null,
  };

  return { query, useGemini, summaryLength, context };
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
