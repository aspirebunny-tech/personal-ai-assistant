const express = require('express');
const path = require('path');
const fs = require('fs');

const router = express.Router();

const RELEASES_DIR = path.join(__dirname, '../../releases');
const MANIFEST_PATH = path.join(RELEASES_DIR, 'android-latest.json');

function defaultManifest(req) {
  return {
    platform: 'android',
    latest_version: process.env.ANDROID_LATEST_VERSION || '1.0.0',
    latest_build_number: Number(process.env.ANDROID_LATEST_BUILD || 1),
    apk_url: process.env.ANDROID_APK_URL || `${req.protocol}://${req.get('host')}/releases/personal_ai_assistant-latest.apk`,
    force_update: false,
    release_notes: 'Bug fixes and improvements',
    published_at: new Date().toISOString(),
  };
}

router.get('/version/android', (req, res) => {
  try {
    if (!fs.existsSync(MANIFEST_PATH)) {
      return res.json({ success: true, update: defaultManifest(req) });
    }
    const raw = fs.readFileSync(MANIFEST_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    const update = {
      ...defaultManifest(req),
      ...parsed,
    };
    return res.json({ success: true, update });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;

