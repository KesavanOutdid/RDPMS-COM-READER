const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const { startPolling } = require('./core/portScanner');
const { setupSocketEvents } = require('./core/socketEvents');
const { activeConnections } = require('./core/portManager');
const apiRoutes = require('./routes/api');

const app = express();
const httpServer = http.createServer(app);
const io = new Server(httpServer, { cors: { origin: '*' } });

app.use(cors());
app.use(express.json());
app.use(express.static('.')); // Serve static files like index.html

// Use API routes
app.use('/api', apiRoutes);

// Setup socket events
setupSocketEvents(io);

// Start polling for ports
startPolling(io, activeConnections);

const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => {
  console.log(`\n🚀 Serial Backend: http://localhost:${PORT}`);
  console.log(`\nSocket.io Real-Time Events:`);
  console.log(`  port_added         → USB device plugged in (auto)`);
  console.log(`  port_removed       → USB device unplugged (auto)`);
  console.log(`  connection_status  → connected / disconnected`);
  console.log(`  data_received      → incoming data from device`);
  console.log(`  data_sent          → data sent to device\n`);
});
