import mongoose from 'mongoose';

const RoomMissionSchema = new mongoose.Schema(
  {
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    prompt: { type: String, required: true, trim: true, maxlength: 4000 },
    requestedBy: { type: String, required: true, trim: true, maxlength: 120 },
    requestedByName: { type: String, default: 'Anonyme', trim: true, maxlength: 120 },
    agentType: {
      type: String,
      enum: ['auto', 'strategist', 'researcher', 'facilitator', 'analyst', 'writer'],
      default: 'auto',
    },
    agentLabel: { type: String, default: 'Agent auto', trim: true, maxlength: 80 },
    status: {
      type: String,
      enum: ['queued', 'running', 'done', 'failed'],
      default: 'queued',
    },
    resultMessageId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RoomMessage',
      default: null,
    },
    resultArtifactId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RoomArtifact',
      default: null,
    },
    error: { type: String, trim: true, maxlength: 500, default: '' },
  },
  { timestamps: true }
);

RoomMissionSchema.index({ roomId: 1, createdAt: -1 });

export default mongoose.model('RoomMission', RoomMissionSchema);
