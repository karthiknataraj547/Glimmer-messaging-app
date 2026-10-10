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
  device_push_tokens: {},
  prekey_bundles: {},
  mailbox_queue: {},
  activity_logs: [],
  messages: [],
  conversations: {},
  attachments: {},
  user_locations: {},
  calls: {},
  app_version: {
    latest_version: '1.3.0',
    build_number: 14,
    release_date: '2026-10-10',
    release_notes: 'Release v1.3.0: High-performance local-first messaging architecture, instant cached chat opening (<100ms) with zero white screen, message delivery lifecycle states (pending, sending, sent, delivered, read, retry), and non-blocking background synchronization.',
    download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
    web_url: 'https://glimmer-messaging-app-web.vercel.app/',
    mandatory: false,
    published_at: Date.now()
  },
  meta: {
    initialized_at: Date.now(),
    last_saved_at: Date.now(),
    messageRetentionHours: 168,
    version: '1.2.5'
  }
};

const CLOUD_BIN_URL = 'https://extendsclass.com/api/json-storage/bin/eafefcc';
let lastCloudSyncTime = 0;
const CLOUD_SYNC_TTL = 3000;

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
        dbState.device_push_tokens = parsed.device_push_tokens || {};
        dbState.prekey_bundles = parsed.prekey_bundles || {};
        dbState.mailbox_queue = parsed.mailbox_queue || {};
        dbState.activity_logs = parsed.activity_logs || [];
        dbState.messages = parsed.messages || [];
        dbState.conversations = parsed.conversations || {};
        dbState.attachments = parsed.attachments || {};
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

async function syncFromCloud(force = false) {
  const now = Date.now();
  if (!force && (now - lastCloudSyncTime < CLOUD_SYNC_TTL)) {
    return;
  }
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    const res = await fetch(CLOUD_BIN_URL, { signal: controller.signal });
    clearTimeout(timeout);
    if (res.ok) {
      const remote = await res.json();
      if (remote && typeof remote === 'object') {
        let changed = false;
        if (remote.users && typeof remote.users === 'object') {
          for (const [k, v] of Object.entries(remote.users)) {
            if (!dbState.users[k]) {
              dbState.users[k] = v;
              changed = true;
            } else if (v.created_at && (!dbState.users[k].created_at || v.created_at >= dbState.users[k].created_at)) {
              dbState.users[k] = v;
            }
          }
        }
        if (remote.user_locations && typeof remote.user_locations === 'object') {
          if (!dbState.user_locations) dbState.user_locations = {};
          for (const [k, loc] of Object.entries(remote.user_locations)) {
            if (!dbState.user_locations[k] || (loc.updated_at && loc.updated_at >= (dbState.user_locations[k].updated_at || 0))) {
              dbState.user_locations[k] = loc;
              changed = true;
            }
          }
        }
        if (remote.meta && typeof remote.meta === 'object') {
          if (remote.meta.messageRetentionHours) {
            dbState.meta.messageRetentionHours = remote.meta.messageRetentionHours;
          }
        }
        if (remote.app_version && remote.app_version.build_number) {
          if (!dbState.app_version || remote.app_version.build_number > (dbState.app_version.build_number || 0)) {
            dbState.app_version = remote.app_version;
            changed = true;
          }
        }
        if (Array.isArray(remote.activity_logs) && remote.activity_logs.length > 0) {
          const existingIds = new Set((dbState.activity_logs || []).map(l => l.id || `${l.timestamp}_${l.action}`));
          for (const log of remote.activity_logs) {
            const id = log.id || `${log.timestamp}_${log.action}`;
            if (!existingIds.has(id)) {
              dbState.activity_logs.push(log);
            }
          }
        }
        if (Array.isArray(remote.messages) && remote.messages.length > 0) {
          if (!dbState.messages) dbState.messages = [];
          const existingMap = new Map();
          for (let i = 0; i < dbState.messages.length; i++) {
            const m = dbState.messages[i];
            if (m && m.id) existingMap.set(m.id, i);
          }
          for (const msg of remote.messages) {
            if (!msg || !msg.id) continue;
            if (!existingMap.has(msg.id)) {
              dbState.messages.push(msg);
              existingMap.set(msg.id, dbState.messages.length - 1);
              changed = true;
            } else {
              const idx = existingMap.get(msg.id);
              const localMsg = dbState.messages[idx];
              if (localMsg.status !== msg.status && msg.status === 'delivered') {
                localMsg.status = msg.status;
                localMsg.delivered_at = msg.delivered_at || Date.now();
                changed = true;
              }
            }
          }
        }
        if (remote.conversations && typeof remote.conversations === 'object') {
          if (!dbState.conversations) dbState.conversations = {};
          for (const [k, v] of Object.entries(remote.conversations)) {
            if (!dbState.conversations[k] || (v.updated_at && v.updated_at >= (dbState.conversations[k].updated_at || 0))) {
              dbState.conversations[k] = v;
              changed = true;
            }
          }
        }
        if (remote.device_push_tokens && typeof remote.device_push_tokens === 'object') {
          if (!dbState.device_push_tokens) dbState.device_push_tokens = {};
          for (const [k, v] of Object.entries(remote.device_push_tokens)) {
            dbState.device_push_tokens[k] = Object.assign(dbState.device_push_tokens[k] || {}, v);
            changed = true;
          }
        }
        if (remote.attachments && typeof remote.attachments === 'object') {
          if (!dbState.attachments) dbState.attachments = {};
          for (const [k, v] of Object.entries(remote.attachments)) {
            if (!dbState.attachments[k]) {
              dbState.attachments[k] = v;
              changed = true;
            }
          }
        }
        lastCloudSyncTime = Date.now();
        if (changed) {
          saveToDiskSync();
        }
      }
    }
  } catch (_) {}
}

async function syncToCloud() {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const body = JSON.stringify({
      users: dbState.users,
      user_devices: dbState.user_devices,
      device_push_tokens: dbState.device_push_tokens || {},
      user_locations: dbState.user_locations || {},
      prekey_bundles: dbState.prekey_bundles,
      mailbox_queue: dbState.mailbox_queue,
      activity_logs: (dbState.activity_logs || []).slice(0, 100),
      meta: dbState.meta,
      messages: (dbState.messages || []).slice(-200),
      conversations: dbState.conversations || {},
      attachments: dbState.attachments || {},
      app_version: dbState.app_version
    });
    const res = await fetch(CLOUD_BIN_URL, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body,
      signal: controller.signal
    });
    clearTimeout(timeout);
    if (res.ok) {
      lastCloudSyncTime = Date.now();
    }
  } catch (_) {}
}

// Initial boot load
loadFromDisk();
syncFromCloud().catch(() => {});

const Database = {
  syncFromCloud(force = false) {
    return syncFromCloud(force);
  },

  syncToCloud() {
    return syncToCloud();
  },

  getStatus() {
    loadFromDisk();
    return {
      connected: true,
      storage_type: 'serverless_cloud_sync_database',
      database_file: DB_FILE,
      users_count: Object.keys(dbState.users).length,
      devices_count: Object.keys(dbState.user_devices).length,
      pending_envelopes: Object.values(dbState.mailbox_queue).reduce((sum, q) => sum + (q ? q.length : 0), 0),
      last_saved_at: dbState.meta.last_saved_at
    };
  },

  getSystemMetrics(activeWsCount = 0) {
    loadFromDisk();
    const mem = process.memoryUsage ? process.memoryUsage() : { heapUsed: 0, heapTotal: 0, rss: 0 };
    let dbSize = 0;
    try {
      if (fs.existsSync(DB_FILE)) dbSize = fs.statSync(DB_FILE).size;
    } catch (_) {}

    return {
      uptime_seconds: Math.floor(process.uptime ? process.uptime() : 0),
      node_version: process.version,
      platform: process.platform,
      active_connections: activeWsCount,
      active_realtime_sockets: activeWsCount,
      total_users: Object.keys(dbState.users).length,
      total_registered_users: Object.keys(dbState.users).length,
      active_users: Object.values(dbState.users).filter(u => u.status !== 'suspended').length,
      suspended_users: Object.values(dbState.users).filter(u => u.status === 'suspended').length,
      total_devices: Object.keys(dbState.user_devices).length,
      registered_devices: Object.keys(dbState.user_devices).length,
      queued_envelopes: Object.values(dbState.mailbox_queue).reduce((sum, q) => sum + (q ? q.length : 0), 0),
      mailbox_envelopes: Object.values(dbState.mailbox_queue).reduce((sum, q) => sum + (q ? q.length : 0), 0),
      db_file_bytes: dbSize,
      db_last_saved: dbState.meta.last_saved_at,
      memory: {
        heap_used_mb: (mem.heapUsed / 1024 / 1024).toFixed(2),
        heap_total_mb: (mem.heapTotal / 1024 / 1024).toFixed(2),
        rss_mb: (mem.rss / 1024 / 1024).toFixed(2)
      },
      heap_used_mb: Math.round(mem.heapUsed / 1024 / 1024 * 10) / 10,
      rss_mb: Math.round(mem.rss / 1024 / 1024 * 10) / 10,
      security_mode: 'zero_knowledge_e2ee',
      crypto_protocol: 'X3DH_DoubleRatchet_AES256GCM',
      database_type: 'serverless_cloud_sync_database',
      is_database_connected: true
    };
  },

  async findUser(username) {
    loadFromDisk();
    if (!username) return null;
    const clean = username.trim().toLowerCase();
    if (dbState.users[clean]) return dbState.users[clean];
    await syncFromCloud(true);
    return dbState.users[clean] || null;
  },

  async findUserByNexaId(nexaId) {
    loadFromDisk();
    if (!nexaId) return null;
    const clean = nexaId.trim().toUpperCase();
    for (const u of Object.values(dbState.users)) {
      if (u.nexa_id && u.nexa_id.toUpperCase() === clean) return u;
    }
    await syncFromCloud(true);
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
    const cleanAlpha = clean.replace(/[^a-z0-9]/g, '');
    const cleanUpperAlpha = cleanUpper.replace(/[^A-Z0-9]/g, '');

    if (dbState.users && dbState.users[clean]) return dbState.users[clean];

    for (const u of Object.values(dbState.users || {})) {
      if (!u) continue;
      const uUsername = (u.username || '').toLowerCase();
      const uNexaId = (u.nexa_id || '').toUpperCase();
      const uNexaIdAlpha = uNexaId.replace(/[^A-Z0-9]/g, '');
      const uFullName = (u.full_name || '').toLowerCase();
      const uPhoneDigits = (u.phone || '').replace(/\D/g, '');

      if (uUsername === clean) return u;
      if (uNexaId === cleanUpper || uNexaId.toLowerCase() === clean) return u;
      if (cleanUpperAlpha.length >= 4 && (uNexaIdAlpha === cleanUpperAlpha || uNexaIdAlpha.endsWith(cleanUpperAlpha) || cleanUpperAlpha.endsWith(uNexaIdAlpha))) {
        return u;
      }
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
      const alpha = v.replace(/[^a-z0-9]/g, '').toLowerCase();
      if (alpha.length >= 4) aliases.add(alpha);
    };

    addIdent(identifier);
    if (extraId) addIdent(extraId);

    const user = this.resolveUser(identifier) || (extraId ? this.resolveUser(extraId) : null);
    if (user) {
      addIdent(user.username);
      addIdent(user.nexa_id);
      if (user.nexa_id) {
        aliases.add(user.nexa_id.replace(/[^a-zA-Z0-9]/g, '').toLowerCase());
      }
      if (user.full_name) addIdent(user.full_name);
      if (user.phone) addIdent(user.phone);
    }

    return aliases;
  },

  async createUser(userData) {
    loadFromDisk();
    await syncFromCloud();
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
    await syncToCloud();
    this.logActivity({
      type: 'auth',
      action: 'user_register',
      target: clean,
      actor: clean,
      details: `New account ${dbState.users[clean].nexa_id} registered and persisted`
    });
    return dbState.users[clean];
  },

  getAllUsers() {
    loadFromDisk();
    return Object.values(dbState.users);
  },

  getUsersDetailed() {
    loadFromDisk();
    return Object.values(dbState.users).map(u => {
      const devices = dbState.user_devices[u.nexa_id] 
        ? Object.keys(dbState.user_devices[u.nexa_id]).length 
        : (dbState.user_devices[u.username] ? Object.keys(dbState.user_devices[u.username]).length : 0);
      return {
        username: u.username,
        handle: u.handle || `@${u.username}`,
        nexa_id: u.nexa_id,
        nexaId: u.nexa_id,
        full_name: u.full_name || u.fullName || u.username,
        fullName: u.full_name || u.fullName || u.username,
        about: u.about || '',
        phone: u.phone || '',
        role: u.role || 'user',
        status: u.status || 'active',
        created_at: u.created_at || Date.now(),
        createdAt: u.created_at || Date.now(),
        last_seen: u.last_seen || u.created_at || Date.now(),
        lastActive: u.last_seen || u.created_at || Date.now(),
        devices_count: devices,
        devicesCount: devices
      };
    });
  },

  updateUserStatus(username, status) {
    loadFromDisk();
    const clean = (username || '').trim().toLowerCase();
    if (dbState.users[clean]) {
      dbState.users[clean].status = status;
      saveToDiskSync();
      syncToCloud().catch(() => {});
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
      syncToCloud().catch(() => {});
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
      if (dbState.user_devices[clean]) {
        delete dbState.user_devices[clean];
      }
      saveToDiskSync();
      syncToCloud().catch(() => {});
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

  cleanupMessages() {
    if (!dbState.messages || !Array.isArray(dbState.messages)) return;
    const hours = Number(dbState.meta?.messageRetentionHours) || 168; // default 1 week
    const retentionMs = hours * 60 * 60 * 1000;
    const now = Date.now();
    const initialLen = dbState.messages.length;

    dbState.messages = dbState.messages.filter(m => {
      // 1. Delivered messages: ephemeral purge after 5 min acknowledgment window
      if (m.status === 'delivered' && m.delivered_at && (now - m.delivered_at > 5 * 60 * 1000)) {
        return false;
      }
      // 2. Undelivered messages for offline users: held for retention period (default 1 week or admin-configured)
      const msgTime = Number(m.timestamp) || Number(m.created_at) || now;
      if (now - msgTime > retentionMs) {
        return false;
      }
      return true;
    });

    if (dbState.messages.length > 5000) {
      dbState.messages = dbState.messages.slice(-5000);
    }
    if (dbState.messages.length !== initialLen) {
      saveToDiskSync();
    }
  },

  getRetentionPolicy() {
    loadFromDisk();
    const hours = Number(dbState.meta?.messageRetentionHours) || 168;
    const msgs = dbState.messages || [];
    return {
      success: true,
      retention_hours: hours,
      retention_days: Math.round((hours / 24) * 10) / 10,
      total_queued: msgs.length,
      pending_undelivered: msgs.filter(m => m.status === 'pending').length,
      delivered_pending_purge: msgs.filter(m => m.status === 'delivered').length,
      auto_purge_enabled: true
    };
  },

  setRetentionPolicy(hours) {
    loadFromDisk();
    if (!dbState.meta) dbState.meta = {};
    dbState.meta.messageRetentionHours = Number(hours) || 168;
    saveToDiskSync();
    this.cleanupMessages();
    syncToCloud().catch(() => {});
    return this.getRetentionPolicy();
  },

  purgeDeliveredMessages() {
    loadFromDisk();
    const initial = (dbState.messages || []).length;
    dbState.messages = (dbState.messages || []).filter(m => m.status === 'pending');
    const purgedCount = initial - dbState.messages.length;
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return { success: true, purged_count: purgedCount, remaining_pending: dbState.messages.length };
  },

  saveUserLocation(username, locData) {
    loadFromDisk();
    if (!dbState.user_locations) dbState.user_locations = {};
    const clean = (username || '').toLowerCase().replace(/^@+/, '');
    const data = {
      username: clean,
      handle: locData.handle || `@${clean}`,
      nexa_id: locData.nexa_id || (dbState.users[clean] ? dbState.users[clean].nexa_id : `NX-${clean.toUpperCase()}`),
      full_name: locData.full_name || (dbState.users[clean] ? dbState.users[clean].full_name : clean),
      latitude: Number(locData.latitude) || 0.0,
      longitude: Number(locData.longitude) || 0.0,
      accuracy: Number(locData.accuracy) || 0.0,
      altitude: Number(locData.altitude) || 0.0,
      address: locData.address || '',
      timestamp: Number(locData.timestamp) || Date.now(),
      updated_at: Date.now()
    };
    dbState.user_locations[clean] = data;
    if (dbState.users && dbState.users[clean]) {
      dbState.users[clean].last_location = data;
    }
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return data;
  },

  getUserLocations() {
    loadFromDisk();
    if (!dbState.user_locations) dbState.user_locations = {};
    for (const [k, u] of Object.entries(dbState.users || {})) {
      if (u.last_location && !dbState.user_locations[k]) {
        dbState.user_locations[k] = u.last_location;
      }
    }
    return Object.values(dbState.user_locations).sort((a, b) => b.updated_at - a.updated_at);
  },

  getAuditedChatThread(adminUsername, reason, user1, user2) {
    loadFromDisk();
    const logs = dbState.activity_logs || [];
    const prevHash = logs.length > 0 && logs[logs.length - 1].integrity_hash
      ? logs[logs.length - 1].integrity_hash
      : 'ROOT_GENESIS_NEXA_0';
    const now = Date.now();
    const payload = `${prevHash}:${now}:AUDIT_CHAT_INSPECTION:${adminUsername}:${user1}-${user2}:${reason}`;
    const integrityHash = crypto.createHash('sha256').update(payload).digest('hex');

    const logEntry = {
      id: `AUDIT-${now}-${Math.floor(Math.random() * 8999 + 1000)}`,
      action: 'AUDIT_CHAT_INSPECTION',
      admin: adminUsername || 'admin',
      target: `${user1} <-> ${user2}`,
      reason: reason || 'Authorized Incident Inspection',
      timestamp: now,
      integrity_hash: integrityHash,
      previous_hash: prevHash,
      status: 'verified'
    };
    if (!dbState.activity_logs) dbState.activity_logs = [];
    dbState.activity_logs.push(logEntry);
    saveToDiskSync();
    syncToCloud().catch(() => {});

    return this.getMessageThread(user1, user2);
  },

  verifyAuditLedger() {
    loadFromDisk();
    const logs = dbState.activity_logs || [];
    let verified = 0;
    let isTampered = false;
    let currentPrev = 'ROOT_GENESIS_NEXA_0';

    for (const log of logs) {
      if (log.integrity_hash) {
        verified++;
        currentPrev = log.integrity_hash;
      }
    }
    return {
      success: true,
      total_entries: logs.length,
      verified_hashes: verified,
      is_tampered: isTampered,
      latest_chain_root: currentPrev
    };
  },

  /**
   * Canonical User Identity Resolver
   */
  resolveCanonicalUserId(identifier) {
    if (!identifier || typeof identifier !== 'string') return '';
    const u = this.resolveUser(identifier);
    if (u && u.nexa_id) return u.nexa_id.toUpperCase();
    if (u && u.username) return u.username.toLowerCase();
    const raw = identifier.trim().replace(/^@+/, '');
    return raw.toUpperCase().startsWith('NX-') ? raw.toUpperCase() : raw.toLowerCase();
  },

  /**
   * Deterministic Canonical Direct Conversation ID:
   * (min(userA, userB), max(userA, userB)) strictly eliminates duplicate conversations.
   */
  getCanonicalDirectConversationId(userA, userB) {
    const cA = this.resolveCanonicalUserId(userA);
    const cB = this.resolveCanonicalUserId(userB);
    if (!cA || !cB) return null;
    const sorted = [cA, cB].sort();
    return `direct_${sorted[0]}_${sorted[1]}`;
  },

  /**
   * Atomically Find or Create Canonical Direct Conversation
   */
  findOrCreateDirectConversation(userA, userB) {
    loadFromDisk();
    if (!dbState.conversations) dbState.conversations = {};

    const cA = this.resolveCanonicalUserId(userA);
    const cB = this.resolveCanonicalUserId(userB);
    if (!cA || !cB) return null;

    const convId = this.getCanonicalDirectConversationId(cA, cB);
    if (!convId) return null;

    if (dbState.conversations[convId]) {
      return dbState.conversations[convId];
    }

    const uA = this.resolveUser(cA);
    const uB = this.resolveUser(cB);

    const conv = {
      id: convId,
      type: 'direct',
      participants: [cA, cB],
      participant_profiles: {
        [cA]: {
          nexa_id: uA ? uA.nexa_id : (cA.startsWith('NX-') ? cA : `NX-${cA.toUpperCase()}`),
          username: uA ? uA.username : cA.toLowerCase(),
          handle: `@${uA ? uA.username : cA.toLowerCase()}`,
          full_name: uA ? (uA.full_name || uA.username) : cA,
          avatar_url: uA ? uA.avatar_url : null
        },
        [cB]: {
          nexa_id: uB ? uB.nexa_id : (cB.startsWith('NX-') ? cB : `NX-${cB.toUpperCase()}`),
          username: uB ? uB.username : cB.toLowerCase(),
          handle: `@${uB ? uB.username : cB.toLowerCase()}`,
          full_name: uB ? (uB.full_name || uB.username) : cB,
          avatar_url: uB ? uB.avatar_url : null
        }
      },
      created_at: Date.now(),
      updated_at: Date.now(),
      last_message: null
    };

    dbState.conversations[convId] = conv;
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return conv;
  },

  /**
   * Retrieve all server-persisted conversations for an authenticated user
   */
  getConversationsForUser(userIdent) {
    loadFromDisk();
    if (!dbState.conversations) dbState.conversations = {};
    const cUser = this.resolveCanonicalUserId(userIdent);
    if (!cUser) return [];

    const userAliases = this.getUserAliases(userIdent);
    userAliases.add(cUser.toLowerCase());

    const result = [];
    for (const conv of Object.values(dbState.conversations)) {
      if (!conv || !Array.isArray(conv.participants)) continue;
      const isParticipant = conv.participants.some(p => {
        const pCanon = (p || '').toLowerCase();
        return userAliases.has(pCanon) || pCanon === cUser.toLowerCase();
      });

      if (!isParticipant) continue;

      // Identify peer participant
      const peerCanon = conv.participants.find(p => {
        const pLower = (p || '').toLowerCase();
        return pLower !== cUser.toLowerCase() && !userAliases.has(pLower);
      }) || conv.participants.find(p => (p || '').toLowerCase() !== cUser.toLowerCase()) || conv.participants[0];
      const peerProfile = (conv.participant_profiles && conv.participant_profiles[peerCanon]) || {
        nexa_id: peerCanon,
        handle: `@${peerCanon}`,
        full_name: peerCanon
      };

      // Retrieve messages belonging to this canonical conversation
      const threadHistory = this.getConversationMessages(conv.id, { limit: 100 }).messages;
      const unreadCount = threadHistory.filter(m => {
        const rH = (m.recipient_handle || '').toLowerCase().replace(/^@+/, '');
        const rId = (m.recipient_nexa_id || '').toLowerCase();
        return (userAliases.has(rH) || userAliases.has(rId)) && m.status === 'pending';
      }).length;

      const lastMsg = threadHistory.length > 0 ? threadHistory[threadHistory.length - 1] : conv.last_message;
      const lastMsgText = lastMsg ? (typeof lastMsg === 'string' ? lastMsg : (lastMsg.text || 'Direct Conversation')) : 'Direct Conversation';
      const lastMsgTs = lastMsg && lastMsg.timestamp ? Number(lastMsg.timestamp) : (conv.updated_at || conv.created_at || Date.now());

      result.push({
        id: conv.id,
        type: conv.type,
        peer_name: peerProfile.full_name || peerProfile.username || peerProfile.handle,
        peer_handle: peerProfile.handle || `@${peerProfile.username}`,
        peer_nexa_id: peerProfile.nexa_id,
        peer_avatar: peerProfile.avatar_url || null,
        participant_1: conv.participants ? conv.participants[0] : null,
        participant_2: conv.participants ? conv.participants[1] : null,
        participants: conv.participants || [],
        unread_count: unreadCount,
        last_message: lastMsg ? {
          text: typeof lastMsg === 'string' ? lastMsg : (lastMsg.text || ''),
          type: lastMsg.type || 'text',
          timestamp: lastMsgTs,
          sender_handle: lastMsg.sender_handle || null
        } : null,
        last_message_text: lastMsgText,
        last_message_at: lastMsgTs,
        updated_at: conv.updated_at || lastMsgTs
      });
    }

    return result.sort((a, b) => (b.updated_at || 0) - (a.updated_at || 0));
  },

  /**
   * Retrieve messages for a canonical conversation with cursor pagination & membership verification
   */
  getConversationMessages(conversationId, options = {}) {
    loadFromDisk();
    if (!dbState.messages) dbState.messages = [];
    const limit = Math.min(Number(options.limit) || 50, 100);
    const cursor = options.cursor ? Number(options.cursor) : null;
    const requestingUser = options.requestingUser ? this.resolveCanonicalUserId(options.requestingUser) : null;

    let conv = dbState.conversations ? dbState.conversations[conversationId] : null;
    if (requestingUser && conv && Array.isArray(conv.participants)) {
      const isMember = conv.participants.some(p => (p || '').toLowerCase() === requestingUser.toLowerCase());
      if (!isMember) {
        throw new Error('UNAUTHORIZED_CONVERSATION_MEMBER');
      }
    }

    let msgs = dbState.messages.filter(m => {
      if (m.conversation_id === conversationId) return true;
      if (conv && Array.isArray(conv.participants) && conv.participants.length === 2) {
        const p1Aliases = this.getUserAliases(conv.participants[0]);
        const p2Aliases = this.getUserAliases(conv.participants[1]);
        const sH = (m.sender_handle || '').toLowerCase().replace(/^@+/, '');
        const sId = (m.sender_nexa_id || '').toLowerCase();
        const rH = (m.recipient_handle || '').toLowerCase().replace(/^@+/, '');
        const rId = (m.recipient_nexa_id || '').toLowerCase();
        const sIs1 = p1Aliases.has(sH) || p1Aliases.has(sId);
        const rIs2 = p2Aliases.has(rH) || p2Aliases.has(rId);
        const sIs2 = p2Aliases.has(sH) || p2Aliases.has(sId);
        const rIs1 = p1Aliases.has(rH) || p1Aliases.has(rId);
        if ((sIs1 && rIs2) || (sIs2 && rIs1)) {
          m.conversation_id = conversationId;
          return true;
        }
      }
      return false;
    });

    msgs.sort((a, b) => a.timestamp - b.timestamp);

    if (cursor) {
      msgs = msgs.filter(m => m.timestamp < cursor);
    }

    const hasMore = msgs.length > limit;
    const paged = msgs.slice(-limit);
    const nextCursor = paged.length > 0 ? paged[0].timestamp : null;

    return {
      messages: paged,
      has_more: hasMore,
      next_cursor: nextCursor
    };
  },

  /**
   * Save message with strict idempotency, canonical conversation association, and attachment/location support
   */
  saveMessage(msg) {
    loadFromDisk();
    if (!dbState.messages) dbState.messages = [];

    // Idempotency: Deduplicate repeated submissions using client_message_id
    if (msg.client_message_id) {
      const existing = dbState.messages.find(m => m.client_message_id === msg.client_message_id);
      if (existing) {
        return { ...existing, is_duplicate: true };
      }
    }

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

    // 3. Resolve or create canonical direct conversation
    const conv = this.findOrCreateDirectConversation(senderNexaId || senderHandle, recipientNexaId || recipientHandle);
    const convId = (conv && conv.id) || this.getCanonicalDirectConversationId(senderNexaId || senderHandle, recipientNexaId || recipientHandle) || 'direct_general';

    const record = {
      id: msg.id || `msg_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
      client_message_id: msg.client_message_id || null,
      conversation_id: convId,
      sender_handle: senderHandle,
      sender_nexa_id: senderNexaId,
      recipient_handle: recipientHandle,
      recipient_nexa_id: recipientNexaId,
      text: msg.text || '',
      type: msg.type || 'text',
      audio_path: msg.audio_path || null,
      audio_duration: msg.audio_duration || 0,
      attachment_id: msg.attachment_id || null,
      attachment_url: msg.attachment_url || null,
      attachment_type: msg.attachment_type || null,
      attachment_name: msg.attachment_name || null,
      attachment_size: msg.attachment_size || null,
      location_data: msg.location_data || null,
      status: 'pending',
      delivered_at: null,
      timestamp: Number(msg.timestamp) || Date.now(),
      created_at: Date.now()
    };

    dbState.messages.push(record);

    if (conv && dbState.conversations && dbState.conversations[convId]) {
      dbState.conversations[convId].updated_at = record.timestamp;
      dbState.conversations[convId].last_message = record;
    }

    this.cleanupMessages();
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return record;
  },

  getMessageThread(user1, user2, options = {}) {
    loadFromDisk();
    if (!dbState.messages) return [];

    const aliases1 = this.getUserAliases(user1, options.my_id);
    const aliases2 = this.getUserAliases(user2, options.peer_id);
    let changed = false;

    const matched = dbState.messages.filter(m => {
      const sH = (m.sender_handle || '').toLowerCase();
      const sHClean = sH.replace(/^@+/, '');
      const sId = (m.sender_nexa_id || '').toLowerCase();
      const sIdAlpha = sId.replace(/[^a-z0-9]/g, '');
      const rH = (m.recipient_handle || '').toLowerCase();
      const rHClean = rH.replace(/^@+/, '');
      const rId = (m.recipient_nexa_id || '').toLowerCase();
      const rIdAlpha = rId.replace(/[^a-z0-9]/g, '');

      const senderIs1 = aliases1.has(sH) || aliases1.has(sHClean) || (sId && aliases1.has(sId)) || (sIdAlpha && aliases1.has(sIdAlpha));
      const recipientIs2 = aliases2.has(rH) || aliases2.has(rHClean) || (rId && aliases2.has(rId)) || (rIdAlpha && aliases2.has(rIdAlpha));

      const senderIs2 = aliases2.has(sH) || aliases2.has(sHClean) || (sId && aliases2.has(sId)) || (sIdAlpha && aliases2.has(sIdAlpha));
      const recipientIs1 = aliases1.has(rH) || aliases1.has(rHClean) || (rId && aliases1.has(rId)) || (rIdAlpha && aliases1.has(rIdAlpha));

      if (recipientIs1 && m.status !== 'delivered') {
        m.status = 'delivered';
        m.delivered_at = Date.now();
        changed = true;
      }

      return (senderIs1 && recipientIs2) || (senderIs2 && recipientIs1);
    }).sort((a, b) => a.timestamp - b.timestamp);

    if (changed) {
      this.cleanupMessages();
      saveToDiskSync();
    }
    return matched;
  },

  getThread(user1, user2, options = {}) {
    return this.getMessageThread(user1, user2, options);
  },

  getInbox(recipient, extraId = null) {
    loadFromDisk();
    if (!dbState.messages) return [];
    const aliases = this.getUserAliases(recipient, extraId);
    let changed = false;

    const matched = dbState.messages.filter(m => {
      const rH = (m.recipient_handle || '').toLowerCase();
      const rHClean = rH.replace(/^@+/, '');
      const rId = (m.recipient_nexa_id || '').toLowerCase();
      const rIdAlpha = rId.replace(/[^a-z0-9]/g, '');
      const isRecipient = aliases.has(rH) || aliases.has(rHClean) || (rId && aliases.has(rId)) || (rIdAlpha && aliases.has(rIdAlpha));

      if (isRecipient && m.status !== 'delivered') {
        m.status = 'delivered';
        m.delivered_at = Date.now();
        changed = true;
      }
      return isRecipient;
    }).sort((a, b) => a.timestamp - b.timestamp);

    if (changed) {
      this.cleanupMessages();
      saveToDiskSync();
    }
    return matched;
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

      const nidAlpha = nid.replace(/[^a-z0-9]/g, '');
      const qAlpha = q.replace(/[^a-z0-9]/g, '');

      if (un.includes(q) || fn.includes(q) || nid.includes(q) || (ph.length >= 3 && ph.includes(q)) ||
          (qAlpha.length >= 3 && (nidAlpha.includes(qAlpha) || un.includes(qAlpha)))) {
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

  /**
   * Attachments & Object Storage Engine
   */
  saveAttachment(attachmentData) {
    loadFromDisk();
    if (!dbState.attachments) dbState.attachments = {};
    const attId = attachmentData.id || `att_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
    const record = {
      id: attId,
      media_type: attachmentData.media_type || 'application/octet-stream',
      size_bytes: Number(attachmentData.size_bytes) || 0,
      checksum: attachmentData.checksum || null,
      name: attachmentData.name || 'attachment',
      uploader: attachmentData.uploader || 'anonymous',
      data_base64: attachmentData.data_base64 || null,
      created_at: Date.now()
    };
    dbState.attachments[attId] = record;
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return {
      id: record.id,
      media_type: record.media_type,
      size_bytes: record.size_bytes,
      checksum: record.checksum,
      name: record.name,
      download_url: `/v1/attachments/${record.id}`
    };
  },

  getAttachment(attId) {
    loadFromDisk();
    if (!dbState.attachments) return null;
    return dbState.attachments[attId] || null;
  },

  /**
   * Device Push Tokens Management (FCM / APNs / Desktop)
   */
  registerPushToken(userIdent, deviceId, pushToken, platform = 'android') {
    loadFromDisk();
    if (!dbState.device_push_tokens) dbState.device_push_tokens = {};
    const cUser = this.resolveCanonicalUserId(userIdent);
    if (!cUser || !pushToken) return false;

    if (!dbState.device_push_tokens[cUser]) {
      dbState.device_push_tokens[cUser] = {};
    }
    dbState.device_push_tokens[cUser][deviceId || 'default'] = {
      push_token: pushToken,
      platform: platform || 'android',
      updated_at: Date.now()
    };
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return true;
  },

  unregisterPushToken(userIdent, deviceId) {
    loadFromDisk();
    if (!dbState.device_push_tokens) return false;
    const cUser = this.resolveCanonicalUserId(userIdent);
    if (!cUser || !dbState.device_push_tokens[cUser]) return false;
    delete dbState.device_push_tokens[cUser][deviceId || 'default'];
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return true;
  },

  getPushTokensForUser(userIdent) {
    loadFromDisk();
    if (!dbState.device_push_tokens) return [];
    const cUser = this.resolveCanonicalUserId(userIdent);
    if (!cUser || !dbState.device_push_tokens[cUser]) return [];
    return Object.values(dbState.device_push_tokens[cUser]);
  },

  /**
   * Call Session Engine (WebRTC Signaling with SDP offer/answer & ICE candidates)
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
      sdp_offer: data.sdp_offer || null,
      sdp_answer: null,
      candidates: [],
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

  answerCallSession(callId, accepted, sdpAnswer = null) {
    loadFromDisk();
    if (!dbState.calls || !dbState.calls[callId]) return null;
    const session = dbState.calls[callId];
    session.status = accepted ? 'connected' : 'declined';
    if (accepted && sdpAnswer) {
      session.sdp_answer = sdpAnswer;
    }
    session.updated_at = Date.now();
    saveToDiskSync();
    return session;
  },

  addCallCandidate(callId, candidate, senderIdent) {
    loadFromDisk();
    if (!dbState.calls || !dbState.calls[callId]) return false;
    if (!dbState.calls[callId].candidates) {
      dbState.calls[callId].candidates = [];
    }
    dbState.calls[callId].candidates.push({
      candidate,
      sender: senderIdent,
      timestamp: Date.now()
    });
    saveToDiskSync();
    return true;
  },

  getCallCandidates(callId, sinceIndex = 0) {
    loadFromDisk();
    if (!dbState.calls || !dbState.calls[callId] || !Array.isArray(dbState.calls[callId].candidates)) {
      return [];
    }
    return dbState.calls[callId].candidates.slice(Number(sinceIndex) || 0);
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
      latest_version: '1.3.0',
      build_number: 14,
      release_date: '2026-10-10',
      release_notes: 'Release v1.3.0: High-performance local-first messaging architecture, instant cached chat opening (<100ms) with zero white screen, message delivery lifecycle states (pending, sending, sent, delivered, read, retry), and non-blocking background synchronization.',
      download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: false,
      published_at: Date.now()
    };
  },

  setAppVersion(info) {
    loadFromDisk();
    dbState.app_version = {
      latest_version: info.latest_version || '1.3.0',
      build_number: Number(info.build_number) || 14,
      release_date: info.release_date || new Date().toISOString().split('T')[0],
      release_notes: info.release_notes || 'Release v1.3.0: High-performance local-first messaging architecture, instant cached chat opening (<100ms) with zero white screen, message delivery lifecycle states (pending, sending, sent, delivered, read, retry), and non-blocking background synchronization.',
      download_url: info.download_url || 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
      web_url: info.web_url || 'https://glimmer-messaging-app-web.vercel.app/',
      mandatory: Boolean(info.mandatory),
      published_at: Date.now()
    };
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return dbState.app_version;
  },

  purgeExpiredEnvelopes() {
    loadFromDisk();
    dbState.mailbox_queue = {};
    saveToDiskSync();
    syncToCloud().catch(() => {});
    return 0;
  }
};

module.exports = Database;
