const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { getDB } = require('../models/database');

// Register
router.post('/register', async (req, res) => {
  try {
    const { email, password, name } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email aur password zaroori hai' });
    }

    const db = getDB();
    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
    if (existing) {
      return res.status(400).json({ error: 'Yeh email pehle se register hai' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const result = db.prepare(
      'INSERT INTO users (email, password, name) VALUES (?, ?, ?)'
    ).run(email, hashedPassword, name || email.split('@')[0]);

    const token = jwt.sign(
      { id: result.lastInsertRowid, email },
      process.env.JWT_SECRET || 'default_secret',
      { expiresIn: '365d' }
    );

    res.json({ success: true, token, user: { id: result.lastInsertRowid, email, name } });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const db = getDB();

    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
    if (!user) {
      return res.status(400).json({ error: 'Email ya password galat hai' });
    }

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      return res.status(400).json({ error: 'Email ya password galat hai' });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email },
      process.env.JWT_SECRET || 'default_secret',
      { expiresIn: '365d' }
    );

    res.json({
      success: true, token,
      user: { id: user.id, email: user.email, name: user.name }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
