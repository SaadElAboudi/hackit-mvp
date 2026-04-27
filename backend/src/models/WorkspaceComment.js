import mongoose from 'mongoose';

const WorkspaceCommentSchema = new mongoose.Schema(
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
            required: true,
            index: true,
        },
        blockId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'WorkspaceBlock',
            required: true,
            index: true,
        },
        text: { type: String, trim: true, maxlength: 2000, required: true },
        createdBy: { type: String, trim: true, maxlength: 120, default: '' },
        createdByName: { type: String, trim: true, maxlength: 120, default: '' },
        resolved: { type: Boolean, default: false },
        resolvedAt: { type: Date, default: null },
        resolvedBy: { type: String, trim: true, maxlength: 120, default: '' },
        resolvedByName: { type: String, trim: true, maxlength: 120, default: '' },
    },
    { timestamps: true }
);

WorkspaceCommentSchema.index({ pageId: 1, createdAt: -1 });
WorkspaceCommentSchema.index({ blockId: 1, resolved: 1, createdAt: -1 });

export default mongoose.model('WorkspaceComment', WorkspaceCommentSchema);
