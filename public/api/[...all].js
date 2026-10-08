/**
 * Vercel Serverless Function entry point in public/api/[...all].js
 */

const { app } = require('./server.js');

module.exports = (req, res) => {
  return app(req, res);
};
