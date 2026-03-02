const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const auth = require('../middleware/auth');
const { getDB } = require('../models/database');

// Get all notes (with optional folder filter)
router.get('/', auth, (req, res) => {
  try {
    const db = getDB();
    const { folder_id, search, date } = req.query;

    let query = `
      SELECT n.*, f.name as folder_name, f.icon as folder_icon,
             GROUP_CONCAT(m.id) as media_ids,
             GROUP_CONCAT(m.file_type) as media_types,
             GROUP_CONCAT(m.file_path) as media_paths
      FROM notes n
      LEFT JOIN folders f ON n.folder_id = f.id
      LEFT JOIN media m ON n.id = m.note_id
      WHERE n.user_id = ?
    `;
    const params = [req.user.id];

    if (folder_id) {
      query += ' AND n.folder_id = ?';
      params.push(folder_id);
    }

    if (search) {
      query += ' AND (n.content LIKE ? OR n.title LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    if (date) {
      query += ' AND DATE(n.created_at) = ?';
      params.push(date);
    }

    query += ' GROUP BY n.id ORDER BY n.created_at DESC';

    const notes = db.prepare(query).all(...params);
    res.json({ success: true, notes });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get single note
router.get('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    const note = db.prepare(`
      SELECT n.*, f.name as folder_name, f.icon as folder_icon
      FROM notes n
      LEFT JOIN folders f ON n.folder_id = f.id
      WHERE n.id = ? AND n.user_id = ?
    `).get(req.params.id, req.user.id);

    if (!note) return res.status(404).json({ error: 'Note nahi mila' });

    const media = db.prepare('SELECT * FROM media WHERE note_id = ?').all(req.params.id);
    res.json({ success: true, note: { ...note, media } });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Create note
router.post('/', auth, (req, res) => {
  try {
    const db = getDB();
    const { title, content, folder_id, tags, language, note_type } = req.body;

    if (!content) return res.status(400).json({ error: 'Content zaroori hai' });

    const id = uuidv4();
    db.prepare(`
      INSERT INTO notes (id, user_id, folder_id, title, content, tags, language, note_type)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id, req.user.id, folder_id || null,
      title || content.substring(0, 50),
      content,
      JSON.stringify(tags || []),
      language || 'auto',
      note_type || 'text'
    );

    const note = db.prepare('SELECT * FROM notes WHERE id = ?').get(id);

    // Real-time sync
    const io = req.app.get('io');
    io.to(`user_${req.user.id}`).emit('note_created', note);

    res.json({ success: true, note });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update note
router.put('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    const { title, content, folder_id, tags } = req.body;

    db.prepare(`
      UPDATE notes SET title = ?, content = ?, folder_id = ?, tags = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ? AND user_id = ?
    `).run(
      title, content, folder_id || null,
      JSON.stringify(tags || []),
      req.params.id, req.user.id
    );

    const note = db.prepare('SELECT * FROM notes WHERE id = ?').get(req.params.id);

    const io = req.app.get('io');
    io.to(`user_${req.user.id}`).emit('note_updated', note);

    res.json({ success: true, note });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete note
router.delete('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    db.prepare('DELETE FROM notes WHERE id = ? AND user_id = ?').run(req.params.id, req.user.id);
    db.prepare('DELETE FROM media WHERE note_id = ?').run(req.params.id);

    const io = req.app.get('io');
    io.to(`user_${req.user.id}`).emit('note_deleted', { id: req.params.id });

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
