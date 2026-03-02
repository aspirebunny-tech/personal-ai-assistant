const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const auth = require('../middleware/auth');
const { getDB } = require('../models/database');
const fs = require('fs');

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const isVideo = file.mimetype.startsWith('video/');
    const isAudio = file.mimetype.startsWith('audio/');
    const bucket = isVideo ? 'videos' : (isAudio ? 'audio' : 'images');
    cb(null, path.join(__dirname, `../../uploads/${bucket}`));
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${uuidv4()}${ext}`);
  }
});

const upload = multer({
  storage,
  limits: { fileSize: (parseInt(process.env.MAX_FILE_SIZE_MB) || 100) * 1024 * 1024 }
});

// Upload media for a note
router.post('/upload/:note_id', auth, upload.single('file'), (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'File nahi mili' });

    const db = getDB();
    const id = uuidv4();
    const displayNameRaw = (req.body?.display_name || '').toString().trim();
    const captionRaw = (req.body?.caption || '').toString().trim();
    const isVideo = req.file.mimetype.startsWith('video/');
    const isAudio = req.file.mimetype.startsWith('audio/');
    const filePath = `/uploads/${isVideo ? 'videos' : (isAudio ? 'audio' : 'images')}/${req.file.filename}`;

    db.prepare(`
      INSERT INTO media (id, note_id, user_id, file_name, display_name, caption, file_path, file_type, file_size)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      req.params.note_id,
      req.user.id,
      req.file.originalname,
      displayNameRaw || req.file.originalname,
      captionRaw || null,
      filePath,
      req.file.mimetype,
      req.file.size,
    );

    const media = db.prepare('SELECT * FROM media WHERE id = ?').get(id);
    res.json({ success: true, media });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get media for a note
router.get('/note/:note_id', auth, (req, res) => {
  try {
    const db = getDB();
    const media = db.prepare('SELECT * FROM media WHERE note_id = ? AND user_id = ?')
      .all(req.params.note_id, req.user.id);
    res.json({ success: true, media });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Stream media file by media id (auth-protected, robust for mobile/tunnel usage)
router.get('/file/:id', auth, (req, res) => {
  try {
    const db = getDB();
    const media = db
      .prepare('SELECT * FROM media WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id);
    if (!media) return res.status(404).json({ error: 'Media nahi mili' });

    const absPath = path.join(__dirname, '../..', media.file_path);
    if (!fs.existsSync(absPath)) {
      return res.status(404).json({ error: 'Media file missing' });
    }
    if (media.file_type) {
      res.setHeader('Content-Type', media.file_type);
    }
    return res.sendFile(absPath);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// Update media metadata (display name / caption)
router.patch('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    const media = db
      .prepare('SELECT * FROM media WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id);
    if (!media) return res.status(404).json({ error: 'Media nahi mili' });

    const displayNameRaw = (req.body?.display_name ?? '').toString().trim();
    const captionRaw = (req.body?.caption ?? '').toString().trim();
    const nextDisplayName = displayNameRaw || media.file_name;
    const nextCaption = captionRaw || null;

    db.prepare(`
      UPDATE media
      SET display_name = ?, caption = ?
      WHERE id = ? AND user_id = ?
    `).run(nextDisplayName, nextCaption, req.params.id, req.user.id);

    const updated = db.prepare('SELECT * FROM media WHERE id = ?').get(req.params.id);
    res.json({ success: true, media: updated });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete media
router.delete('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    const media = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!media) return res.status(404).json({ error: 'Media nahi mili' });

    const fullPath = path.join(__dirname, '../..', media.file_path);
    if (fs.existsSync(fullPath)) fs.unlinkSync(fullPath);

    db.prepare('DELETE FROM media WHERE id = ?').run(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
