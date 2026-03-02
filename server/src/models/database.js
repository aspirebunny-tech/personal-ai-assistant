const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const DB_PATH = path.join(__dirname, '../../data/assistant.db');

// Ensure data directory exists
const dataDir = path.dirname(DB_PATH);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

let db;

function getDB() {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
  }
  return db;
}

function initDB() {
  const db = getDB();

  // Users table
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      name TEXT,
      ai_style_profile TEXT DEFAULT '{}',
      ai_provider_config TEXT DEFAULT '{}',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  const userColumns = db.prepare('PRAGMA table_info(users)').all();
  const userColumnNames = new Set(userColumns.map((c) => c.name));
  if (!userColumnNames.has('ai_provider_config')) {
    db.exec(`ALTER TABLE users ADD COLUMN ai_provider_config TEXT DEFAULT '{}'`);
  }

  // Folders / Categories
  db.exec(`
    CREATE TABLE IF NOT EXISTS folders (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      icon TEXT DEFAULT '📁',
      color TEXT DEFAULT '#E8884A',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  `);

  // Notes
  db.exec(`
    CREATE TABLE IF NOT EXISTS notes (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL,
      folder_id TEXT,
      title TEXT,
      content TEXT NOT NULL,
      note_type TEXT DEFAULT 'text',
      language TEXT DEFAULT 'auto',
      tags TEXT DEFAULT '[]',
      is_synced INTEGER DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (folder_id) REFERENCES folders(id)
    )
  `);

  // Media attachments
  db.exec(`
    CREATE TABLE IF NOT EXISTS media (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      user_id INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      display_name TEXT,
      caption TEXT,
      file_path TEXT NOT NULL,
      file_type TEXT NOT NULL,
      file_size INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (note_id) REFERENCES notes(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  `);

  // Safe schema migration for existing databases.
  const mediaColumns = db.prepare('PRAGMA table_info(media)').all();
  const mediaColumnNames = new Set(mediaColumns.map((c) => c.name));
  if (!mediaColumnNames.has('display_name')) {
    db.exec('ALTER TABLE media ADD COLUMN display_name TEXT');
  }
  if (!mediaColumnNames.has('caption')) {
    db.exec('ALTER TABLE media ADD COLUMN caption TEXT');
  }

  // Reminders
  db.exec(`
    CREATE TABLE IF NOT EXISTS reminders (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL,
      note_id TEXT,
      title TEXT NOT NULL,
      description TEXT,
      remind_at DATETIME NOT NULL,
      is_sent INTEGER DEFAULT 0,
      is_recurring INTEGER DEFAULT 0,
      recur_pattern TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (note_id) REFERENCES notes(id)
    )
  `);

  // AI Interactions log (for style learning)
  db.exec(`
    CREATE TABLE IF NOT EXISTS ai_interactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      interaction_type TEXT NOT NULL,
      input_text TEXT,
      output_text TEXT,
      feedback INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  `);

  console.log('✅ Database tables initialized');
}

module.exports = { getDB, initDB };
