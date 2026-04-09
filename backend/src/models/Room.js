import mongoose from 'mongoose';

const RoomMemberSchema = new mongoose.Schema(
    {
        userId: { type: String, required: true },
        displayName: { type: String, default: 'Anonyme' },
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
        members: { type: [RoomMemberSchema], default: [] },
        // Natural-language directives that any member can set for the AI colleague
        aiDirectives: { type: String, trim: true, maxlength: 2000, default: '' },
    },
    { timestamps: true }
);

export default mongoose.model('Room', RoomSchema);
