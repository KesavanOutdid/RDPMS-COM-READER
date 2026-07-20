const express = require('express');
const router  = express.Router();
const db      = require('../core/db');

// ── Health check ──
router.get('/health', (req, res) => {
  res.json({ success: true, message: 'RDPMS DB Backend running', uptime: process.uptime() });
});

// ── Save test record ──
// Body: { serialNumber, paramType, paramValue, result, timestamp }
router.post('/tests', async (req, res) => {
  const { serialNumber } = req.body;

  if (!serialNumber) {
    return res.status(400).json({ success: false, error: 'serialNumber is required' });
  }

  try {
    const saved = await db.saveTest(req.body);
    res.status(201).json({ success: true, record: saved });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── Fetch paginated test records ──
// Query: ?serialNumber=...&startDate=...&endDate=...&limit=...&cursor=...
router.get('/tests', async (req, res) => {
  const { serialNumber, startDate, endDate, limit, cursor } = req.query;

  try {
    const data = await db.getTests({
      serialNumber,
      startDate,
      endDate,
      limit,
      cursor
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── Fetch unique serial numbers ──
router.get('/tests/serial-numbers', async (req, res) => {
  try {
    const serialNumbers = await db.getUniqueSerialNumbers();
    res.json({ success: true, serialNumbers });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = () => router;