import mongoose from 'mongoose';

const RoomShareHistorySchema = new mongoose.Schema(
    {
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true,
            index: true,
        },
        artifactId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'RoomArtifact',
            default: null,
            index: true,
        },
        target: {
            type: String,
            enum: ['slack', 'notion', 'csv'],
            required: true,
            index: true,
        },
        status: {
            type: String,
            enum: ['pending', 'success', 'failed'],
            default: 'pending',
            index: true,
        },
        idempotencyKey: { type: String, trim: true, maxlength: 120, default: '' },
        actorId: { type: String, trim: true, maxlength: 120, default: '' },
        actorName: { type: String, trim: true, maxlength: 120, default: '' },
        note: { type: String, trim: true, maxlength: 300, default: '' },
        summary: { type: String, trim: true, maxlength: 1000, default: '' },
        retries: { type: Number, default: 0 },
        errorCode: { type: String, trim: true, maxlength: 120, default: '' },
        errorMessage: { type: String, trim: true, maxlength: 3000, default: '' },
        externalId: { type: String, trim: true, maxlength: 160, default: '' },
        externalUrl: { type: String, trim: true, maxlength: 1000, default: '' },
        metadata: { type: mongoose.Schema.Types.Mixed, default: null },
    },
    { timestamps: true }
);

RoomShareHistorySchema.index({ roomId: 1, createdAt: -1 });
RoomShareHistorySchema.index({ roomId: 1, artifactId: 1, createdAt: -1 });
RoomShareHistorySchema.index(
    { roomId: 1, idempotencyKey: 1 },
    { unique: true, partialFilterExpression: { idempotencyKey: { $type: 'string', $ne: '' } } }
);

export default mongoose.model('RoomShareHistory', RoomShareHistorySchema);
