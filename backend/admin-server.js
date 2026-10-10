/**
 * NEXA dedicated administrator gateway.
 *
 * The dashboard can run on its own port, but it deliberately reuses the
 * production admin router.  Keeping a second, partial set of handlers here
 * previously meant the portal displayed controls (retention, GPS, and audit
 * tools) that only worked when it was served through the main relay.
 */

const express = require('express');
const path = require('path');
const Database = require('./database/db');
const { router: adminRouter } = require('./routes/admin');

const app = express();
const ADMIN_PORT = Number(process.env.ADMIN_PORT) || 8081;
const adminPublicDir = path.join(__dirname, 'public/admin');

app.use(express.json({ limit: '10mb' }));

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-admin-master-key');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  return next();
});

app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on('finish', () => {
    if (req.path.startsWith('/v1/admin')) {
      console.log(`[ADMIN ACCESS] ${req.method} ${req.path} -> ${res.statusCode} (${Date.now() - startedAt}ms) [${req.ip}]`);
    }
  });
  next();
});

// One router powers the main relay, Vercel function, and dedicated portal.
// This keeps every control exposed by the UI available at :8081 as well.
app.use(adminRouter);

app.get('/health', (req, res) => {
  const dbStatus = Database.getStatus();
  res.json({
    status: 'healthy',
    service: 'nexa-admin-portal',
    port: ADMIN_PORT,
    database_connected: true,
    registered_users_count: dbStatus.users_count,
    db_status: dbStatus
  });
});

// Serve both the dedicated root URL and /admin so absolute dashboard assets
// resolve identically in local, relay, and hosted deployments.
app.use('/admin', express.static(adminPublicDir));
app.use(express.static(adminPublicDir));

app.get('*', (req, res) => {
  res.sendFile(path.join(adminPublicDir, 'index.html'));
});

if (require.main === module) {
  app.listen(ADMIN_PORT, '0.0.0.0', () => {
    console.log('================================================================');
    console.log('  NEXA SOVEREIGN ADMIN PORTAL ONLINE');
    console.log(`  Dedicated Port: http://0.0.0.0:${ADMIN_PORT}`);
    console.log('  Security Mode : Master Key Protected');
    console.log('================================================================');
  });
}

module.exports = app;
