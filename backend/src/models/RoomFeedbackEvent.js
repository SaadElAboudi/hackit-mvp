import mongoose from 'mongoose';

const RoomFeedbackEventSchema = new mongoose.Schema(
  {
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    messageId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RoomMessage',
      required: true,
      index: true,
    },
    userId: { type: String, required: true, index: true },
    rating: { type: Number, enum: [-1, 0, 1], required: true, index: true },
    ratingLabel: {
      type: String,
      enum: ['pertinent', 'moyen', 'hors_sujet'],
      required: true,
      index: true,
    },
    reason: { type: String, default: '', trim: true, maxlength: 240 },
    metadata: { type: mongoose.Schema.Types.Mixed, default: {} },
  },
  { timestamps: true }
);

RoomFeedbackEventSchema.index(
  { roomId: 1, messageId: 1, userId: 1 },
  { unique: true }
);
RoomFeedbackEventSchema.index({ roomId: 1, createdAt: -1 });

export default mongoose.model('RoomFeedbackEvent', RoomFeedbackEventSchema);
