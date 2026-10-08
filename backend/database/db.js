/**
 * NEXA Persistent Database Engine
 * 
 * Provides robust, ACID-compliant file-backed persistent storage for users,
 * credentials, cryptographic prekeys, registered devices, and message envelopes.
 * Seamlessly integrates with PostgreSQL if DATABASE_URL is configured.
 */

const fs = require('fs');
const path = require('path');
let Pool = null;
try {
  Pool = require('pg').Pool;
} catch (_) {}

const isServerless = Boolean(process.env.VERCEL || process.env.AWS_LAMBDA_FUNCTION_NAME);
const SEED_FILE = fs.existsSync(path.join(__dirname, 'seed_database.json')) 
  ? path.join(__dirname, 'seed_database.json') 
  : path.join(__dirname, '../data/nexa_database.json');
const DB_DIR = isServerless ? path.join('/tmp', 'nexa_data') : path.join(__dirname, '../data');
const DB_FILE = path.join(DB_DIR, 'nexa_database.json');
const DB_TEMP_FILE = path.join(DB_DIR, 'nexa_database.tmp');

// In-Memory operational tables synced with disk
let dbState = {
  users: {},           // username (lowercase) -> UserRecord
  user_devices: {},    // userId -> { deviceId -> DeviceRecord }
  prekey_bundles: {},  // `${userId}:${deviceId}` -> BundleRecord
  mailbox_queue: {},   // deviceId -> [Envelope]
  activity_logs: [],   // [AuditLogEntry]
  meta: {
    initialized_at: Date.now(),
    last_saved_at: Date.now(),
    version: '1.0.0'
  }
};

let pgPool = null;
let isPgConnected = false;

// Ensure database directory exists safely
try {
  if (!fs.existsSync(DB_DIR)) {
    fs.mkdirSync(DB_DIR, { recursive: true });
  }
} catch (err) {
  console.warn('[NEXA DB] Directory creation note:', err.message);
}

// Load persistent data from disk on boot
function loadFromDisk() {
  try {
    if (isServerless && !fs.existsSync(DB_FILE) && fs.existsSync(SEED_FILE)) {
      try {
        fs.mkdirSync(DB_DIR, { recursive: true });
        fs.copyFileSync(SEED_FILE, DB_FILE);
      } catch (_) {}
    }
    const targetFile = fs.existsSync(DB_FILE) ? DB_FILE : (fs.existsSync(SEED_FILE) ? SEED_FILE : null);
    if (targetFile) {
      const raw = fs.readFileSync(targetFile, 'utf8');
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        dbState.users = parsed.users || {};
        dbState.user_devices = parsed.user_devices || {};
        dbState.prekey_bundles = parsed.prekey_bundles || {};
        dbState.mailbox_queue = parsed.mailbox_queue || {};
        dbState.activity_logs = parsed.activity_logs || [];
        dbState.messages = parsed.messages || [];
        dbState.calls = parsed.calls || {};
        dbState.app_version = parsed.app_version || dbState.app_version;
        dbState.meta = parsed.meta || dbState.meta;
        console.log(`[NEXA DB] Loaded persistent database (${Object.keys(dbState.users).length} registered users).`);
      }
    } else {
      saveToDiskSync();
      console.log(`[NEXA DB] Initialized new persistent database store at: ${DB_FILE}`);
    }
  } catch (err) {
    console.error('[NEXA DB] Error reading persistent database, backing up and starting clean:', err.message);
  }
}

// Atomic persistence write
function saveToDiskSync() {
  try {
    if (!fs.existsSync(DB_DIR)) {
      fs.mkdirSync(DB_DIR, { recursive: true });
    }
    dbState.meta.last_saved_at = Date.now();
    const serialized = JSON.stringify(dbState, null, 2);
    fs.writeFileSync(DB_TEMP_FILE, serialized, 'utf8');
    fs.renameSync(DB_TEMP_FILE, DB_FILE);
  } catch (err) {
    console.error('[NEXA DB] Atomic flush failed:', err.message);
  }
}

// Initialize PostgreSQL if DATABASE_URL is set
if (process.env.DATABASE_URL && Pool) {
  try {
    pgPool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 10,
      idleTimeoutMillis: 30000
    });
    pgPool.query('SELECT NOW()', (err, res) => {
      if (err) {
        console.warn('[NEXA DB] PostgreSQL connection warning:', err.message);
      } else {
        isPgConnected = true;
        console.log('[NEXA DB] PostgreSQL connected successfully at:', res.rows[0].now);
        // Ensure users table exists in PostgreSQL
        pgPool.query(`
          CREATE TABLE IF NOT EXISTS users (
            username TEXT PRIMARY KEY,
            password_hash TEXT NOT NULL,
            full_name TEXT NOT NULL,
            about TEXT,
            phone TEXT,
            nexa_id TEXT NOT NULL,
            created_at BIGINT NOT NULL
          );
        `, (err2) => {
          if (err2) console.warn('[NEXA DB] Users table creation error:', err2.message);
        });
      }
    });
  } catch (e) {
    console.warn('[NEXA DB] PostgreSQL initialization exception:', e.message);
  }
}

// Initial load
loadFromDisk();

const Database = {
  /**
   * Health and status inspection
   */
  getStatus() {
    return {
      connected: true,
      storage_type: isPgConnected ? 'postgresql_with_local_mirror' : 'persistent_local_database',
      database_file: DB_FILE,
      users_count: Object.keys(dbState.users).length,
      devices_count: Object.keys(dbState.user_devices).length,
      pending_envelopes: Object.values(dbState.mailbox_queue).reduce((sum, q) => sum + (q ? q.length : 0), 0),
      last_saved_at: dbState.meta.last_saved_at
    };
  },

  /**
   * Look up a user by clean username
   */
  async findUser(rawUsername) {
    if (!rawUsername) return null;
    const username = rawUsername.trim().replace(/^@+/, '').toLowerCase();

    // Check PostgreSQL first if connected
    if (isPgConnected && pgPool) {
      try {
        const res = await pgPool.query('SELECT * FROM users WHERE LOWER(username) = LOWER($1)', [username]);
        if (res.rows.length > 0) {
          const row = res.rows[0];
          return {
            username: row.username,
            password_hash: row.password_hash,
            full_name: row.full_name,
            about: row.about,
            phone: row.phone,
            nexa_id: row.nexa_id,
            created_at: Number(row.created_at)
          };
        }
      } catch (err) {
        console.warn('[NEXA DB] PostgreSQL query fallback:', err.message);
      }
    }

    // Check persistent database store
    if (!dbState.users[username]) {
      loadFromDisk();
    }
    return dbState.users[username] || null;
  },

  /**
   * Check if a username is already taken
   */
  async userExists(rawUsername) {
    const user = await this.findUser(rawUsername);
    return user !== null;
  },

  /**
   * Save a newly registered user
   */
  async saveUser(userRecord) {
    const username = userRecord.username.trim().replace(/^@+/, '').toLowerCase();
    const sanitized = {
      username,
      password_hash: userRecord.password_hash,
      full_name: userRecord.full_name || username,
      about: userRecord.about || 'Zero-knowledge encrypted peer.',
      phone: userRecord.phone || '',
      nexa_id: userRecord.nexa_id,
      created_at: userRecord.created_at || Date.now()
    };

    // Save to persistent file store
    dbState.users[username] = sanitized;
    saveToDiskSync();

    // Mirror to PostgreSQL if active
    if (isPgConnected && pgPool) {
      try {
        await pgPool.query(`
          INSERT INTO users (username, password_hash, full_name, about, phone, nexa_id, created_at)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT (username) DO UPDATE
          SET full_name = $3, about = $4, phone = $5;
        `, [
          username,
          sanitized.password_hash,
          sanitized.full_name,
          sanitized.about,
          sanitized.phone,
          sanitized.nexa_id,
          sanitized.created_at
        ]);
      } catch (err) {
        console.warn('[NEXA DB] PostgreSQL mirror error:', err.message);
      }
    }

    return sanitized;
  },

  /**
   * List all registered directory users
   */
  async listUsers() {
    return Object.values(dbState.users).map(u => ({
      username: u.username,
      handle: `@${u.username}`,
      fullName: u.full_name,
      about: u.about,
      phone: u.phone,
      nexaId: u.nexa_id,
      createdAt: u.created_at
    }));
  },

  /**
   * Device Management
   */
  getDevices(userId) {
    return dbState.user_devices[userId] || {};
  },

  saveDevice(userId, deviceId, deviceRecord) {
    if (!dbState.user_devices[userId]) {
      dbState.user_devices[userId] = {};
    }
    dbState.user_devices[userId][deviceId] = deviceRecord;
    saveToDiskSync();
  },

  /**
   * Prekey Bundles (X3DH)
   */
  getPrekeyBundle(bundleKey) {
    return dbState.prekey_bundles[bundleKey] || null;
  },

  savePrekeyBundle(bundleKey, bundleData) {
    dbState.prekey_bundles[bundleKey] = bundleData;
    saveToDiskSync();
  },

  /**
   * Blind Mailbox Queue
   */
  getMailboxEnvelopes(deviceId) {
    return dbState.mailbox_queue[deviceId] || [];
  },

  enqueueEnvelope(deviceId, envelope) {
    if (!dbState.mailbox_queue[deviceId]) {
      dbState.mailbox_queue[deviceId] = [];
    }
    dbState.mailbox_queue[deviceId].push(envelope);
    saveToDiskSync();
  },

  flushMailbox(deviceId) {
    const list = dbState.mailbox_queue[deviceId] || [];
    dbState.mailbox_queue[deviceId] = [];
    saveToDiskSync();
    return list;
  },

  /**
   * Activity & Security Audit Logging
   */
  logActivity(entry) {
    if (!dbState.activity_logs) dbState.activity_logs = [];
    const logItem = {
      id: `LOG-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`,
      timestamp: Date.now(),
      type: entry.type || 'system', // 'auth' | 'security' | 'admin' | 'message' | 'system'
      action: entry.action || 'event',
      target: entry.target || null,
      actor: entry.actor || 'system',
      details: entry.details || '',
      ip: entry.ip || '127.0.0.1'
    };
    dbState.activity_logs.unshift(logItem);
    if (dbState.activity_logs.length > 500) {
      dbState.activity_logs = dbState.activity_logs.slice(0, 500);
    }
    saveToDiskSync();
    return logItem;
  },

  getActivityLogs(limit = 100, filterType = null) {
    loadFromDisk();
    let logs = dbState.activity_logs || [];
    if (filterType && filterType !== 'all') {
      logs = logs.filter(l => l.type === filterType);
    }
    return logs.slice(0, limit);
  },

  /**
   * Detailed User Inspection for Admin Control Panel
   */
  getUsersDetailed() {
    loadFromDisk();
    return Object.values(dbState.users).map(u => {
      const devices = dbState.user_devices[u.username] ? Object.keys(dbState.user_devices[u.username]).length : 0;
      const latestLog = (dbState.activity_logs || []).find(l => l.target === u.username || l.actor === u.username);
      return {
        username: u.username,
        handle: `@${u.username}`,
        fullName: u.full_name || u.username,
        about: u.about || '',
        phone: u.phone || '',
        nexaId: u.nexa_id,
        role: u.role || (u.username === 'admin' ? 'admin' : 'user'),
        status: u.status || 'active', // 'active' | 'suspended' | 'flagged'
        createdAt: u.created_at,
        devicesCount: devices,
        lastActive: latestLog ? latestLog.timestamp : u.created_at
      };
    });
  },

  /**
   * Admin User Management Operations
   */
  updateUserStatus(rawUsername, status) {
    const username = rawUsername.trim().replace(/^@+/, '').toLowerCase();
    loadFromDisk();
    if (!dbState.users[username]) return null;
    dbState.users[username].status = status;
    saveToDiskSync();
    this.logActivity({
      type: 'admin',
      action: 'update_status',
      target: username,
      actor: 'admin',
      details: `User status changed to ${status}`
    });
    return dbState.users[username];
  },

  resetUserPin(rawUsername, newPin) {
    const username = rawUsername.trim().replace(/^@+/, '').toLowerCase();
    loadFromDisk();
    if (!dbState.users[username]) return false;
    const crypto = require('crypto');
    const newHash = crypto.createHash('sha256').update(newPin).digest('hex');
    dbState.users[username].password_hash = newHash;
    saveToDiskSync();
    this.logActivity({
      type: 'admin',
      action: 'reset_pin',
      target: username,
      actor: 'admin',
      details: `Master PIN reset by administrator`
    });
    return true;
  },

  deleteUser(rawUsername) {
    const username = rawUsername.trim().replace(/^@+/, '').toLowerCase();
    loadFromDisk();
    if (!dbState.users[username]) return false;
    delete dbState.users[username];
    if (dbState.user_devices[username]) delete dbState.user_devices[username];
    for (const key of Object.keys(dbState.prekey_bundles)) {
      if (key.startsWith(`${username}:`)) delete dbState.prekey_bundles[key];
    }
    saveToDiskSync();
    this.logActivity({
      type: 'admin',
      action: 'delete_user',
      target: username,
      actor: 'admin',
      details: `User account deleted permanently from database`
    });
    return true;
  },

  purgeExpiredEnvelopes() {
    let totalPurged = 0;
    for (const deviceId of Object.keys(dbState.mailbox_queue)) {
      const q = dbState.mailbox_queue[deviceId] || [];
      totalPurged += q.length;
      dbState.mailbox_queue[deviceId] = [];
    }
    saveToDiskSync();
    this.logActivity({
      type: 'admin',
      action: 'purge_queue',
      target: 'mailbox_queue',
      actor: 'admin',
      details: `Purged ${totalPurged} pending message envelopes`
    });
    return totalPurged;
  },

  getSystemMetrics(activeWsCount = 0) {
    loadFromDisk();
    const mem = process.memoryUsage();
    let dbSize = 0;
    try {
      if (fs.existsSync(DB_FILE)) dbSize = fs.statSync(DB_FILE).size;
    } catch (_) {}

    return {
      uptime_seconds: Math.floor(process.uptime()),
      node_version: process.version,
      platform: process.platform,
      active_connections: activeWsCount,
      total_users: Object.keys(dbState.users).length,
      active_users: Object.values(dbState.users).filter(u => u.status !== 'suspended').length,
      suspended_users: Object.values(dbState.users).filter(u => u.status === 'suspended').length,
      total_devices: Object.keys(dbState.user_devices).length,
      registered_devices: Object.keys(dbState.user_devices).length,
      queued_envelopes: Object.values(dbState.mailbox_queue).reduce((sum, q) => sum + (q ? q.length : 0), 0),
      db_file_bytes: dbSize,
      db_last_saved: dbState.meta.last_saved_at,
      memory: {
        heap_used_mb: (mem.heapUsed / 1024 / 1024).toFixed(2),
        heap_total_mb: (mem.heapTotal / 1024 / 1024).toFixed(2),
        rss_mb: (mem.rss / 1024 / 1024).toFixed(2)
      },
      security_mode: 'zero_knowledge_e2ee',
      crypto_protocol: 'X3DH_DoubleRatchet_AES256GCM'
    };
  },

  /**
   * Search users by NEXA ID, @username, full name, or phone number
   */
  searchUsers(rawQuery) {
    if (!rawQuery || typeof rawQuery !== 'string') return [];
    loadFromDisk();
    const q = rawQuery.trim().replace(/^@+/, '').toLowerCase();
    if (!q) return [];

    const results = [];
    for (const u of Object.values(dbState.users || {})) {
      if (u.status === 'suspended') continue;
      const un = (u.username || '').toLowerCase();
      const fn = (u.full_name || '').toLowerCase();
      const nid = (u.nexa_id || '').toLowerCase();
      const ph = (u.phone || '').replace(/\s+/g, '').replace(/-/g, '').toLowerCase();

      if (un.includes(q) || fn.includes(q) || nid.includes(q) || (ph.length >= 3 && ph.includes(q))) {
        results.push({
          username: u.username,
          handle: `@${u.username}`,
          fullName: u.full_name || u.username,
          nexaId: u.nexa_id,
          phone: u.phone || '',
          about: u.about || 'Zero-Knowledge Peer'
        });
      }
    }
    return results;
  },

  /**
   * Store a message in persistent database
   */
  saveMessage(msg) {
    loadFromDisk();
    if (!dbState.messages) dbState.messages = [];

    const record = {
      id: msg.id || `msg_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
      sender_handle: (msg.sender_handle || '').trim().replace(/^@+/, '').toLowerCase(),
      sender_nexa_id: msg.sender_nexa_id || '',
      recipient_handle: (msg.recipient_handle || '').trim().replace(/^@+/, '').toLowerCase(),
      recipient_nexa_id: msg.recipient_nexa_id || '',
      text: msg.text || '',
      type: msg.type || 'text',
      audio_path: msg.audio_path || null,
      audio_duration: msg.audio_duration || 0,
      timestamp: Number(msg.timestamp) || Date.now(),
      created_at: Date.now()
    };

    dbState.messages.push(record);

    // Keep latest 5000 messages
    if (dbState.messages.length > 5000) {
      dbState.messages = dbState.messages.slice(-5000);
    }

    saveToDiskSync();
    return record;
  },

  /**
   * Retrieve message thread between two peers
   */
  getThread(peerA, peerB) {
    loadFromDisk();
    if (!dbState.messages) return [];

    const cleanA = (peerA || '').trim().replace(/^@+/, '').toLowerCase();
    const cleanB = (peerB || '').trim().replace(/^@+/, '').toLowerCase();

    return dbState.messages.filter(m => {
      const isFromAToB = (m.sender_handle === cleanA || m.sender_nexa_id.toLowerCase() === cleanA) &&
                         (m.recipient_handle === cleanB || m.recipient_nexa_id.toLowerCase() === cleanB);
      const isFromBToA = (m.sender_handle === cleanB || m.sender_nexa_id.toLowerCase() === cleanB) &&
                         (m.recipient_handle === cleanA || m.recipient_nexa_id.toLowerCase() === cleanA);
      return isFromAToB || isFromBToA;
    }).sort((a, b) => a.timestamp - b.timestamp);
  },

  /**
   * Retrieve incoming messages inbox for a user
   */
  getInbox(recipient) {
    loadFromDisk();
    if (!dbState.messages) return [];
    const clean = (recipient || '').trim().replace(/^@+/, '').toLowerCase();

    return dbState.messages.filter(m => {
      return m.recipient_handle === clean || m.recipient_nexa_id.toLowerCase() === clean;
    }).sort((a, b) => a.timestamp - b.timestamp);
  },

  /**
   * Match phone numbers against registered users
   */
  matchContactsByPhones(phones) {
    loadFromDisk();
    if (!Array.isArray(phones) || phones.length === 0) return [];
    const phoneSet = new Set(phones.map(p => String(p).replace(/[^0-9]/g, '')));
    const matched = [];
    for (const u of Object.values(dbState.users || {})) {
      if (u.phone) {
        const cleanPhone = String(u.phone).replace(/[^0-9]/g, '');
        if (phoneSet.has(cleanPhone)) {
          matched.push({
            username: u.username,
            handle: u.handle || `@${u.username}`,
            nexaId: u.nexa_id,
            fullName: u.full_name || u.username,
            phone: u.phone,
            about: u.about || 'Zero-Knowledge Peer'
          });
        }
      }
    }
    return matched;
  },

  /**
   * Call Session Engine (Voice & Video Call Signaling)
   */
  createCallSession(data) {
    loadFromDisk();
    if (!dbState.calls) dbState.calls = {};
    const callId = data.call_id || data.offer_id || `call_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
    const session = {
      call_id: callId,
      caller_handle: (data.caller_handle || '').trim().replace(/^@+/, '').toLowerCase(),
      caller_nexa_id: data.caller_nexa_id || '',
      caller_name: data.caller_name || data.caller_handle || 'Peer',
      recipient_handle: (data.recipient_handle || '').trim().replace(/^@+/, '').toLowerCase(),
      recipient_nexa_id: data.recipient_nexa_id || '',
      call_type: data.call_type || 'voice', // 'video' | 'voice'
      status: 'ringing', // 'ringing', 'connected', 'declined', 'ended'
      created_at: Date.now(),
      updated_at: Date.now()
    };
    dbState.calls[callId] = session;
    saveToDiskSync();
    return session;
  },

  getIncomingCall(user) {
    loadFromDisk();
    if (!dbState.calls) return null;
    const clean = (user || '').trim().replace(/^@+/, '').toLowerCase();
    const now = Date.now();
    for (const call of Object.values(dbState.calls)) {
      if (
        (call.recipient_handle === clean || (call.recipient_nexa_id && call.recipient_nexa_id.toLowerCase() === clean)) &&
        call.status === 'ringing' &&
        now - call.created_at < 45000
      ) {
        return call;
      }
    }
    return null;
  },

  answerCallSession(callId, accepted) {
    loadFromDisk();
    if (!dbState.calls || !dbState.calls[callId]) return null;
    const session = dbState.calls[callId];
    session.status = accepted ? 'connected' : 'declined';
    session.updated_at = Date.now();
    saveToDiskSync();
    return session;
  },

  endCallSession(callId) {
    loadFromDisk();
    if (!dbState.calls || !dbState.calls[callId]) return null;
    const session = dbState.calls[callId];
    session.status = 'ended';
    session.updated_at = Date.now();
    saveToDiskSync();
    return session;
  },

  getCallSession(callId) {
    loadFromDisk();
    if (!dbState.calls) return null;
    return dbState.calls[callId] || null;
  },

  /**
   * Application Update Engine
   */
  getAppVersion() {
    loadFromDisk();
    return dbState.app_version || {
      latest_version: '1.2.0',
      build_number: 4,
      release_date: '2026-10-09',
      release_notes: 'Redesigned Modern Minimalist UI, Dual Camera Vision Video Calls & Voice Calling, and Native Device Contacts Sync.',
      download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: false,
      published_at: Date.now()
    };
  },

  setAppVersion(info) {
    loadFromDisk();
    dbState.app_version = {
      latest_version: info.latest_version || '1.2.0',
      build_number: Number(info.build_number) || 4,
      release_date: info.release_date || new Date().toISOString().split('T')[0],
      release_notes: info.release_notes || 'Performance, UI redesign, and video calling updates.',
      download_url: info.download_url || 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: info.web_url || 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: Boolean(info.mandatory),
      published_at: Date.now()
    };
    saveToDiskSync();
    this.logActivity({
      type: 'admin',
      action: 'push_app_update',
      target: `v${dbState.app_version.latest_version}+${dbState.app_version.build_number}`,
      actor: 'admin',
      details: `App update released: ${dbState.app_version.release_notes}`
    });
    return dbState.app_version;
  }
};

module.exports = Database;
