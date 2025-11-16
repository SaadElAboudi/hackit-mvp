import mongoose from 'mongoose';

const LessonSchema = new mongoose.Schema({
    userId: { type: String, required: true, index: true },
    title: { type: String, required: true },
    steps: { type: [String], required: true },
    videoUrl: { type: String, required: true },
    summary: { type: String },
    favorite: { type: Boolean, default: false },
    views: { type: Number, default: 0 },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
});

export default mongoose.model('Lesson', LessonSchema);
