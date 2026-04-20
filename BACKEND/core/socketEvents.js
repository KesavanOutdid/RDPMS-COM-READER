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

    socket.on('disconnect', () => {
      console.log('🌐 Frontend disconnected:', socket.id);
    });
  });
}

module.exports = { setupSocketEvents };