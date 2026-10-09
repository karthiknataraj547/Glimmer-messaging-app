/**
 * NEXA Serverless Persistent Database Engine
 * 
 * High-performance, zero-external-dependency database engine for Vercel Serverless.
 * Automatically initializes from seed_database.json and persists in /tmp/nexa_data.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SEED_FILE = path.join(__dirname, 'seed_database.json');
const DB_DIR = path.join('/tmp', 'nexa_data');
const DB_FILE = path.join(DB_DIR, 'nexa_database.json');
const DB_TEMP_FILE = path.join(DB_DIR, 'nexa_database.tmp');

let dbState = {
  users: {},
  user_devices: {},
  prekey_bundles: {},
  mailbox_queue: {},
  activity_logs: [],
  messages: [],
  app_version: {
    latest_version: '1.2.1',
    build_number: 5,
    release_date: '2026-10-09',
    release_notes: 'New Chat mobile contacts & saved identities selector, custom NEXA ID & handle messaging, bidirectional real-time delivery fixes.',
    download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
    web_url: 'https://glimmer-messaging-app-web.vercel.app/',
    mandatory: false,
    published_at: Date.now()
  },
  meta: {
    initialized_at: Date.now(),
    last_saved_at: Date.now(),
    version: '1.0.0'
  }
};

function ensureDir() {
  try {
    if (!fs.existsSync(DB_DIR)) {
      fs.mkdirSync(DB_DIR, { recursive: true });
    }
  } catch (_) {}
}

function loadFromDisk() {
  try {
    ensureDir();
    if (!fs.existsSync(DB_FILE) && fs.existsSync(SEED_FILE)) {
      try {
        fs.copyFileSync(SEED_FILE, DB_FILE);
      } catch (_) {}
    }
    const target = fs.existsSync(DB_FILE) ? DB_FILE : (fs.existsSync(SEED_FILE) ? SEED_FILE : null);
    if (target) {
      const raw = fs.readFileSync(target, 'utf8');
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
      }
    }
  } catch (err) {
    console.error('[NEXA Serverless DB] Load error:', err.message);
  }
}

function saveToDiskSync() {
  try {
    ensureDir();
    dbState.meta.last_saved_at = Date.now();
    const serialized = JSON.stringify(dbState, null, 2);
    fs.writeFileSync(DB_TEMP_FILE, serialized, 'utf8');
    fs.renameSync(DB_TEMP_FILE, DB_FILE);
  } catch (err) {
    console.error('[NEXA Serverless DB] Save error:', err.message);
  }
}

// Initial boot load
loadFromDisk();

const Database = {
  getStatus() {
    loadFromDisk();
    return {
      connected: true,
      storage_type: 'serverless_tmp_database',
      database_file: DB_FILE,
      users_count: Object.keys(dbState.users).length,
      devices_count: Object.keys(dbState.user_devices).length,
      pending_envelopes: Object.values(dbState.mailbox_queue).reduce((sum, q) => sum + (q ? q.length : 0), 0),
      last_saved_at: dbState.meta.last_saved_at
    };
  },

  findUser(username) {
    loadFromDisk();
    if (!username) return null;
    const clean = username.trim().toLowerCase();
    return dbState.users[clean] || null;
  },

  findUserByNexaId(nexaId) {
    loadFromDisk();
    if (!nexaId) return null;
    const clean = nexaId.trim().toUpperCase();
    for (const u of Object.values(dbState.users)) {
      if (u.nexa_id && u.nexa_id.toUpperCase() === clean) return u;
    }
    return null;
  },

  resolveUser(identifier) {
    if (!identifier || typeof identifier !== 'string') return null;
    loadFromDisk();
    const raw = identifier.trim();
    if (!raw) return null;

    const clean = raw.replace(/^@+/, '').toLowerCase();
    const cleanUpper = raw.toUpperCase();
    const cleanDigits = raw.replace(/\D/g, '');

    if (dbState.users && dbState.users[clean]) return dbState.users[clean];

    for (const u of Object.values(dbState.users || {})) {
      if (!u) continue;
      const uUsername = (u.username || '').toLowerCase();
      const uNexaId = (u.nexa_id || '').toUpperCase();
      const uFullName = (u.full_name || '').toLowerCase();
      const uPhoneDigits = (u.phone || '').replace(/\D/g, '');

      if (uUsername === clean) return u;
      if (uNexaId === cleanUpper || uNexaId.toLowerCase() === clean) return u;
      if (cleanDigits.length >= 7 && uPhoneDigits.length >= 7) {
        if (cleanDigits === uPhoneDigits || cleanDigits.endsWith(uPhoneDigits) || uPhoneDigits.endsWith(cleanDigits)) {
          return u;
        }
      }
      if (uFullName && uFullName === clean) return u;
    }
    return null;
  },

  getUserAliases(identifier, extraId = null) {
    const aliases = new Set();
    if (!identifier && !extraId) return aliases;

    const addIdent = (val) => {
      if (!val || typeof val !== 'string') return;
      const v = val.trim();
      if (!v) return;
      aliases.add(v.toLowerCase());
      aliases.add(v.replace(/^@+/, '').toLowerCase());
      const digits = v.replace(/\D/g, '');
      if (digits.length >= 7) aliases.add(digits);
    };

    addIdent(identifier);
    if (extraId) addIdent(extraId);

    const user = this.resolveUser(identifier) || (extraId ? this.resolveUser(extraId) : null);
    if (user) {
      addIdent(user.username);
      addIdent(user.nexa_id);
      if (user.full_name) addIdent(user.full_name);
      if (user.phone) addIdent(user.phone);
    }

    return aliases;
  },

  createUser(userData) {
    loadFromDisk();
    const clean = (userData.username || '').trim().toLowerCase();
    dbState.users[clean] = {
      username: clean,
      handle: userData.handle || `@${clean}`,
      nexa_id: userData.nexa_id || `NX-${crypto.randomBytes(4).toString('hex').toUpperCase()}`,
      password_hash: userData.password_hash,
      full_name: userData.full_name || clean,
      about: userData.about || 'Hey there! I am using NEXA.',
      phone: userData.phone || null,
      role: userData.role || 'user',
      status: userData.status || 'active',
      created_at: Date.now(),
      last_seen: Date.now()
    };
    saveToDiskSync();
    return dbState.users[clean];
  },

  getAllUsers() {
    loadFromDisk();
    return Object.values(dbState.users);
  },

  getUsersDetailed() {
    loadFromDisk();
    return Object.values(dbState.users).map(u => ({
      username: u.username,
      handle: u.handle || `@${u.username}`,
      nexa_id: u.nexa_id,
      full_name: u.full_name,
      about: u.about,
      role: u.role || 'user',
      status: u.status || 'active',
      created_at: u.created_at || Date.now(),
      last_seen: u.last_seen || Date.now(),
      devices: dbState.user_devices[u.nexa_id] ? Object.keys(dbState.user_devices[u.nexa_id]).length : 0
    }));
  },

  updateUserStatus(username, status) {
    loadFromDisk();
    const clean = (username || '').trim().toLowerCase();
    if (dbState.users[clean]) {
      dbState.users[clean].status = status;
      saveToDiskSync();
      return true;
    }
    return false;
  },

  resetUserPin(username, newPin) {
    loadFromDisk();
    const clean = (username || '').trim().toLowerCase();
    if (dbState.users[clean]) {
      dbState.users[clean].password_hash = crypto.createHash('sha256').update(String(newPin)).digest('hex');
      saveToDiskSync();
      return true;
    }
    return false;
  },

  deleteUser(username) {
    loadFromDisk();
    const clean = (username || '').trim().toLowerCase();
    if (dbState.users[clean]) {
      const nexaId = dbState.users[clean].nexa_id;
      delete dbState.users[clean];
      if (nexaId && dbState.user_devices[nexaId]) {
        delete dbState.user_devices[nexaId];
      }
      saveToDiskSync();
      return true;
    }
    return false;
  },

  logActivity(entry) {
    loadFromDisk();
    const item = {
      id: `LOG-${Date.now()}-${Math.floor(Math.random() * 8999 + 1000)}`,
      timestamp: Date.now(),
      ...entry
    };
    dbState.activity_logs.unshift(item);
    if (dbState.activity_logs.length > 500) {
      dbState.activity_logs = dbState.activity_logs.slice(0, 500);
    }
    saveToDiskSync();
    return item;
  },

  getActivityLogs(limit = 100, filterType = 'all') {
    loadFromDisk();
    let logs = dbState.activity_logs || [];
    if (filterType && filterType !== 'all') {
      logs = logs.filter(l => l.type === filterType);
    }
    return logs.slice(0, limit);
  },

  saveMessage(msg) {
    loadFromDisk();
    if (!dbState.messages) dbState.messages = [];

    const rawSender = (msg.sender_handle || '').trim();
    const rawSenderId = (msg.sender_nexa_id || '').trim();
    const rawRecipient = (msg.recipient_handle || '').trim();
    const rawRecipientId = (msg.recipient_nexa_id || '').trim();

    // 1. Resolve Sender
    const senderUser = this.resolveUser(rawSender) || this.resolveUser(rawSenderId);
    const senderHandle = senderUser ? senderUser.username.toLowerCase() : rawSender.replace(/^@+/, '').toLowerCase();
    const senderNexaId = senderUser ? senderUser.nexa_id : (rawSenderId || (senderHandle ? `NX-${senderHandle.toUpperCase()}` : 'NX-PEER'));

    // 2. Resolve Recipient
    const recipientUser = this.resolveUser(rawRecipient) || this.resolveUser(rawRecipientId);
    const recipientHandle = recipientUser ? recipientUser.username.toLowerCase() : rawRecipient.replace(/^@+/, '').toLowerCase();
    const recipientNexaId = recipientUser ? recipientUser.nexa_id : (rawRecipientId || (recipientHandle.toUpperCase().startsWith('NX-') ? recipientHandle.toUpperCase() : `NX-${recipientHandle.toUpperCase()}`));

    const item = {
      id: msg.id || `MSG-${Date.now()}-${Math.floor(Math.random() * 8999 + 1000)}`,
      ...msg,
      sender_handle: senderHandle,
      sender_nexa_id: senderNexaId,
      recipient_handle: recipientHandle,
      recipient_nexa_id: recipientNexaId,
      timestamp: Number(msg.timestamp) || Date.now(),
      created_at: Date.now()
    };
    dbState.messages.push(item);
    if (dbState.messages.length > 5000) {
      dbState.messages = dbState.messages.slice(-5000);
    }
    saveToDiskSync();
    return item;
  },

  getMessageThread(user1, user2, options = {}) {
    loadFromDisk();
    if (!dbState.messages) return [];

    const aliases1 = this.getUserAliases(user1, options.my_id);
    const aliases2 = this.getUserAliases(user2, options.peer_id);

    return dbState.messages.filter(m => {
      const sH = (m.sender_handle || '').toLowerCase();
      const sId = (m.sender_nexa_id || '').toLowerCase();
      const rH = (m.recipient_handle || '').toLowerCase();
      const rId = (m.recipient_nexa_id || '').toLowerCase();

      const senderIs1 = aliases1.has(sH) || aliases1.has(sId);
      const recipientIs2 = aliases2.has(rH) || aliases2.has(rId);

      const senderIs2 = aliases2.has(sH) || aliases2.has(sId);
      const recipientIs1 = aliases1.has(rH) || aliases1.has(rId);

      return (senderIs1 && recipientIs2) || (senderIs2 && recipientIs1);
    }).sort((a, b) => a.timestamp - b.timestamp);
  },

  getThread(user1, user2, options = {}) {
    return this.getMessageThread(user1, user2, options);
  },

  getInbox(recipient, extraId = null) {
    loadFromDisk();
    if (!dbState.messages) return [];
    const aliases = this.getUserAliases(recipient, extraId);

    return dbState.messages.filter(m => {
      const rH = (m.recipient_handle || '').toLowerCase();
      const rId = (m.recipient_nexa_id || '').toLowerCase();
      return aliases.has(rH) || aliases.has(rId);
    }).sort((a, b) => a.timestamp - b.timestamp);
  },

  matchContactsByPhones(phones) {
    loadFromDisk();
    if (!Array.isArray(phones) || phones.length === 0) return [];
    const phoneSet = new Set(phones.map(p => String(p).replace(/[^0-9]/g, '')));
    const matched = [];
    for (const u of Object.values(dbState.users)) {
      if (u.phone) {
        const cleanPhone = String(u.phone).replace(/[^0-9]/g, '');
        if (phoneSet.has(cleanPhone)) {
          matched.push({
            username: u.username,
            handle: u.handle || `@${u.username}`,
            nexa_id: u.nexa_id,
            full_name: u.full_name,
            phone: u.phone
          });
        }
      }
    }
    return matched;
  },

  searchUsers(rawQuery) {
    loadFromDisk();
    if (!rawQuery || typeof rawQuery !== 'string') return [];
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
          handle: u.handle || `@${u.username}`,
          fullName: u.full_name || u.username,
          nexaId: u.nexa_id,
          phone: u.phone || '',
          about: u.about || 'Zero-Knowledge Peer'
        });
      }
    }
    return results;
  },

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
      call_type: data.call_type || 'voice',
      status: 'ringing',
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

  getAppVersion() {
    loadFromDisk();
    return dbState.app_version || {
      latest_version: '1.2.1',
      build_number: 5,
      release_date: '2026-10-09',
      release_notes: 'New Chat mobile contacts & saved identities selector, custom NEXA ID & handle messaging, bidirectional real-time delivery fixes.',
      download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: false,
      published_at: Date.now()
    };
  },

  setAppVersion(info) {
    loadFromDisk();
    dbState.app_version = {
      latest_version: info.latest_version || '1.2.1',
      build_number: Number(info.build_number) || 5,
      release_date: info.release_date || new Date().toISOString().split('T')[0],
      release_notes: info.release_notes || 'Performance and security updates.',
      download_url: info.download_url || 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: info.web_url || 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: Boolean(info.mandatory),
      published_at: Date.now()
    };
    saveToDiskSync();
    return dbState.app_version;
  },

  purgeExpiredEnvelopes() {
    loadFromDisk();
    dbState.mailbox_queue = {};
    saveToDiskSync();
    return 0;
  },

  getSystemMetrics(uptime = 0) {
    loadFromDisk();
    const mem = process.memoryUsage();
    return {
      total_registered_users: Object.keys(dbState.users).length,
      active_realtime_sockets: 0,
      mailbox_envelopes: 0,
      heap_used_mb: Math.round(mem.heapUsed / 1024 / 1024 * 10) / 10,
      rss_mb: Math.round(mem.rss / 1024 / 1024 * 10) / 10,
      uptime_seconds: Math.floor(process.uptime()),
      database_type: 'serverless_tmp_database',
      is_database_connected: true
    };
  }
};

module.exports = Database;
