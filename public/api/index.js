/**
 * Vercel Serverless Function entry point in public/api/index.js
 */

const { app } = require('./server.js');

module.exports = (req, res) => {
  return app(req, res);
};
