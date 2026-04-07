import mongoose from 'mongoose';

/**
 * Thread — a persistent conversation within a Project.
 *
 * Each thread holds an ordered list of messages (user prompts + Gemini responses)
 * and a list of versions (snapshots of Gemini outputs that have been "saved").
 *
 * message roles:
 *   'user'   — a member's prompt sent to Gemini
 *   'ai'     — Gemini's raw text response
 *   'system' — internal context / branch note (not shown to Gemini)
 */
const MessageSchema = new mongoose.Schema(
  {
    role: { type: String, enum: ['user', 'ai', 'system'], required: true },
    content: { type: String, required: true },
    authorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
    // Which version was created from this AI message (if any)
    versionRef: { type: mongoose.Schema.Types.ObjectId, ref: 'Version', default: null },
    // Gemini model metadata (tokens, model name) — stored only on 'ai' messages
    meta: {
      model: String,
      promptTokens: Number,
      completionTokens: Number,
      latencyMs: Number,
    },
  },
  { timestamps: true }
);

const ThreadSchema = new mongoose.Schema(
  {
    projectId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Project',
      required: true,
      index: true,
    },
    title: { type: String, trim: true, maxlength: 120, default: 'Conversation' },
    // Optional: thread was forked from another thread at a specific message
    parentThreadId: { type: mongoose.Schema.Types.ObjectId, ref: 'Thread', default: null },
    forkMessageIndex: { type: Number, default: null },
    messages: { type: [MessageSchema], default: [] },
    // Current "active" version id (the one shown by default)
    activeVersionId: { type: mongoose.Schema.Types.ObjectId, ref: 'Version', default: null },
    // Mode passed to Gemini (communiquer, auditer, etc.)
    mode: { type: String, default: null },
    // Context inputs (client type, budget, etc.)
    context: { type: mongoose.Schema.Types.Mixed, default: {} },
    archivedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

// Index for listing threads of a project sorted by creation
ThreadSchema.index({ projectId: 1, createdAt: -1 });

export default mongoose.model('Thread', ThreadSchema);
