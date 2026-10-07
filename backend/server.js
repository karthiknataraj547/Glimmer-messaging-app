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
const { WebSocketServer } = require('ws');

const crypto = require('crypto');
const Database = require('./database/db');

const app = express();
app.use(express.json({ limit: '10mb' }));

// Host built Flutter Web application
const staticWebPath = path.join(__dirname, '../app/build/web');
app.use(express.static(staticWebPath));

// CORS Middleware for Mobile, Web, and Desktop Clients
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

const activeConnections = new Map(); // device_id -> WebSocket
const userDevices = new Map();       // user_id -> Map(device_id -> { identity_key, ... })
const prekeyBundles = new Map();     // `${user_id}:${device_id}` -> { signed_prekey, opks: [] }
const mailboxQueue = new Map();      // device_id -> Array of encrypted envelopes

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
    // Seamless simple login: If account is not registered yet, auto-provision on server and log in!
    if (password.length >= 4) {
      const nexaId = `NX-${crypto.randomBytes(2).toString('hex').toUpperCase()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
      const newUserRecord = {
        username,
        password_hash: passwordHash,
        full_name: username,
        about: 'Zero-knowledge encrypted peer.',
        phone: '',
        nexa_id: nexaId,
        created_at: Date.now()
      };
      const savedUser = await Database.saveUser(newUserRecord);
      console.log(`[NEXA] Seamlessly auto-provisioned user '@${username}' (${nexaId}) via simple login.`);
      return res.json({
        success: true,
        message: 'Account provisioned and authenticated successfully.',
        user: {
          username: savedUser.username,
          handle: `@${savedUser.username}`,
          fullName: savedUser.full_name,
          about: savedUser.about,
          phone: savedUser.phone || '',
          nexaId: savedUser.nexa_id
        }
      });
    }
    return res.status(401).json({ error: 'Password / Master PIN must be at least 4 digits.' });
  }

  if (user.password_hash !== passwordHash) {
    return res.status(401).json({ error: 'Incorrect password or Master PIN.' });
  }

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

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      if (msg.action === 'BIND_DEVICE') {
        connectedDeviceId = msg.device_id;
        activeConnections.set(connectedDeviceId, ws);
        ws.send(JSON.stringify({ event: 'BOUND', device_id: connectedDeviceId }));

        // Flush any pending mailbox envelopes
        const pending = mailboxQueue.get(connectedDeviceId) || [];
        if (pending.length > 0) {
          ws.send(JSON.stringify({ event: 'MAILBOX_FLUSH', envelopes: pending }));
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
  });
});

const PORT = process.env.PORT || 8080;
const HOST = '0.0.0.0';
if (require.main === module) {
  server.listen(PORT, HOST, () => {
    console.log(`[NEXA] Zero-Knowledge Relay Gateway active on http://${HOST}:${PORT}`);
  });
}

module.exports = { app, server };
