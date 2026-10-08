/**
 * Dedicated Vercel Serverless Function for /health endpoint
 */

const { app } = require('../backend/server.js');

module.exports = (req, res) => {
  return app(req, res);
};
