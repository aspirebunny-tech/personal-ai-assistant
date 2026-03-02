const express = require('express');
const fs = require('fs/promises');
const fsSync = require('fs');
const multer = require('multer');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { promisify } = require('util');
const auth = require('../middleware/auth');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage() });
const execFileAsync = promisify(execFile);

function isWeakTranscript(text, confidence) {
  const value = (text || '').trim();
  if (!value) return true;

  if (typeof confidence === 'number' && !Number.isNaN(confidence)) {
    const threshold = Number(process.env.STT_LOCAL_CONFIDENCE_THRESHOLD || 0.55);
    if (confidence < threshold) return true;
  }

  if (value.length < 4) return true;
  if (value.includes('\uFFFD')) return true;

  // Heuristic: if too many duplicated tokens, local output is likely unstable.
  const words = value.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length >= 4) {
    let duplicateRuns = 0;
    for (let i = 1; i < words.length; i += 1) {
      if (words[i] === words[i - 1]) duplicateRuns += 1;
    }
    if (duplicateRuns >= Math.floor(words.length / 3)) return true;
  }

  return false;
}

function normalizeLanguageHint(languageHint) {
  const hint = String(languageHint || '').trim().toLowerCase();
  if (!hint || hint === 'auto') return null;
  if (hint.startsWith('hi')) return 'Hindi';
  if (hint.startsWith('mr')) return 'Marathi';
  if (hint.startsWith('en')) return 'English';
  return null;
}

async function transcribeWithLocalWhisper(audioPath, languageHint) {
  const whisperBin = process.env.LOCAL_WHISPER_BIN
    || (fsSync.existsSync('/opt/homebrew/bin/whisper') ? '/opt/homebrew/bin/whisper' : 'whisper');
  const ffmpegBin = process.env.LOCAL_FFMPEG_BIN
    || (fsSync.existsSync('/opt/homebrew/bin/ffmpeg') ? '/opt/homebrew/bin/ffmpeg' : 'ffmpeg');
  const localModel = process.env.LOCAL_WHISPER_MODEL || 'small';
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'pai-stt-local-'));
  const wavPath = path.join(tempDir, 'input.wav');
  const preprocessedPath = path.join(tempDir, 'preprocessed.wav');
  const outputDir = path.join(tempDir, 'out');

  try {
    await fs.mkdir(outputDir, { recursive: true });
    await execFileAsync(ffmpegBin, ['-y', '-i', audioPath, '-ac', '1', '-ar', '16000', wavPath]);
    await execFileAsync(ffmpegBin, [
      '-y',
      '-i',
      wavPath,
      '-af',
      'highpass=f=120,lowpass=f=7600,afftdn,loudnorm',
      preprocessedPath,
    ]);

    const args = [
      preprocessedPath,
      '--model',
      localModel,
      '--task',
      'transcribe',
      '--output_format',
      'json',
      '--output_dir',
      outputDir,
      '--fp16',
      'False',
      '--verbose',
      'False',
      '--condition_on_previous_text',
      'False',
    ];

    const languageName = normalizeLanguageHint(languageHint);
    if (languageName) {
      args.push('--language', languageName);
    }

    await execFileAsync(whisperBin, args, { maxBuffer: 10 * 1024 * 1024 });

    const baseName = path.parse(preprocessedPath).name;
    const jsonPath = path.join(outputDir, `${baseName}.json`);
    const raw = await fs.readFile(jsonPath, 'utf8');
    const parsed = JSON.parse(raw);
    return String(parsed.text || '').trim();
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
}

async function transcribeWithOpenAI(buffer, mimeType, fileName, languageHint) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return '';

  const model = process.env.OPENAI_STT_MODEL || 'gpt-4o-transcribe';
  const form = new FormData();
  form.append('model', model);
  form.append('file', new Blob([buffer], { type: mimeType }), fileName);

  const openAiLanguage = (() => {
    const hint = String(languageHint || '').trim().toLowerCase();
    if (hint.startsWith('hi')) return 'hi';
    if (hint.startsWith('mr')) return 'mr';
    if (hint.startsWith('en')) return 'en';
    return '';
  })();
  if (openAiLanguage) form.append('language', openAiLanguage);

  form.append(
    'prompt',
    'Multilingual dictation (Hindi/Marathi/English) for personal notes. Keep words exactly as spoken.'
  );

  const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  if (!response.ok) return '';
  const data = await response.json();
  return String(data.text || '').trim();
}

router.post('/transcribe', auth, upload.single('audio'), async (req, res) => {
  let tempDir = null;
  try {
    const languageHint = String(req.body.language_hint || '').trim();
    const mode = String(req.body.mode || 'cloud').toLowerCase(); // local | cloud | hybrid
    const localConfidence = req.body.local_confidence ? Number(req.body.local_confidence) : NaN;
    const localTextFromClient = String(req.body.local_text || '').trim();

    if (!req.file || !req.file.buffer || req.file.size === 0) {
      return res.status(400).json({ error: 'Audio file missing' });
    }

    const mimeType = req.file.mimetype || 'audio/m4a';
    const fileName = req.file.originalname || 'speech.m4a';

    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'pai-stt-req-'));
    const audioPath = path.join(tempDir, fileName);
    await fs.writeFile(audioPath, req.file.buffer);

    let localText = '';
    let localError = '';
    if (mode !== 'cloud') {
      try {
        if (localTextFromClient) {
          localText = localTextFromClient;
        } else {
          localText = await transcribeWithLocalWhisper(audioPath, languageHint);
        }
      } catch (err) {
        localError = err.message || String(err);
      }
    }

    if (mode === 'local') {
      return res.json({
        success: true,
        source: 'local',
        text: localText,
        fallbackApplied: false,
        reason: 'local_only',
        details: localError || undefined,
      });
    }

    const weakLocal = isWeakTranscript(localText, localConfidence);
    if (mode === 'hybrid' && !weakLocal && localText) {
      return res.json({
        success: true,
        source: 'local',
        text: localText,
        fallbackApplied: false,
        reason: 'local_strong',
      });
    }

    const cloudText = await transcribeWithOpenAI(
      req.file.buffer,
      mimeType,
      fileName,
      languageHint
    );
    if (!cloudText) {
      const bestFallbackText = localText || localTextFromClient;
      return res.json({
        success: true,
        source: bestFallbackText ? 'local_preview' : 'none',
        text: bestFallbackText,
        fallbackApplied: false,
        reason: 'cloud_unavailable',
        details: localError || undefined,
      });
    }

    if (mode === 'cloud') {
      return res.json({
        success: true,
        source: 'openai',
        text: cloudText,
        fallbackApplied: true,
        reason: 'cloud_only',
      });
    }

    return res.json({
      success: true,
      source: 'openai',
      text: cloudText,
      fallbackApplied: true,
      reason: weakLocal ? 'local_weak' : 'hybrid',
      localText,
      cloudText,
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  } finally {
    if (tempDir) {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  }
});

module.exports = router;
