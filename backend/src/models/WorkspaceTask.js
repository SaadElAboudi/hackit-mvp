import mongoose from 'mongoose';

const WorkspaceTaskSchema = new mongoose.Schema(
    {
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true,
            index: true,
        },
        decisionId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'WorkspaceDecision',
            default: null,
            index: true,
        },
        title: { type: String, trim: true, maxlength: 180, required: true },
        description: { type: String, trim: true, maxlength: 2000, default: '' },
        status: {
            type: String,
            enum: ['todo', 'in_progress', 'blocked', 'done'],
            default: 'todo',
            index: true,
        },
        ownerId: { type: String, trim: true, maxlength: 120, default: '' },
        ownerName: { type: String, trim: true, maxlength: 120, default: '' },
        dueDate: { type: Date, default: null },
        createdBy: { type: String, trim: true, maxlength: 120, default: '' },
        createdByName: { type: String, trim: true, maxlength: 120, default: '' },
        lastUpdatedBy: { type: String, trim: true, maxlength: 120, default: '' },
        lastUpdatedByName: { type: String, trim: true, maxlength: 120, default: '' },
    },
    { timestamps: true }
);

WorkspaceTaskSchema.index({ roomId: 1, status: 1, updatedAt: -1 });

export default mongoose.model('WorkspaceTask', WorkspaceTaskSchema);
