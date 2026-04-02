import mongoose from 'mongoose';

const MessageSchema = new mongoose.Schema({
    role: { type: String, enum: ['user', 'assistant'], required: true },
    content: { type: String, required: true },
    timestamp: { type: Date, default: Date.now }
});

const ConversationSchema = new mongoose.Schema({
    conversationId: { type: String, required: true, unique: true },
    messages: [MessageSchema],
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now }
});

const Conversation = mongoose.model('Conversation', ConversationSchema);
export default Conversation;
