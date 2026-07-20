// =========================================================================
// RDPMS Backend Server - Entry Point
// =========================================================================
// Express.js REST API server for the RDPMS Serial Monitor application.
// Connects to MongoDB Atlas, serves the Reports web viewer, and exposes
// REST API endpoints for saving/fetching QC test records.
//
// Host Machine IP : 192.168.0.12
// Default Port    : 3001 (configured in ./config/default.js)
// Binding         : 0.0.0.0 (all network interfaces — allows LAN access)
// =========================================================================

// --- Module Imports ---
const express = require('express');   // Web framework for REST API
const cors = require('cors');         // Cross-Origin Resource Sharing middleware
const path = require('path');         // File path utility
const db = require('./core/db');      // MongoDB Atlas database connection & operations
const apiRoutes = require('./routes/api');           // REST API route definitions
const { SERVER_PORT } = require('./config/default'); // Server port from config (default: 3001)

// --- Initialize Express Application ---
const app = express();

// --- Global Middleware ---
app.use(cors());          // Enable CORS for all origins (Flutter desktop + web clients)
app.use(express.json());  // Parse incoming JSON request bodies

// --- Active Client Connection Counter ---
// Tracks the number of currently open TCP socket connections to the server.
let activeSockets = 0;

// --- HTTP Request Logger Middleware ---
// Logs every incoming HTTP request with method, URL, and client IP address.
app.use((req, res, next) => {
  const clientIp = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'Unknown').replace(/^.*:/, '');
  console.log(`📥 [REQUEST] ${req.method} ${req.originalUrl} from IP: ${clientIp}`);
  next();
});

// --- Static File Serving ---
// Serves static files (reports.html, CSS, JS assets) from the backend root directory.
app.use(express.static(__dirname));

// --- REST API Routes ---
// All API endpoints are mounted under /api (e.g., /api/tests, /api/tests/serial-numbers)
app.use('/api', apiRoutes());

// --- Reports Web Page Route ---
// Serves the QC Reports web viewer at http://<host>:3001/reports
app.get('/reports', (req, res) => {
  res.sendFile(path.join(__dirname, 'reports.html'));
});

// --- Root Redirect ---
// Visiting http://<host>:3001/ automatically redirects to /reports
app.get('/', (req, res) => {
  res.redirect('/reports');
});

// =========================================================================
// Server Startup
// =========================================================================
// 1. Connects to MongoDB Atlas database
// 2. Starts Express HTTP server on 0.0.0.0:<port> (all network interfaces)
// 3. Attaches TCP socket connection/disconnection event listeners for
//    real-time client monitoring in the console
// =========================================================================
async function startServer() {
  try {
    // Step 1: Connect to MongoDB Atlas
    await db.connect();
    
    // Step 2: Start HTTP server — bind to 0.0.0.0 so other LAN machines can reach it
    const server = app.listen(SERVER_PORT, '0.0.0.0', () => {
      console.log(`\n🚀 RDPMS Backend running on LAN: http://192.168.0.12:${SERVER_PORT}`);
      console.log(`📊 Report Viewer available at: http://192.168.0.12:${SERVER_PORT}/reports`);
      console.log(`📡 Real-Time Client Connection Logging Enabled\n`);
    });

    // Step 3: Monitor TCP socket connections & disconnections
    // Each time a client (Flutter app or browser) opens a connection, log it.
    server.on('connection', (socket) => {
      activeSockets++;
      const remoteIp = (socket.remoteAddress || '').replace(/^.*:/, '') || '127.0.0.1';
      console.log(`🟢 [CLIENT CONNECTED] IP: ${remoteIp} | Total Active Clients: ${activeSockets}`);

      // When the client disconnects, decrement the counter and log it.
      socket.on('close', () => {
        activeSockets = Math.max(0, activeSockets - 1);
        console.log(`🔴 [CLIENT DISCONNECTED] IP: ${remoteIp} | Total Active Clients: ${activeSockets}`);
      });
    });

  } catch (err) {
    // If database connection fails, abort server startup entirely
    console.error('❌ Server startup aborted: Failed to connect to database.', err);
    process.exit(1);
  }
}

// --- Launch the server ---
startServer();