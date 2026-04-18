const { connectToPort, disconnectFromPort, sendData, getActiveConnections } = require('./portManager');
const { SerialPort } = require('serialport');

async function setupSocketEvents(io) {
  io.on('connection', async (socket) => {
    console.log('Client connected:', socket.id);

    // Send all available ports to new client
    try {
      const allPorts = await SerialPort.list();
      socket.emit('available_ports', allPorts.map(p => ({
        port: p.path,
        manufacturer: p.manufacturer || 'Unknown Device',
        serialNumber: p.serialNumber || '',
        vendorId: p.vendorId || '',
        productId: p.productId || '',
      })));
      console.log(`Sent ${allPorts.length} available ports to client ${socket.id}`);
    } catch (err) {
      console.error('Error listing ports:', err);
    }

    // Send current active connections to new client
    socket.emit('initial_ports', getActiveConnections());

    // ────────────────────────────────────────
    // LISTEN: Manual connect request from UI with CAN settings
    // ────────────────────────────────────────
    socket.on('connect_port', async (data) => {
      const { port, baudRate = 0x08, channel = 0, mode = 0, isFD = false, brs = false, nonISO = false } = data;
      console.log(`\n🔗 Connect request: ${port} (Baud:${baudRate}, Ch:${channel}, Mode:${mode})`);

      try {
        const result = await canManager.connect(port, {
          channel,
          baudRate,
          mode,
          isFD,
          brs,
          nonISO
        });

        if (result.success) {
          socket.emit('connect_response', {
            success: true,
            port,
            message: result.status,
            canType: result.canType
          });
        } else {
          socket.emit('connect_response', {
            success: false,
            port,
            error: result.error
          });
        }
      } catch (err) {
        socket.emit('connect_response', {
          success: false,
          port,
          error: err.message
        });
      }
    });

    socket.on('disconnect_port', (data) => {
      const { port } = data;
      const result = disconnectFromPort(port);
      socket.emit('disconnect_response', { port, ...result });
    });

    socket.on('send_data', (data) => {
      const { port, message } = data;
      const result = sendData(port, message);
      socket.emit('send_response', { port, ...result });
    });

    socket.on('disconnect', () => {
      console.log('Client disconnected:', socket.id);
    });
  });
}

module.exports = { setupSocketEvents };