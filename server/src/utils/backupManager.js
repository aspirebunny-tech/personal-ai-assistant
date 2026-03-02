const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const DATA_DIR = path.join(ROOT, 'data');
const DB_FILE = path.join(DATA_DIR, 'assistant.db');
const UPLOADS_DIR = path.join(ROOT, 'uploads');
const BACKUPS_DIR = path.join(ROOT, 'backups');

function stamp() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}_${hh}-${mi}-${ss}`;
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function copyIfExists(src, dst) {
  if (!fs.existsSync(src)) return false;
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.cpSync(src, dst, { recursive: true });
  } else {
    ensureDir(path.dirname(dst));
    fs.copyFileSync(src, dst);
  }
  return true;
}

function pruneOldBackups(keepDays = 14) {
  if (!fs.existsSync(BACKUPS_DIR)) return;
  const cutoff = Date.now() - keepDays * 24 * 60 * 60 * 1000;
  for (const entry of fs.readdirSync(BACKUPS_DIR)) {
    const full = path.join(BACKUPS_DIR, entry);
    try {
      const stat = fs.statSync(full);
      if (stat.isDirectory() && stat.mtimeMs < cutoff) {
        fs.rmSync(full, { recursive: true, force: true });
      }
    } catch (_) {}
  }
}

function createBackup(reason = 'scheduled') {
  try {
    ensureDir(BACKUPS_DIR);
    const folder = path.join(BACKUPS_DIR, stamp());
    ensureDir(folder);

    const dbCopied = copyIfExists(DB_FILE, path.join(folder, 'assistant.db'));
    const uploadsCopied = copyIfExists(UPLOADS_DIR, path.join(folder, 'uploads'));

    const manifest = {
      created_at: new Date().toISOString(),
      reason,
      db_copied: dbCopied,
      uploads_copied: uploadsCopied,
      source: {
        db: DB_FILE,
        uploads: UPLOADS_DIR,
      },
    };
    fs.writeFileSync(
      path.join(folder, 'manifest.json'),
      JSON.stringify(manifest, null, 2),
      'utf8',
    );

    pruneOldBackups(14);
    console.log(`💾 Backup created: ${folder}`);
    return { ok: true, folder };
  } catch (err) {
    console.error('Backup failed:', err.message);
    return { ok: false, error: err.message };
  }
}

module.exports = { createBackup };

