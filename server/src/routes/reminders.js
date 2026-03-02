const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const auth = require('../middleware/auth');
const { getDB } = require('../models/database');

// Get all reminders
router.get('/', auth, (req, res) => {
  try {
    const db = getDB();
    const reminders = db.prepare(`
      SELECT r.*, n.title as note_title
      FROM reminders r
      LEFT JOIN notes n ON r.note_id = n.id
      WHERE r.user_id = ? AND r.is_sent = 0
      ORDER BY r.remind_at ASC
    `).all(req.user.id);
    res.json({ success: true, reminders });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Create reminder
router.post('/', auth, (req, res) => {
  try {
    const db = getDB();
    const { note_id, title, description, remind_at } = req.body;
    if (!title || !remind_at) return res.status(400).json({ error: 'Title aur time zaroori hai' });

    const id = uuidv4();
    db.prepare(`
      INSERT INTO reminders (id, user_id, note_id, title, description, remind_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, req.user.id, note_id || null, title, description || '', remind_at);

    const reminder = db.prepare('SELECT * FROM reminders WHERE id = ?').get(id);
    res.json({ success: true, reminder });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete reminder
router.delete('/:id', auth, (req, res) => {
  try {
    const db = getDB();
    db.prepare('DELETE FROM reminders WHERE id = ? AND user_id = ?').run(req.params.id, req.user.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
