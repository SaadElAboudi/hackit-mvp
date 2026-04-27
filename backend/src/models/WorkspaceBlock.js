import mongoose from 'mongoose';

const WorkspaceBlockSchema = new mongoose.Schema(
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
        type: {
            type: String,
            enum: ['paragraph', 'heading1', 'heading2', 'heading3', 'checklist', 'quote', 'callout', 'divider'],
            default: 'paragraph',
            index: true,
        },
        text: { type: String, trim: true, maxlength: 10000, default: '' },
        checked: { type: Boolean, default: false },
        order: { type: Number, min: 0, required: true },
        attrs: { type: mongoose.Schema.Types.Mixed, default: {} },
        // Incremented on each update to support optimistic concurrency.
        version: { type: Number, min: 1, default: 1 },
        createdBy: { type: String, trim: true, maxlength: 120, default: '' },
        createdByName: { type: String, trim: true, maxlength: 120, default: '' },
        updatedBy: { type: String, trim: true, maxlength: 120, default: '' },
        updatedByName: { type: String, trim: true, maxlength: 120, default: '' },
    },
    { timestamps: true }
);

WorkspaceBlockSchema.index({ pageId: 1, order: 1 }, { unique: true });
WorkspaceBlockSchema.index({ pageId: 1, updatedAt: -1 });

export default mongoose.model('WorkspaceBlock', WorkspaceBlockSchema);
