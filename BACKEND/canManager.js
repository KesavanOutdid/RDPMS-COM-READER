// ─────────────────────────────────────────────────────────────
// canManager.js
// Core logic: open port → send CONNECT frame → heartbeat loop
//             → parse RX frames → send TX frames
// ─────────────────────────────────────────────────────────────

const { SerialPort }          = require('serialport');
const { buildConnectFrame, buildTxFrame, buildHeartbeatFrame } = require('./frameBuilder');
const { identifyFrame }       = require('./frameParser');
const { HEARTBEAT_INTERVAL, HEARTBEAT_TIMEOUT, HEARTBEAT_MAX_MISS, BUFFER_LIMIT } = require('./config/default');

class CANManager {
  constructor(io) {
    this.io          = io;
    this.connections = {};  // portPath → connection object
  }

  // ─────────────────────────────────────────────
  // CONNECT to CAN device
  // ─────────────────────────────────────────────
  connect(portPath, options = {}) {
    return new Promise((resolve, reject) => {
      if (this.connections[portPath]) {
        return resolve({ success: true, message: 'Already connected', status: 'connected' });
      }

      const {
        channel    = 0x00,
        baudRate   = 0x08,   // 500 kbps default
        mode       = 0x00,   // Normal mode
        isFD       = false,
        brs        = false,
        nonISO     = false,
      } = options;

      // 1. Open the raw serial/USB port
      const serialPort = new SerialPort({
        path:     portPath,
        baudRate: 115200,    // USB serial speed (always 115200 for USB-CAN devices)
        autoOpen: false,
      });

      const rxBuffer  = [];   // received CAN frames
      const rawBuffer = [];   // raw byte accumulator for frame parsing

      // ── Handle incoming raw bytes from device ──
      serialPort.on('data', (chunk) => {
        // Accumulate bytes into rawBuffer
        for (const byte of chunk) rawBuffer.push(byte);

        // Try to parse complete frames from rawBuffer
        this._parseBuffer(rawBuffer, portPath, rxBuffer);
      });

      serialPort.on('error', (err) => {
        console.error(`[${portPath}] Serial error:`, err.message);
        this.io.emit('can_error', { port: portPath, error: err.message });
      });

      serialPort.on('close', () => {
        console.log(`[${portPath}] Port closed`);
        this._cleanup(portPath);
        this.io.emit('device_disconnected', { port: portPath });
      });

      // 2. Open the port
      serialPort.open((err) => {
        if (err) {
          return reject({ success: false, error: `Cannot open port: ${err.message}` });
        }

        console.log(`[${portPath}] Port opened`);

        // 3. Send CONNECT frame (0xA0...)
        const connectFrame = buildConnectFrame({ channel, baudRate, mode, isFD, brs, nonISO });
        console.log(`[${portPath}] → Sending CONNECT frame: ${connectFrame.toString('hex').toUpperCase()}`);

        serialPort.write(connectFrame, (writeErr) => {
          if (writeErr) {
            serialPort.close();
            return reject({ success: false, error: `Connect frame write failed: ${writeErr.message}` });
          }

          // 4. Wait for ACK (0xA1) — timeout after 3s
          let ackReceived = false;
          const ackTimeout = setTimeout(() => {
            if (!ackReceived) {
              console.error(`[${portPath}] No ACK received — closing`);
              serialPort.close();
              reject({ success: false, error: 'No ACK from device (timeout 3s)' });
            }
          }, 3000);

          // Store connection object
          const conn = {
            serialPort,
            rxBuffer,
            rawBuffer,
            config: { portPath, channel, baudRate, mode, isFD, brs, nonISO },
            stats:  { framesRx: 0, framesTx: 0, errors: 0 },
            heartbeat: {
              timer:    null,
              missCount: 0,
              lastAck:  null,
              waiting:  false,
            },
            ackTimeout,
            ackReceived: false,
            onAck: (ackResult) => {
              if (ackReceived) return;
              ackReceived = true;
              clearTimeout(ackTimeout);

              if (ackResult.success) {
                console.log(`[${portPath}] ✔ CONNECT ACK received — ${ackResult.canType}`);
                conn.ackReceived = true;
                conn.canType = ackResult.canType;

                // 5. Start heartbeat loop
                this._startHeartbeat(portPath);

                this.io.emit('device_connected', {
                  port:    portPath,
                  canType: ackResult.canType,
                  channel: ackResult.channel,
                  config:  conn.config,
                });

                resolve({ success: true, status: 'connected', canType: ackResult.canType });
              } else {
                console.error(`[${portPath}] CONNECT failed: ${ackResult.status}`);
                serialPort.close();
                reject({ success: false, error: `Device rejected connect: ${ackResult.status}` });
              }
            },
          };

          this.connections[portPath] = conn;
        });
      });
    });
  }

  // ─────────────────────────────────────────────
  // DISCONNECT from CAN device
  // ─────────────────────────────────────────────
  disconnect(portPath) {
    return new Promise((resolve, reject) => {
      const conn = this.connections[portPath];
      if (!conn) return resolve({ success: true, message: 'Not connected' });

      this._cleanup(portPath);

      conn.serialPort.close((err) => {
        if (err) return reject({ success: false, error: err.message });
        resolve({ success: true, status: 'disconnected' });
      });
    });
  }

  // ─────────────────────────────────────────────
  // SEND CAN TX FRAME (0xF1 0x01 ...)
  // ─────────────────────────────────────────────
  sendFrame(portPath, { canId, data = [], channel = 0, isExtended = false, isFD = null }) {
    return new Promise((resolve, reject) => {
      const conn = this.connections[portPath];
      if (!conn || !conn.serialPort.isOpen) {
        return reject({ success: false, error: `${portPath} not connected` });
      }

      // Auto-detect FD if not provided, based on connection config
      const frameIsFD = isFD !== null ? isFD : conn.config.isFD;

      // Validation: Classic CAN cannot exceed 8 bytes
      if (!frameIsFD && data.length > 8) {
        return reject({ success: false, error: 'Classic CAN supports maximum 8 bytes. Use CAN FD for larger payloads.' });
      }

      const frame = buildTxFrame({ canId, data, channel, isExtended });
      console.log(`[${portPath}] → TX: ${frame.toString('hex').toUpperCase()}`);

      conn.serialPort.write(frame, (err) => {
        if (err) return reject({ success: false, error: err.message });

        conn.stats.framesTx++;

        const txLog = {
          direction: 'TX',
          canId:     '0x' + canId.toString(16).toUpperCase().padStart(isExtended ? 8 : 3, '0'),
          channel:   channel + 1,
          dlc:       data.length,
          dataHex:   data.map(b => b.toString(16).toUpperCase().padStart(2, '0')).join(' '),
          timestamp: new Date().toISOString(),
          raw:       frame.toString('hex').toUpperCase(),
        };

        this.io.emit('can_tx', { port: portPath, frame: txLog });
        resolve({ success: true, frame: txLog });
      });
    });
  }

  // ─────────────────────────────────────────────
  // GET STATUS
  // ─────────────────────────────────────────────
  getStatus(portPath) {
    if (portPath) {
      const conn = this.connections[portPath];
      if (!conn) return { port: portPath, status: 'disconnected' };
      return {
        port:    portPath,
        status:  conn.serialPort.isOpen ? 'connected' : 'disconnected',
        canType: conn.canType || 'CLASSIC_CAN',
        config:  conn.config,
        stats:   conn.stats,
        heartbeat: {
          lastAck:   conn.heartbeat.lastAck,
          missCount: conn.heartbeat.missCount,
        },
      };
    }

    // All connections
    return Object.keys(this.connections).map(p => this.getStatus(p));
  }

  // Get buffered RX frames
  getRxFrames(portPath) {
    const conn = this.connections[portPath];
    if (!conn) return [];
    const frames = [...conn.rxBuffer];
    conn.rxBuffer.length = 0;  // clear after read
    return frames;
  }

  // ─────────────────────────────────────────────
  // HEARTBEAT — send D0 every 1s, check D1 reply
  // ─────────────────────────────────────────────
  _startHeartbeat(portPath) {
    const conn = this.connections[portPath];
    if (!conn) return;

    console.log(`[${portPath}] 💓 Heartbeat started`);

    conn.heartbeat.timer = setInterval(() => {
      const c = this.connections[portPath];
      if (!c || !c.serialPort.isOpen) return;

      if (c.heartbeat.waiting) {
        // Previous heartbeat not acknowledged
        c.heartbeat.missCount++;
        console.warn(`[${portPath}] ⚠ Heartbeat miss #${c.heartbeat.missCount}`);
        this.io.emit('heartbeat_miss', { port: portPath, missCount: c.heartbeat.missCount });

        if (c.heartbeat.missCount >= HEARTBEAT_MAX_MISS) {
          console.error(`[${portPath}] ✖ Heartbeat timeout — disconnecting`);
          this.io.emit('heartbeat_timeout', { port: portPath });
          this.disconnect(portPath);
          return;
        }
      }

      // Send heartbeat frame D0 00
      const hbFrame = buildHeartbeatFrame();
      c.serialPort.write(hbFrame, (err) => {
        if (!err) {
          c.heartbeat.waiting = true;
          this.io.emit('heartbeat_sent', { port: portPath, timestamp: new Date().toISOString() });
        }
      });

    }, HEARTBEAT_INTERVAL);
  }

  // ─────────────────────────────────────────────
  // PARSE incoming raw bytes → identify frames
  // ─────────────────────────────────────────────
  _parseBuffer(rawBuffer, portPath, rxBuffer) {
    const conn = this.connections[portPath];
    if (!conn) return;

    while (rawBuffer.length > 0) {
      const first = rawBuffer[0];

      // ── CONNECT ACK: A1 xx xx xx xx (5 bytes) ──
      if (first === 0xA1) {
        if (rawBuffer.length < 5) break;
        const frameBuf = Buffer.from(rawBuffer.splice(0, 5));
        const parsed   = identifyFrame(frameBuf);
        if (parsed && conn.onAck) conn.onAck(parsed);
        continue;
      }

      // ── HEARTBEAT RESPONSE: D1 xx (2 bytes) ──
      if (first === 0xD1) {
        if (rawBuffer.length < 2) break;
        const frameBuf = Buffer.from(rawBuffer.splice(0, 2));
        const parsed   = identifyFrame(frameBuf);
        if (parsed && conn.heartbeat) {
          conn.heartbeat.waiting  = false;
          conn.heartbeat.missCount = 0;
          conn.heartbeat.lastAck  = new Date().toISOString();
          if (!parsed.healthy) conn.stats.errors++;
          this.io.emit('heartbeat_ack', { port: portPath, status: parsed.status, timestamp: conn.heartbeat.lastAck });
        }
        continue;
      }

      // ── RX FRAME: F1 00 [4 timestamp] [4 canid] [1 dlc+ch] [data] ──
      if (first === 0xF1 && rawBuffer.length > 1 && rawBuffer[1] === 0x00) {
        if (rawBuffer.length < 11) break;  // wait for more bytes

        // Read DLC byte to know data length
        const dlcByte = rawBuffer[10];
        const dlc     = dlcByte & 0x0F;
        const { DLC_MAP } = require('./config/default');
        const dataLen = DLC_MAP[dlc] !== undefined ? DLC_MAP[dlc] : dlc;
        const totalLen = 11 + dataLen;

        if (rawBuffer.length < totalLen) break;  // wait for full frame

        const frameBuf = Buffer.from(rawBuffer.splice(0, totalLen));
        const parsed   = identifyFrame(frameBuf);

        if (parsed) {
          parsed.direction = 'RX';
          rxBuffer.push(parsed);
          if (rxBuffer.length > BUFFER_LIMIT) rxBuffer.shift();
          conn.stats.framesRx++;

          console.log(`[${portPath}] ← RX: ID=${parsed.canId} CH=${parsed.channel} DLC=${parsed.dlc} Data=${parsed.dataHex}`);
          this.io.emit('can_rx', { port: portPath, frame: parsed });
        }
        continue;
      }

      // Unknown byte — skip it
      console.warn(`[${portPath}] Unknown byte: 0x${rawBuffer[0].toString(16).toUpperCase()} — skipping`);
      rawBuffer.shift();
    }
  }

  // ─────────────────────────────────────────────
  // CLEANUP timers and state
  // ─────────────────────────────────────────────
  _cleanup(portPath) {
    const conn = this.connections[portPath];
    if (!conn) return;

    if (conn.heartbeat.timer) clearInterval(conn.heartbeat.timer);
    if (conn.ackTimeout)      clearTimeout(conn.ackTimeout);

    delete this.connections[portPath];
    console.log(`[${portPath}] Cleaned up`);
  }
}

module.exports = CANManager;