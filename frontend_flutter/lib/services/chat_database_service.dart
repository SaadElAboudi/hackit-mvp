import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_message.dart';

class ChatDatabaseService {
  static final ChatDatabaseService _instance = ChatDatabaseService._internal();
  factory ChatDatabaseService() => _instance;
  ChatDatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'chat_messages.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_messages(
            id TEXT PRIMARY KEY,
            role TEXT,
            kind TEXT,
            content TEXT,
            ts TEXT
          )
        ''');
      },
    );
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      'chat_messages',
      message.toSqlMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> getMessages() async {
    final db = await database;
    final maps = await db.query('chat_messages', orderBy: 'ts ASC');
    return maps.map((m) => ChatMessage.fromSqlMap(m)).toList();
  }

  Future<void> deleteAllMessages() async {
    final db = await database;
    await db.delete('chat_messages');
  }
}
