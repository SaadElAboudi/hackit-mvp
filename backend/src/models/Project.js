import mongoose from 'mongoose';
import { randomBytes } from 'crypto';

/**
 * Project — shared workspace owned by one user, accessible to members via invite link.
 *
 * projectId  : human-friendly slug derived from title + random suffix
 * inviteToken: secret token embedded in the invite URL
 * members    : [{ userId, role: 'owner'|'editor'|'viewer', joinedAt }]
 * threads    : references to Thread documents belonging to this project
 */
const MemberSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true },
    role: { type: String, enum: ['owner', 'editor', 'viewer'], default: 'editor' },
    joinedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const ProjectSchema = new mongoose.Schema(
  {
    title: { type: String, required: true, trim: true, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 500 },
    // Short slug used in URLs: "my-project-a3f2"
    slug: { type: String, required: true, unique: true, index: true },
    // Secret token embedded in invite URL — regeneratable
    inviteToken: {
      type: String,
      required: true,
      default: () => randomBytes(16).toString('hex'),
    },
    members: { type: [MemberSchema], default: [] },
    // Ordered list of thread ids (the project's conversation history)
    threadIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Thread' }],
    // Whether the project is readable by anyone with the invite link (no auth required)
    isPublic: { type: Boolean, default: false },
    archivedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

// Helper: generate a URL-safe slug from a title
ProjectSchema.statics.generateSlug = function (title) {
  const base = title
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 40);
  const suffix = randomBytes(3).toString('hex'); // 6 chars
  return `${base}-${suffix}`;
};

// Virtual: members count
ProjectSchema.virtual('memberCount').get(function () {
  return this.members.length;
});

export default mongoose.model('Project', ProjectSchema);
