import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDB {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'local_notes.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_notes (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            title TEXT,
            folder_id TEXT,
            tags TEXT DEFAULT '[]',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            is_synced INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_notes (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            title TEXT,
            folder_id TEXT,
            folder_name TEXT,
            tags TEXT DEFAULT '[]',
            created_at TEXT,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon TEXT DEFAULT '📁',
            color TEXT DEFAULT '#E8884A',
            note_count INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  // Save note locally when offline
  static Future<void> savePendingNote({
    required String id,
    required String content,
    String? title,
    String? folderId,
  }) async {
    final database = await db;
    await database.insert('pending_notes', {
      'id': id,
      'content': content,
      'title': title ?? content.substring(0, content.length.clamp(0, 50)),
      'folder_id': folderId,
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Get all pending (unsynced) notes
  static Future<List<Map<String, dynamic>>> getPendingNotes() async {
    final database = await db;
    return database.query('pending_notes', where: 'is_synced = ?', whereArgs: [0]);
  }

  // Mark note as synced
  static Future<void> markSynced(String id) async {
    final database = await db;
    await database.update('pending_notes', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // Cache notes for offline viewing
  static Future<void> cacheNotes(List<dynamic> notes) async {
    final database = await db;
    final batch = database.batch();
    for (final note in notes) {
      batch.insert('cached_notes', {
        'id': note['id'],
        'content': note['content'] ?? '',
        'title': note['title'] ?? '',
        'folder_id': note['folder_id'] ?? '',
        'folder_name': note['folder_name'] ?? '',
        'tags': note['tags'] ?? '[]',
        'created_at': note['created_at'] ?? '',
        'updated_at': note['updated_at'] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // Cache folders
  static Future<void> cacheFolders(List<dynamic> folders) async {
    final database = await db;
    final batch = database.batch();
    for (final folder in folders) {
      batch.insert('cached_folders', {
        'id': folder['id'],
        'name': folder['name'] ?? '',
        'icon': folder['icon'] ?? '📁',
        'color': folder['color'] ?? '#E8884A',
        'note_count': folder['note_count'] ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedNotes({String? folderId}) async {
    final database = await db;
    if (folderId != null) {
      return database.query('cached_notes', where: 'folder_id = ?', whereArgs: [folderId], orderBy: 'created_at DESC');
    }
    return database.query('cached_notes', orderBy: 'created_at DESC');
  }

  static Future<List<Map<String, dynamic>>> getCachedFolders() async {
    final database = await db;
    return database.query('cached_folders');
  }
}
