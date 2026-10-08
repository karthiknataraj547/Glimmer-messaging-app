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
        }
      }, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
      });

      proxyReq.on('error', (err) => {
        console.warn('[Vercel Gateway] Forwarding to BACKEND_URL failed, falling back to embedded engine:', err.message);
        return app(req, res);
      });

      if (req.body && (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH')) {
        const payload = typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
        proxyReq.write(payload);
      }
      proxyReq.end();
      return;
    } catch (err) {
      console.warn('[Vercel Gateway] Forwarding error, falling back to embedded engine:', err.message);
    }
  }

  // Autonomous serverless execution
  return app(req, res);
};
