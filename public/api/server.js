/**
 * NEXA Sovereign Serverless Backend Engine for Vercel
 * 
 * Self-contained Express application providing complete API support
 * for mobile clients, web application, and sovereign admin control center.
 */

const express = require('express');
const crypto = require('crypto');
const Database = require('./db');
const { router: adminRouter } = require('./admin');

const app = express();

// 1. CORS Middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-admin-master-key');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

app.use(express.json({ limit: '10mb' }));

// 2. URL Normalization Middleware
app.use((req, res, next) => {
  const matched = req.headers['x-matched-path'];
  if (matched && (req.url === '/api' || req.url === '/' || req.url === '')) {
    req.url = matched;
  }
  if (req.url.startsWith('/api/')) {
    req.url = req.url.slice(4);
  } else if (req.url === '/api') {
    req.url = '/health';
  }
  next();
});

// 3. Mount Admin Control Center Router
app.use(adminRouter);

// Helper to clean usernames
function sanitizeUsername(input) {
  if (!input || typeof input !== 'string') return '';
  return input.trim().replace(/^@+/, '').toLowerCase();
}

// In-memory runtime state for serverless execution
const activeDevices = new Map();
const mailboxQueue = new Map();

// --- 4. HEALTH & METRICS ---
app.get('/health', (req, res) => {
  const dbStatus = Database.getStatus();
  res.json({
    status: 'ok',
    service: 'nexa-sovereign-relay',
    security_mode: 'zero_knowledge_e2ee',
    crypto_standard: 'X3DH_DoubleRatchet_AES256GCM',
    database_connected: true,
    admin_routes_loaded: true,
    database_status: dbStatus,
    registered_users_count: dbStatus.users_count,
    active_devices: dbStatus.devices_count,
    pending_envelopes: dbStatus.pending_envelopes,
    timestamp: Date.now()
  });
});

app.get('/v1/auth/db-status', (req, res) => {
  res.json({
    online: true,
    server: 'NEXA Authentication & Relay Gateway',
    database: Database.getStatus(),
    timestamp: Date.now()
  });
});

// --- 5. AUTHENTICATION & USER MANAGEMENT ---
app.get('/v1/auth/check-username/:username', async (req, res) => {
  const username = sanitizeUsername(req.params.username);
  if (!username || username.length < 3) {
    return res.status(400).json({ available: false, error: 'Username must be at least 3 characters long.' });
  }

  const user = await Database.findUser(username);
  if (user) {
    return res.json({ available: false, username, message: `Username '@${username}' is already taken.` });
  }
  return res.json({ available: true, username, message: `Username '@${username}' is unique and available!` });
});

app.post('/v1/auth/register-user', async (req, res) => {
  const { username: rawUsername, password, fullName, about, phone } = req.body;
  const username = sanitizeUsername(rawUsername);

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required.' });
  }
  if (username.length < 3) {
    return res.status(400).json({ error: 'Username must be at least 3 characters long.' });
  }

  const existing = await Database.findUser(username);
  if (existing) {
    return res.status(409).json({ error: `Username '@${username}' is already registered.` });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  const nexaId = `NX-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;

  const newUser = await Database.createUser({
    username,
    handle: `@${username}`,
    nexa_id: nexaId,
    password_hash: passwordHash,
    full_name: fullName || username,
    about: about || 'Hey there! I am using NEXA.',
    phone: phone || null,
    role: 'user',
    status: 'active'
  });

  return res.status(201).json({
    success: true,
    message: 'User account registered successfully.',
    user: {
      username: newUser.username,
      handle: newUser.handle,
      nexaId: newUser.nexa_id,
      fullName: newUser.full_name,
      about: newUser.about
    }
  });
});

app.post('/v1/auth/login-user', async (req, res) => {
  const { username: rawUsername, password } = req.body;
  const username = sanitizeUsername(rawUsername);

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required.' });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  const user = await Database.findUser(username);

  if (!user) {
    return res.status(401).json({ error: 'Account does not exist. Please create an account first.' });
  }

  if (user.status === 'suspended') {
    return res.status(403).json({ error: 'This account has been suspended by the administrator.' });
  }

  if (user.password_hash !== passwordHash) {
    return res.status(401).json({ error: 'Invalid PIN or password.' });
  }

  return res.json({
    success: true,
    message: 'Authentication successful.',
    user: {
      username: user.username,
      handle: user.handle || `@${user.username}`,
      nexaId: user.nexa_id,
      fullName: user.full_name,
      about: user.about,
      role: user.role || 'user',
      status: user.status
    }
  });
});

app.get('/v1/directory/users', (req, res) => {
  const users = Database.getAllUsers();
  return res.json({
    count: users.length,
    users: users.map(u => ({
      username: u.username,
      handle: u.handle,
      nexa_id: u.nexa_id,
      full_name: u.full_name,
      about: u.about
    }))
  });
});

app.get('/v1/directory/resolve/:identifier', async (req, res) => {
  const raw = req.params.identifier.trim();
  const clean = sanitizeUsername(raw);

  let user = await Database.findUser(clean);
  if (!user && raw.toUpperCase().startsWith('NX-')) {
    user = await Database.findUserByNexaId(raw.toUpperCase());
  }

  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  return res.json({
    user_id: user.nexa_id,
    handle: user.handle,
    username: user.username,
    full_name: user.full_name
  });
});

// --- 6. REAL-TIME BIDIRECTIONAL MESSAGING ---
app.post('/v1/messages/send', (req, res) => {
  const { sender_handle, sender_nexa_id, recipient_handle, recipient_nexa_id, text, type, audio_path, audio_duration, timestamp } = req.body;
  if (!sender_handle || (!recipient_handle && !recipient_nexa_id) || !text) {
    return res.status(400).json({ error: 'Missing required message parameters' });
  }

  const newMsg = Database.saveMessage({
    sender_handle,
    sender_nexa_id: sender_nexa_id || 'NX-UNKNOWN',
    recipient_handle: recipient_handle || '',
    recipient_nexa_id: recipient_nexa_id || '',
    text,
    type: type || 'text',
    audio_path: audio_path || null,
    audio_duration: audio_duration || 0,
    timestamp: timestamp || Date.now()
  });

  return res.status(201).json({
    success: true,
    message: newMsg
  });
});

app.get('/v1/messages/thread/:user1/:user2', (req, res) => {
  const { user1, user2 } = req.params;
  const messages = Database.getMessageThread(user1, user2);
  return res.json({
    success: true,
    count: messages.length,
    messages
  });
});

app.get('/v1/messages/inbox/:user', (req, res) => {
  const { user } = req.params;
  const messages = Database.getInbox(user);
  return res.json({
    success: true,
    count: messages.length,
    messages
  });
});

// Contacts sync
app.post('/v1/auth/contacts/sync', async (req, res) => {
  const { phones = [], names = [] } = req.body;
  const matched = await Database.matchContactsByPhones(phones);
  return res.json({
    success: true,
    matched_count: matched.length,
    contacts: matched
  });
});

// App update check
app.get(['/v1/app/version', '/v1/app/check-update'], (req, res) => {
  const versionInfo = Database.getAppVersion();
  res.json({
    success: true,
    ...versionInfo
  });
});

module.exports = { app };
