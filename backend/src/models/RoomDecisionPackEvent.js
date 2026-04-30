import mongoose from 'mongoose';

const RoomDecisionPackEventSchema = new mongoose.Schema(
  {
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    userId: { type: String, trim: true, maxlength: 120, default: '' },
    eventType: {
      type: String,
      enum: ['viewed', 'shared', 'share_failed'],
      required: true,
      index: true,
    },
    mode: {
      type: String,
      enum: ['checklist', 'executive'],
      required: true,
      default: 'checklist',
    },
    target: { type: String, trim: true, maxlength: 40, default: '' },
    metadata: { type: mongoose.Schema.Types.Mixed, default: null },
  },
  { timestamps: true }
);

RoomDecisionPackEventSchema.index({ roomId: 1, createdAt: -1 });
RoomDecisionPackEventSchema.index({ roomId: 1, eventType: 1, createdAt: -1 });

export default mongoose.model('RoomDecisionPackEvent', RoomDecisionPackEventSchema);
