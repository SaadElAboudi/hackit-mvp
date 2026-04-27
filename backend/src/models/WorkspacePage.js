import mongoose from 'mongoose';

const WorkspacePageSchema = new mongoose.Schema(
    {
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true,
            index: true,
        },
        title: { type: String, trim: true, maxlength: 180, default: 'Untitled page' },
        icon: { type: String, trim: true, maxlength: 8, default: '' },
        coverUrl: { type: String, trim: true, maxlength: 500, default: '' },
        status: {
            type: String,
            enum: ['draft', 'review', 'published', 'archived'],
            default: 'draft',
            index: true,
        },
        createdBy: { type: String, trim: true, maxlength: 120, default: '' },
        createdByName: { type: String, trim: true, maxlength: 120, default: '' },
        lastEditedBy: { type: String, trim: true, maxlength: 120, default: '' },
        lastEditedByName: { type: String, trim: true, maxlength: 120, default: '' },
        revision: { type: Number, min: 1, default: 1 },
        summary: { type: String, trim: true, maxlength: 500, default: '' },
    },
    { timestamps: true }
);

WorkspacePageSchema.index({ roomId: 1, updatedAt: -1 });

export default mongoose.model('WorkspacePage', WorkspacePageSchema);
