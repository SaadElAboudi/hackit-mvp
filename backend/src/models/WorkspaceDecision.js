import mongoose from 'mongoose';

const WorkspaceDecisionSchema = new mongoose.Schema(
    {
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true,
            index: true,
        },
        pageId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'WorkspacePage',
            default: null,
            index: true,
        },
        sourceType: {
            type: String,
            enum: ['manual', 'mission', 'message', 'artifact'],
            default: 'manual',
        },
        sourceId: { type: String, trim: true, maxlength: 120, default: '' },
        title: { type: String, trim: true, maxlength: 180, required: true },
        summary: { type: String, trim: true, maxlength: 2000, default: '' },
        createdBy: { type: String, trim: true, maxlength: 120, default: '' },
        createdByName: { type: String, trim: true, maxlength: 120, default: '' },
        convertedAt: { type: Date, default: null },
    },
    { timestamps: true }
);

WorkspaceDecisionSchema.index({ roomId: 1, createdAt: -1 });

export default mongoose.model('WorkspaceDecision', WorkspaceDecisionSchema);
