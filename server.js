require('dotenv').config();
const express = require('express');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const APP_ROOT = __dirname;

// Auto-gen SESSION_SECRET if missing (first-boot bootstrap).
// Setup wizard still asks for it but server must boot before setup is reachable.
if (!process.env.SESSION_SECRET) {
  const generated = crypto.randomBytes(32).toString('hex');
  process.env.SESSION_SECRET = generated;
  try {
    const envPath = path.join(APP_ROOT, '.env');
    let envText = '';
    try { envText = fs.readFileSync(envPath, 'utf8'); } catch {}
    if (!/^\s*SESSION_SECRET\s*=/m.test(envText)) {
      envText += (envText && !envText.endsWith('\n') ? '\n' : '') + `SESSION_SECRET=${generated}\n`;
      fs.writeFileSync(envPath, envText);
    }
  } catch {}
}

const { createSource } = require('./lib/source-factory');
const { pollAndIngest } = require('./lib/ingest');
const auth = require('./lib/auth');
const { mountLicense } = require('./lib/license');

const app = express();
const PORT = process.env.PORT || 3100;

app.use(express.json());

// flowiqa.com license gate (mounts /activate + /api/license/*).
// MUST be before auth/setup so users cannot access app without valid license.
mountLicense(app);

// Setup gate: license var ama .env'de DATA_SOURCE eksikse /setup wizard'ina yonlendir.
// SESSION_SECRET zaten auto-gen edildi, kullanici secmesi gereken sadece veri kaynagi.
function isSetupComplete() {
  return !!process.env.DATA_SOURCE;
}

app.get('/setup', (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.sendFile(path.join(APP_ROOT, 'public', 'setup.html'));
});

app.post('/api/setup', express.json(), (req, res) => {
  const { dataSource, easyship, session } = req.body || {};
  const validSources = ['mock', 'easyship', 'navlungo', 'shipentegra', 'email'];
  if (!validSources.includes(dataSource)) return res.status(400).json({ error: 'invalid_data_source' });
  if (dataSource === 'easyship' && (typeof easyship !== 'string' || !easyship.trim())) {
    return res.status(400).json({ error: 'missing_easyship_token' });
  }
  if (typeof session !== 'string' || session.length < 32) {
    return res.status(400).json({ error: 'invalid_session_secret' });
  }
  try {
    const envPath = path.join(APP_ROOT, '.env');
    let envText = '';
    try { envText = fs.readFileSync(envPath, 'utf8'); } catch {}
    const lines = envText.split(/\r?\n/);
    function setKey(key, value) {
      const idx = lines.findIndex(l => l.match(new RegExp('^\\s*' + key + '\\s*=')));
      if (idx >= 0) lines[idx] = `${key}=${value}`;
      else lines.push(`${key}=${value}`);
    }
    setKey('DATA_SOURCE', dataSource);
    if (easyship) setKey('EASYSHIP_API_TOKEN', easyship.trim());
    setKey('SESSION_SECRET', session.trim());
    fs.writeFileSync(envPath, lines.join('\n'));

    process.env.DATA_SOURCE = dataSource;
    if (easyship) process.env.EASYSHIP_API_TOKEN = easyship.trim();
    process.env.SESSION_SECRET = session.trim();

    return res.json({ ok: true });
  } catch (err) {
    console.error('[setup] write failed:', err.message);
    return res.status(500).json({ error: 'setup_failed' });
  }
});

// Setup gate middleware: /setup, /api/setup, /api/license/*, /activate haric
// .env'siz hicbir uygulama endpoint'ine girilemez.
app.use((req, res, next) => {
  const p = req.path;
  if (p === '/setup' || p.startsWith('/api/setup')) return next();
  if (p.startsWith('/api/license/')) return next();
  if (p === '/activate') return next();
  if (isSetupComplete()) return next();
  if (p.startsWith('/api/')) return res.status(412).json({ error: 'setup_required', setupUrl: '/setup' });
  return res.redirect('/setup');
});

app.use(auth.sessionMiddleware());
app.use(express.static(path.join(APP_ROOT, 'public')));

// Auth
app.post('/api/auth/login', auth.login);
app.post('/api/auth/logout', auth.logout);
app.post('/api/auth/signup', auth.signup);
app.get('/api/auth/me', auth.requireAuth, auth.me);

// Role-scoped route groups
app.use('/api/admin', require('./routes/admin'));
app.use('/api/store', require('./routes/store'));
app.use('/api/supplier', require('./routes/supplier'));

// Background poller (admin-triggered or interval)
const source = createSource(process.env);
const pollInterval = parseInt(process.env.POLL_INTERVAL_MS || '120000', 10);

async function pollTick() {
  try {
    const result = await pollAndIngest(source);
    if (result.inserted > 0) {
      console.log(`[poll] fetched ${result.fetched}, inserted ${result.inserted}`);
    }
    return result;
  } catch (err) {
    console.error('[poll] error:', err.message);
    return { error: err.message };
  }
}

app.post('/api/admin/poll-now', auth.requireAuth, auth.requireRole('admin'), async (req, res) => {
  const result = await pollTick();
  res.json(result || { ok: true });
});

app.listen(PORT, () => {
  console.log(`Supplier Hub running on http://localhost:${PORT}`);
  console.log(`Data source: ${process.env.DATA_SOURCE || 'mock'}`);
  if ((process.env.DATA_SOURCE || 'mock') !== 'mock') {
    setInterval(pollTick, pollInterval);
    pollTick();
  }
});
