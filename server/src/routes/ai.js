const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const { getDB } = require('../models/database');
const axios = require('axios');

const PROVIDERS = ['openrouter', 'openai', 'ollama'];

function getCandidateModels(modelOverride = null) {
  const configured = [
    modelOverride,
    process.env.OPENROUTER_MODEL,
    process.env.OPENROUTER_FALLBACK_MODEL,
  ].filter(Boolean);
  const defaults = [
    'google/gemma-2-9b-it:free',
    'qwen/qwen-2.5-7b-instruct:free',
    'mistralai/mistral-7b-instruct:free',
    'meta-llama/llama-3.1-8b-instruct:free',
  ];
  return Array.from(new Set([...configured, ...defaults]));
}

function defaultProviderConfig() {
  return {
    primary: {
      provider: 'openrouter',
      api_key: '',
      model: process.env.OPENROUTER_MODEL || 'x-ai/grok-4.1-fast',
      base_url: '',
    },
    fallback: {
      provider: '',
      api_key: '',
      model: '',
      base_url: '',
    },
    use_fallback: true,
  };
}

function maskApiKey(key = '') {
  const t = (key || '').trim();
  if (!t) return '';
  if (t.length <= 8) return '*'.repeat(t.length);
  return `${t.substring(0, 4)}${'*'.repeat(Math.max(0, t.length - 8))}${t.substring(t.length - 4)}`;
}

function sanitizeProvider(p) {
  const v = (p || '').toLowerCase().trim();
  return PROVIDERS.includes(v) ? v : '';
}

function getUserProviderConfig(userId) {
  const db = getDB();
  const row = db.prepare('SELECT ai_provider_config FROM users WHERE id = ?').get(userId);
  let parsed = {};
  try {
    parsed = JSON.parse(row?.ai_provider_config || '{}');
  } catch (_) {
    parsed = {};
  }
  const d = defaultProviderConfig();
  return {
    primary: {
      provider: sanitizeProvider(parsed?.primary?.provider) || d.primary.provider,
      api_key: (parsed?.primary?.api_key || '').toString().trim(),
      model: (parsed?.primary?.model || d.primary.model).toString().trim(),
      base_url: (parsed?.primary?.base_url || '').toString().trim(),
    },
    fallback: {
      provider: sanitizeProvider(parsed?.fallback?.provider),
      api_key: (parsed?.fallback?.api_key || '').toString().trim(),
      model: (parsed?.fallback?.model || '').toString().trim(),
      base_url: (parsed?.fallback?.base_url || '').toString().trim(),
    },
    use_fallback: parsed?.use_fallback !== false,
  };
}

function saveUserProviderConfig(userId, cfg) {
  const db = getDB();
  db.prepare('UPDATE users SET ai_provider_config = ? WHERE id = ?')
    .run(JSON.stringify(cfg), userId);
}

function resolveRuntimeChain(userId) {
  const userCfg = userId ? getUserProviderConfig(userId) : defaultProviderConfig();
  const chain = [];

  const addEntry = (slot, fallback = false) => {
    const provider = sanitizeProvider(slot?.provider);
    if (!provider) return;
    const isOpenRouter = provider === 'openrouter';
    const isOpenAI = provider === 'openai';
    const isOllama = provider === 'ollama';
    const apiKey =
      (slot?.api_key || '').trim() ||
      (isOpenRouter ? process.env.OPENROUTER_API_KEY || '' : '') ||
      (isOpenAI ? process.env.OPENAI_API_KEY || '' : '');
    const model =
      (slot?.model || '').trim() ||
      (isOpenRouter ? process.env.OPENROUTER_MODEL || '' : '') ||
      (isOpenAI ? process.env.OPENAI_MODEL || 'gpt-4o-mini' : '') ||
      (isOllama ? process.env.OLLAMA_MODEL || 'llama3.1:8b' : '');
    const baseUrl =
      (slot?.base_url || '').trim() ||
      (isOpenRouter ? 'https://openrouter.ai/api/v1' : '') ||
      (isOpenAI ? 'https://api.openai.com/v1' : '') ||
      (isOllama ? 'http://localhost:11434' : '');

    // For non-local providers, key is required.
    if (!isOllama && (!apiKey || apiKey === 'your_openrouter_api_key_here')) return;

    chain.push({
      provider,
      api_key: apiKey,
      model,
      base_url: baseUrl,
      fallback,
    });
  };

  addEntry(userCfg.primary, false);
  if (userCfg.use_fallback) addEntry(userCfg.fallback, true);
  if (!chain.length) {
    addEntry(defaultProviderConfig().primary, false);
  }
  return chain;
}

async function callOpenRouter(messages, model, apiKey, baseUrl = 'https://openrouter.ai/api/v1') {
  const modelsToTry = getCandidateModels(model);
  let lastError = null;
  for (const m of modelsToTry) {
    try {
      const isGrok = m.startsWith('x-ai/');
      const response = await axios.post(
        `${baseUrl.replace(/\/$/, '')}/chat/completions`,
        {
          model: m,
          messages,
          max_tokens: isGrok ? 700 : 1000,
          ...(isGrok ? { reasoning: { effort: 'low' } } : {}),
        },
        {
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'HTTP-Referer': 'personal-ai-assistant',
          },
          timeout: isGrok ? 30000 : 18000,
        }
      );
      const content = response.data?.choices?.[0]?.message?.content;
      if (content) return { content, model: m };
    } catch (err) {
      lastError = err;
    }
  }
  if (lastError) throw lastError;
  return null;
}

async function callOpenAI(messages, model, apiKey, baseUrl = 'https://api.openai.com/v1') {
  const response = await axios.post(
    `${baseUrl.replace(/\/$/, '')}/chat/completions`,
    {
      model: model || 'gpt-4o-mini',
      messages,
      max_tokens: 900,
    },
    {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      timeout: 20000,
    }
  );
  const content = response.data?.choices?.[0]?.message?.content;
  if (!content) return null;
  return { content, model: model || 'gpt-4o-mini' };
}

async function callOllama(messages, model, baseUrl = 'http://localhost:11434') {
  const response = await axios.post(
    `${baseUrl.replace(/\/$/, '')}/api/chat`,
    {
      model: model || 'llama3.1:8b',
      messages,
      stream: false,
      options: { num_predict: 700 },
    },
    { timeout: 22000 }
  );
  const content = response.data?.message?.content;
  if (!content) return null;
  return { content, model: model || 'llama3.1:8b' };
}

async function callAI(messages, model = null, userId = null) {
  const chain = resolveRuntimeChain(userId);
  let lastError = null;

  for (const cfg of chain) {
    try {
      if (cfg.provider === 'openrouter') {
        const res = await callOpenRouter(messages, model || cfg.model, cfg.api_key, cfg.base_url);
        if (res?.content) return res.content;
      } else if (cfg.provider === 'openai') {
        const res = await callOpenAI(messages, model || cfg.model, cfg.api_key, cfg.base_url);
        if (res?.content) return res.content;
      } else if (cfg.provider === 'ollama') {
        const res = await callOllama(messages, model || cfg.model, cfg.base_url);
        if (res?.content) return res.content;
      }
    } catch (err) {
      lastError = err;
    }
  }

  if (lastError) {
    const reason = lastError.response?.data?.error?.message || lastError.message || 'unknown';
    console.log(`AI provider unavailable, using fallback mode: ${reason}`);
  }
  return null;
}

async function checkProviderStatus(entry) {
  const provider = sanitizeProvider(entry?.provider);
  if (!provider) return { available: false, reason: 'invalid_provider' };
  try {
    if (provider === 'openrouter') {
      const result = await callOpenRouter(
        [
          { role: 'system', content: 'Reply with OK' },
          { role: 'user', content: 'health-check' },
        ],
        entry.model || process.env.OPENROUTER_MODEL || 'google/gemma-2-9b-it:free',
        entry.api_key || process.env.OPENROUTER_API_KEY || '',
        entry.base_url || 'https://openrouter.ai/api/v1',
      );
      if (result?.content) return { available: true, model: result.model || entry.model };
      return { available: false, reason: 'no_response' };
    }
    if (provider === 'openai') {
      const response = await axios.get(
        `${(entry.base_url || 'https://api.openai.com/v1').replace(/\/$/, '')}/models`,
        {
          headers: {
            Authorization: `Bearer ${entry.api_key || process.env.OPENAI_API_KEY || ''}`,
          },
          timeout: 12000,
        }
      );
      if (Array.isArray(response.data?.data)) {
        return { available: true, model: entry.model || 'gpt-4o-mini' };
      }
      return { available: false, reason: 'invalid_models_response' };
    }
    if (provider === 'ollama') {
      const response = await axios.get(
        `${(entry.base_url || 'http://localhost:11434').replace(/\/$/, '')}/api/tags`,
        { timeout: 7000 }
      );
      if (Array.isArray(response.data?.models)) {
        return { available: true, model: entry.model || response.data.models[0]?.name || 'ollama' };
      }
      return { available: false, reason: 'ollama_not_ready' };
    }
    return { available: false, reason: 'unsupported_provider' };
  } catch (err) {
    return {
      available: false,
      reason: err.response?.data?.error?.message || err.message || 'unknown',
    };
  }
}

const OPENAI_MODEL_RATE_PER_1M = {
  'gpt-4o-mini': 0.9,
  'gpt-4.1-mini': 0.8,
  'gpt-4.1-nano': 0.2,
  'gpt-4.1': 5.0,
  'gpt-4o': 5.0,
};

function toRateNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return n;
}

function sortModelsByRate(models) {
  return [...models].sort((a, b) => {
    const ra = toRateNumber(a.rate_per_1m);
    const rb = toRateNumber(b.rate_per_1m);
    if (ra == null && rb == null) return a.model.localeCompare(b.model);
    if (ra == null) return 1;
    if (rb == null) return -1;
    if (ra === rb) return a.model.localeCompare(b.model);
    return ra - rb;
  });
}

async function fetchProviderModels({ provider, apiKey, baseUrl }) {
  const p = sanitizeProvider(provider);
  if (!p) return [];

  if (p === 'openrouter') {
    const response = await axios.get(
      `${(baseUrl || 'https://openrouter.ai/api/v1').replace(/\/$/, '')}/models`,
      {
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        timeout: 15000,
      }
    );
    const models = (response.data?.data || []).map((m) => {
      const promptRate = Number(m?.pricing?.prompt || 0); // per token
      const completionRate = Number(m?.pricing?.completion || 0); // per token
      const blended = Number.isFinite(promptRate + completionRate)
        ? (promptRate + completionRate) * 1000000
        : null;
      return {
        model: m.id,
        rate_per_1m: blended,
        provider: 'openrouter',
      };
    });
    return sortModelsByRate(models);
  }

  if (p === 'openai') {
    const response = await axios.get(
      `${(baseUrl || 'https://api.openai.com/v1').replace(/\/$/, '')}/models`,
      {
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        timeout: 15000,
      }
    );
    const models = (response.data?.data || [])
      .map((m) => m.id)
      .filter((id) => id.startsWith('gpt-'))
      .map((id) => ({
        model: id,
        rate_per_1m: OPENAI_MODEL_RATE_PER_1M[id] ?? null,
        provider: 'openai',
      }));
    return sortModelsByRate(models);
  }

  if (p === 'ollama') {
    const response = await axios.get(
      `${(baseUrl || 'http://localhost:11434').replace(/\/$/, '')}/api/tags`,
      { timeout: 10000 }
    );
    const models = (response.data?.models || []).map((m) => ({
      model: m.name,
      rate_per_1m: 0,
      provider: 'ollama',
    }));
    return sortModelsByRate(models);
  }

  return [];
}

// Get user's style profile
function getUserStyleProfile(userId) {
  const db = getDB();
  const user = db.prepare('SELECT ai_style_profile FROM users WHERE id = ?').get(userId);
  try {
    return JSON.parse(user?.ai_style_profile || '{}');
  } catch {
    return {};
  }
}

// Save user style profile
function updateStyleProfile(userId, profile) {
  const db = getDB();
  db.prepare('UPDATE users SET ai_style_profile = ? WHERE id = ?')
    .run(JSON.stringify(profile), userId);
}

function normalizeForKey(text) {
  return (text || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function shortenToWords(text, maxWords = 18) {
  const words = (text || '').trim().split(/\s+/).filter(Boolean);
  if (words.length <= maxWords) return text.trim();
  return `${words.slice(0, maxWords).join(' ')}...`;
}

function clampNumber(v, min, max, fallback) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(n)));
}

function limitTextBySentencesAndWords(text, maxWords = 120, maxSentences = 6) {
  const raw = (text || '').trim();
  if (!raw) return '';
  const sentenceParts = raw
    .split(/(?<=[.!?।])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
  const sentenceLimited = sentenceParts.slice(0, maxSentences).join(' ').trim();
  return shortenToWords(sentenceLimited || raw, maxWords);
}

function answerLengthDefaults(answerLength) {
  const mode = (answerLength || 'medium').toString().toLowerCase();
  if (mode === 'short') return { maxWords: 80, maxSentences: 4 };
  if (mode === 'long') return { maxWords: 260, maxSentences: 12 };
  return { maxWords: 150, maxSentences: 7 };
}

function inferHeading(text, index = 0) {
  const t = (text || '').toLowerCase();
  if (/\b(promise|wada|gift|dena|denge|surprise)\b/.test(t)) return 'Commitment';
  if (/\b(idea|concept|khayal|vichar|song|music|lyrics)\b/.test(t)) return 'Idea';
  if (/\b(todo|task|karna|next|step|plan|reminder|buy|bhejna|send)\b/.test(t)) return 'Action';
  if (/\b(call|meeting|baat|discussion|chat|mulaqat)\b/.test(t)) return 'Discussion';
  if (/\b(date|time|today|tomorrow|kal|aaj|deadline)\b/.test(t)) return 'Timeline';
  return `Point ${index + 1}`;
}

function stripExistingHeading(text) {
  return (text || '')
    .replace(/^\s*[-*•]?\s*/g, '')
    .replace(/^(point\s*\d+|action|idea|timeline|discussion|commitment)\s*:\s*/i, '')
    .trim();
}

function toHeadlineBullets(lines) {
  return lines
    .map(l => l.replace(/^(\d+\.|[-*•])\s+/, '').trim())
    .filter(Boolean)
    .slice(0, 10)
    .map((line, i) => {
      const finalLine = stripExistingHeading(line);
      return `- ${inferHeading(finalLine, i)}: ${shortenToWords(finalLine, 24)}`;
    })
    .join('\n');
}

// Better fallback summarize (no AI): short actionable bullets
function simpleSummarize(text) {
  const rawPieces = (text || '')
    .split(/[\n\r]+|[।.!?]+/g)
    .map(s => s.trim())
    .filter(s => s.length > 14);

  const seen = new Set();
  const candidates = [];
  for (const p of rawPieces) {
    const tokens = normalizeForKey(p).filter(t => t.length > 2);
    if (!tokens.length) continue;
    const key = tokens.slice(0, 8).join(' ');
    if (seen.has(key)) continue;
    seen.add(key);
    let score = Math.min(tokens.length, 20);
    if (/\b(idea|gift|promise|wada|important|urgent|deadline|meeting|call|todo|reminder|buy|dena)\b/i.test(p)) {
      score += 8;
    }
    if (/\b(today|kal|tomorrow|aaj|date|time)\b/i.test(p)) {
      score += 4;
    }
    candidates.push({ text: p, score });
  }

  const selected = candidates
    .sort((a, b) => b.score - a.score)
    .slice(0, 8)
    .map(c => c.text);

  if (!selected.length) {
    return toHeadlineBullets([shortenToWords((text || '').trim(), 24)]);
  }
  return toHeadlineBullets(selected);
}

function normalizeSummary(summary, sourceText) {
  const cleaned = (summary || '').trim();
  if (!cleaned) return simpleSummarize(sourceText);
  const source = (sourceText || '').trim();
  if (!source) return cleaned;
  const sourceShort = source.substring(0, 2000).replace(/\s+/g, ' ').toLowerCase();
  const summaryShort = cleaned.substring(0, 2000).replace(/\s+/g, ' ').toLowerCase();
  if (summaryShort.length > sourceShort.length * 0.9 || sourceShort.includes(summaryShort)) {
    return simpleSummarize(sourceText);
  }
  return cleaned;
}

function ensureBulletSummary(text) {
  const raw = (text || '').trim();
  if (!raw) return '';
  const lines = raw.split('\n').map(l => l.trim()).filter(Boolean);
  const bulletLike = lines.filter(l => /^(\d+\.|[-*•])\s+/.test(l));
  if (bulletLike.length >= 2) {
    return toHeadlineBullets(bulletLike);
  }

  const chunks = raw
    .split(/[।.!?\n]+/)
    .map(s => s.trim())
    .filter(s => s.length > 6)
    .slice(0, 10);
  if (!chunks.length) return `- ${raw}`;
  return toHeadlineBullets(chunks);
}

function extractJsonObject(rawText) {
  if (!rawText) return null;
  const fenced = rawText.match(/```json\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : rawText;
  const jsonMatch = candidate.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return null;
  try {
    return JSON.parse(jsonMatch[0]);
  } catch {
    return null;
  }
}

function tokenize(text) {
  return (text || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter(t => t.length > 1);
}

function buildCombinedNoteText(note) {
  return `${note.title || ''}. ${note.content || ''}. ${note.media_context || ''}`.trim();
}

function loadSourceMediaPreview(db, userId, noteIds) {
  if (!Array.isArray(noteIds) || noteIds.length === 0) return [];
  const placeholders = noteIds.map(() => '?').join(',');
  const rows = db.prepare(`
    SELECT
      m.note_id,
      m.file_path,
      m.file_type,
      COALESCE(m.display_name, m.file_name) as display_name,
      COALESCE(m.caption, '') as caption
    FROM media m
    WHERE m.user_id = ?
      AND m.note_id IN (${placeholders})
    ORDER BY
      CASE WHEN m.file_type LIKE 'image/%' THEN 0 ELSE 1 END,
      m.created_at DESC
    LIMIT 24
  `).all(userId, ...noteIds);

  return rows.map((r) => ({
    note_id: r.note_id,
    file_path: r.file_path,
    file_type: r.file_type,
    display_name: r.display_name,
    caption: r.caption,
  }));
}

const SYNONYM_GROUPS = [
  ['girlfriend', 'gf', 'partner', 'love', 'pyaar', 'purwa'],
  ['gift', 'dena', 'denge', 'promise', 'wada', 'surprise'],
  ['song', 'music', 'track', 'melody', 'lyrics', 'beat'],
  ['idea', 'concept', 'notion', 'soch', 'khayal', 'vichar'],
  ['meeting', 'call', 'discussion', 'baat', 'conversation'],
];

function expandTokens(tokens) {
  const expanded = new Set(tokens);
  for (const token of tokens) {
    for (const group of SYNONYM_GROUPS) {
      if (group.includes(token)) {
        for (const g of group) expanded.add(g);
      }
    }
  }
  return expanded;
}

function semanticFallbackSearch(query, notes) {
  const queryTokens = tokenize(query);
  const expandedQuery = expandTokens(queryTokens);

  const scored = notes.map((n) => {
    const content = buildCombinedNoteText(n);
    const chunks = content
      .split(/[.!?\n।]+/g)
      .map(s => s.trim())
      .filter(Boolean);
    let bestScore = 0;
    let bestChunk = content.substring(0, 180);
    let bestTerms = [];

    for (const c of chunks) {
      const cTokens = new Set(tokenize(c));
      let overlap = 0;
      const matched = [];
      for (const t of expandedQuery) {
        if (cTokens.has(t)) {
          overlap += 1;
          matched.push(t);
        }
      }
      // lightweight fuzzy match for misspelled/partial words
      for (const t of expandedQuery) {
        if (t.length < 4) continue;
        if (c.toLowerCase().includes(t.substring(0, 4))) overlap += 0.25;
      }
      const score = overlap;
      if (score > bestScore) {
        bestScore = score;
        bestChunk = c;
        bestTerms = matched;
      }
    }

    const recencyBoost = n.created_at ? (new Date(n.created_at).getTime() / 1e13) : 0;
    const score = bestScore * 10 + recencyBoost;
    return {
      note: {
        ...n,
        match_snippet: shortenToWords(bestChunk, 26),
        match_terms: bestTerms.slice(0, 8),
      },
      score,
    };
  });

  return scored
    .filter((x) => x.score >= 6)
    .sort((a, b) => b.score - a.score)
    .slice(0, 20)
    .map((x) => x.note);
}

function buildSearchMetadata(note, query) {
  const queryTokens = Array.from(expandTokens(tokenize(query)));
  const content = buildCombinedNoteText(note).replace(/\s+/g, ' ').trim();
  const lowered = content.toLowerCase();
  const matchedTerms = queryTokens.filter(t => lowered.includes(t)).slice(0, 8);

  let snippet = content.substring(0, 180);
  let anchorIndex = -1;
  for (const t of matchedTerms) {
    const i = lowered.indexOf(t);
    if (i >= 0 && (anchorIndex < 0 || i < anchorIndex)) anchorIndex = i;
  }
  if (anchorIndex >= 0) {
    const start = Math.max(0, anchorIndex - 45);
    const end = Math.min(content.length, anchorIndex + 140);
    snippet = `${start > 0 ? '...' : ''}${content.substring(start, end)}${end < content.length ? '...' : ''}`;
  }

  return {
    ...note,
    match_terms: matchedTerms,
    match_snippet: snippet,
  };
}

function buildEvidenceWindow(content, entities = [], maxLen = 360) {
  const text = (content || '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  const lowered = text.toLowerCase();
  let anchor = -1;
  for (const e of entities) {
    const re = entityAliasRegex(e);
    if (!re) continue;
    const hit = lowered.match(re);
    if (hit?.index != null) {
      anchor = hit.index;
      break;
    }
  }
  if (anchor < 0) return text.substring(0, maxLen);
  const start = Math.max(0, anchor - 120);
  const end = Math.min(text.length, anchor + maxLen - 120);
  return `${start > 0 ? '...' : ''}${text.substring(start, end)}${end < text.length ? '...' : ''}`;
}

function buildAiSearchPrompt(query, notesContext) {
  return [
    {
      role: 'system',
      content: [
        'You are a multilingual semantic note search engine.',
        'Return STRICT JSON only with this schema:',
        '{"intent":"...", "relevant":[{"id":"...", "why":"...", "evidence":"...", "confidence":0.0}], "query_terms":["..."]}',
        'Rules:',
        '1) Match by intent and context, not only exact words.',
        '2) Prefer notes with concrete commitments, promises, plans, deadlines, people names.',
        '3) evidence must be a short snippet copied from note text that caused the match.',
        '4) confidence between 0 and 1.',
        '5) Maximum 10 relevant items.',
      ].join('\n'),
    },
    {
      role: 'user',
      content: `User query: "${query}"\n\nNotes:\n${notesContext}`,
    },
  ];
}

function parseAiSearchResponse(aiText) {
  const parsed = extractJsonObject(aiText);
  if (!parsed || !Array.isArray(parsed.relevant)) {
    return { intent: '', items: [], queryTerms: [] };
  }
  const items = parsed.relevant
    .map((r) => ({
      id: (r.id || '').toString(),
      why: (r.why || '').toString(),
      evidence: (r.evidence || '').toString(),
      confidence: Number(r.confidence || 0),
    }))
    .filter((r) => r.id);
  const queryTerms = Array.isArray(parsed.query_terms)
    ? parsed.query_terms.map((t) => t.toString()).filter(Boolean)
    : [];
  return {
    intent: (parsed.intent || '').toString(),
    items,
    queryTerms,
  };
}

function extractQuestionEntities(question) {
  return tokenize(question)
    .filter((t) => t.length > 2 && !QUERY_STOPWORDS.has(t))
    .slice(0, 8);
}

function isPresenceQuery(question) {
  const q = (question || '').toLowerCase();
  return /name|naam|mention|hai kya|he kya|exists|mila|present/.test(q);
}

const QUERY_STOPWORDS = new Set([
  'kya', 'ka', 'ki', 'ke', 'ko', 'hai', 'tha', 'thi', 'the', 'mujhe', 'mene',
  'maine', 'mera', 'meri', 'mere', 'yaad', 'nahi', 'please', 'bolo', 'about',
  'for', 'with', 'and', 'tha?', 'hai?', 'karna', 'tha.', 'name', 'naam', 'note',
  'notes', 'kahi', 'kahan', 'konsa', 'kaunsi', 'kon', 'kaun', 'he',
]);

const PROMISE_TERMS = ['wada', 'promise', 'dena', 'denge', 'gift', 'surprise', 'bhejna', 'lena'];

function entityAliasRegex(entity) {
  const e = (entity || '').toLowerCase();
  if (!e) return null;
  if (/krishna|kishna|krushna|kishan/.test(e)) {
    return /\b(krishna|kishna|krushna|kishan|kanha|kanhaaiya|keshav)\b/i;
  }
  if (e.length <= 3) return new RegExp(`\\b${e}\\b`, 'i');
  const stem = e.substring(0, 4);
  return new RegExp(`\\b${stem}\\w*\\b`, 'i');
}

function entityHitsInAllNotes(entities, notes) {
  const hits = [];
  for (const e of entities) {
    const re = entityAliasRegex(e);
    if (!re) continue;
    if (notes.some((n) => re.test(buildCombinedNoteText(n).toLowerCase()))) {
      hits.push(e);
    }
  }
  return hits;
}

function keywordMemorySearch(query, notes) {
  const q = (query || '').toLowerCase();
  const qTokens = tokenize(query).filter(t => !QUERY_STOPWORDS.has(t));
  const queryHasPromiseIntent = /kya dena tha|wada|promise|gift|dena/i.test(q);
  const personHints = qTokens.filter(t => t.length > 2).slice(0, 6);

  const scored = notes.map((n) => {
    const content = buildCombinedNoteText(n);
    const lowered = content.toLowerCase();
    let score = 0;
    const reasons = [];
    const matchTerms = [];

    for (const p of personHints) {
      if (lowered.includes(p)) {
        score += 5;
        reasons.push(`person match "${p}"`);
        matchTerms.push(p);
      }
    }

    const notePromiseTerms = PROMISE_TERMS.filter(t => lowered.includes(t));
    if (queryHasPromiseIntent && notePromiseTerms.length) {
      score += 6 + notePromiseTerms.length;
      reasons.push('promise/gift intent match');
      matchTerms.push(...notePromiseTerms);
    }

    if (/birthday|anniversary|meeting|kal|tomorrow|deadline/i.test(lowered) && queryHasPromiseIntent) {
      score += 2;
    }

    if (score < 7) return null;

    const snippet = buildSearchMetadata(n, query).match_snippet;
    return {
      ...n,
      match_snippet: snippet,
      match_terms: Array.from(new Set(matchTerms)).slice(0, 8),
      match_reason: `Keyword memory: ${reasons.join(', ')}`,
      match_confidence: Number(Math.min(0.99, 0.55 + score / 20).toFixed(2)),
      _memory_score: score,
    };
  }).filter(Boolean);

  return scored
    .sort((a, b) => (b._memory_score || 0) - (a._memory_score || 0))
    .slice(0, 10)
    .map(({ _memory_score, ...rest }) => rest);
}

// ── SUMMARIZE ──
router.post('/summarize', auth, async (req, res) => {
  try {
    const { text, note_ids, folder_id } = req.body;
    const db = getDB();

    let contentToSummarize = text;

    if (note_ids?.length) {
      const placeholders = note_ids.map(() => '?').join(',');
      const notes = db.prepare(`SELECT content FROM notes WHERE id IN (${placeholders}) AND user_id = ?`)
        .all(...note_ids, req.user.id);
      contentToSummarize = notes.map(n => n.content).join('\n\n');
    } else if (folder_id) {
      const notes = db.prepare('SELECT content FROM notes WHERE folder_id = ? AND user_id = ? ORDER BY created_at DESC LIMIT 20')
        .all(folder_id, req.user.id);
      contentToSummarize = notes.map(n => n.content).join('\n\n');
    }

    if (!contentToSummarize) return res.status(400).json({ error: 'Summarize karne ke liye content do' });

    const styleProfile = getUserStyleProfile(req.user.id);
    const styleHint = styleProfile.summary_style
      ? `\nUser ki style: ${styleProfile.summary_style}`
      : '';

    const aiResponse = await callAI([
      {
        role: 'system',
        content: `Tu ek personal AI assistant hai. Sirf concise action bullets do. Har bullet max 16 words. 6-10 bullets. Full paragraph ya copy-paste allowed nahi.${styleHint}`
      },
      {
        role: 'user',
        content: `Yeh notes ka high-value summary banao: decisions, promises, next actions, people, deadlines.\n\n${contentToSummarize}`
      }
    ], null, req.user.id);

    let summary;
    let usedAI = true;

    if (aiResponse) {
      summary = normalizeSummary(aiResponse, contentToSummarize);
      // Log for style learning
      db.prepare('INSERT INTO ai_interactions (user_id, interaction_type, input_text, output_text) VALUES (?, ?, ?, ?)')
        .run(req.user.id, 'summarize', contentToSummarize.substring(0, 500), summary.substring(0, 500));
    } else {
      // Fallback: simple summarize
      summary = simpleSummarize(contentToSummarize);
      usedAI = false;
    }

    summary = ensureBulletSummary(summary);

    res.json({ success: true, summary, usedAI });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── SMART SEARCH ──
router.post('/search', auth, async (req, res) => {
  try {
    const { query } = req.body;
    if (!query) return res.status(400).json({ error: 'Search query do' });

    const db = getDB();

    // Get all user notes
    const allNotes = db.prepare(`
      SELECT
        n.id,
        n.title,
        n.content,
        n.created_at,
        f.name as folder_name,
        (
          SELECT m.file_path
          FROM media m
          WHERE m.note_id = n.id
            AND m.user_id = n.user_id
            AND (
              m.file_type LIKE 'image/%'
              OR LOWER(m.file_path) LIKE '%.png'
              OR LOWER(m.file_path) LIKE '%.jpg'
              OR LOWER(m.file_path) LIKE '%.jpeg'
              OR LOWER(m.file_path) LIKE '%.webp'
            )
          ORDER BY m.created_at DESC
          LIMIT 1
        ) as preview_image_path,
        (
          SELECT GROUP_CONCAT(COALESCE(m.display_name, m.file_name), ' | ')
          FROM media m
          WHERE m.note_id = n.id AND m.user_id = n.user_id
        ) as media_labels,
        (
          SELECT GROUP_CONCAT(
            TRIM(
              COALESCE(m.display_name, m.file_name, '') ||
              CASE
                WHEN m.caption IS NOT NULL AND m.caption != '' THEN ': ' || m.caption
                ELSE ''
              END
            ),
            ' | '
          )
          FROM media m
          WHERE m.note_id = n.id AND m.user_id = n.user_id
        ) as media_context
      FROM notes n LEFT JOIN folders f ON n.folder_id = f.id
      WHERE n.user_id = ?
      ORDER BY n.created_at DESC
    `).all(req.user.id);

    if (!allNotes.length) {
      return res.json({ success: true, results: [], message: 'Koi notes nahi hain abhi' });
    }

    // Deterministic personal keyword-memory pass (cheap and stable)
    const memoryResults = keywordMemorySearch(query, allNotes);

    // Try AI search first
    const notesContext = allNotes.map((n, i) =>
      `[${i}] ID:${n.id} | Folder:${n.folder_name || 'None'} | Date:${n.created_at}\n${buildCombinedNoteText(n).substring(0, 450)}`
    ).join('\n---\n');

    const aiResponse = await callAI(buildAiSearchPrompt(query, notesContext), null, req.user.id);

    let results = [];
    let explanation = '';

    if (aiResponse) {
      const parsed = parseAiSearchResponse(aiResponse);
      if (parsed.items.length) {
        const byId = new Map(allNotes.map((n) => [n.id, n]));
        results = parsed.items
          .map((r) => {
            const note = byId.get(r.id);
            if (!note) return null;
            return {
              ...note,
              match_snippet: r.evidence || (note.content || '').substring(0, 180),
              match_terms: parsed.queryTerms,
              match_reason: r.why,
              match_confidence: r.confidence,
            };
          })
          .filter(Boolean);
        explanation = parsed.intent || 'Intent-based semantic search result';
      }
    }

    if (memoryResults.length) {
      const map = new Map(results.map(r => [r.id, r]));
      for (const mr of memoryResults) {
        if (!map.has(mr.id)) {
          results.push(mr);
          continue;
        }
        const existing = map.get(mr.id);
        if (!existing.match_reason) {
          existing.match_reason = mr.match_reason;
          existing.match_confidence = mr.match_confidence;
          existing.match_terms = mr.match_terms;
          existing.match_snippet = mr.match_snippet;
        }
      }
      if (!explanation) {
        explanation = 'Personal keyword-memory + semantic match';
      }
    }

    // Fallback: semantic token search (local, no API cost)
    if (!results.length) {
      results = semanticFallbackSearch(query, allNotes);
      explanation = results.length
        ? 'Semantic fallback se relevant notes mile (exact word match zaroori nahi).'
        : '';
    }

    results = results.map((r) => {
      if (r.match_snippet) return r;
      return buildSearchMetadata(r, query);
    });

    res.json({ success: true, results, explanation, usedAI: !!aiResponse });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── ASK NOTES (ESSAY STYLE) ──
router.post('/ask', auth, async (req, res) => {
  try {
    const {
      question,
      tone = 'creative',
      answer_length = 'medium',
      max_words,
      max_sentences,
      include_counter_question = false,
      conversation_history = [],
    } = req.body;
    if (!question) return res.status(400).json({ error: 'Question do' });
    const defaults = answerLengthDefaults(answer_length);
    const wordsLimit = clampNumber(max_words, 30, 450, defaults.maxWords);
    const sentenceLimit = clampNumber(max_sentences, 2, 20, defaults.maxSentences);

    const db = getDB();
    const allNotes = db.prepare(`
      SELECT
        n.id,
        n.title,
        n.content,
        n.created_at,
        f.name as folder_name,
        (
          SELECT GROUP_CONCAT(
            TRIM(
              COALESCE(m.display_name, m.file_name, '') ||
              CASE
                WHEN m.caption IS NOT NULL AND m.caption != '' THEN ': ' || m.caption
                ELSE ''
              END
            ),
            ' | '
          )
          FROM media m
          WHERE m.note_id = n.id AND m.user_id = n.user_id
        ) as media_context
      FROM notes n LEFT JOIN folders f ON n.folder_id = f.id
      WHERE n.user_id = ?
      ORDER BY n.created_at DESC
      LIMIT 120
    `).all(req.user.id);

    if (!allNotes.length) {
      return res.json({
        success: true,
        answer: 'Abhi notes nahi hain. Thode notes save karo, fir main essay answer dunga.',
        usedAI: false,
      });
    }

    const ranked = keywordMemorySearch(question, allNotes);
    const picked = ranked.length ? ranked : semanticFallbackSearch(question, allNotes);
    const sourceNotes = (picked.length ? picked : allNotes.slice(0, 10)).slice(0, 15);
    const entities = extractQuestionEntities(question);
    const exactEntityHits = entityHitsInAllNotes(entities, allNotes);

    if (isPresenceQuery(question) && exactEntityHits.length) {
      const evidence = allNotes
        .filter((n) => exactEntityHits.some((e) => {
          const re = entityAliasRegex(e);
          return re ? re.test(buildCombinedNoteText(n).toLowerCase()) : false;
        }))
        .slice(0, 6)
        .map((n) => `- ${buildCombinedNoteText(n).replace(/\s+/g, ' ').trim().substring(0, 220)}...`)
        .join('\n');
      return res.json({
        success: true,
        answer:
          `Title: Haan, mention mila\n\n` +
          `Question entity "${exactEntityHits.join(', ')}" notes me mili. Evidence:\n${evidence}\n\n` +
          `Conclusion: notes me yeh reference present hai.`,
        usedAI: false,
        source_media: loadSourceMediaPreview(
          db,
          req.user.id,
          allNotes
            .filter((n) => exactEntityHits.some((e) => {
              const re = entityAliasRegex(e);
              return re ? re.test(buildCombinedNoteText(n).toLowerCase()) : false;
            }))
            .slice(0, 6)
            .map((n) => n.id),
        ),
        sources: allNotes
          .filter((n) => exactEntityHits.some((e) => {
            const re = entityAliasRegex(e);
            return re ? re.test(buildCombinedNoteText(n).toLowerCase()) : false;
          }))
          .slice(0, 6)
          .map((n) => n.id),
      });
    }

    const notesContext = sourceNotes.map((n, i) => {
      const text = buildEvidenceWindow(buildCombinedNoteText(n), entities, 520);
      return `[${i + 1}] ${n.created_at} | ${n.folder_name || 'No folder'}\n${text}`;
    }).join('\n---\n');
    const historyLines = Array.isArray(conversation_history)
      ? conversation_history
          .slice(-6)
          .map((h, i) => {
            const q = (h?.question || '').toString().trim();
            const a = (h?.answer || '').toString().trim();
            if (!q && !a) return '';
            return `Turn ${i + 1}\nQ: ${q}\nA: ${a}`;
          })
          .filter(Boolean)
          .join('\n\n')
      : '';

    const aiMessages = [
      {
        role: 'system',
        content: `Tum personal note analyst ho. User ke notes se grounded answer do. Style: ${tone}. Hindi/Hinglish mein natural likho. 
Output strictly JSON:
{
  "answer": "string",
  "counter_question": "string or empty"
}
Rules:
- answer max ${wordsLimit} words aur max ${sentenceLimit} sentences.
- concise, useful, evidence-based.
- notes ki lines verbatim copy-paste mat karo; paraphrase karo.
- agar info unclear ho to clearly bolo.
- IMPORTANT: agar question entity notes mein mil rahi ho, kabhi "mention nahi mila" mat bolo.
- counter_question tabhi do jab include_counter_question=true, warna empty string.`,
      },
      {
        role: 'user',
        content: `Question: ${question}
include_counter_question=${include_counter_question ? 'true' : 'false'}

Hard facts: exact entity hits = ${exactEntityHits.join(', ') || 'none'}

Relevant notes:
${notesContext}`,
      },
    ];
    if (historyLines) {
      aiMessages.push({
        role: 'user',
        content: `Conversation history (latest turns):\n${historyLines}`,
      });
    }
    const aiResponse = await callAI(aiMessages, null, req.user.id);

    let answer = '';
    let counterQuestion = '';
    let usedAI = true;
    if (aiResponse) {
      const parsed = extractJsonObject(aiResponse);
      if (parsed && typeof parsed === 'object') {
        answer = (parsed.answer || '').toString().trim();
        counterQuestion = include_counter_question
          ? (parsed.counter_question || '').toString().trim()
          : '';
      }
      if (!answer) {
        answer = aiResponse.toString().trim();
      }
    }
    const aiDeniedEntity =
      (answer || '').toLowerCase().includes('nahi mila') ||
      (answer || '').toLowerCase().includes('match nahi') ||
      (answer || '').toLowerCase().includes('nazar nahi') ||
      (answer || '').toLowerCase().includes('directly nazar');
    if (answer && exactEntityHits.length > 0 && aiDeniedEntity) {
      const snippets = sourceNotes
        .filter((n) => exactEntityHits.some((e) => {
          const re = entityAliasRegex(e);
          return re ? re.test(buildCombinedNoteText(n).toLowerCase()) : false;
        }))
        .slice(0, 4)
        .map((n) => `- ${buildEvidenceWindow(buildCombinedNoteText(n), exactEntityHits, 180)}`)
        .join('\n');
      answer = `Title: Notes mein clear mention mila

Tumhare notes mein question wali entity ka mention hai. Yeh direct evidence mila:
${snippets}

Is basis pe answer: connection present hai, exact context upar evidence mein diya hai.`;
    }
    if (!answer) {
      usedAI = false;
      const lines = sourceNotes
        .map((n) => buildCombinedNoteText(n).trim())
        .filter(Boolean)
        .slice(0, 4)
        .map((line) => `- ${shortenToWords(line, 24)}`)
        .join('\n');
      answer = `Title: Notes se jo samajh aaya\n\nMere paas AI response available nahi tha, lekin tumhare notes ke basis par yeh relevant points lage:\n${lines}`;
      if (include_counter_question) {
        counterQuestion = 'Kya tum is answer me kisi specific person/date/event pe aur detail chahte ho?';
      }
    }

    answer = limitTextBySentencesAndWords(answer, wordsLimit, sentenceLimit);
    if (!include_counter_question) {
      counterQuestion = '';
    }

    res.json({
      success: true,
      answer,
      counter_question: counterQuestion,
      usedAI,
      source_media: loadSourceMediaPreview(db, req.user.id, sourceNotes.map((n) => n.id)),
      sources: sourceNotes.map((n) => n.id),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── VOICE POST-CLEANUP (NON-REALTIME) ──
router.post('/cleanup-text', auth, async (req, res) => {
  try {
    const { text } = req.body;
    if (!text || text.trim().length < 12) {
      return res.json({ success: true, cleaned_text: text || '', usedAI: false });
    }

    const aiResponse = await callAI([
      {
        role: 'system',
        content:
          'Fix transcript text with minimal edits: add punctuation (. , ?), sentence boundaries, and likely word corrections from context. Keep original language/style and meaning. Do NOT add new facts. Return only cleaned text.',
      },
      { role: 'user', content: text },
    ], null, req.user.id);

    if (aiResponse && aiResponse.trim().length > 0) {
      return res.json({ success: true, cleaned_text: aiResponse.trim(), usedAI: true });
    }

    const fallback = text
      .replace(/\s+/g, ' ')
      .replace(/\s+([,.!?])/g, '$1')
      .trim();
    return res.json({ success: true, cleaned_text: fallback, usedAI: false });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── STYLE LEARNING ──
router.post('/learn-style', auth, async (req, res) => {
  try {
    const db = getDB();

    // Get last 20 notes
    const notes = db.prepare('SELECT content FROM notes WHERE user_id = ? ORDER BY created_at DESC LIMIT 20')
      .all(req.user.id);

    if (notes.length < 3) {
      return res.json({ success: false, message: 'Abhi 3 se zyada notes likhne ke baad style seekha jaayega' });
    }

    const sampleText = notes.map(n => n.content).join('\n---\n');

    const aiResponse = await callAI([
      {
        role: 'system',
        content: 'User ke notes padhkar unki writing style analyze kar. Ek short style description do jo summarization mein use ho sake.'
      },
      {
        role: 'user',
        content: `Meri writing style kya hai? Yeh mere notes hain:\n\n${sampleText}`
      }
    ], null, req.user.id);

    if (aiResponse) {
      updateStyleProfile(req.user.id, { summary_style: aiResponse.substring(0, 300) });
      res.json({ success: true, message: 'Style seekh li!', style: aiResponse });
    } else {
      res.json({ success: false, message: 'AI available nahi — baad mein try karo' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── PROVIDER CONFIG ──
router.get('/providers-config', auth, (req, res) => {
  try {
    const cfg = getUserProviderConfig(req.user.id);
    res.json({
      success: true,
      config: {
        ...cfg,
        primary: { ...cfg.primary, api_key: maskApiKey(cfg.primary.api_key) },
        fallback: { ...cfg.fallback, api_key: maskApiKey(cfg.fallback.api_key) },
      },
      provider_options: PROVIDERS,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/providers-config', auth, (req, res) => {
  try {
    const body = req.body || {};
    const existing = getUserProviderConfig(req.user.id);
    const nextPrimaryKey = (body?.primary?.api_key || '').toString().trim();
    const nextFallbackKey = (body?.fallback?.api_key || '').toString().trim();
    const cfg = {
      primary: {
        provider: sanitizeProvider(body?.primary?.provider) || 'openrouter',
        api_key: nextPrimaryKey.length > 0 ? nextPrimaryKey : (existing.primary?.api_key || ''),
        model: (body?.primary?.model || '').toString().trim(),
        base_url: (body?.primary?.base_url || '').toString().trim(),
      },
      fallback: {
        provider: sanitizeProvider(body?.fallback?.provider),
        api_key: nextFallbackKey.length > 0 ? nextFallbackKey : (existing.fallback?.api_key || ''),
        model: (body?.fallback?.model || '').toString().trim(),
        base_url: (body?.fallback?.base_url || '').toString().trim(),
      },
      use_fallback: body?.use_fallback !== false,
    };
    saveUserProviderConfig(req.user.id, cfg);
    res.json({
      success: true,
      config: {
        ...cfg,
        primary: { ...cfg.primary, api_key: maskApiKey(cfg.primary.api_key) },
        fallback: { ...cfg.fallback, api_key: maskApiKey(cfg.fallback.api_key) },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/providers-models', auth, async (req, res) => {
  try {
    const provider = sanitizeProvider(req.body?.provider);
    if (!provider) {
      return res.status(400).json({ success: false, error: 'Provider required' });
    }

    const userCfg = getUserProviderConfig(req.user.id);
    const slot = req.body?.slot === 'fallback' ? userCfg.fallback : userCfg.primary;

    const apiKey =
      (req.body?.api_key || '').toString().trim() ||
      (slot?.api_key || '').toString().trim() ||
      (provider === 'openrouter' ? process.env.OPENROUTER_API_KEY || '' : '') ||
      (provider === 'openai' ? process.env.OPENAI_API_KEY || '' : '');
    const baseUrl =
      (req.body?.base_url || '').toString().trim() ||
      (slot?.base_url || '').toString().trim();

    const models = await fetchProviderModels({ provider, apiKey, baseUrl });
    res.json({ success: true, provider, models });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.response?.data?.error?.message || err.message,
    });
  }
});

// ── AI STATUS ──
router.get('/status', auth, async (req, res) => {
  try {
    const configured = getUserProviderConfig(req.user.id);
    const configuredChain = [
      {
        provider: configured.primary?.provider || '',
        model: configured.primary?.model || '',
        fallback: false,
      },
    ];
    if (configured.use_fallback && (configured.fallback?.provider || '').length > 0) {
      configuredChain.push({
        provider: configured.fallback.provider,
        model: configured.fallback.model || '',
        fallback: true,
      });
    }

    const chain = resolveRuntimeChain(req.user.id);
    const providers = {};
    let firstAvailable = null;

    for (const entry of chain) {
      const result = await checkProviderStatus(entry);
      const autoFallbackModels = entry.provider === 'openrouter'
        ? getCandidateModels(entry.model).slice(1, 6)
        : [];
      providers[entry.fallback ? `${entry.provider}_fallback` : entry.provider] = {
        provider: entry.provider,
        model: entry.model,
        fallback: !!entry.fallback,
        auto_fallback_models: autoFallbackModels,
        ...result,
      };
      if (!firstAvailable && result.available) {
        firstAvailable = { ...entry, ...result };
      }
    }

    res.json({
      success: true,
      ai_available: !!firstAvailable,
      providers,
      configured_chain: configuredChain,
      chain: chain.map((c) => ({
        provider: c.provider,
        model: c.model,
        fallback: c.fallback,
      })),
      message: firstAvailable
        ? `AI ready (${firstAvailable.provider}: ${firstAvailable.model || firstAvailable.model})`
        : `AI fallback mode: no provider reachable (configured: ${configuredChain.map((x) => `${x.provider}${x.fallback ? ' [fallback]' : ''}`).join(' -> ') || 'none'})`,
    });
  } catch (err) {
    res.json({
      success: true,
      ai_available: false,
      providers: { unknown: { available: false, reason: err.message } },
      message: `AI fallback mode: ${err.message}`,
    });
  }
});

module.exports = router;
