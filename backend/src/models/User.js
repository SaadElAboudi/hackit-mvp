import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';

const UserSchema = new mongoose.Schema({
    email: { type: String, required: true, unique: true },
    password: { type: String, required: true }, // hashed
    favorites: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Lesson' }],
    history: [{
        query: String,
        date: { type: Date, default: Date.now }
    }],
    savedLessons: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Lesson' }],
});

// Add a demo user if none exists (for dev/test only)
if (process.env.NODE_ENV !== 'production') {
    mongoose.connection.once('open', async () => {
        const demoEmail = 'demo';
        const demoPassword = 'demo';
        const count = await mongoose.model('User', UserSchema).countDocuments({ email: demoEmail });
        if (count === 0) {
            const hash = await bcrypt.hash(demoPassword, 10);
            await mongoose.model('User', UserSchema).create({
                email: demoEmail,
                password: hash,
                favorites: [],
                history: [],
                savedLessons: []
            });
            console.log('Demo user created: demo/demo');
        }
    });
}

export default mongoose.model('User', UserSchema);
