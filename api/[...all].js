/**
 * Catch-All Vercel Serverless Function for all API and Relay Endpoints
 * 
 * Handles /api/*, /v1/*, and administrative routes seamlessly on Vercel.
 */

const { app } = require('../backend/server.js');

module.exports = (req, res) => {
  return app(req, res);
};
