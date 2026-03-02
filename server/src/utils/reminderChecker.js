const { getDB } = require('../models/database');
const notifier = require('node-notifier');

function checkReminders(io) {
  try {
    const db = getDB();
    const now = new Date();
    const nowStr = now.toISOString().slice(0, 16); // YYYY-MM-DDTHH:MM

    const dueReminders = db.prepare(`
      SELECT r.*, u.email
      FROM reminders r
      JOIN users u ON r.user_id = u.id
      WHERE r.is_sent = 0
        AND strftime('%Y-%m-%dT%H:%M', r.remind_at) <= ?
    `).all(nowStr);

    dueReminders.forEach(reminder => {
      // Mac Mini system notification
      notifier.notify({
        title: `⏰ ${reminder.title}`,
        message: reminder.description || 'Reminder time ho gaya!',
        sound: true,
        wait: false
      });

      // Push to Android via Socket.IO
      io.to(`user_${reminder.user_id}`).emit('reminder_due', {
        id: reminder.id,
        title: reminder.title,
        description: reminder.description,
        note_id: reminder.note_id
      });

      // Mark as sent
      db.prepare('UPDATE reminders SET is_sent = 1 WHERE id = ?').run(reminder.id);

      console.log(`⏰ Reminder sent: ${reminder.title}`);
    });
  } catch (err) {
    console.error('Reminder check error:', err.message);
  }
}

module.exports = { checkReminders };
