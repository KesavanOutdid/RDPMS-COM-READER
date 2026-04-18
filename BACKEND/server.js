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
portScanner.onAdded = (portInfo) => {
  console.log(`\n📍 Auto-connecting to ${portInfo.path}...`);
  
  // Wait 500ms for device to settle
  setTimeout(async () => {
    try {
      const result = await canManager.connect(portInfo.path, {
        channel:   0x00,        // Channel 1
        baudRate:  0x08,        // 500 kbps (default)
        mode:      0x00,        // Normal mode
        isFD:      false,       // Classic CAN
        brs:       false,
        nonISO:    false,
      });
      
      if (result.success) {
        console.log(`✅ Auto-connected to ${portInfo.path} → ${result.canType}`);
      } else {
        console.error(`❌ Auto-connect failed: ${result.error}`);
      }
    } catch (err) {
      console.error(`❌ Auto-connect error: ${err.message}`);
    }
  }, 500);
};

// Auto-disconnect when device unplugged
portScanner.onRemoved = (portInfo) => {
  console.log(`\n🔌 Device unplugged: ${portInfo.path}`);
  canManager.disconnect(portInfo.path).catch(err => {
    console.error(`Disconnect error: ${err.message}`);
  });
};

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
