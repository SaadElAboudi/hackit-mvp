// Lightweight persistence layer with MongoDB (via mongoose) when MONGO_URI is set,
// and an in-memory fallback for local/dev without Mongo.
import crypto from 'crypto';

let isMongo = false;
let mongoose; // lazy import
let LessonModel; // mongoose model when available

const memory = {
    lessons: new Map(), // id -> lesson
};

export async function initPersistence() {
    const uri = process.env.MONGO_URI || '';
    if (!uri) {
        isMongo = false;
        return { ok: true, mode: 'memory' };
    }
    try {
        // dynamic import so tests without deps won't crash
        ({ default: mongoose } = await import('mongoose'));
        await mongoose.connect(uri, {
            dbName: process.env.MONGO_DB || undefined,
            autoIndex: true,
        });
        const lessonSchema = new mongoose.Schema(
            {
                userId: { type: String, index: true, required: true },
                title: { type: String, required: true },
                summary: { type: String, default: '' },
                steps: { type: [String], default: [] },
                videoUrl: { type: String, required: true },
                favorite: { type: Boolean, default: false, index: true },
                views: { type: Number, default: 0 },
                lastViewedAt: { type: Date, default: null, index: true },
            },
            { timestamps: { createdAt: true, updatedAt: true } }
        );
        LessonModel = mongoose.models.Lesson || mongoose.model('Lesson', lessonSchema);
        isMongo = true;
        return { ok: true, mode: 'mongo' };
    } catch (e) {
        console.warn('Mongo init failed, falling back to memory:', e?.message || e);
        isMongo = false;
        return { ok: false, mode: 'memory', error: e?.message };
    }
}

export async function saveLesson({ userId, title, summary, steps, videoUrl }) {
    const createdAt = new Date();
    if (isMongo && LessonModel) {
        const doc = await LessonModel.create({ userId, title, summary, steps, videoUrl });
        return toPublic(doc);
    }
    const id = crypto.randomUUID();
    const rec = {
        id,
        userId,
        title: String(title || ''),
        summary: String(summary || ''),
        steps: Array.isArray(steps) ? steps.map(String) : [],
        videoUrl: String(videoUrl || ''),
        favorite: false,
        views: 0,
        lastViewedAt: null,
        createdAt,
        updatedAt: createdAt,
    };
    memory.lessons.set(id, rec);
    return rec;
}

export async function setFavorite(lessonId, favorite) {
    if (isMongo && LessonModel) {
        const doc = await LessonModel.findByIdAndUpdate(lessonId, { favorite: !!favorite }, { new: true });
        if (!doc) return null;
        return toPublic(doc);
    }
    const rec = memory.lessons.get(lessonId);
    if (!rec) return null;
    rec.favorite = !!favorite;
    rec.updatedAt = new Date();
    return rec;
}

export async function recordView(lessonId) {
    const now = new Date();
    if (isMongo && LessonModel) {
        const doc = await LessonModel.findByIdAndUpdate(
            lessonId,
            { $inc: { views: 1 }, lastViewedAt: now },
            { new: true }
        );
        if (!doc) return null;
        return toPublic(doc);
    }
    const rec = memory.lessons.get(lessonId);
    if (!rec) return null;
    rec.views += 1;
    rec.lastViewedAt = now;
    rec.updatedAt = now;
    return rec;
}

export async function listLessons({ userId, favorite, sortBy = 'createdAt', order = 'desc', limit = 50, offset = 0 } = {}) {
    if (isMongo && LessonModel) {
        const q = { userId };
        if (favorite !== undefined) q.favorite = !!favorite;
        const sort = {};
        sort[sortBy] = order === 'asc' ? 1 : -1;
        const docs = await LessonModel.find(q).sort(sort).skip(offset).limit(limit);
        return docs.map(toPublic);
    }
    const arr = Array.from(memory.lessons.values()).filter((l) => (userId ? l.userId === userId : true));
    const filtered = favorite === undefined ? arr : arr.filter((l) => !!l.favorite === !!favorite);
    const sorter = (a, b) => {
        const va = a[sortBy];
        const vb = b[sortBy];
        const cmp = (va > vb ? 1 : va < vb ? -1 : 0);
        return order === 'asc' ? cmp : -cmp;
    };
    return filtered.sort(sorter).slice(offset, offset + limit);
}

function toPublic(doc) {
    const o = doc.toObject ? doc.toObject({ getters: false, virtuals: false }) : doc;
    return {
        id: String(o._id || o.id),
        userId: String(o.userId),
        title: String(o.title || ''),
        summary: String(o.summary || ''),
        steps: Array.isArray(o.steps) ? o.steps.map(String) : [],
        videoUrl: String(o.videoUrl || ''),
        favorite: !!o.favorite,
        views: Number(o.views || 0),
        lastViewedAt: o.lastViewedAt ? new Date(o.lastViewedAt) : null,
        createdAt: o.createdAt ? new Date(o.createdAt) : undefined,
        updatedAt: o.updatedAt ? new Date(o.updatedAt) : undefined,
    };
}
