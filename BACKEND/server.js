const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const PortScanner = require('./core/portScanner');
const CANManager  = require('./canManager');
const apiRoutes    = require('./routes/api');

const app = express();
const httpServer = http.createServer(app);
const io = new Server(httpServer, { cors: { origin: '*' } });

app.use(cors());
app.use(express.json());
app.use(express.static('.')); // Serve static files like index.html

// Initialize managers
const portScanner = new PortScanner(io);
const canManager  = new CANManager(io);

// Use API routes
app.use('/api', apiRoutes(canManager, portScanner));

// ─────────────────────────────────────────────────────
// AUTO-CONNECT: When USB device detected, automatically
// send CONNECT frame (0xA0) to initiate handshake
// ─────────────────────────────────────────────────────
// REMOVED: Auto-connect now handled by frontend via socket events

// Start port scanner
portScanner.start();

const { SERVER_PORT } = require('./config/default');
httpServer.listen(SERVER_PORT, () => {
  console.log(`\n🚀 CAN Backend: http://localhost:${SERVER_PORT}`);
  console.log(`\nSocket.io Real-Time Events:`);
  console.log(`  port_detected      → USB device plugged in`);
  console.log(`  port_removed       → USB device unplugged`);
  console.log(`  device_connected   → CAN device connected`);
  console.log(`  device_disconnected→ CAN device disconnected`);
  console.log(`  can_rx             → CAN frame received`);
  console.log(`  can_tx             → CAN frame sent`);
  console.log(`  heartbeat_sent     → Heartbeat sent`);
  console.log(`  heartbeat_ack      → Heartbeat acknowledged`);
  console.log(`  heartbeat_miss     → Heartbeat missed`);
  console.log(`  heartbeat_timeout  → Heartbeat timeout (disconnect)`);
  console.log(`  can_error          → CAN error\n`);
});
