/**
 * Vercel Serverless Gateway for NEXA Relay API
 * 
 * Provides unified, high-availability API execution on Vercel:
 * 1. If BACKEND_URL environment variable is configured, transparently forwards requests.
 * 2. Otherwise, executes the embedded Express serverless engine directly on Vercel with persistent database support.
 */

const { app } = require('../backend/server.js');
const http = require('http');
const https = require('https');

module.exports = async (req, res) => {
  const externalBackend = process.env.BACKEND_URL;

  if (externalBackend && !req.headers['x-nexa-forwarded']) {
    let proxied = false;
    await new Promise((resolve) => {
      try {
        const targetUrl = new URL(req.url, externalBackend);
        const isHttps = targetUrl.protocol === 'https:';
        const client = isHttps ? https : http;

        const proxyReq = client.request(targetUrl, {
          method: req.method,
          headers: {
            ...req.headers,
            host: targetUrl.host,
            'x-nexa-forwarded': 'true'
          },
          timeout: 1500
        }, (proxyRes) => {
          if (proxyRes.statusCode >= 500) {
            console.warn('[Vercel Gateway] External backend returned ' + proxyRes.statusCode + ', falling back to embedded engine');
            return resolve();
          }
          proxied = true;
          res.writeHead(proxyRes.statusCode, proxyRes.headers);
          proxyRes.pipe(res);
          proxyRes.on('end', resolve);
        });

        proxyReq.on('timeout', () => {
          proxyReq.destroy();
          console.warn('[Vercel Gateway] BACKEND_URL timeout (1.5s), falling back to embedded engine');
          resolve();
        });

        proxyReq.on('error', (err) => {
          console.warn('[Vercel Gateway] Forwarding failed (' + err.message + '), falling back to embedded engine');
          resolve();
        });

        if (req.body && (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH')) {
          const payload = typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
          proxyReq.write(payload);
        }
        proxyReq.end();
      } catch (err) {
        console.warn('[Vercel Gateway] Proxy setup error:', err.message);
        resolve();
      }
    });

    if (proxied) return;
  }

  // Autonomous serverless execution on Vercel
  return app(req, res);
};
