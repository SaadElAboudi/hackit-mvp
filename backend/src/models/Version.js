import mongoose from 'mongoose';

/**
 * Version — a named snapshot of a Gemini output within a Thread.
 *
 * Created when a member explicitly saves ("épingle") an AI message.
 * Versions are immutable once created; new edits create a new Version.
 *
 * status:
 *   'draft'    — saved, not yet approved
 *   'approved' — at least one member marked it approved
 *   'rejected' — explicitly rejected after review
 *   'merged'   — set as the canonical deliverable of the project
 */
const ApprovalSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true },
    decision: { type: String, enum: ['approved', 'rejected'], required: true },
    comment: { type: String, maxlength: 500, default: '' },
    decidedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const CommentSchema = new mongoose.Schema(
  {
    authorId: { type: String, required: true },
    // Optional: anchored to a specific section heading in the content
    sectionAnchor: { type: String, default: null },
    text: { type: String, required: true, maxlength: 2000 },
    resolved: { type: Boolean, default: false },
  },
  { timestamps: true }
);

const VersionSchema = new mongoose.Schema(
  {
    threadId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Thread',
      required: true,
      index: true,
    },
    projectId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Project',
      required: true,
      index: true,
    },
    // Sequential version number within the thread (v1, v2, …)
    number: { type: Number, required: true },
    label: { type: String, trim: true, maxlength: 80, default: null },
    // The full Gemini output text (immutable)
    content: { type: String, required: true },
    // Prompt that produced this version
    prompt: { type: String, required: true },
    // Member who pinned / created this version
    createdBy: { type: String, required: true },
    status: {
      type: String,
      enum: ['draft', 'approved', 'rejected', 'merged'],
      default: 'draft',
    },
    approvals: { type: [ApprovalSchema], default: [] },
    comments: { type: [CommentSchema], default: [] },
    // Which message index in the thread this snapshot was taken from
    messageIndex: { type: Number, required: true },
    // Tags for filtering (e.g. 'milestone', 'client-ready')
    tags: [{ type: String, maxlength: 40 }],
  },
  { timestamps: true }
);

// Compound index: thread + number must be unique
VersionSchema.index({ threadId: 1, number: 1 }, { unique: true });

// Virtual: approval summary
VersionSchema.virtual('approvalSummary').get(function () {
  const approved = this.approvals.filter((a) => a.decision === 'approved').length;
  const rejected = this.approvals.filter((a) => a.decision === 'rejected').length;
  return { approved, rejected, total: this.approvals.length };
});

export default mongoose.model('Version', VersionSchema);
