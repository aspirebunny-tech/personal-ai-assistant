require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { initDB } = require('./models/database');
const authRoutes = require('./routes/auth');
const notesRoutes = require('./routes/notes');
const foldersRoutes = require('./routes/folders');
const remindersRoutes = require('./routes/reminders');
const aiRoutes = require('./routes/ai');
const mediaRoutes = require('./routes/media');
const sttRoutes = require('./routes/stt');
const appUpdateRoutes = require('./routes/appUpdate');
const systemRoutes = require('./routes/system');
const { checkReminders } = require('./utils/reminderChecker');
const { createBackup } = require('./utils/backupManager');
const cron = require('node-cron');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] }
});

// Ensure upload folders exist before serving or writing files.
for (const dir of ['images', 'videos', 'audio']) {
  fs.mkdirSync(path.join(__dirname, `../uploads/${dir}`), { recursive: true });
}

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));
app.use('/releases', express.static(path.join(__dirname, '../releases')));

// Make io available in routes
app.set('io', io);

// Initialize Database
initDB();

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/notes', notesRoutes);
app.use('/api/folders', foldersRoutes);
app.use('/api/reminders', remindersRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/media', mediaRoutes);
app.use('/api/stt', sttRoutes);
app.use('/api/app', appUpdateRoutes);
app.use('/api/system', systemRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'Personal AI Assistant Server Running!', time: new Date().toISOString() });
});

// Socket.IO - Real-time sync
io.on('connection', (socket) => {
  console.log('Device connected:', socket.id);

  socket.on('join', (userId) => {
    socket.join(`user_${userId}`);
    console.log(`User ${userId} joined`);
  });

  socket.on('disconnect', () => {
    console.log('Device disconnected:', socket.id);
  });
});

// Reminder checker - every minute
cron.schedule('* * * * *', () => {
  checkReminders(io);
});

// Nightly backup at 02:00 local server time (DB + uploads).
cron.schedule('0 2 * * *', () => {
  createBackup('nightly');
});

// Startup snapshot backup (useful after reboot/crash recovery).
createBackup('startup');

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Personal AI Assistant Server running on port ${PORT}`);
  console.log(`📱 Android/Mac app se connect karo: http://localhost:${PORT}`);
  console.log(`✅ Database initialized`);
  console.log(`⏰ Reminder checker active\n`);
});
