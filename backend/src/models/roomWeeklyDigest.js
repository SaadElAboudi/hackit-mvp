import mongoose from 'mongoose';

const roomWeeklyDigestSchema = new mongoose.Schema(
    {
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true,
            index: true,
        },
        period: {
            type: Date,
            required: true,
            // Monday of the week digest covers
        },
        content: {
            roomName: String,
            metrics: [
                {
                    label: String,
                    value: Number,
                },
            ],
            patterns: [
                {
                    type: String, // 'FRICTION' | 'WIN'
                    text: String,
                },
            ],
            recommendations: [String],
        },
        emailSent: {
            type: Boolean,
            default: false,
            index: true,
        },
        sentAt: Date,
    },
    {
        timestamps: true,
    },
);

// Index for finding recent digests
roomWeeklyDigestSchema.index({ roomId: 1, period: -1 });

export default mongoose.model('RoomWeeklyDigest', roomWeeklyDigestSchema);
