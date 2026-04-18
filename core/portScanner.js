const { SerialPort } = require('serialport');
const config = require('../config/default');
const { connectToPort } = require('./portManager');

let knownPorts = [];

async function pollPorts(io, activeConnections) {
  try {
    const currentPorts = await SerialPort.list();
    const currentPaths = currentPorts.map(p => p.path);
    const knownPaths = knownPorts.map(p => p.path);

    const added = currentPorts.filter(p => !knownPaths.includes(p.path));
    const removed = knownPorts.filter(p => !currentPaths.includes(p.path));

    for (const p of added) {
      console.log(`🔌 Port detected: ${p.path}`);
      io.emit('port_added', {
        port: p.path,
        manufacturer: p.manufacturer || 'Unknown Device',
        serialNumber: p.serialNumber || '',
        vendorId: p.vendorId || '',
        productId: p.productId || '',
      });

      // Auto-connect to newly detected port
      console.log(`🔄 Auto-connecting to ${p.path}...`);
      connectToPort(p.path, io);
    }

    for (const p of removed) {
      console.log(`🔴 Port removed: ${p.path}`);
      if (activeConnections[p.path]) {
        try { activeConnections[p.path].serialPort.close(); } catch (_) {}
        delete activeConnections[p.path];
      }
      io.emit('port_removed', { port: p.path });
      io.emit('connection_status', { port: p.path, status: 'disconnected', reason: 'Device unplugged' });
    }

    knownPorts = currentPorts;
  } catch (error) {
    console.error('Error polling ports:', error);
  }
}

function startPolling(io, activeConnections) {
  setInterval(() => pollPorts(io, activeConnections), config.pollInterval);
}

module.exports = { startPolling, pollPorts };