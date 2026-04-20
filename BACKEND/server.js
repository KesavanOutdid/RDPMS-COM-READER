const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const PortScanner            = require('./core/portScanner');
const CANManager             = require('./canManager');
const { setupSocketEvents }  = require('./core/socketEvents');  // ← FIXED: now imported
const apiRoutes              = require('./routes/api');

const app        = express();
const httpServer = http.createServer(app);
const io         = new Server(httpServer, { cors: { origin: '*' } });

app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// Initialize managers
const portScanner = new PortScanner(io);
const canManager  = new CANManager(io);

// REST API routes
app.use('/api', apiRoutes(canManager, portScanner));

// Socket.io events — FIXED: now called with canManager passed in
setupSocketEvents(io, canManager);

// Port scanner: emit events when USB device plugged/unplugged
portScanner.start();

const { SERVER_PORT } = require('./config/default');
httpServer.listen(SERVER_PORT, () => {
  console.log(`\n🚀 CAN Backend running: http://localhost:${SERVER_PORT}`);
  console.log(`\nSocket.io Events (Backend → Frontend):`);
  console.log(`  available_ports    → List of USB ports on connect`);
  console.log(`  port_detected      → USB device plugged in`);
  console.log(`  port_removed       → USB device unplugged`);
  console.log(`  device_connected   → CAN ACK received (A1 00)`);
  console.log(`  device_disconnected→ CAN port closed`);
  console.log(`  can_rx             → CAN frame received (F1 00)`);
  console.log(`  can_tx             → CAN frame sent (F1 01)`);
  console.log(`  heartbeat_sent     → D0 sent`);
  console.log(`  heartbeat_ack      → D1 received`);
  console.log(`  heartbeat_miss     → No D1 reply`);
  console.log(`  heartbeat_timeout  → 3 misses — disconnected`);
  console.log(`  can_error          → Device error\n`);
  console.log(`Socket.io Events (Frontend → Backend):`);
  console.log(`  connect_port       → Connect to a CAN port`);
  console.log(`  disconnect_port    → Disconnect from a CAN port`);
  console.log(`  send_frame         → Send a CAN TX frame\n`);
});