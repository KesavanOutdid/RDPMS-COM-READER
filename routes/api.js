const express = require('express');
const { connectToPort, disconnectFromPort, sendData, getActiveConnections } = require('../core/portManager');

const router = express.Router();

// GET /api/ports - List active connections
router.get('/ports', (req, res) => {
  res.json({ activePorts: getActiveConnections() });
});

// POST /api/connect - Connect to a port
router.post('/connect', (req, res) => {
  const { port } = req.body;
  if (!port) {
    return res.status(400).json({ error: 'Port is required' });
  }
  // Note: For REST, we might not emit to io here, but since it's a POC, perhaps keep simple
  // Actually, since it's socket-based, maybe REST is not primary, but for completeness
  res.json({ message: 'Use socket for connection' });
});

// POST /api/disconnect - Disconnect from a port
router.post('/disconnect', (req, res) => {
  const { port } = req.body;
  const result = disconnectFromPort(port);
  res.json(result);
});

// POST /api/send - Send data to a port
router.post('/send', (req, res) => {
  const { port, data } = req.body;
  const result = sendData(port, data);
  res.json(result);
});

module.exports = router;