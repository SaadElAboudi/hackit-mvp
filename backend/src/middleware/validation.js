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

export function validateCreateWorkspaceDecisionPayload(body) {
  const title = String(body?.title || '').trim();
  if (!title) {
    throw badRequest('title is required', { field: 'title' });
  }
  const sourceType = String(body?.sourceType || 'manual').trim();
  const validSourceTypes = ['manual', 'mission', 'message', 'artifact'];
  if (!validSourceTypes.includes(sourceType)) {
    throw badRequest(`sourceType must be one of: ${validSourceTypes.join(', ')}`, {
      field: 'sourceType',
      received: sourceType,
    });
  }

  const summary = String(body?.summary || '').trim().slice(0, 2000);
  const sourceId = String(body?.sourceId || '').trim().slice(0, 120);
  const pageId = String(body?.pageId || '').trim();

  return {
    title: title.slice(0, 180),
    summary,
    sourceType,
    sourceId,
    pageId,
  };
}

export function validateCreateWorkspaceTaskPayload(body) {
  const title = String(body?.title || '').trim();
  if (!title) {
    throw badRequest('title is required', { field: 'title' });
  }

  const dueDateRaw = String(body?.dueDate || '').trim();
  let dueDate = null;
  if (dueDateRaw) {
    const parsed = new Date(dueDateRaw);
    if (Number.isNaN(parsed.getTime())) {
      throw badRequest('dueDate must be a valid date', { field: 'dueDate' });
    }
    dueDate = parsed;
  }

  return {
    title: title.slice(0, 180),
    description: String(body?.description || '').trim().slice(0, 2000),
    ownerId: String(body?.ownerId || '').trim().slice(0, 120),
    ownerName: String(body?.ownerName || '').trim().slice(0, 120),
    dueDate,
  };
}

export function validateConvertDecisionToTasksPayload(body) {
  const tasks = Array.isArray(body?.tasks) ? body.tasks : [];
  if (!tasks.length) {
    throw badRequest('tasks is required and must be a non-empty array', {
      field: 'tasks',
    });
  }

  return {
    tasks: tasks.map((task, index) => {
      const title = String(task?.title || '').trim();
      if (!title) {
        throw badRequest(`tasks[${index}].title is required`, {
          field: `tasks.${index}.title`,
        });
      }

      const dueDateRaw = String(task?.dueDate || '').trim();
      let dueDate = null;
      if (dueDateRaw) {
        const parsed = new Date(dueDateRaw);
        if (Number.isNaN(parsed.getTime())) {
          throw badRequest(`tasks[${index}].dueDate must be a valid date`, {
            field: `tasks.${index}.dueDate`,
          });
        }
        dueDate = parsed;
      }

      return {
        title: title.slice(0, 180),
        description: String(task?.description || '').trim().slice(0, 2000),
        ownerId: String(task?.ownerId || '').trim().slice(0, 120),
        ownerName: String(task?.ownerName || '').trim().slice(0, 120),
        dueDate,
      };
    }),
  };
}

export function validateUpdateWorkspaceTaskPayload(body) {
  const next = {};
  if (body?.title !== undefined) {
    const title = String(body.title || '').trim();
    if (!title) {
      throw badRequest('title must not be empty', { field: 'title' });
    }
    next.title = title.slice(0, 180);
  }
  if (body?.description !== undefined) {
    next.description = String(body.description || '').trim().slice(0, 2000);
  }
  if (body?.status !== undefined) {
    const status = String(body.status || '').trim();
    const validStatuses = ['todo', 'in_progress', 'blocked', 'done'];
    if (!validStatuses.includes(status)) {
      throw badRequest(`status must be one of: ${validStatuses.join(', ')}`, {
        field: 'status',
        received: status,
      });
    }
    next.status = status;
  }
  if (body?.ownerId !== undefined) {
    next.ownerId = String(body.ownerId || '').trim().slice(0, 120);
  }
  if (body?.ownerName !== undefined) {
    next.ownerName = String(body.ownerName || '').trim().slice(0, 120);
  }
  if (body?.dueDate !== undefined) {
    if (!body.dueDate) {
      next.dueDate = null;
    } else {
      const parsed = new Date(String(body.dueDate));
      if (Number.isNaN(parsed.getTime())) {
        throw badRequest('dueDate must be a valid date', { field: 'dueDate' });
      }
      next.dueDate = parsed;
    }
  }
  if (!Object.keys(next).length) {
    throw badRequest('at least one field must be provided', {
      field: 'body',
    });
  }
  return next;
}

export function validateExtractWorkspaceDecisionsPayload(body) {
  const recentLimitRaw = Number(body?.recentLimit ?? 30);
  const maxDecisionsRaw = Number(body?.maxDecisions ?? 5);
  const maxTasksPerDecisionRaw = Number(body?.maxTasksPerDecision ?? 4);
  const persist = body?.persist !== false;
  const missionId = String(body?.missionId || '').trim();

  if (!Number.isInteger(recentLimitRaw) || recentLimitRaw < 5 || recentLimitRaw > 120) {
    throw badRequest('recentLimit must be an integer between 5 and 120', {
      field: 'recentLimit',
    });
  }
  if (!Number.isInteger(maxDecisionsRaw) || maxDecisionsRaw < 1 || maxDecisionsRaw > 12) {
    throw badRequest('maxDecisions must be an integer between 1 and 12', {
      field: 'maxDecisions',
    });
  }
  if (!Number.isInteger(maxTasksPerDecisionRaw) || maxTasksPerDecisionRaw < 1 || maxTasksPerDecisionRaw > 10) {
    throw badRequest('maxTasksPerDecision must be an integer between 1 and 10', {
      field: 'maxTasksPerDecision',
    });
  }
  if (body?.persist !== undefined && typeof body.persist !== 'boolean') {
    throw badRequest('persist must be a boolean', { field: 'persist' });
  }
  if (body?.missionId !== undefined && !missionId) {
    throw badRequest('missionId must be a non-empty string when provided', {
      field: 'missionId',
    });
  }

  return {
    recentLimit: recentLimitRaw,
    maxDecisions: maxDecisionsRaw,
    maxTasksPerDecision: maxTasksPerDecisionRaw,
    persist,
    missionId,
  };
}

export function validateCreateMilestonePayload(body) {
  const title = String(body?.title || '').trim();
  if (!title) {
    throw badRequest('title is required', { field: 'title' });
  }
  const targetDateRaw = String(body?.targetDate || '').trim();
  let targetDate = null;
  if (targetDateRaw) {
    const parsed = new Date(targetDateRaw);
    if (Number.isNaN(parsed.getTime())) {
      throw badRequest('targetDate must be a valid date', { field: 'targetDate' });
    }
    targetDate = parsed;
  }
  return {
    title: title.slice(0, 180),
    description: String(body?.description || '').trim().slice(0, 2000),
    targetDate,
  };
}

export function validateChallengePayload(body) {
  const content = String(body?.content || '').trim();
  if (!content) {
    throw badRequest('content is required', { field: 'content' });
  }
  if (content.length > 2000) {
    throw badRequest('content must be 2000 characters or fewer', { field: 'content', maxLength: 2000 });
  }
  return { content };
}

export function validateArtifactCommentPayload(body) {
  const content = String(body?.content || '').trim();
  if (!content) {
    throw badRequest('content is required', { field: 'content' });
  }
  if (content.length > 2000) {
    throw badRequest('content must be 2000 characters or fewer', { field: 'content', maxLength: 2000 });
  }
  return { content };
}

export function validateArtifactRejectPayload(body) {
  const reason = String(body?.reason || '').trim().slice(0, 400);
  return { reason };
}

export function validateRoomSearchPayload(body) {
  const query = String(body?.query || '').trim();
  if (!query) {
    throw badRequest('query is required', { field: 'query' });
  }
  if (query.length > 1000) {
    throw badRequest('query is too long', { field: 'query', max: 1000 });
  }
  return { query };
}

export function validateCreateDocumentPayload(body) {
  const content = String(body?.content || '').trim();
  if (!content) {
    throw badRequest('content is required', { field: 'content' });
  }
  return {
    title: String(body?.title || '').trim().slice(0, 180),
    content,
  };
}

export function validateConnectSlackPayload(body) {
  const botToken = String(body?.botToken || '').trim();
  const channelId = String(body?.channelId || '').trim();

  if (!botToken) {
    throw badRequest('botToken is required', { field: 'botToken' });
  }
  if (!channelId) {
    throw badRequest('channelId is required', { field: 'channelId' });
  }
  if (!/^xoxb-/.test(botToken)) {
    throw badRequest('botToken must be a Slack Bot token (starts with xoxb-)', { field: 'botToken' });
  }
  if (!/^[CG][A-Z0-9]{6,}$/.test(channelId)) {
    throw badRequest('channelId must be a Slack channel ID (e.g. C012AB3CD)', { field: 'channelId' });
  }
  return { botToken, channelId };
}

export function validateConnectNotionPayload(body) {
  const apiToken = String(body?.apiToken || '').trim();
  const parentPageId = String(body?.parentPageId || '').trim();

  if (!apiToken) {
    throw badRequest('apiToken is required', { field: 'apiToken' });
  }
  if (!parentPageId) {
    throw badRequest('parentPageId is required', { field: 'parentPageId' });
  }
  if (!/^(secret_|ntn_)/.test(apiToken)) {
    throw badRequest('apiToken must be a Notion integration token (starts with secret_ or ntn_)', { field: 'apiToken' });
  }
  return { apiToken, parentPageId };
}

export function validateDiscoverNotionPagesPayload(body) {
  const apiToken = String(body?.apiToken || '').trim();
  if (!apiToken) {
    throw badRequest('apiToken is required', { field: 'apiToken' });
  }
  if (!/^(secret_|ntn_)/.test(apiToken)) {
    throw badRequest('apiToken must be a Notion integration token (starts with secret_ or ntn_)', { field: 'apiToken' });
  }
  const query = String(body?.query || '').trim().slice(0, 200);
  const limitRaw = Number(body?.limit);
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(50, limitRaw)) : 20;
  return { apiToken, query, limit };
}

export function validateAiFeedbackPayload(body) {
  const rating = Number(body?.rating);
  if (![-1, 1].includes(rating)) {
    throw badRequest('rating must be 1 (thumbs up) or -1 (thumbs down)', { field: 'rating' });
  }
  return { rating };
}
