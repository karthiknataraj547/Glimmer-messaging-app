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
    latest_version: '1.0.1',
    build_number: 2,
    release_date: '2026-10-08',
    release_notes: 'Native device contacts synchronization, peer ID servicing option, real-time message delivery enhancements, and security upgrades.',
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
    const item = {
      id: `MSG-${Date.now()}-${Math.floor(Math.random() * 8999 + 1000)}`,
      ...msg,
      timestamp: msg.timestamp || Date.now()
    };
    dbState.messages.push(item);
    saveToDiskSync();
    return item;
  },

  getMessageThread(user1, user2) {
    loadFromDisk();
    if (!dbState.messages) return [];
    const u1 = (user1 || '').trim().replace(/^@+/, '').toLowerCase();
    const u2 = (user2 || '').trim().replace(/^@+/, '').toLowerCase();

    return dbState.messages.filter(m => {
      const sender = (m.sender_handle || '').toLowerCase();
      const recip = (m.recipient_handle || '').toLowerCase();
      const sId = (m.sender_nexa_id || '').toLowerCase();
      const rId = (m.recipient_nexa_id || '').toLowerCase();

      const isFrom1To2 = (sender === u1 || sId === u1) && (recip === u2 || rId === u2);
      const isFrom2To1 = (sender === u2 || sId === u2) && (recip === u1 || rId === u1);
      return isFrom1To2 || isFrom2To1;
    }).sort((a, b) => a.timestamp - b.timestamp);
  },

  getInbox(recipient) {
    loadFromDisk();
    if (!dbState.messages) return [];
    const clean = (recipient || '').trim().replace(/^@+/, '').toLowerCase();
    return dbState.messages.filter(m => {
      return (m.recipient_handle || '').toLowerCase() === clean || (m.recipient_nexa_id || '').toLowerCase() === clean;
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

  getAppVersion() {
    loadFromDisk();
    return dbState.app_version || {
      latest_version: '1.0.1',
      build_number: 2,
      release_date: '2026-10-08',
      release_notes: 'Native device contacts synchronization, peer ID servicing option, real-time message delivery enhancements, and security upgrades.',
      download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: false,
      published_at: Date.now()
    };
  },

  setAppVersion(info) {
    loadFromDisk();
    dbState.app_version = {
      latest_version: info.latest_version || '1.0.1',
      build_number: Number(info.build_number) || 2,
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
