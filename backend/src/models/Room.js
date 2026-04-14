import mongoose from 'mongoose';

const RoomMemberSchema = new mongoose.Schema(
    {
        userId: { type: String, required: true },
        displayName: { type: String, default: 'Anonyme' },
        role: {
            type: String,
            enum: ['owner', 'member', 'guest'],
            default: 'member',
        },
    },
    { _id: false }
);

const RoomSlackIntegrationSchema = new mongoose.Schema(
    {
        enabled: { type: Boolean, default: false },
        botToken: { type: String, trim: true, default: '' },
        channelId: { type: String, trim: true, default: '' },
        connectedBy: { type: String, trim: true, default: '' },
        connectedAt: { type: Date, default: null },
    },
    { _id: false }
);

const RoomNotionIntegrationSchema = new mongoose.Schema(
    {
        enabled: { type: Boolean, default: false },
        apiToken: { type: String, trim: true, default: '' },
        parentPageId: { type: String, trim: true, default: '' },
        connectedBy: { type: String, trim: true, default: '' },
        connectedAt: { type: Date, default: null },
    },
    { _id: false }
);

const RoomIntegrationsSchema = new mongoose.Schema(
    {
        slack: { type: RoomSlackIntegrationSchema, default: () => ({}) },
        notion: { type: RoomNotionIntegrationSchema, default: () => ({}) },
    },
    { _id: false }
);

/**
 * Room — a salon de discussion.
 *  type = 'dm'    : direct message between two users
 *  type = 'group' : group chat room (2+ users)
 *
 * aiDirectives : free-text instructions any member can set to guide the AI colleague.
 */
const RoomSchema = new mongoose.Schema(
    {
        name: { type: String, trim: true, maxlength: 80 },
        type: { type: String, enum: ['dm', 'group'], required: true },
        purpose: { type: String, trim: true, maxlength: 240, default: '' },
        visibility: {
            type: String,
            enum: ['invite_only', 'public'],
            default: 'invite_only',
        },
        ownerId: { type: String, trim: true, maxlength: 120, default: '' },
        members: { type: [RoomMemberSchema], default: [] },
        // Natural-language directives that any member can set for the AI colleague
        aiDirectives: { type: String, trim: true, maxlength: 2000, default: '' },
        pinnedArtifactId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'RoomArtifact',
            default: null,
        },
        integrations: { type: RoomIntegrationsSchema, default: () => ({}) },
        lastActivityAt: { type: Date, default: Date.now },
    },
    { timestamps: true }
);

export default mongoose.model('Room', RoomSchema);
