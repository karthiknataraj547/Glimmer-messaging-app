/**
 * NEXA Dedicated Admin API Router
 * 
 * Exposes administrative endpoints for database inspection, user status management,
 * PIN resets, security audit logs, mailbox queue purging, and app update management.
 * Works uniformly in standalone Express, dedicated admin portal, and Vercel serverless.
 */

const express = require('express');
const crypto = require('crypto');
const Database = require('./db');

const router = express.Router();
const ADMIN_MASTER_KEY = process.env.ADMIN_MASTER_KEY || 'nexa_admin_master_secret_2026';

// Active administrator sessions (Token -> session data)
const adminSessions = new Map();

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
router.post('/v1/admin/login', async (req, res) => {
  let { username, password, adminKey, pin, masterKey } = req.body || {};
  if (!adminKey && masterKey) adminKey = masterKey;
  if (!password && pin) password = pin;
  if (!username && password) username = 'admin';

  // Master Key unlock (accepts via adminKey, masterKey, or password field)
  if ((adminKey && adminKey === ADMIN_MASTER_KEY) || (password && password === ADMIN_MASTER_KEY)) {
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
      details: 'Administrator authenticated via Master Key',
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
      details: 'Unauthorized admin panel access attempt',
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
    details: 'Administrator authenticated successfully',
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
router.get('/v1/admin/overview', adminAuthMiddleware, (req, res) => {
  const metrics = Database.getSystemMetrics(0);
  res.json({
    success: true,
    metrics: {
      ...metrics,
      timestamp: new Date().toISOString()
    }
  });
});

// --------------------------------------------------------------------------
// 3. User Database Inspection
// --------------------------------------------------------------------------
router.get('/v1/admin/users', adminAuthMiddleware, (req, res) => {
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
router.post('/v1/admin/users/status', adminAuthMiddleware, (req, res) => {
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
    details: `User status changed to ${status} via admin panel`,
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
router.post('/v1/admin/users/reset-pin', adminAuthMiddleware, (req, res) => {
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
router.delete('/v1/admin/users/:username', adminAuthMiddleware, (req, res) => {
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
router.get('/v1/admin/activity', adminAuthMiddleware, (req, res) => {
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
router.post('/v1/admin/purge-queue', adminAuthMiddleware, (req, res) => {
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

// --------------------------------------------------------------------------
// 9. Application Releases & Update Engine
// --------------------------------------------------------------------------
router.get(['/v1/app/version', '/v1/app/check-update'], (req, res) => {
  const versionInfo = Database.getAppVersion();
  res.json({
    success: true,
    ...versionInfo
  });
});

router.post('/v1/admin/app/push-update', adminAuthMiddleware, (req, res) => {
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

  Database.logActivity({
    type: 'admin',
    action: 'app_update_published',
    target: `v${updated.latest_version}+${updated.build_number}`,
    actor: req.adminUser.username,
    details: `Published application update v${updated.latest_version}+${updated.build_number}`,
    ip: req.ip
  });

  res.json({
    success: true,
    message: `Application update v${updated.latest_version}+${updated.build_number} published successfully.`,
    app_version: updated
  });
});

module.exports = { router, adminSessions, adminAuthMiddleware };
