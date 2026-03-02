const express = require('express');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const auth = require('../middleware/auth');
const { getDB } = require('../models/database');

const router = express.Router();

function addCheck(target, key, title, status, message, details = '') {
  target.push({
    key,
    title,
    status, // ok | warn | fail
    message: (message || '').toString(),
    details: (details || '').toString(),
  });
}

function maskKey(key = '') {
  const t = String(key || '').trim();
  if (!t) return '';
  if (t.length <= 8) return '*'.repeat(t.length);
  return `${t.slice(0, 4)}${'*'.repeat(Math.max(0, t.length - 8))}${t.slice(-4)}`;
}

function checkDirAccess(absPath) {
  try {
    fs.mkdirSync(absPath, { recursive: true });
    fs.accessSync(absPath, fs.constants.R_OK | fs.constants.W_OK);
    return { ok: true, message: 'read/write ok' };
  } catch (err) {
    return { ok: false, message: err.message || String(err) };
  }
}

function checkTailscaleSession() {
  try {
    const raw = execFileSync('tailscale', ['status', '--json'], {
      encoding: 'utf8',
      timeout: 2500,
      maxBuffer: 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const json = JSON.parse(raw || '{}');
    const backendState = String(json?.BackendState || '').toLowerCase();
    const self = json?.Self || {};
    const hostName = String(self?.DNSName || self?.HostName || '').trim();
    const tailscaleIps = Array.isArray(self?.TailscaleIPs) ? self.TailscaleIPs : [];
    const loggedOut =
      backendState === 'needslogin' ||
      backendState === 'stopped' ||
      self?.LoggedOut === true;

    if (loggedOut) {
      return {
        status: 'fail',
        message: 'Tailscale login required',
        details: `backend_state=${backendState || 'unknown'}`,
      };
    }

    const expiryRaw = self?.KeyExpiry || self?.NodeKeyExpiry || '';
    if (expiryRaw) {
      const expiry = new Date(expiryRaw);
      if (!Number.isNaN(expiry.getTime())) {
        const msLeft = expiry.getTime() - Date.now();
        const daysLeft = Math.floor(msLeft / (1000 * 60 * 60 * 24));
        if (msLeft <= 0) {
          return {
            status: 'fail',
            message: 'Tailscale auth key expired',
            details: `expired_at=${expiry.toISOString()}`,
          };
        }
        if (daysLeft <= 7) {
          return {
            status: 'warn',
            message: `Tailscale key expires in ${daysLeft} day(s)`,
            details: `expiry=${expiry.toISOString()} | host=${hostName || 'unknown'}`,
          };
        }
      }
    }

    if (backendState !== 'running') {
      return {
        status: 'warn',
        message: `Tailscale state: ${backendState || 'unknown'}`,
        details: `host=${hostName || 'unknown'}`,
      };
    }

    return {
      status: 'ok',
      message: 'Tailscale connected',
      details: `host=${hostName || 'unknown'} | ips=${tailscaleIps.join(', ') || 'n/a'}`,
    };
  } catch (err) {
    const details = (err?.stderr || err?.message || String(err) || '').toString().trim();
    if (details.toLowerCase().includes('logged out')) {
      return {
        status: 'fail',
        message: 'Tailscale logged out',
        details,
      };
    }
    if (details.toLowerCase().includes('failed to connect to local tailscale service')) {
      return {
        status: 'fail',
        message: 'Tailscale service not running',
        details,
      };
    }
    return {
      status: 'warn',
      message: 'Tailscale status unavailable',
      details: details || 'tailscale cli check failed',
    };
  }
}

router.get('/diagnostics', auth, (req, res) => {
  const checks = [];
  const now = new Date().toISOString();

  const requestHost = (req.get('host') || '').toLowerCase().trim();
  if (!requestHost) {
    addCheck(checks, 'request-host', 'Request Host', 'warn', 'Host header missing', 'Proxy or client stripped host header.');
  } else if (requestHost.includes('trycloudflare.com')) {
    addCheck(
      checks,
      'request-host',
      'Request Host',
      'warn',
      `Quick tunnel host detected: ${requestHost}`,
      'Ye temporary URL hota hai; restart par badal sakta hai.'
    );
  } else if (requestHost.includes('.ts.net')) {
    addCheck(checks, 'request-host', 'Request Host', 'ok', `Tailscale host: ${requestHost}`);
  } else {
    addCheck(checks, 'request-host', 'Request Host', 'ok', `Host: ${requestHost}`);
  }

  addCheck(
    checks,
    'runtime',
    'Runtime',
    'ok',
    `Node ${process.version}, pid ${process.pid}`,
    `uptime ${Math.round(process.uptime())}s, platform ${os.platform()}`
  );

  const ts = checkTailscaleSession();
  addCheck(checks, 'tailscale-session', 'Tailscale Session', ts.status, ts.message, ts.details);

  let db = null;
  try {
    db = getDB();
    const users = db.prepare('SELECT COUNT(*) as count FROM users').get();
    const notes = db.prepare('SELECT COUNT(*) as count FROM notes').get();
    const media = db.prepare('SELECT COUNT(*) as count FROM media').get();
    addCheck(
      checks,
      'database',
      'Database',
      'ok',
      'SQLite reachable',
      `users=${users?.count ?? 0}, notes=${notes?.count ?? 0}, media=${media?.count ?? 0}`
    );
  } catch (err) {
    addCheck(checks, 'database', 'Database', 'fail', 'Database query failed', err.message || String(err));
  }

  const root = path.join(__dirname, '../..');
  const imageDir = path.join(root, 'uploads/images');
  const videoDir = path.join(root, 'uploads/videos');
  const audioDir = path.join(root, 'uploads/audio');
  const releaseDir = path.join(root, 'releases');
  const backupDir = path.join(root, 'backups');

  const dirs = [
    ['uploads-images', 'Uploads Images', imageDir],
    ['uploads-videos', 'Uploads Videos', videoDir],
    ['uploads-audio', 'Uploads Audio', audioDir],
    ['releases-dir', 'Releases Dir', releaseDir],
    ['backup-dir', 'Backup Dir', backupDir],
  ];
  for (const [key, title, dir] of dirs) {
    const dirCheck = checkDirAccess(dir);
    addCheck(
      checks,
      key,
      title,
      dirCheck.ok ? 'ok' : 'fail',
      dirCheck.ok ? 'directory ready' : 'directory issue',
      `${dir} | ${dirCheck.message}`
    );
  }

  const hasOpenRouterEnv = !!String(process.env.OPENROUTER_API_KEY || '').trim();
  const hasOpenAiEnv = !!String(process.env.OPENAI_API_KEY || '').trim();
  const ollamaBase = String(process.env.OLLAMA_BASE_URL || 'http://localhost:11434').trim();
  if (hasOpenRouterEnv || hasOpenAiEnv) {
    addCheck(
      checks,
      'ai-env',
      'AI Env Keys',
      'ok',
      `openrouter=${hasOpenRouterEnv ? 'yes' : 'no'}, openai=${hasOpenAiEnv ? 'yes' : 'no'}`,
      `ollama_base=${ollamaBase}`
    );
  } else {
    addCheck(
      checks,
      'ai-env',
      'AI Env Keys',
      'warn',
      'No global AI keys in env',
      'Per-user provider config still possible.'
    );
  }

  const sttModel = String(process.env.OPENAI_STT_MODEL || 'gpt-4o-transcribe').trim();
  if (hasOpenAiEnv) {
    addCheck(checks, 'stt-openai', 'OpenAI STT', 'ok', `model=${sttModel}`, 'OPENAI_API_KEY found in env');
  } else {
    addCheck(
      checks,
      'stt-openai',
      'OpenAI STT',
      'warn',
      `model=${sttModel}`,
      'OPENAI_API_KEY env missing, cloud STT fail ho sakta hai.'
    );
  }

  try {
    if (!db) db = getDB();
    const row = db
      .prepare('SELECT ai_provider_config FROM users WHERE id = ?')
      .get(req.user.id);
    let cfg = {};
    try {
      cfg = JSON.parse(row?.ai_provider_config || '{}');
    } catch (_) {
      cfg = {};
    }
    const primaryProvider = String(cfg?.primary?.provider || '').trim();
    const primaryModel = String(cfg?.primary?.model || '').trim();
    const primaryKey = String(cfg?.primary?.api_key || '').trim();

    const useFallback = cfg?.use_fallback !== false;
    const fallbackProvider = String(cfg?.fallback?.provider || '').trim();
    const fallbackModel = String(cfg?.fallback?.model || '').trim();
    const fallbackKey = String(cfg?.fallback?.api_key || '').trim();

    if (!primaryProvider) {
      addCheck(
        checks,
        'ai-user-config',
        'AI User Config',
        'warn',
        'Primary provider missing',
        'AI provider settings screen se primary set karo.'
      );
    } else {
      addCheck(
        checks,
        'ai-user-config',
        'AI User Config',
        'ok',
        `primary=${primaryProvider}${primaryModel ? ` (${primaryModel})` : ''}`,
        `key=${primaryKey ? maskKey(primaryKey) : 'not set'}`
      );
    }

    if (!useFallback) {
      addCheck(checks, 'ai-fallback', 'AI Fallback', 'warn', 'Fallback disabled');
    } else if (!fallbackProvider) {
      addCheck(checks, 'ai-fallback', 'AI Fallback', 'warn', 'Fallback enabled but provider missing');
    } else {
      addCheck(
        checks,
        'ai-fallback',
        'AI Fallback',
        'ok',
        `fallback=${fallbackProvider}${fallbackModel ? ` (${fallbackModel})` : ''}`,
        `key=${fallbackKey ? maskKey(fallbackKey) : 'not set'}`
      );
    }
  } catch (err) {
    addCheck(checks, 'ai-user-config', 'AI User Config', 'fail', 'Cannot read user provider config', err.message || String(err));
  }

  const summary = checks.reduce(
    (acc, item) => {
      if (item.status === 'ok') acc.ok += 1;
      else if (item.status === 'warn') acc.warn += 1;
      else acc.fail += 1;
      return acc;
    },
    { ok: 0, warn: 0, fail: 0 }
  );

  res.json({
    success: true,
    generated_at: now,
    request_host: requestHost,
    checks,
    summary,
  });
});

module.exports = router;
