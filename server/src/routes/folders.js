const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const auth = require('../middleware/auth');
const { getDB } = require('../models/database');

// Get all folders
router.get('/', auth, (req, res) => {
  try {
    const db = getDB();
    const folders = db.prepare(`
      SELECT f.*, COUNT(n.id) as note_count
      FROM folders f
      LEFT JOIN notes n ON f.id = n.folder_id
      WHERE f.user_id = ?
      GROUP BY f.id
      ORDER BY f.created_at ASC
    `).all(req.user.id);
    res.json({ success: true, folders });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Create folder
router.post('/', auth, (req, res) => {
  try {
    const db = getDB();
    const { name, icon, color } = req.body;
    if (!name) return res.status(400).json({ error: 'Folder ka naam zaroori hai' });

    const id = uuidv4();
    db.prepare('INSERT INTO folders (id, user_id, name, icon, color) VALUES (?, ?, ?, ?, ?)')
      .run(id, req.user.id, name, icon || '📁', color || '#E8884A');

    const folder = db.prepare('SELECT * FROM folders WHERE id = ?').get(id);
    const io = req.app.get('io');
    io.to(`user_${req.user.id}`).emit('folder_created', folder);

    res.json({ success: true, folder });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update folder
router.put('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    const { name, icon, color } = req.body;
    db.prepare('UPDATE folders SET name = ?, icon = ?, color = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?')
      .run(name, icon, color, req.params.id, req.user.id);

    const folder = db.prepare('SELECT * FROM folders WHERE id = ?').get(req.params.id);
    res.json({ success: true, folder });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete folder
router.delete('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    db.prepare('DELETE FROM folders WHERE id = ? AND user_id = ?').run(req.params.id, req.user.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
