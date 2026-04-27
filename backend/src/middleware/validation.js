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

function normalizeMember(member) {
  const userId = String(member?.userId || '').trim();
  const displayName = String(member?.displayName || '').trim();
  const rawRole = String(member?.role || 'member').trim();
  const role = ['owner', 'member', 'guest'].includes(rawRole) ? rawRole : 'member';

  return {
    userId,
    displayName: displayName || (userId ? `User_${userId.slice(-6)}` : ''),
    role,
  };
}

export function validateCreateRoomPayload(body) {
  const name = String(body?.name || '').trim().slice(0, 120);
  const type = String(body?.type || 'group').trim();
  const purpose = String(body?.purpose || '').trim().slice(0, 240);
  const visibility = String(body?.visibility || 'invite_only').trim();

  if (!['dm', 'group'].includes(type)) {
    throw badRequest('type must be "dm" or "group"', { field: 'type' });
  }
  if (!['invite_only', 'public'].includes(visibility)) {
    throw badRequest('visibility must be "invite_only" or "public"', { field: 'visibility' });
  }

  const rawMembers = Array.isArray(body?.members) ? body.members : [];
  const members = rawMembers
    .map((member) => normalizeMember(member))
    .filter((member) => member.userId);

  return { name, type, purpose, visibility, members };
}

export function validateSendMessagePayload(body) {
  const content = String(body?.content || '').trim();
  if (!content) {
    throw badRequest('content is required', { field: 'content' });
  }
  if (content.length > 8000) {
    throw badRequest('content is too long', { field: 'content', max: 8000 });
  }
  return { content };
}

export function validateDirectivesPayload(body) {
  const directives = String(body?.directives || '').slice(0, 2000);
  return { directives };
}

export function validateAddMemberPayload(body) {
  const userId = String(body?.userId || '').trim();
  if (!userId) {
    throw badRequest('userId is required', { field: 'userId' });
  }
  const displayName = String(body?.displayName || '').trim();
  const rawRole = String(body?.role || 'member').trim();
  const role = ['owner', 'member', 'guest'].includes(rawRole) ? rawRole : 'member';
  return {
    userId,
    displayName,
    role,
  };
}

export function validateCreateArtifactPayload(body) {
  const title = String(body?.title || '').trim().slice(0, 140);
  const content = String(body?.content || '').trim();
  if (!content) {
    throw badRequest('content is required', { field: 'content' });
  }
  const rawKind = String(body?.kind || 'canvas').trim();
  const kind = ['canvas', 'document', 'decision', 'research'].includes(rawKind) ? rawKind : 'canvas';
  return {
    title,
    content,
    kind,
  };
}

export function validateCreateMissionPayload(body) {
  const prompt = String(body?.prompt || '').trim();
  if (!prompt) {
    throw badRequest('prompt is required', { field: 'prompt' });
  }
  const agentType = String(body?.agentType || 'auto').trim().toLowerCase();
  return {
    prompt,
    agentType,
  };
}

export function validateCreateMemoryPayload(body) {
  const content = String(body?.content || '').trim();
  if (!content) {
    throw badRequest('content is required', { field: 'content' });
  }
  const rawType = String(body?.type || 'fact').trim();
  const type = ['fact', 'preference', 'decision'].includes(rawType) ? rawType : 'fact';
  const pinned = body?.pinned !== false;
  return {
    content,
    type,
    pinned,
  };
}

export function validateArtifactStatusPayload(body) {
  const VALID_STATUSES = ['draft', 'review', 'validated', 'archived'];
  const status = String(body?.status || '').trim();
  if (!status) {
    throw badRequest('status is required', { field: 'status' });
  }
  if (!VALID_STATUSES.includes(status)) {
    throw badRequest(
      `status must be one of: ${VALID_STATUSES.join(', ')}`,
      { field: 'status', received: status }
    );
  }
  return { status };
}

export function validateReviseArtifactPayload(body) {
  const instructions = String(body?.instructions || '').trim();
  if (!instructions) {
    throw badRequest('instructions is required', { field: 'instructions' });
  }
  if (instructions.length > 2000) {
    throw badRequest('instructions must be 2000 characters or fewer', {
      field: 'instructions',
      maxLength: 2000,
    });
  }
  const changeSummary = String(body?.changeSummary || '').trim().slice(0, 400);
  return { instructions, changeSummary };
}

export function validateResolveCommentPayload(body) {
  const resolved = body?.resolved !== false;
  return { resolved };
}

export function validateSharePayload(body) {
  const target = String(body?.target || 'slack').trim().toLowerCase();
  if (!['slack', 'notion'].includes(target)) {
    throw badRequest('target must be one of: slack, notion', {
      field: 'target',
      received: target,
    });
  }

  const note = String(body?.note || '').trim().slice(0, 300);
  const artifactId = String(body?.artifactId || '').trim();
  const idempotencyKey = String(body?.idempotencyKey || '').trim().slice(0, 120);

  return {
    target,
    note,
    artifactId,
    idempotencyKey,
  };
}

export function validateShareHistoryQuery(query) {
  const target = String(query?.target || '').trim().toLowerCase();
  const status = String(query?.status || '').trim().toLowerCase();
  const artifactId = String(query?.artifactId || '').trim();
  const limitRaw = Number(query?.limit || 20);
  const limit = Number.isFinite(limitRaw)
    ? Math.min(100, Math.max(1, Math.floor(limitRaw)))
    : 20;

  if (target && !['slack', 'notion'].includes(target)) {
    throw badRequest('target must be one of: slack, notion', {
      field: 'target',
      received: target,
    });
  }

  if (status && !['pending', 'success', 'failed'].includes(status)) {
    throw badRequest('status must be one of: pending, success, failed', {
      field: 'status',
      received: status,
    });
  }

  return {
    target,
    status,
    artifactId,
    limit,
  };
}

export function validateCreateWorkspacePagePayload(body) {
  const title = String(body?.title || '').trim().slice(0, 180) || 'Untitled page';
  const icon = String(body?.icon || '').trim().slice(0, 8);
  const coverUrl = String(body?.coverUrl || '').trim().slice(0, 500);
  const summary = String(body?.summary || '').trim().slice(0, 500);
  return { title, icon, coverUrl, summary };
}

export function validateUpdateWorkspacePagePayload(body) {
  const next = {};
  if (body?.title !== undefined) {
    const title = String(body.title || '').trim().slice(0, 180);
    if (!title) {
      throw badRequest('title must not be empty', { field: 'title' });
    }
    next.title = title;
  }
  if (body?.icon !== undefined) {
    next.icon = String(body.icon || '').trim().slice(0, 8);
  }
  if (body?.coverUrl !== undefined) {
    next.coverUrl = String(body.coverUrl || '').trim().slice(0, 500);
  }
  if (body?.summary !== undefined) {
    next.summary = String(body.summary || '').trim().slice(0, 500);
  }
  if (body?.status !== undefined) {
    const status = String(body.status || '').trim();
    const valid = ['draft', 'review', 'published', 'archived'];
    if (!valid.includes(status)) {
      throw badRequest(`status must be one of: ${valid.join(', ')}`, {
        field: 'status',
        received: status,
      });
    }
    next.status = status;
  }
  if (!Object.keys(next).length) {
    throw badRequest('at least one field must be provided', {
      field: 'body',
    });
  }
  return next;
}

export function validateCreateWorkspaceBlockPayload(body) {
  const type = String(body?.type || 'paragraph').trim();
  const valid = ['paragraph', 'heading1', 'heading2', 'heading3', 'checklist', 'quote', 'callout', 'divider'];
  if (!valid.includes(type)) {
    throw badRequest(`type must be one of: ${valid.join(', ')}`, {
      field: 'type',
      received: type,
    });
  }
  const text = String(body?.text || '').trim().slice(0, 10000);
  const checked = body?.checked === true;
  const attrs = body?.attrs && typeof body.attrs === 'object' && !Array.isArray(body.attrs)
    ? body.attrs
    : {};
  return { type, text, checked, attrs };
}

export function validateUpdateWorkspaceBlockPayload(body) {
  const next = {};
  if (body?.expectedVersion !== undefined) {
    const expectedVersion = Number(body.expectedVersion);
    if (!Number.isInteger(expectedVersion) || expectedVersion < 1) {
      throw badRequest('expectedVersion must be an integer >= 1', {
        field: 'expectedVersion',
      });
    }
    next.expectedVersion = expectedVersion;
  }
  if (body?.type !== undefined) {
    const type = String(body.type || '').trim();
    const valid = ['paragraph', 'heading1', 'heading2', 'heading3', 'checklist', 'quote', 'callout', 'divider'];
    if (!valid.includes(type)) {
      throw badRequest(`type must be one of: ${valid.join(', ')}`, {
        field: 'type',
        received: type,
      });
    }
    next.type = type;
  }
  if (body?.text !== undefined) {
    next.text = String(body.text || '').trim().slice(0, 10000);
  }
  if (body?.checked !== undefined) {
    if (typeof body.checked !== 'boolean') {
      throw badRequest('checked must be a boolean', {
        field: 'checked',
      });
    }
    next.checked = body.checked;
  }
  if (body?.attrs !== undefined) {
    if (!body.attrs || typeof body.attrs !== 'object' || Array.isArray(body.attrs)) {
      throw badRequest('attrs must be an object', {
        field: 'attrs',
      });
    }
    next.attrs = body.attrs;
  }
  if (!Object.keys(next).length) {
    throw badRequest('at least one field must be provided', {
      field: 'body',
    });
  }
  return next;
}

export function validateReorderWorkspaceBlocksPayload(body) {
  const orders = Array.isArray(body?.orders) ? body.orders : null;
  if (!orders || !orders.length) {
    throw badRequest('orders is required and must be a non-empty array', {
      field: 'orders',
    });
  }

  const normalized = orders.map((entry) => {
    const blockId = String(entry?.blockId || '').trim();
    const order = Number(entry?.order);
    if (!blockId) {
      throw badRequest('orders[].blockId is required', { field: 'orders.blockId' });
    }
    if (!Number.isInteger(order) || order < 0) {
      throw badRequest('orders[].order must be an integer >= 0', {
        field: 'orders.order',
      });
    }
    return { blockId, order };
  });

  return { orders: normalized };
}

export function validateCreateWorkspaceCommentPayload(body) {
  const blockId = String(body?.blockId || '').trim();
  if (!blockId) {
    throw badRequest('blockId is required', { field: 'blockId' });
  }
  const text = String(body?.text || '').trim();
  if (!text) {
    throw badRequest('text is required', { field: 'text' });
  }
  if (text.length > 2000) {
    throw badRequest('text must be 2000 characters or fewer', {
      field: 'text',
      maxLength: 2000,
    });
  }
  return { blockId, text };
}

export function validateResolveWorkspaceCommentPayload(body) {
  if (body?.resolved !== undefined && typeof body.resolved !== 'boolean') {
    throw badRequest('resolved must be a boolean', { field: 'resolved' });
  }
  return {
    resolved: body?.resolved !== false,
  };
}
