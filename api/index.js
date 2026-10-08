/**
 * Vercel Serverless Gateway for NEXA Relay API
 * 
 * Executes the embedded Express serverless engine directly on Vercel with persistent database support.
 * Standalone sovereign operation without external proxies or tunnels.
 */

const { app } = require('../backend/server.js');

module.exports = (req, res) => {
  return app(req, res);
};
