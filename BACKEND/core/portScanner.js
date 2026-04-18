const { SerialPort } = require('serialport');
const { POLL_INTERVAL } = require('../config/default');

class PortScanner {
  constructor(io) {
    this.io        = io;
    this.knownPorts = [];     // last known port list
    this.timer     = null;
    this.onAdded   = null;    // callback when new port appears
    this.onRemoved = null;    // callback when port disappears
  }

  start() {
    console.log(`🔍 Port scanner started — polling every ${POLL_INTERVAL}ms`);
    this.poll();                              // run immediately on start
    this.timer = setInterval(() => this.poll(), POLL_INTERVAL);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
  }

  async poll() {
    try {
      const currentPorts = await SerialPort.list();
      const currentPaths = currentPorts.map(p => p.path);
      const knownPaths   = this.knownPorts.map(p => p.path);

      // ── New ports appeared (USB plugged in) ──
      const added = currentPorts.filter(p => !knownPaths.includes(p.path));
      added.forEach(portInfo => {
        console.log(`\n🔌 USB device detected: ${portInfo.path} (${portInfo.manufacturer || 'Unknown'})`);
        this.io.emit('port_detected', {
          port:         portInfo.path,
          manufacturer: portInfo.manufacturer || 'Unknown Device',
          serialNumber: portInfo.serialNumber || '',
          vendorId:     portInfo.vendorId || '',
          productId:    portInfo.productId || '',
        });
        if (this.onAdded) this.onAdded(portInfo);
      });

      // ── Ports disappeared (USB unplugged) ──
      const removed = this.knownPorts.filter(p => !currentPaths.includes(p.path));
      removed.forEach(portInfo => {
        console.log(`\n🔴 USB device removed: ${portInfo.path}`);
        this.io.emit('port_removed', { port: portInfo.path });
        if (this.onRemoved) this.onRemoved(portInfo);
      });

      this.knownPorts = currentPorts;
    } catch (err) {
      console.error('Scanner poll error:', err.message);
    }
  }

  async listPorts() {
    return await SerialPort.list();
  }
}

module.exports = PortScanner;