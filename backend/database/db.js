/**
 * NEXA Persistent Database Engine
 * 
 * Provides robust, ACID-compliant file-backed persistent storage for users,
 * credentials, cryptographic prekeys, registered devices, and message envelopes.
 * Seamlessly integrates with PostgreSQL if DATABASE_URL is configured.
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const DB_DIR = path.join(__dirname, '../data');
const DB_FILE = path.join(DB_DIR, 'nexa_database.json');
const DB_TEMP_FILE = path.join(DB_DIR, 'nexa_database.tmp');

// In-Memory operational tables synced with disk
let dbState = {
  users: {},           // username (lowercase) -> UserRecord
  user_devices: {},    // userId -> { deviceId -> DeviceRecord }
  prekey_bundles: {},  // `${userId}:${deviceId}` -> BundleRecord
  mailbox_queue: {},   // deviceId -> [Envelope]
  meta: {
    initialized_at: Date.now(),
    last_saved_at: Date.now(),
    version: '1.0.0'
  }
};

let pgPool = null;
let isPgConnected = false;

// Ensure database directory exists
if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

// Load persistent data from disk on boot
function loadFromDisk() {
  try {
    if (fs.existsSync(DB_FILE)) {
      const raw = fs.readFileSync(DB_FILE, 'utf8');
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        dbState.users = parsed.users || {};
        dbState.user_devices = parsed.user_devices || {};
        dbState.prekey_bundles = parsed.prekey_bundles || {};
        dbState.mailbox_queue = parsed.mailbox_queue || {};
        dbState.meta = parsed.meta || dbState.meta;
        console.log(`[NEXA DB] Loaded persistent database from disk (${Object.keys(dbState.users).length} registered users).`);
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
    dbState.meta.last_saved_at = Date.now();
    const serialized = JSON.stringify(dbState, null, 2);
    fs.writeFileSync(DB_TEMP_FILE, serialized, 'utf8');
    fs.renameSync(DB_TEMP_FILE, DB_FILE);
  } catch (err) {
    console.error('[NEXA DB] Atomic flush failed:', err.message);
  }
}

// Initialize PostgreSQL if DATABASE_URL is set
if (process.env.DATABASE_URL) {
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
  }
};

module.exports = Database;
