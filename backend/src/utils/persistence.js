export async function deleteLesson(lessonId) {
    if (!db) initPersistence();
    db.prepare('DELETE FROM lessons WHERE id = ?').run(lessonId);
    return { deleted: true, id: lessonId };
}
// Lightweight persistence layer with MongoDB (via mongoose) when MONGO_URI is set,
// and an in-memory fallback for local/dev without Mongo.


import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';
import crypto from 'crypto';

let db;

function getDbPath() {
    // Place DB in backend root
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);
    return path.join(__dirname, '../../hackit.db');
}

export function initPersistence() {
    if (!db) {
        const dbPath = getDbPath();
        db = new Database(dbPath);
        db.pragma('journal_mode = WAL');
        db.exec(`CREATE TABLE IF NOT EXISTS lessons (
            id TEXT PRIMARY KEY,
            userId TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT,
            steps TEXT NOT NULL,
            videoUrl TEXT NOT NULL,
            favorite INTEGER DEFAULT 0,
            views INTEGER DEFAULT 0,
            lastViewedAt TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
        )`);
        db.exec(`CREATE TABLE IF NOT EXISTS gemini_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            videoId TEXT,
            transcriptHash TEXT,
            summary TEXT,
            keyTakeaways TEXT,
            quiz TEXT,
            createdAt TEXT NOT NULL
        )`);


        // Gemini cache helpers (top-level, ES module compliant)
        function hashTranscript(transcript) {
            return crypto.createHash('sha256').update(transcript.join('\n')).digest('hex');
        }

        function levenshtein(a, b) {
            const matrix = Array(a.length + 1).fill(null).map(() => Array(b.length + 1).fill(null));
            for (let i = 0; i <= a.length; i++) matrix[i][0] = i;
            for (let j = 0; j <= b.length; j++) matrix[0][j] = j;
            for (let i = 1; i <= a.length; i++) {
                for (let j = 1; j <= b.length; j++) {
                    const cost = a[i - 1] === b[j - 1] ? 0 : 1;
                    matrix[i][j] = Math.min(
                        matrix[i - 1][j] + 1,
                        matrix[i][j - 1] + 1,
                        matrix[i - 1][j - 1] + cost
                    );
                }
            }
            return matrix[a.length][b.length];
        }

        function getGeminiCacheFuzzy(transcript, threshold = 0.15) {
            if (!db) initPersistence();
            const rows = db.prepare('SELECT * FROM gemini_cache').all();
            if (!rows.length) return null;
            const inputText = transcript.join('\n');
            let best = null;
            let bestScore = Infinity;
            for (const row of rows) {
                const rowText = row.transcriptHash || '';
                if (rowText === hashTranscript(transcript)) {
                    return {
                        summary: row.summary || '',
                        keyTakeaways: row.keyTakeaways ? JSON.parse(row.keyTakeaways) : [],
                        quiz: row.quiz ? JSON.parse(row.quiz) : [],
                        createdAt: row.createdAt
                    };
                }
                const rowTranscript = db.prepare('SELECT transcriptHash FROM gemini_cache WHERE id = ?').get(row.id)?.transcriptHash || '';
                const dist = levenshtein(inputText, rowTranscript);
                const norm = dist / Math.max(inputText.length, rowTranscript.length, 1);
                if (norm < threshold && norm < bestScore) {
                    best = row;
                    bestScore = norm;
                }
            }
            if (best) {
                return {
                    summary: best.summary || '',
                    keyTakeaways: best.keyTakeaways ? JSON.parse(best.keyTakeaways) : [],
                    quiz: best.quiz ? JSON.parse(best.quiz) : [],
                    createdAt: best.createdAt
                };
            }
            return null;
        }

        function setGeminiCache(videoId, { summary, keyTakeaways, quiz, transcript }) {
            if (!db) initPersistence();
            const transcriptHash = hashTranscript(transcript || []);
            db.prepare(`INSERT OR REPLACE INTO gemini_cache (videoId, transcriptHash, summary, keyTakeaways, quiz, createdAt)
            VALUES (?, ?, ?, ?, ?, ?)`)
                .run(videoId, transcriptHash, summary || '', JSON.stringify(keyTakeaways || []), JSON.stringify(quiz || []), new Date().toISOString());
        }

        function getGeminiCache(videoId) {
            if (!db) initPersistence();
            const row = db.prepare('SELECT * FROM gemini_cache WHERE videoId = ?').get(videoId);
            if (!row) return null;
            return {
                summary: row.summary || '',
                keyTakeaways: row.keyTakeaways ? JSON.parse(row.keyTakeaways) : [],
                quiz: row.quiz ? JSON.parse(row.quiz) : [],
                createdAt: row.createdAt
            };
        }

    }
    return { ok: true, mode: 'sqlite' };
}

export async function saveLesson({ userId, title, summary, steps, videoUrl }) {
    if (!db) initPersistence();
    // Vérifier si une leçon existe déjà pour ce userId, ce titre et ce videoUrl
    const existing = db.prepare(`SELECT * FROM lessons WHERE userId = ? AND title = ? AND videoUrl = ?`).get(userId, title, videoUrl);
    if (existing) {
        return toPublic(existing);
    }
    const id = cryptoRandomId();
    const now = new Date().toISOString();
    db.prepare(`INSERT INTO lessons (id, userId, title, summary, steps, videoUrl, favorite, views, lastViewedAt, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, 0, 0, NULL, ?, ?)`)
        .run(id, userId, title, summary || '', JSON.stringify(steps), videoUrl, now, now);
    return getLessonById(id);
}

export async function setFavorite(lessonId, favorite) {
    if (!db) initPersistence();
    db.prepare(`UPDATE lessons SET favorite = ?, updatedAt = ? WHERE id = ?`)
        .run(favorite ? 1 : 0, new Date().toISOString(), lessonId);
    return getLessonById(lessonId);
}

export async function recordView(lessonId) {
    if (!db) initPersistence();
    const now = new Date().toISOString();
    db.prepare(`UPDATE lessons SET views = views + 1, lastViewedAt = ?, updatedAt = ? WHERE id = ?`)
        .run(now, now, lessonId);
    return getLessonById(lessonId);
}

export async function listLessons({ userId, favorite, sortBy = 'createdAt', order = 'desc', limit = 50, offset = 0 } = {}) {
    if (!db) initPersistence();
    let sql = `SELECT * FROM lessons WHERE userId = ?`;
    const params = [userId];
    if (favorite !== undefined) {
        sql += ' AND favorite = ?';
        params.push(favorite ? 1 : 0);
    }
    const allowedSort = ['createdAt', 'lastViewedAt', 'views'];
    sql += ` ORDER BY ${allowedSort.includes(sortBy) ? sortBy : 'createdAt'} ${order === 'asc' ? 'ASC' : 'DESC'}`;
    sql += ' LIMIT ? OFFSET ?';
    params.push(limit, offset);
    console.log('[listLessons] DB path:', getDbPath());
    console.log('[listLessons] SQL:', sql);
    console.log('[listLessons] Params:', params);
    try {
        const rows = db.prepare(sql).all(...params);
        return rows.map(toPublic);
    } catch (err) {
        console.error('[listLessons] DB error:', err);
        throw err;
    }
}


function getLessonById(id) {
    if (!db) initPersistence();
    const row = db.prepare('SELECT * FROM lessons WHERE id = ?').get(id);
    return row ? toPublic(row) : null;
}

function toPublic(row) {
    return {
        id: row.id,
        userId: row.userId,
        title: row.title,
        summary: row.summary,
        steps: JSON.parse(row.steps),
        videoUrl: row.videoUrl,
        favorite: !!row.favorite,
        views: row.views,
        lastViewedAt: row.lastViewedAt ? new Date(row.lastViewedAt) : null,
        createdAt: row.createdAt ? new Date(row.createdAt) : undefined,
        updatedAt: row.updatedAt ? new Date(row.updatedAt) : undefined,
    };
}

function cryptoRandomId() {
    if (crypto.randomUUID) return crypto.randomUUID();
    // fallback for Node < 16.14
    return ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, c =>
        (c ^ crypto.randomBytes(1)[0] & 15 >> c / 4).toString(16)
    );
}
