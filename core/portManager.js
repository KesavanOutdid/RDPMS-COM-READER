const { SerialPort } = require('serialport');
const { ReadlineParser } = require('@serialport/parser-readline');
const config = require('../config/default');

const activeConnections = {};

function connectToPort(portPath, io) {
  if (activeConnections[portPath]) {
    return { success: false, message: 'Port already connected' };
  }

  try {
    const serialPort = new SerialPort({
      path: portPath,
      baudRate: config.baudRate,
      dataBits: config.dataBits,
      parity: config.parity,
      stopBits: config.stopBits,
      flowControl: config.flowControl,
    });

    // Use \r as delimiter (standard for many CAN modules/SLCAN)
    const parser = serialPort.pipe(new ReadlineParser({ delimiter: '\r' }));

    parser.on('data', (data) => {
      io.emit('data_received', { port: portPath, data: data.toString() });
    });

    serialPort.on('open', () => {
      console.log(`✅ Connected to ${portPath}`);
      io.emit('connection_status', { port: portPath, status: 'connected' });
    });

    serialPort.on('close', () => {
      console.log(`❌ Disconnected from ${portPath}`);
      delete activeConnections[portPath];
      io.emit('connection_status', { port: portPath, status: 'disconnected' });
    });

    serialPort.on('error', (err) => {
      console.error(`Error on ${portPath}:`, err.message);
      io.emit('connection_status', { port: portPath, status: 'error', error: err.message });
    });

    activeConnections[portPath] = { serialPort, parser };
    return { success: true, message: 'Connecting...' };
  } catch (error) {
    console.error(`Failed to connect to ${portPath}:`, error.message);
    return { success: false, message: error.message };
  }
}

function disconnectFromPort(portPath) {
  if (!activeConnections[portPath]) {
    return { success: false, message: 'Port not connected' };
  }

  try {
    activeConnections[portPath].serialPort.close();
    delete activeConnections[portPath];
    return { success: true, message: 'Disconnected' };
  } catch (error) {
    return { success: false, message: error.message };
  }
}

function sendData(portPath, data) {
  if (!activeConnections[portPath]) {
    return { success: false, message: 'Port not connected' };
  }

  try {
    let buffer;
    
    // Check if data is hex format (e.g., "01 02 AB" or "0102AB")
    const hexPattern = /^[0-9A-Fa-f\s]+$/;
    if (hexPattern.test(data) && data.length >= 2) {
      const cleanHex = data.replace(/\s+/g, '');
      if (cleanHex.length % 2 === 0) {
        buffer = Buffer.from(cleanHex, 'hex');
      } else {
        buffer = Buffer.from(data + '\r');
      }
    } else {
      // Default to string with CR (common for CAN modules)
      buffer = Buffer.from(data + '\r');
    }

    activeConnections[portPath].serialPort.write(buffer);
    return { success: true, message: 'Data sent', hex: buffer.toString('hex').toUpperCase() };
  } catch (error) {
    return { success: false, message: error.message };
  }
}

function getActiveConnections() {
  return Object.keys(activeConnections);
}

module.exports = { connectToPort, disconnectFromPort, sendData, getActiveConnections, activeConnections };