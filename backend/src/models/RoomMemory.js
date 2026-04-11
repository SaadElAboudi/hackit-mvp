import mongoose from 'mongoose';

const RoomMemorySchema = new mongoose.Schema(
  {
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    type: {
      type: String,
      enum: ['fact', 'preference', 'decision'],
      default: 'fact',
    },
    content: { type: String, required: true, trim: true, maxlength: 2000 },
    createdBy: { type: String, required: true, trim: true, maxlength: 120 },
    createdByName: { type: String, default: 'Anonyme', trim: true, maxlength: 120 },
    pinned: { type: Boolean, default: true },
  },
  { timestamps: true }
);

RoomMemorySchema.index({ roomId: 1, pinned: -1, createdAt: -1 });

export default mongoose.model('RoomMemory', RoomMemorySchema);
