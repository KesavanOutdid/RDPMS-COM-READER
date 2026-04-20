// ─────────────────────────────────────────────────────────────
// core/socketEvents.js
// All Socket.io event listeners — frontend talks to backend here
// ─────────────────────────────────────────────────────────────

const { SerialPort } = require('serialport');

async function setupSocketEvents(io, canManager) {
  io.on('connection', async (socket) => {
    console.log('🌐 Frontend connected:', socket.id);

    // Send available ports to new browser client immediately
    try {
      const allPorts = await SerialPort.list();
      socket.emit('available_ports', allPorts.map(p => ({
        port:         p.path,
        manufacturer: p.manufacturer  || 'Unknown Device',
        serialNumber: p.serialNumber  || '',
        vendorId:     p.vendorId      || '',
        productId:    p.productId     || '',
      })));
    } catch (err) {
      console.error('Error listing ports:', err);
    }

    // Send current active CAN connections
    socket.emit('status_update', { connections: canManager.getStatus() });

    // ── CONNECT to CAN port ──
    socket.on('connect_port', async (data) => {
      const { port, baudRate = 0x08, channel = 0, mode = 0, isFD = false, brs = false, nonISO = false } = data;
      console.log(`\n🔗 Connect request: ${port}`);
      try {
        const result = await canManager.connect(port, { channel, baudRate, mode, isFD, brs, nonISO });
        socket.emit('connect_response', { success: true, port, message: result.status, canType: result.canType });
      } catch (err) {
        socket.emit('connect_response', { success: false, port, error: err.error || err.message || 'Connect failed' });
      }
    });

    // ── DISCONNECT from CAN port ──
    socket.on('disconnect_port', async (data) => {
      const { port } = data;
      try {
        const result = await canManager.disconnect(port);
        socket.emit('disconnect_response', { success: true, port, ...result });
      } catch (err) {
        socket.emit('disconnect_response', { success: false, port, error: err.message });
      }
    });

    // ── SEND CAN frame ──
    socket.on('send_frame', async (data) => {
      let { port, canId, data: frameData = [], channel = 0, isExtended = false, isFD = null } = data;
      if (typeof canId === 'string') canId = parseInt(canId, canId.startsWith('0x') ? 16 : 10);
      frameData = frameData.map(b => typeof b === 'string' ? parseInt(b, 16) : b);
      try {
        const result = await canManager.sendFrame(port, { canId, data: frameData, channel, isExtended, isFD });
        socket.emit('send_response', { success: true, port, frame: result.frame });
      } catch (err) {
        socket.emit('send_response', { success: false, port, error: err.error || err.message });
      }
    });

    // ── REMOTE HARDWARE MODE (Frontend has the USB) ──
    
    // 1. Frontend sends raw bytes from its local Web Serial to Backend for parsing
    socket.on('remote_raw_stream', (data) => {
      const { sessionId, rawBytes } = data;
      // Use frameParser to identify frames and emit 'can_rx' back to frontend
      const buffer = Buffer.from(rawBytes);
      const parsed = canManager.parseRemoteBytes(sessionId, buffer);
      if (parsed && parsed.length > 0) {
        parsed.forEach(frame => socket.emit('can_rx', { port: 'REMOTE', frame }));
      }
    });

    // 2. Frontend asks Backend to build a binary TX frame to write to its local USB
    socket.on('request_tx_binary', (data) => {
      const { canId, frameData, channel, isExtended } = data;
      const binaryFrame = canManager.buildBinaryFrame({ canId, data: frameData, channel, isExtended });
      socket.emit('tx_binary_response', { binary: binaryFrame.toString('hex') });
    });

    socket.on('disconnect', () => {
      console.log('🌐 Frontend disconnected:', socket.id);
    });
  });
}

module.exports = { setupSocketEvents };