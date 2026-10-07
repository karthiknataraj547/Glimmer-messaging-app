/**
 * ============================================================================
 * NEXA DEDICATED SOVEREIGN ADMIN GATEWAY
 * ============================================================================
 * Independent, highly-secure Administrative Control Server.
 * Runs on a dedicated port (default: 8081) with its own isolated tunnel link,
 * serving the Admin Dashboard directly at root (/) and providing full control
 * over the user database, account statuses, PIN resets, and audit activity.
 * ============================================================================
 */

const express = require('express');
const path = require('path');
const crypto = require('crypto');
const Database = require('./database/db');

const app = express();
const ADMIN_PORT = process.env.ADMIN_PORT || 8081;
const ADMIN_MASTER_KEY = process.env.ADMIN_MASTER_KEY || 'nexa_admin_master_secret_2026';

// Active administrator sessions (Token -> session data)
const adminSessions = new Map();

app.use(express.json());

// CORS Middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-admin-master-key');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// Request logger for admin audit
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (req.path.startsWith('/v1/admin')) {
      console.log(`[ADMIN ACCESS] ${req.method} ${req.path} -> ${res.statusCode} (${duration}ms) [${req.ip}]`);
    }
  });
  next();
});

// Helper to sanitize usernames
function sanitizeUsername(username) {
  if (!username) return null;
  return username.trim().replace(/^@+/, '').toLowerCase();
}

/**
 * High-Security Admin Authentication Middleware
 */
function adminAuthMiddleware(req, res, next) {
  const authHeader = req.headers['authorization'];
  const masterKeyHeader = req.headers['x-admin-master-key'];

  // Option A: Direct Master Key bypass
  if (masterKeyHeader && masterKeyHeader === ADMIN_MASTER_KEY) {
    req.adminUser = { username: 'admin', role: 'admin', isMaster: true };
    return next();
  }

  // Option B: Bearer Session Token
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.substring(7).trim();
    const session = adminSessions.get(token);
    if (session) {
      if (Date.now() > session.expires_at) {
        adminSessions.delete(token);
        return res.status(401).json({ error: 'Admin session expired. Please re-authenticate.' });
      }
      req.adminUser = session;
      return next();
    }
  }

  return res.status(401).json({ error: 'Unauthorized: Master Administrator authentication required.' });
}

// --------------------------------------------------------------------------
// 1. Admin Authentication Endpoint
// --------------------------------------------------------------------------
app.post('/v1/admin/login', async (req, res) => {
  let { username, password, adminKey, pin, masterKey } = req.body || {};
  if (!adminKey && masterKey) adminKey = masterKey;
  if (!password && pin) password = pin;
  if (!username && password) username = 'admin';

  // Master Key unlock
  if (adminKey && adminKey === ADMIN_MASTER_KEY) {
    const token = `NX-ADM-${crypto.randomBytes(16).toString('hex')}`;
    adminSessions.set(token, {
      username: 'admin',
      role: 'admin',
      created_at: Date.now(),
      expires_at: Date.now() + 24 * 60 * 60 * 1000
    });
    Database.logActivity({ 
      type: 'admin', 
      action: 'admin_login', 
      target: 'admin', 
      actor: 'admin', 
      details: 'Administrator authenticated via Master Key on dedicated portal',
      ip: req.ip
    });
    return res.json({ 
      success: true, 
      token, 
      admin: { username: 'admin', handle: '@admin', fullName: 'System Administrator', role: 'admin' } 
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
      details: 'Unauthorized admin panel access attempt on dedicated portal',
      ip: req.ip
    });
    return res.status(403).json({ error: 'Access denied: User does not have administrative rights.' });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  if (user.password_hash !== passwordHash) {
    Database.logActivity({ 
      type: 'security', 
      action: 'admin_login_failed', 
      target: clean, 
      actor: clean, 
      details: 'Incorrect password for administrator account',
      ip: req.ip
    });
    return res.status(401).json({ error: 'Invalid administrator credentials.' });
  }

  // Issue 24-hour admin session token
  const token = `NX-ADM-${crypto.randomBytes(16).toString('hex')}`;
  adminSessions.set(token, {
    username: user.username,
    role: user.role || 'admin',
    created_at: Date.now(),
    expires_at: Date.now() + 24 * 60 * 60 * 1000
  });

  Database.logActivity({ 
    type: 'admin', 
    action: 'admin_login', 
    target: clean, 
    actor: clean, 
    details: 'Administrator authenticated successfully on dedicated portal',
    ip: req.ip
  });

  res.json({
    success: true,
    token,
    admin: {
      username: user.username,
      handle: user.handle,
      fullName: user.full_name || 'System Administrator',
      role: user.role || 'admin'
    }
  });
});

// --------------------------------------------------------------------------
// 2. Admin System Telemetry & Metrics
// --------------------------------------------------------------------------
app.get('/v1/admin/overview', adminAuthMiddleware, (req, res) => {
  const metrics = Database.getSystemMetrics(0);
  res.json({
    success: true,
    metrics: {
      ...metrics,
      admin_port: ADMIN_PORT,
      dedicated_portal: true,
      timestamp: new Date().toISOString()
    }
  });
});

// --------------------------------------------------------------------------
// 3. User Database Inspection
// --------------------------------------------------------------------------
app.get('/v1/admin/users', adminAuthMiddleware, (req, res) => {
  const users = Database.getUsersDetailed();
  res.json({
    success: true,
    count: users.length,
    users
  });
});

// --------------------------------------------------------------------------
// 4. User Status Management (Suspend / Reactivate)
// --------------------------------------------------------------------------
app.post('/v1/admin/users/status', adminAuthMiddleware, (req, res) => {
  const { username, status } = req.body || {};
  const clean = sanitizeUsername(username);

  if (!clean || !['active', 'suspended'].includes(status)) {
    return res.status(400).json({ error: 'Invalid username or status. Status must be "active" or "suspended".' });
  }

  if (clean === 'admin') {
    return res.status(400).json({ error: 'Cannot modify primary root administrator account status.' });
  }

  const updated = Database.updateUserStatus(clean, status);
  if (!updated) {
    return res.status(404).json({ error: `User @${clean} not found in database.` });
  }

  Database.logActivity({
    type: 'admin',
    action: status === 'suspended' ? 'user_suspended' : 'user_reactivated',
    target: clean,
    actor: req.adminUser.username,
    details: `User status changed to ${status} via dedicated admin panel`,
    ip: req.ip
  });

  res.json({
    success: true,
    username: clean,
    status,
    message: `User @${clean} status updated to ${status}.`
  });
});

// --------------------------------------------------------------------------
// 5. Remote PIN Reset
// --------------------------------------------------------------------------
app.post('/v1/admin/users/reset-pin', adminAuthMiddleware, (req, res) => {
  const { username, newPin } = req.body || {};
  const clean = sanitizeUsername(username);

  if (!clean || !newPin || String(newPin).length < 4) {
    return res.status(400).json({ error: 'Username and new PIN (minimum 4 characters) are required.' });
  }

  const success = Database.resetUserPin(clean, String(newPin));
  if (!success) {
    return res.status(404).json({ error: `User @${clean} not found in database.` });
  }

  Database.logActivity({
    type: 'admin',
    action: 'pin_reset',
    target: clean,
    actor: req.adminUser.username,
    details: `Administrator performed remote PIN reset for @${clean}`,
    ip: req.ip
  });

  res.json({
    success: true,
    username: clean,
    message: `PIN for @${clean} has been successfully updated.`
  });
});

// --------------------------------------------------------------------------
// 6. User Account Deletion
// --------------------------------------------------------------------------
app.delete('/v1/admin/users/:username', adminAuthMiddleware, (req, res) => {
  const clean = sanitizeUsername(req.params.username);

  if (!clean) {
    return res.status(400).json({ error: 'Valid username required.' });
  }

  if (clean === 'admin') {
    return res.status(403).json({ error: 'The primary root administrator account cannot be deleted.' });
  }

  const deleted = Database.deleteUser(clean);
  if (!deleted) {
    return res.status(404).json({ error: `User @${clean} not found in database.` });
  }

  Database.logActivity({
    type: 'admin',
    action: 'user_deleted',
    target: clean,
    actor: req.adminUser.username,
    details: `Permanently deleted user account @${clean} and associated device keys`,
    ip: req.ip
  });

  res.json({
    success: true,
    deletedUser: clean,
    message: `User @${clean} permanently removed from database.`
  });
});

// --------------------------------------------------------------------------
// 7. Security Audit & Activity Logs
// --------------------------------------------------------------------------
app.get('/v1/admin/activity', adminAuthMiddleware, (req, res) => {
  const limit = parseInt(req.query.limit, 10) || 100;
  const filterType = req.query.type || 'all';

  const logs = Database.getActivityLogs(limit, filterType);
  res.json({
    success: true,
    count: logs.length,
    logs
  });
});

// --------------------------------------------------------------------------
// 8. Mailbox Queue Purge
// --------------------------------------------------------------------------
app.post('/v1/admin/purge-queue', adminAuthMiddleware, (req, res) => {
  const purgedCount = Database.purgeExpiredEnvelopes();
  Database.logActivity({
    type: 'admin',
    action: 'queue_purged',
    target: 'mailbox_queue',
    actor: req.adminUser.username,
    details: `Purged ${purgedCount} expired envelopes from relay buffer`,
    ip: req.ip
  });

  res.json({
    success: true,
    purgedCount,
    message: `Successfully purged ${purgedCount} envelopes from relay memory.`
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'nexa-admin-portal', port: ADMIN_PORT });
});

// --------------------------------------------------------------------------
// 9. Host Web Admin Dashboard at Root (/)
// --------------------------------------------------------------------------
const adminPublicDir = path.join(__dirname, 'public/admin');
app.use(express.static(adminPublicDir));

// Fallback to index.html for SPA routing
app.get('*', (req, res) => {
  res.sendFile(path.join(adminPublicDir, 'index.html'));
});

// Start Dedicated Server
app.listen(ADMIN_PORT, '0.0.0.0', () => {
  console.log(`================================================================`);
  console.log(`  NEXA SOVEREIGN ADMIN PORTAL ONLINE`);
  console.log(`  Dedicated Port: http://0.0.0.0:${ADMIN_PORT}`);
  console.log(`  Security Mode : Master Key Protected`);
  console.log(`================================================================`);
});
