/**
 * Vercel Serverless Gateway for NEXA Relay & Sovereign Admin API
 * 
 * Exports the Express app instance directly for Vercel Serverless execution.
 */

const { app } = require('../backend/server.js');

module.exports = app;
