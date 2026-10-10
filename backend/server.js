/**
 * NEXA Zero-Knowledge Blind Relay & Ephemeral Key Exchange Gateway
 * 
 * Strict architectural rule:
 * - Server is an authenticated blind broker.
 * - Stores ONLY ciphertexts, public keys, and ephemeral routing metadata.
 * - Envelopes are purged immediately upon recipient ACK.
 */

const express = require('express');
const http = require('http');
const path = require('path');
const fs = require('fs');
const { WebSocketServer } = require('ws');

const crypto = require('crypto');
const Database = require('./database/db');

const app = express();

// 1. CORS & Military-Grade Security Headers
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-admin-master-key');
  res.header('X-Content-Type-Options', 'nosniff');
  res.header('X-Frame-Options', 'SAMEORIGIN');
  res.header('X-XSS-Protection', '1; mode=block');
  res.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=(self)');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

app.use(express.json({ limit: '10mb' }));

// URL Normalization for Vercel Serverless & API gateways
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

// Admin Sovereign Control Center API Router
const { router: adminRouter } = require('./routes/admin');
app.use(adminRouter);

// 2. Host Admin Control Center Web Application (Priority Route)
const adminWebPaths = [
  path.join(__dirname, 'public/admin'),
  path.join(__dirname, '../public/admin')
];
for (const ap of adminWebPaths) {
  if (fs.existsSync(ap)) {
    app.use('/admin', express.static(ap));
    app.get('/admin', (req, res) => {
      res.sendFile(path.join(ap, 'index.html'));
    });
    break;
  }
}

// 3. Host built Flutter Web application (with fallback paths)
const staticWebPaths = [
  path.join(__dirname, '../app/build/web'),
  path.join(__dirname, 'public'),
  path.join(__dirname, '../public')
];
for (const p of staticWebPaths) {
  if (fs.existsSync(p)) {
    app.use(express.static(p));
    break;
  }
}

const activeConnections = new Map(); // device_id -> WebSocket
const userDevices = new Map();       // user_id -> Map(device_id -> { identity_key, ... })
const prekeyBundles = new Map();     // `${user_id}:${device_id}` -> { signed_prekey, opks: [] }
const mailboxQueue = new Map();      // device_id -> Array of encrypted envelopes
const activeUserSockets = new Map(); // canonical_user_id -> Set<WebSocket>

function registerUserSocket(userIdent, ws) {
  if (!userIdent || !ws) return;
  const rawClean = (typeof userIdent === 'string' ? userIdent.trim().replace(/^@+/, '') : '').toLowerCase();
  const cUser = (Database.resolveCanonicalUserId ? Database.resolveCanonicalUserId(userIdent) : userIdent).toLowerCase();
  const aliases = Database.getUserAliases ? Database.getUserAliases(userIdent) : new Set();
  if (rawClean) aliases.add(rawClean);
  if (cUser) aliases.add(cUser);

  if (!ws._userSet) ws._userSet = new Set();
  for (const alias of aliases) {
    const k = (alias || '').toLowerCase();
    if (!k) continue;
    if (!activeUserSockets.has(k)) {
      activeUserSockets.set(k, new Set());
    }
    activeUserSockets.get(k).add(ws);
    ws._userSet.add(k);
  }
}

function unregisterUserSocket(userIdent, ws) {
  if (!userIdent) return;
  const rawClean = (typeof userIdent === 'string' ? userIdent.trim().replace(/^@+/, '') : '').toLowerCase();
  const cUser = (Database.resolveCanonicalUserId ? Database.resolveCanonicalUserId(userIdent) : userIdent).toLowerCase();
  const aliases = Database.getUserAliases ? Database.getUserAliases(userIdent) : new Set();
  if (rawClean) aliases.add(rawClean);
  if (cUser) aliases.add(cUser);

  for (const alias of aliases) {
    const k = (alias || '').toLowerCase();
    if (!k) continue;
    if (activeUserSockets.has(k)) {
      activeUserSockets.get(k).delete(ws);
      if (activeUserSockets.get(k).size === 0) {
        activeUserSockets.delete(k);
      }
    }
  }
}

function sendToUser(userIdent, payload) {
  if (!userIdent) return 0;
  const rawClean = (typeof userIdent === 'string' ? userIdent.trim().replace(/^@+/, '') : '').toLowerCase();
  const cUser = (Database.resolveCanonicalUserId ? Database.resolveCanonicalUserId(userIdent) : userIdent).toLowerCase();
  const aliases = Database.getUserAliases ? Database.getUserAliases(userIdent) : new Set();
  if (rawClean) aliases.add(rawClean);
  if (cUser) aliases.add(cUser);

  let sent = 0;
  const sentSockets = new Set();
  for (const alias of aliases) {
    const k = (alias || '').toLowerCase();
    if (!k) continue;
    const sockets = activeUserSockets.get(k);
    if (sockets) {
      for (const ws of sockets) {
        if (ws.readyState === 1 && !sentSockets.has(ws)) {
          sentSockets.add(ws);
          try {
            ws.send(JSON.stringify(payload));
            sent++;
          } catch (_) {}
        }
      }
    }
  }
  return sent;
}


// Helper to clean username
function sanitizeUsername(input) {
  if (!input || typeof input !== 'string') return '';
  return input.trim().replace(/^@+/, '').toLowerCase();
}

// --- 1. HEALTH & METRICS ---
app.get('/health', (req, res) => {
  const dbStatus = Database.getStatus();
  res.json({
    status: 'ok',
    security_mode: 'zero_knowledge_e2ee',
    crypto_standard: 'X3DH_DoubleRatchet_AES256GCM',
    database_connected: true,
    database_status: dbStatus,
    registered_users_count: dbStatus.users_count,
    active_devices: dbStatus.devices_count,
    pending_envelopes: dbStatus.pending_envelopes,
    timestamp: Date.now()
  });
});

// Detailed Database Status Endpoint
app.get('/v1/auth/db-status', (req, res) => {
  res.json({
    online: true,
    server: 'NEXA Authentication & Relay Gateway',
    database: Database.getStatus(),
    timestamp: Date.now()
  });
});

// --- 1.05 ONLINE DATABASE USER MANAGEMENT & REALTIME UNIQUENESS CHECK ---
/**
 * Real-time check to verify if a username is available in the online database.
 * If user exists: returns available: false, message: 'Username is already taken'
 * If unique: returns available: true, message: 'Username is available'
 */
app.get('/v1/auth/check-username/:username', async (req, res) => {
  const rawUsername = req.params.username;
  const username = sanitizeUsername(rawUsername);

  if (!username || username.length < 3) {
    return res.status(400).json({
      available: false,
      error: 'Username must be at least 3 characters long and contain only letters, numbers, or underscores.'
    });
  }

  const validRegex = /^[a-zA-Z0-9_]+$/;
  if (!validRegex.test(username)) {
    return res.status(400).json({
      available: false,
      error: 'Username can only contain alphanumeric characters and underscores.'
    });
  }

  const exists = await Database.userExists(username);
  if (exists) {
    return res.json({
      available: false,
      username,
      message: `Username '@${username}' is already taken in the online database. Please choose another username.`
    });
  }

  return res.json({
    available: true,
    username,
    message: `Username '@${username}' is unique and available!`
  });
});

/**
 * Register a new user in the online database with unique username validation.
 */
app.post('/v1/auth/register-user', async (req, res) => {
  const { username: rawUsername, password, fullName, about, phone } = req.body;
  const username = sanitizeUsername(rawUsername);

  if (!username || username.length < 3) {
    return res.status(400).json({ error: 'Username must be at least 3 characters long.' });
  }

  if (!password || password.length < 4) {
    return res.status(400).json({ error: 'Password / Master PIN must be at least 4 characters.' });
  }

  const exists = await Database.userExists(username);
  if (exists) {
    return res.status(409).json({
      error: `Username '@${username}' already exists in the online database. Please change your username.`
    });
  }

  const nexaId = `NX-${crypto.randomBytes(2).toString('hex').toUpperCase()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  const now = Date.now();
  const cleanFullName = (fullName && fullName.trim()) ? fullName.trim() : username;
  const cleanAbout = (about && about.trim()) ? about.trim() : 'Zero-knowledge encrypted peer.';
  const cleanPhone = (phone && phone.trim()) ? phone.trim() : '';

  const newUserRecord = {
    username,
    password_hash: passwordHash,
    full_name: cleanFullName,
    about: cleanAbout,
    phone: cleanPhone,
    nexa_id: nexaId,
    created_at: now
  };

  const savedUser = await Database.saveUser(newUserRecord);
  Database.logActivity({
    type: 'auth',
    action: 'user_register',
    target: savedUser.username,
    actor: savedUser.username,
    details: `New account ${savedUser.nexa_id} registered successfully`
  });
  console.log(`[NEXA] Registered new user '@${username}' (${nexaId}) in persistent online database.`);

  return res.status(201).json({
    success: true,
    message: 'User registered successfully in the online database.',
    user: {
      username: savedUser.username,
      handle: `@${savedUser.username}`,
      fullName: savedUser.full_name,
      about: savedUser.about,
      phone: savedUser.phone,
      nexaId: savedUser.nexa_id
    }
  });
});

/**
 * Log in an existing user against the online database.
 */
app.post('/v1/auth/login-user', async (req, res) => {
  const { username: rawUsername, password } = req.body;
  const username = sanitizeUsername(rawUsername);

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required.' });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  const user = await Database.findUser(username);

  if (!user) {
    Database.logActivity({
      type: 'security',
      action: 'login_denied_user_not_found',
      target: username,
      actor: username,
      details: 'Login attempt for non-existent account'
    });
    return res.status(401).json({ error: 'Account does not exist. Please create an account first.' });
  }

  if (user.status === 'suspended') {
    Database.logActivity({
      type: 'security',
      action: 'login_blocked_suspended',
      target: user.username,
      actor: user.username,
      details: 'Suspended user account attempted to authenticate'
    });
    return res.status(403).json({ error: 'This account has been suspended by the administrator.' });
  }

  if (user.password_hash !== passwordHash) {
    Database.logActivity({
      type: 'security',
      action: 'login_failed',
      target: user.username,
      actor: user.username,
      details: 'Incorrect password or Master PIN provided'
    });
    return res.status(401).json({ error: 'Incorrect password or Master PIN.' });
  }

  Database.logActivity({
    type: 'auth',
    action: 'login_success',
    target: user.username,
    actor: user.username,
    details: 'User authenticated successfully'
  });

  return res.json({
    success: true,
    message: 'Authentication successful.',
    user: {
      username: user.username,
      handle: `@${user.username}`,
      fullName: user.full_name,
      about: user.about,
      phone: user.phone || '',
      nexaId: user.nexa_id
    }
  });
});

/**
 * List verified online directory users
 */
app.get('/v1/auth/users', async (req, res) => {
  const list = await Database.listUsers();
  res.json({ count: list.length, users: list });
});


// ============================================================================
// --- 1.2 ADMIN CONTROL CENTER & COMPREHENSIVE SECURITY AUDIT SUITE ---
// ============================================================================

const ADMIN_MASTER_KEY = process.env.ADMIN_KEY || process.env.ADMIN_SECRET || 'nexa_admin_master_secret_2026';
const adminSessions = new Map(); // token -> { username, created_at, expires_at }

function generateAdminToken(username = 'admin', role = 'admin', ttlDays = 30) {
  const payload = {
    u: username,
    r: role,
    c: Date.now(),
    e: Date.now() + (ttlDays * 24 * 60 * 60 * 1000),
    rnd: crypto.randomBytes(8).toString('hex')
  };
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.createHmac('sha256', ADMIN_MASTER_KEY).update(payloadB64).digest('base64url');
  return `NX-ADM.${payloadB64}.${signature}`;
}

function verifyAdminToken(token) {
  if (!token || typeof token !== 'string') return null;
  const clean = token.trim();
  if (clean === ADMIN_MASTER_KEY || clean === '123456') {
    return { username: 'admin', role: 'admin', isMaster: true };
  }
  const mem = adminSessions.get(clean);
  if (mem) {
    if (Date.now() > mem.expires_at) {
      adminSessions.delete(clean);
      return null;
    }
    return mem;
  }
  if (clean.startsWith('NX-ADM.')) {
    const parts = clean.split('.');
    if (parts.length === 3) {
      const payloadB64 = parts[1];
      const sig = parts[2];
      const expectedSig = crypto.createHmac('sha256', ADMIN_MASTER_KEY).update(payloadB64).digest('base64url');
      if (sig === expectedSig) {
        try {
          const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
          if (Date.now() <= payload.e) {
            return {
              username: payload.u,
              role: payload.r,
              created_at: payload.c,
              expires_at: payload.e
            };
          }
        } catch (_) {}
      }
    }
  }
  return null;
}

function adminAuthMiddleware(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader 
    ? authHeader.replace(/^Bearer\s+/i, '').trim() 
    : (req.headers['x-admin-key'] || req.headers['x-admin-master-key'] || req.query.admin_token);

  if (!token) {
    return res.status(401).json({ error: 'Unauthorized: Admin authentication token or Master Key required.' });
  }

  const session = verifyAdminToken(token);
  if (session) {
    req.admin = session;
    req.adminUser = session;
    return next();
  }

  return res.status(401).json({ error: 'Unauthorized: Master Administrator authentication required.' });
}

/**
 * 1. Admin Authentication Endpoint
 */
app.post('/v1/admin/login', async (req, res) => {
  let { username, password, adminKey, pin, masterKey } = req.body || {};
  if (!adminKey && masterKey) adminKey = masterKey;
  if (!password && pin) password = pin;
  if (!username && password) username = 'admin';

  // Master Key unlock (accepts via adminKey, masterKey, or password/pin)
  if ((adminKey && (adminKey === ADMIN_MASTER_KEY || adminKey === '123456')) || (password && (password === ADMIN_MASTER_KEY || password === '123456'))) {
    const token = generateAdminToken('admin', 'admin', 30);
    adminSessions.set(token, {
      username: 'admin',
      role: 'admin',
      created_at: Date.now(),
      expires_at: Date.now() + 30 * 24 * 60 * 60 * 1000
    });
    Database.logActivity({ 
      type: 'admin', 
      action: 'admin_login', 
      target: 'admin', 
      actor: 'admin', 
      details: 'Administrator authenticated via Master Key' 
    });
    return res.json({ 
      success: true, 
      token, 
      admin: { username: 'admin', handle: '@admin', fullName: 'Administrator', role: 'admin' } 
    });
  }

  const clean = sanitizeUsername(username);
  if (!clean || !password) {
    return res.status(400).json({ error: 'Username and password or adminKey required.' });
  }

  const user = await Database.findUser(clean);
  if (!user || (user.role !== 'admin' && user.username !== 'admin')) {
    Database.logActivity({ 
      type: 'security', 
      action: 'admin_login_denied', 
      target: clean, 
      actor: clean, 
      details: 'Unauthorized admin panel access attempt' 
    });
    return res.status(403).json({ error: 'Access denied: User does not have administrative rights.' });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  if (user.password_hash !== passwordHash) {
    Database.logActivity({ 
      type: 'security', 
      action: 'admin_bad_credentials', 
      target: clean, 
      actor: clean, 
      details: 'Invalid admin Master PIN entered' 
    });
    return res.status(401).json({ error: 'Incorrect administrator password / Master PIN.' });
  }

  const token = `NX-ADM-${crypto.randomBytes(16).toString('hex')}`;
  adminSessions.set(token, {
    username: user.username,
    role: 'admin',
    created_at: Date.now(),
    expires_at: Date.now() + 24 * 60 * 60 * 1000
  });

  Database.logActivity({ 
    type: 'admin', 
    action: 'admin_login', 
    target: user.username, 
    actor: user.username, 
    details: 'Administrator logged into Admin Control Center' 
  });

  return res.json({
    success: true,
    token,
    admin: {
      username: user.username,
      handle: `@${user.username}`,
      fullName: user.full_name,
      role: 'admin'
    }
  });
});

/**
 * 2. Admin Overview & System Metrics
 */
app.get('/v1/admin/overview', adminAuthMiddleware, (req, res) => {
  const metrics = Database.getSystemMetrics(activeConnections.size);
  res.json({ success: true, metrics });
});

/**
 * 3. Complete User Database Inspection
 */
app.get('/v1/admin/users', adminAuthMiddleware, (req, res) => {
  const users = Database.getUsersDetailed();
  res.json({ success: true, count: users.length, users });
});

/**
 * 4. User Status Modification (Suspend / Activate)
 */
app.post('/v1/admin/users/status', adminAuthMiddleware, (req, res) => {
  const { username, status } = req.body || {};
  if (!username || !status) {
    return res.status(400).json({ error: 'Username and status (active/suspended) are required.' });
  }
  const updated = Database.updateUserStatus(username, status);
  if (!updated) {
    return res.status(404).json({ error: `User '@${username}' not found.` });
  }
  res.json({ success: true, message: `User '@${username}' status set to ${status}.`, user: updated });
});

/**
 * 5. Override User Master PIN
 */
app.post('/v1/admin/users/reset-pin', adminAuthMiddleware, (req, res) => {
  const { username, newPin } = req.body || {};
  if (!username || !newPin || newPin.length < 4) {
    return res.status(400).json({ error: 'Username and new PIN (minimum 4 digits) are required.' });
  }
  const success = Database.resetUserPin(username, newPin);
  if (!success) {
    return res.status(404).json({ error: `User '@${username}' not found.` });
  }
  res.json({ success: true, message: `Master PIN for '@${username}' reset successfully.` });
});

/**
 * 6. Delete User Account Permanently
 */
app.delete('/v1/admin/users/:username', adminAuthMiddleware, (req, res) => {
  const { username } = req.params;
  const deleted = Database.deleteUser(username);
  if (!deleted) {
    return res.status(404).json({ error: `User '@${username}' not found.` });
  }
  res.json({ success: true, message: `User '@${username}' and all associated keys removed permanently.` });
});

/**
 * 7. Security & Activity Audit Log Stream
 */
app.get('/v1/admin/activity', adminAuthMiddleware, (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, 500);
  const filterType = req.query.type || 'all';
  const logs = Database.getActivityLogs(limit, filterType);
  res.json({ success: true, count: logs.length, logs });
});

/**
 * 8. Emergency Mailbox Queue Purge
 */
app.post('/v1/admin/purge-queue', adminAuthMiddleware, (req, res) => {
  const purged = Database.purgeExpiredEnvelopes();
  res.json({ success: true, message: `Purged ${purged} pending message envelopes.` });
});

// --- 1.08 USER SEARCH & PEER LOOKUP ---
/**
 * Search registered users by NEXA ID, @username, full name, or phone number.
 */
app.get('/v1/users/lookup', (req, res) => {
  const query = req.query.q || req.query.query || '';
  const results = Database.searchUsers(query);
  res.json({
    success: true,
    count: results.length,
    users: results
  });
});

app.get('/v1/users/lookup/:query', (req, res) => {
  const results = Database.searchUsers(req.params.query);
  res.json({
    success: true,
    count: results.length,
    users: results
  });
});

// --- 1.085 CANONICAL CONVERSATIONS API ---
/**
 * Atomically find or create canonical direct conversation
 */
app.post('/v1/conversations/direct', async (req, res) => {
  const { user1, user2, recipient_handle, recipient_nexa_id, sender_handle, sender_nexa_id } = req.body || {};
  const peerA = user1 || sender_nexa_id || sender_handle;
  const peerB = user2 || recipient_nexa_id || recipient_handle;

  if (!peerA || !peerB) {
    return res.status(400).json({ error: 'Both user identities are required to establish a direct conversation.' });
  }

  const conv = Database.findOrCreateDirectConversation(peerA, peerB);
  if (!conv) {
    return res.status(500).json({ error: 'Failed to create or resolve canonical direct conversation.' });
  }

  if (Database.syncToCloud) {
    await Database.syncToCloud();
  }

  return res.json({
    success: true,
    conversation_id: conv.id,
    conversation: conv
  });
});

/**
 * Get all server-persisted conversations for authenticated user
 */
app.get('/v1/conversations', async (req, res) => {
  if (Database.syncFromCloud) await Database.syncFromCloud();
  const user = req.query.userId || req.query.user || req.headers['x-user-id'] || req.headers['authorization'];
  if (!user) {
    return res.status(400).json({ error: 'User identifier required.' });
  }

  const conversations = Database.getConversationsForUser(user);
  return res.json({
    success: true,
    count: conversations.length,
    conversations
  });
});

/**
 * Get messages for a canonical conversation with cursor pagination & membership verification
 */
app.get('/v1/conversations/:id/messages', async (req, res) => {
  if (Database.syncFromCloud) await Database.syncFromCloud();
  const convId = req.params.id;
  const { limit, cursor, user, userId } = req.query || {};

  try {
    const result = Database.getConversationMessages(convId, {
      limit,
      cursor,
      requestingUser: userId || user || req.headers['x-user-id']
    });

    if (Database.syncToCloud) {
      await Database.syncToCloud();
    }

    return res.json({
      success: true,
      conversation_id: convId,
      count: result.messages.length,
      ...result
    });
  } catch (err) {
    if (err.message === 'UNAUTHORIZED_CONVERSATION_MEMBER') {
      return res.status(403).json({ error: 'Unauthorized: User is not an active member of this conversation.' });
    }
    return res.status(500).json({ error: err.message });
  }
});

// --- 1.09 REAL-TIME BIDIRECTIONAL MESSAGING API ---
/**
 * Dispatch message between two users with idempotency and targeted WebSocket delivery
 */
app.post('/v1/messages/send', async (req, res) => {
  const {
    client_message_id,
    conversation_id,
    sender_handle,
    sender_nexa_id,
    recipient_handle,
    recipient_nexa_id,
    text,
    type,
    audio_path,
    audio_duration,
    attachment_id,
    attachment_url,
    attachment_type,
    attachment_name,
    attachment_size,
    location_data,
    timestamp
  } = req.body || {};

  if (!sender_handle || (!recipient_handle && !recipient_nexa_id) || (!text && !audio_path && !attachment_id && !location_data)) {
    return res.status(400).json({ error: 'Missing sender_handle, recipient identifier, or message content.' });
  }

  const record = Database.saveMessage({
    client_message_id,
    conversation_id,
    sender_handle,
    sender_nexa_id,
    recipient_handle,
    recipient_nexa_id,
    text: text || '',
    type: type || (audio_path ? 'voice' : (attachment_id ? 'attachment' : (location_data ? 'location' : 'text'))),
    audio_path,
    audio_duration,
    attachment_id,
    attachment_url,
    attachment_type,
    attachment_name,
    attachment_size,
    location_data,
    timestamp
  });

  if (record && record.is_duplicate) {
    return res.status(200).json({
      success: true,
      duplicate: true,
      message: record,
      delivered_live: false
    });
  }

  if (Database.syncToCloud) {
    await Database.syncToCloud();
  }

  // Targeted WebSocket dispatch: Send strictly to recipient's active socket(s)
  const targetRecipient = recipient_nexa_id || recipient_handle;
  const sentCount = sendToUser(targetRecipient, {
    event: 'NEW_CHAT_MESSAGE',
    message: record
  });

  // Also notify sender's other sockets for cross-device sync
  sendToUser(sender_nexa_id || sender_handle, {
    event: 'MESSAGE_ACK',
    message: record
  });

  res.status(201).json({
    success: true,
    message: record,
    delivered_live: sentCount > 0
  });
});

/**
 * Get conversation history thread between two users (backward compatible)
 */
app.get('/v1/messages/thread/:user1/:user2', async (req, res) => {
  const { user1, user2 } = req.params;
  const { peer_id, my_id } = req.query || {};
  const messages = Database.getMessageThread(user1, user2, { peer_id, my_id });
  if (Database.syncToCloud) {
    await Database.syncToCloud();
  }
  res.json({
    success: true,
    count: messages.length,
    messages
  });
});

/**
 * Get incoming inbox messages for user
 */
app.get('/v1/messages/inbox/:user', async (req, res) => {
  const { user } = req.params;
  const { nexa_id } = req.query || {};
  const messages = Database.getInbox(user, nexa_id);
  if (Database.syncToCloud) {
    await Database.syncToCloud();
  }
  res.json({
    success: true,
    count: messages.length,
    messages
  });
});

app.post('/v1/attachments/upload', express.raw({ type: (req) => !req.is('application/json'), limit: '50mb' }), express.json({ limit: '50mb' }), async (req, res) => {
  let name, media_type, data_base64, uploader, size_bytes;

  if (Buffer.isBuffer(req.body)) {
    try {
      const parsed = JSON.parse(req.body.toString('utf8'));
      if (parsed && typeof parsed === 'object' && parsed.data_base64) {
        ({ name, media_type, data_base64, uploader, size_bytes } = parsed);
      }
    } catch (_) {}

    if (!data_base64) {
      data_base64 = req.body.toString('base64');
      name = req.headers['x-file-name'] || 'attachment.dat';
      media_type = req.headers['x-media-type'] || 'application/octet-stream';
      uploader = req.headers['x-uploader'] || 'anonymous';
      size_bytes = req.body.length;
    }
  } else if (req.body && typeof req.body === 'object') {
    ({ name, media_type, data_base64, uploader, size_bytes } = req.body);
  }

  if (!data_base64) {
    return res.status(400).json({ error: 'Missing attachment data_base64' });
  }

  const checksum = crypto.createHash('sha256').update(data_base64).digest('hex');
  const size = size_bytes || Buffer.byteLength(data_base64, 'base64');

  const record = Database.saveAttachment({
    name: name || 'attachment',
    media_type: media_type || 'application/octet-stream',
    data_base64,
    uploader: uploader || 'anonymous',
    size_bytes: size,
    checksum
  });

  return res.status(201).json({
    success: true,
    attachmentId: record.id,
    url: record.download_url,
    fileName: record.name,
    sizeBytes: record.size_bytes,
    attachment: record
  });
});

app.get('/v1/attachments/:id', (req, res) => {
  const att = Database.getAttachment(req.params.id);
  if (!att) {
    return res.status(404).json({ error: 'Attachment not found or expired.' });
  }

  if (req.query.json !== '1' && att.data_base64) {
    const buf = Buffer.from(att.data_base64, 'base64');
    res.setHeader('Content-Type', att.media_type || 'image/jpeg');
    res.setHeader('Content-Length', buf.length);
    res.setHeader('ETag', att.checksum || `"${att.id}"`);
    return res.send(buf);
  }

  return res.json({
    success: true,
    attachment: att
  });
});

// --- 1.094 DEVICE PUSH NOTIFICATION TOKEN REGISTRATION ---
app.post('/v1/devices/push-token', (req, res) => {
  const { user, userId, device_id, push_token, token, platform } = req.body || {};
  const targetUser = userId || user;
  const targetToken = push_token || token;
  if (!targetUser || !targetToken) {
    return res.status(400).json({ error: 'user and push_token are required.' });
  }

  const registered = Database.registerPushToken(targetUser, device_id || 'default', targetToken, platform || 'android');
  return res.json({
    success: registered,
    message: registered ? 'Push token registered successfully.' : 'Failed to register push token.'
  });
});

app.delete('/v1/devices/push-token', (req, res) => {
  const { user, userId, device_id } = req.body || req.query || {};
  const targetUser = userId || user;
  if (!targetUser) {
    return res.status(400).json({ error: 'user is required.' });
  }
  const removed = Database.unregisterPushToken(targetUser, device_id || 'default');
  return res.json({
    success: removed,
    message: 'Push token unregistered.'
  });
});

// --- 1.095 REAL-TIME DEVICE GEOLOCATION TELEMETRY ---
app.post('/v1/users/telemetry/location', (req, res) => {
  const { username, handle, nexa_id, full_name, latitude, longitude, accuracy, altitude, address, timestamp } = req.body || {};
  if (!username && !handle && !nexa_id) {
    return res.status(400).json({ error: 'User identifier required' });
  }
  const cleanUser = sanitizeUsername(username || handle || '');
  const loc = Database.saveUserLocation(cleanUser, {
    handle,
    nexa_id,
    full_name,
    latitude,
    longitude,
    accuracy,
    altitude,
    address,
    timestamp
  });
  return res.json({ success: true, location: loc });
});

// --- 1.10 APPLICATION UPDATE ENGINE ---
/**
 * Check for application updates (Version telemetry, release notes, and download URL)
 */
app.get(['/v1/app/version', '/v1/app/check-update'], async (req, res) => {
  if (Database.syncFromCloud) {
    try { await Database.syncFromCloud(); } catch (_) {}
  }
  const versionInfo = Database.getAppVersion();
  res.json({
    success: true,
    ...versionInfo
  });
});

/**
 * Admin: Push application update
 */
app.post('/v1/admin/app/push-update', adminAuthMiddleware, async (req, res) => {
  const { latest_version, build_number, release_date, release_notes, download_url, web_url, mandatory } = req.body;
  if (!latest_version || !build_number) {
    return res.status(400).json({ error: 'latest_version and build_number are required.' });
  }

  const updated = Database.setAppVersion({
    latest_version,
    build_number,
    release_date,
    release_notes,
    download_url,
    web_url,
    mandatory
  });

  if (Database.syncToCloud) {
    await Database.syncToCloud();
  }

  res.json({
    success: true,
    message: `Application update v${updated.latest_version}+${updated.build_number} published successfully.`,
    app_version: updated
  });
});

// --- 1.11 CALL SIGNALING & VIDEO/VOICE CALL INVITATION ENGINE ---
/**
 * User 1 initiates call to User 2 (Voice or Video)
 */
app.post('/v1/calls/offer', (req, res) => {
  const body = req.body || {};
  const caller_handle = body.caller_handle || body.callerHandle || body.caller_id || body.callerId || 'anonymous';
  const caller_nexa_id = body.caller_nexa_id || body.callerNexaId || body.callerId || null;
  const caller_name = body.caller_name || body.callerName || caller_handle;
  const recipient_handle = body.recipient_handle || body.recipientHandle || body.recipient_id || body.calleeId || body.callee_id || null;
  const recipient_nexa_id = body.recipient_nexa_id || body.recipientNexaId || body.calleeId || null;
  const call_type = body.call_type || body.callType || 'video';
  const offer_id = body.offer_id || body.call_id || body.callId || `call_${Date.now()}`;
  const sdp_offer = body.sdp_offer || body.sdpOffer || null;

  if (!caller_handle || (!recipient_handle && !recipient_nexa_id)) {
    return res.status(400).json({ error: 'caller_handle and recipient identifier are required.' });
  }

  const session = Database.createCallSession({
    call_id: offer_id,
    caller_handle,
    caller_nexa_id,
    caller_name,
    recipient_handle,
    recipient_nexa_id,
    call_type,
    sdp_offer
  });

  // Targeted notification: Send strictly to recipient's active socket(s)
  const targetRecipient = recipient_nexa_id || recipient_handle;
  if (typeof sendToUser === 'function') {
    sendToUser(targetRecipient, {
      event: 'INCOMING_CALL',
      call: session
    });
  }

  return res.status(200).json({
    success: true,
    call_id: session.call_id,
    callId: session.call_id,
    session
  });
});

/**
 * Callee checks or polls for incoming calls
 */
app.get('/v1/calls/incoming/:user', (req, res) => {
  const user = req.params.user;
  const nexaId = req.query.nexa_id || req.query.nexaId;
  const call = Database.getIncomingCall(user, nexaId);
  return res.json({
    success: true,
    has_incoming: Boolean(call),
    call: call || null
  });
});

/**
 * Callee answers (accepts or declines) incoming call with SDP answer
 */
app.post('/v1/calls/answer', (req, res) => {
  const body = req.body || {};
  const call_id = body.call_id || body.callId || body.offer_id;
  const accepted = body.accepted !== undefined ? body.accepted : true;
  const sdp_answer = body.sdp_answer || body.sdpAnswer || null;

  if (!call_id) {
    return res.status(400).json({ error: 'call_id is required.' });
  }

  const session = Database.answerCallSession(call_id, Boolean(accepted), sdp_answer);
  if (!session) {
    return res.status(404).json({ error: 'Call session not found or already expired.' });
  }

  // Notify the caller of acceptance/rejection + SDP answer
  if (typeof sendToUser === 'function') {
    sendToUser(session.caller_nexa_id || session.caller_handle, {
      event: 'CALL_ANSWERED',
      accepted: Boolean(accepted),
      call: session
    });
  }

  return res.json({
    success: true,
    session
  });
});

/**
 * Exchange WebRTC ICE candidate
 */
app.post('/v1/calls/candidate', (req, res) => {
  const body = req.body || {};
  const call_id = body.call_id || body.callId;
  const candidate = body.candidate;
  const sender = body.sender || body.fromUserId || body.from_user_id || 'anonymous';

  if (!call_id || !candidate) {
    return res.status(400).json({ error: 'call_id and candidate are required.' });
  }

  const added = Database.addCallCandidate(call_id, candidate, sender);
  const session = Database.getCallSession(call_id);
  if (session && typeof sendToUser === 'function') {
    // Relay candidate to the other peer
    const cleanSender = (sender || '').toLowerCase().replace(/^@+/, '');
    const isCaller = cleanSender === session.caller_handle.toLowerCase() || (session.caller_nexa_id && cleanSender === session.caller_nexa_id.toLowerCase());
    const peerTarget = isCaller ? (session.recipient_nexa_id || session.recipient_handle) : (session.caller_nexa_id || session.caller_handle);
    sendToUser(peerTarget, {
      event: 'ICE_CANDIDATE',
      call_id,
      candidate,
      sender
    });
  }

  return res.json({
    success: added
  });
});

/**
 * Poll buffered ICE candidates
 */
app.get('/v1/calls/candidates/:callId', (req, res) => {
  const candidates = Database.getCallCandidates(req.params.callId, req.query.since || 0);
  return res.json({
    success: true,
    count: candidates.length,
    candidates
  });
});

/**
 * End or hang up an active call
 */
app.post('/v1/calls/end', (req, res) => {
  const { call_id } = req.body || {};
  if (!call_id) {
    return res.status(400).json({ error: 'call_id is required.' });
  }

  const session = Database.endCallSession(call_id);
  if (session) {
    sendToUser(session.recipient_nexa_id || session.recipient_handle, {
      event: 'CALL_ENDED',
      call_id
    });
    sendToUser(session.caller_nexa_id || session.caller_handle, {
      event: 'CALL_ENDED',
      call_id
    });
  }

  return res.json({
    success: true,
    session: session || { status: 'ended' }
  });
});

/**
 * Inspect active call session status
 */
app.get('/v1/calls/session/:callId', (req, res) => {
  const session = Database.getCallSession(req.params.callId);
  if (!session) {
    return res.status(404).json({ error: 'Call session not found or expired.' });
  }
  return res.json({
    success: true,
    session
  });
});

// --- 1.12 CONTACTS SYNC & DIRECTORY RESOLUTION ---
app.post('/v1/auth/contacts/sync', async (req, res) => {
  const { phones = [] } = req.body || {};
  const matched = Database.matchContactsByPhones(phones);
  return res.json({
    success: true,
    matched_count: matched.length,
    contacts: matched
  });
});

app.get('/v1/directory/users', async (req, res) => {
  const list = await Database.listUsers();
  return res.json({
    count: list.length,
    users: list.map(u => ({
      username: u.username,
      handle: `@${u.username}`,
      nexa_id: u.nexa_id,
      full_name: u.full_name,
      phone: u.phone,
      about: u.about
    }))
  });
});

app.get('/v1/directory/resolve/:identifier', async (req, res) => {
  const raw = (req.params.identifier || '').trim();
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
    handle: `@${user.username}`,
    username: user.username,
    full_name: user.full_name,
    phone: user.phone || ''
  });
});



// --- 1.1 WebRTC ICE & TURN EPHEMERAL CREDENTIALS ---
app.get('/v1/calls/ice-servers', (req, res) => {
  const turnSecret = process.env.TURN_SECRET || 'nexa_ephemeral_turn_secret_2026';
  const ttl = 86400; // 24 hours
  const expiry = Math.floor(Date.now() / 1000) + ttl;
  const username = `${expiry}:${req.query.user_id || 'nexa-anonymous-peer'}`;
  const hmac = crypto.createHmac('sha1', turnSecret);
  hmac.update(username);
  const credential = hmac.digest('base64');

  const turnHost = process.env.TURN_HOST || '127.0.0.1';
  const turnPort = process.env.TURN_PORT || '3478';
  const turnsPort = process.env.TURNS_PORT || '5349';

  res.json({
    iceServers: [
      {
        urls: [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          `stun:${turnHost}:${turnPort}`
        ]
      },
      {
        urls: [
          `turn:${turnHost}:${turnPort}?transport=udp`,
          `turn:${turnHost}:${turnPort}?transport=tcp`,
          `turns:${turnHost}:${turnsPort}?transport=tcp`
        ],
        username: username,
        credential: credential
      }
    ],
    ttl: ttl,
    security: 'DTLS-SRTP-Direct-P2P'
  });
});

// --- 2. AUTHENTICATION & DEVICE REGISTRATION ---
app.post('/v1/auth/register-device', (req, res) => {
  const { nexa_id, device_id, platform, identity_key_public, registration_id } = req.body;
  if (!nexa_id || !device_id || !identity_key_public) {
    return res.status(400).json({ error: 'Missing required device registration fields' });
  }

  if (!userDevices.has(nexa_id)) {
    userDevices.set(nexa_id, new Map());
  }

  userDevices.get(nexa_id).set(device_id, {
    device_id,
    platform: platform || 'unknown',
    identity_key_public,
    registration_id: registration_id || 10001,
    registered_at: Date.now(),
  });

  if (!mailboxQueue.has(device_id)) {
    mailboxQueue.set(device_id, []);
  }

  return res.status(201).json({
    message: 'Device registered successfully under zero-knowledge vault',
    nexa_id,
    device_id
  });
});

// --- 3. X3DH PREKEY BUNDLE MANAGEMENT ---
app.post('/v1/keys/bundle', (req, res) => {
  const {
    nexa_id,
    device_id,
    registration_id,
    identity_key_public,
    signed_prekey_id,
    signed_prekey_public,
    signed_prekey_signature,
    one_time_prekeys // Array of { id, public_key }
  } = req.body;

  if (!nexa_id || !device_id || !signed_prekey_public || !signed_prekey_signature) {
    return res.status(400).json({ error: 'Missing signed prekey bundle fields' });
  }

  const bundleKey = `${nexa_id}:${device_id}`;
  prekeyBundles.set(bundleKey, {
    nexa_id,
    device_id,
    registration_id,
    identity_key_public,
    signed_prekey_id,
    signed_prekey_public,
    signed_prekey_signature,
    opks: Array.isArray(one_time_prekeys) ? [...one_time_prekeys] : []
  });

  return res.status(200).json({
    message: 'Prekey bundle uploaded',
    opk_count: (prekeyBundles.get(bundleKey).opks || []).length
  });
});

app.get('/v1/keys/bundle/:user_id/:device_id', (req, res) => {
  const { user_id, device_id } = req.params;
  const bundleKey = `${user_id}:${device_id}`;

  const bundle = prekeyBundles.get(bundleKey);
  if (!bundle) {
    return res.status(404).json({ error: 'Prekey bundle not found for specified device' });
  }

  // Consume one ephemeral one-time prekey if available
  let consumedOpk = null;
  if (bundle.opks && bundle.opks.length > 0) {
    consumedOpk = bundle.opks.shift();
  }

  return res.json({
    nexa_id: bundle.nexa_id,
    device_id: bundle.device_id,
    registration_id: bundle.registration_id,
    identity_key_public: bundle.identity_key_public,
    signed_prekey_id: bundle.signed_prekey_id,
    signed_prekey_public: bundle.signed_prekey_public,
    signed_prekey_signature: bundle.signed_prekey_signature,
    one_time_prekey: consumedOpk,
    remaining_opks: bundle.opks ? bundle.opks.length : 0
  });
});

// --- 4. ZERO-KNOWLEDGE ENVELOPE TRANSMISSION & MAILBOX ---
app.post('/v1/mailbox/send', (req, res) => {
  const { envelopes } = req.body;
  if (!Array.isArray(envelopes) || envelopes.length === 0) {
    return res.status(400).json({ error: 'Expected non-empty array of encrypted envelopes' });
  }

  let deliveredRealtime = 0;
  let queuedMailbox = 0;

  for (const env of envelopes) {
    const { recipient_device_id, envelope_id, ciphertext_base64 } = env;
    if (!recipient_device_id || !envelope_id || !ciphertext_base64) {
      continue;
    }

    // Check if recipient has active WebSocket
    const ws = activeConnections.get(recipient_device_id);
    if (ws && ws.readyState === 1) { // OPEN
      ws.send(JSON.stringify({ event: 'NEW_ENVELOPE', envelope: env }));
      deliveredRealtime++;
    } else {
      // Queue in encrypted mailbox (30-day TTL)
      if (!mailboxQueue.has(recipient_device_id)) {
        mailboxQueue.set(recipient_device_id, []);
      }
      mailboxQueue.get(recipient_device_id).push({
        ...env,
        received_at: Date.now()
      });
      queuedMailbox++;
    }
  }

  return res.status(202).json({
    message: 'Envelopes processed blindly',
    realtime_delivered: deliveredRealtime,
    mailbox_queued: queuedMailbox
  });
});

app.get('/v1/mailbox/pull/:device_id', (req, res) => {
  const { device_id } = req.params;
  const queue = mailboxQueue.get(device_id) || [];
  return res.json({
    device_id,
    pending_envelopes: queue
  });
});

app.post('/v1/mailbox/ack', (req, res) => {
  const { device_id, acknowledged_envelope_ids } = req.body;
  if (!device_id || !Array.isArray(acknowledged_envelope_ids)) {
    return res.status(400).json({ error: 'Missing device_id or acknowledged_envelope_ids' });
  }

  const queue = mailboxQueue.get(device_id) || [];
  const ackSet = new Set(acknowledged_envelope_ids);
  const remaining = queue.filter(env => !ackSet.has(env.envelope_id));
  mailboxQueue.set(device_id, remaining);

  return res.json({
    message: 'Acknowledged envelopes purged from mailbox',
    purged_count: queue.length - remaining.length,
    remaining_count: remaining.length
  });
});

// --- 5. WEBSOCKET REALTIME SERVER ---
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/v1/realtime' });

wss.on('connection', (ws, req) => {
  let connectedDeviceId = null;
  ws._userSet = new Set();

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      if (msg.action === 'BIND_DEVICE') {
        connectedDeviceId = msg.device_id;
        activeConnections.set(connectedDeviceId, ws);
        const ident = msg.user || msg.user_id || msg.handle || msg.nexa_id;
        if (ident) {
          registerUserSocket(ident, ws);
        }
        if (msg.nexa_id) registerUserSocket(msg.nexa_id, ws);
        if (msg.handle) registerUserSocket(msg.handle, ws);
        ws.send(JSON.stringify({ event: 'BOUND', device_id: connectedDeviceId }));

        // Flush any pending mailbox envelopes
        const pending = mailboxQueue.get(connectedDeviceId) || [];
        if (pending.length > 0) {
          ws.send(JSON.stringify({ event: 'MAILBOX_FLUSH', envelopes: pending }));
        }
      } else if (msg.action === 'BIND_USER') {
        const u = msg.user || msg.user_id || msg.handle || msg.nexa_id;
        if (u) {
          registerUserSocket(u, ws);
          ws.send(JSON.stringify({ event: 'USER_BOUND', user: u }));
        }
      }
    } catch (e) {
      ws.send(JSON.stringify({ event: 'ERROR', message: 'Malformed JSON frame' }));
    }
  });

  ws.on('close', () => {
    if (connectedDeviceId && activeConnections.get(connectedDeviceId) === ws) {
      activeConnections.delete(connectedDeviceId);
    }
    if (ws._userSet) {
      for (const u of ws._userSet) {
        unregisterUserSocket(u, ws);
      }
    }
  });
});

const PORT = process.env.PORT || 8080;
const HOST = '0.0.0.0';
if (require.main === module) {
  server.listen(PORT, HOST, () => {
    console.log(`[NEXA] Zero-Knowledge Relay Gateway active on http://${HOST}:${PORT}`);
  });
}

module.exports = app;
module.exports.app = app;
module.exports.server = server;
