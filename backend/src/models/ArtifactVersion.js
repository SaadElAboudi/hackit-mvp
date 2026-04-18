import mongoose from 'mongoose';

const ArtifactCommentSchema = new mongoose.Schema(
  {
    authorId: { type: String, required: true, trim: true, maxlength: 120 },
    authorName: { type: String, default: 'Anonyme', trim: true, maxlength: 120 },
    text: { type: String, required: true, trim: true, maxlength: 2000 },
    resolved: { type: Boolean, default: false },
  },
  { timestamps: true }
);

const ArtifactVersionSchema = new mongoose.Schema(
  {
    artifactId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RoomArtifact',
      required: true,
      index: true,
    },
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    number: { type: Number, required: true },
    content: { type: String, required: true, trim: true },
    createdBy: { type: String, required: true, trim: true, maxlength: 120 },
    authorName: { type: String, trim: true, maxlength: 120, default: '' },
    sourcePrompt: { type: String, trim: true, maxlength: 4000, default: '' },
    changeSummary: { type: String, trim: true, maxlength: 400, default: '' },
    status: {
      type: String,
      enum: ['draft', 'approved', 'rejected', 'merged'],
      default: 'draft',
    },
    comments: { type: [ArtifactCommentSchema], default: [] },
  },
  { timestamps: true }
);

ArtifactVersionSchema.index({ artifactId: 1, number: 1 }, { unique: true });

export default mongoose.model('ArtifactVersion', ArtifactVersionSchema);
