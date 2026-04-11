import mongoose from 'mongoose';

const RoomArtifactSchema = new mongoose.Schema(
  {
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    title: { type: String, trim: true, maxlength: 160, required: true },
    kind: {
      type: String,
      enum: ['canvas', 'document', 'decision', 'research'],
      default: 'canvas',
    },
    status: {
      type: String,
      enum: ['draft', 'validated', 'archived'],
      default: 'draft',
    },
    createdBy: { type: String, required: true, trim: true, maxlength: 120 },
    sourcePrompt: { type: String, trim: true, maxlength: 4000, default: '' },
    sourceMessageId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RoomMessage',
      default: null,
    },
    currentVersionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ArtifactVersion',
      default: null,
    },
    tags: [{ type: String, trim: true, maxlength: 40 }],
  },
  { timestamps: true }
);

RoomArtifactSchema.index({ roomId: 1, updatedAt: -1 });

export default mongoose.model('RoomArtifact', RoomArtifactSchema);
