const express = require('express');
const router  = express.Router();

module.exports = (canManager, portScanner) => {

  // ── Health check ──
  router.get('/health', (req, res) => {
    res.json({ success: true, message: 'CAN Backend running', uptime: process.uptime() });
  });

  // ── List available USB/serial ports ──
  router.get('/ports', async (req, res) => {
    try {
      const ports = await portScanner.listPorts();
      res.json({ success: true, ports });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // ── Connect to CAN device ──
  // Body: { port, channel, baudRate, mode, isFD, brs, nonISO }
  router.post('/connect', async (req, res) => {
    const { port, channel = 0, baudRate = 0x08, mode = 0, isFD = false, brs = false, nonISO = false } = req.body;

    if (!port) return res.status(400).json({ success: false, error: 'port is required' });

    try {
      const result = await canManager.connect(port, { channel, baudRate, mode, isFD, brs, nonISO });
      res.json(result);
    } catch (err) {
      res.status(500).json(err);
    }
  });

  // ── Disconnect from CAN device ──
  router.post('/disconnect', async (req, res) => {
    const { port } = req.body;
    if (!port) return res.status(400).json({ success: false, error: 'port is required' });

    try {
      const result = await canManager.disconnect(port);
      res.json(result);
    } catch (err) {
      res.status(500).json(err);
    }
  });

  // ── Send CAN TX frame ──
  // Body: { port, canId (decimal or hex string), data (array of bytes), channel, isExtended }
  router.post('/send', async (req, res) => {
    let { port, canId, data = [], channel = 0, isExtended = false } = req.body;

    if (!port || canId === undefined) {
      return res.status(400).json({ success: false, error: 'port and canId are required' });
    }

    // Accept canId as hex string like "0x321" or number
    if (typeof canId === 'string') {
      canId = parseInt(canId, canId.startsWith('0x') ? 16 : 10);
    }

    // Accept data as hex string array like ["AA","BB"] or number array
    data = data.map(b => typeof b === 'string' ? parseInt(b, 16) : b);

    try {
      const result = await canManager.sendFrame(port, { canId, data, channel, isExtended });
      res.json(result);
    } catch (err) {
      res.status(500).json(err);
    }
  });

  // ── Get status of one or all connections ──
  router.get('/status', (req, res) => {
    const status = canManager.getStatus();
    res.json({ success: true, connections: status, total: status.length });
  });

  router.get('/status/:port', (req, res) => {
    const port = decodeURIComponent(req.params.port);
    res.json({ success: true, ...canManager.getStatus(port) });
  });

  // ── Read buffered RX frames ──
  router.get('/read/:port', (req, res) => {
    const port   = decodeURIComponent(req.params.port);
    const frames = canManager.getRxFrames(port);
    res.json({ success: true, port, count: frames.length, frames });
  });

  return router;
};