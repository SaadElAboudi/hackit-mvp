import mongoose from 'mongoose';

const WorkspaceMilestoneSchema = new mongoose.Schema(
    {
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true,
            index: true,
        },
        title: { type: String, trim: true, maxlength: 180, required: true },
        description: { type: String, trim: true, maxlength: 2000, default: '' },
        targetDate: { type: Date, default: null },
        status: {
            type: String,
            enum: ['planned', 'active', 'completed'],
            default: 'planned',
            index: true,
        },
        createdBy: { type: String, trim: true, maxlength: 120, default: '' },
        createdByName: { type: String, trim: true, maxlength: 120, default: '' },
    },
    { timestamps: true }
);

WorkspaceMilestoneSchema.index({ roomId: 1, targetDate: 1 });

export default mongoose.model('WorkspaceMilestone', WorkspaceMilestoneSchema);
