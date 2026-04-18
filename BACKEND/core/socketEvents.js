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

    socket.on('connect_port', (data) => {
      const { port } = data;
      const result = connectToPort(port, io);
      socket.emit('connect_response', { port, ...result });
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