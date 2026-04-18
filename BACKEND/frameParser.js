// ─────────────────────────────────────────────────────────────
// frameParser.js
// Parses binary frames RECEIVED from the CAN USB device
// Based on PDF spec
// ─────────────────────────────────────────────────────────────

const { DLC_MAP } = require('./config/default');

/**
 * PARSE CONNECT RESPONSE (Device → PC)
 * Spec: Byte0=0xA1, Byte1=status, Byte2=channel, Byte3=canType, Byte4=reserved
 *
 * Status: 0x00=Success, 0x01=Failure, 0x02=InvalidBaud, 0x03=HardwareError
 */
function parseConnectResponse(buf) {
  if (buf.length < 5 || buf[0] !== 0xA1) return null;

  const statusMap = {
    0x00: 'SUCCESS',
    0x01: 'FAILURE',
    0x02: 'INVALID_BAUD',
    0x03: 'HARDWARE_ERROR',
  };

  return {
    type:      'CONNECT_RESPONSE',
    status:    statusMap[buf[1]] || 'UNKNOWN',
    success:   buf[1] === 0x00,
    channel:   buf[2],
    canType:   buf[3] === 0x01 ? 'CAN_FD' : 'CLASSIC_CAN',
    raw:       buf.toString('hex').toUpperCase(),
  };
}

/**
 * PARSE RX FRAME (Device → PC)
 * Spec: Byte0=0xF1, Byte1=0x00, Byte2-5=Timestamp, Byte6-9=CANID,
 *       Byte10=DLC+Channel, Byte11-N=Data
 */
function parseRxFrame(buf) {
  if (buf.length < 11 || buf[0] !== 0xF1 || buf[1] !== 0x00) return null;

  // Timestamp: 4 bytes little-endian (microseconds)
  const timestamp = buf.readUInt32LE(2);

  // CAN ID: 4 bytes little-endian
  const rawId    = buf.readUInt32LE(6);
  const isExtended = (rawId & 0x80000000) !== 0;
  const canId    = rawId & 0x1FFFFFFF;  // mask out flag bit

  // DLC + Channel byte
  const dlcByte  = buf[10];
  const dlc      = dlcByte & 0x0F;         // lower 4 bits
  const channel  = (dlcByte >> 4) & 0x0F;  // upper 4 bits

  // Actual data length from DLC map
  const dataLen  = DLC_MAP[dlc] !== undefined ? DLC_MAP[dlc] : dlc;
  const data     = buf.slice(11, 11 + dataLen);

  return {
    type:       'RX_FRAME',
    timestamp,
    canId:      '0x' + canId.toString(16).toUpperCase().padStart(isExtended ? 8 : 3, '0'),
    canIdRaw:   canId,
    isExtended,
    channel:    channel + 1,   // 0→Ch1, 1→Ch2
    dlc,
    dataLength: dataLen,
    data:       Array.from(data).map(b => b.toString(16).toUpperCase().padStart(2, '0')),
    dataHex:    Array.from(data).map(b => b.toString(16).toUpperCase().padStart(2, '0')).join(' '),
    raw:        buf.toString('hex').toUpperCase(),
    receivedAt: new Date().toISOString(),
  };
}

/**
 * PARSE HEARTBEAT RESPONSE (Device → PC)
 * Spec: Byte0=0xD1, Byte1=status (0x00=OK, 0x01=Error)
 */
function parseHeartbeatResponse(buf) {
  if (buf.length < 2 || buf[0] !== 0xD1) return null;

  return {
    type:    'HEARTBEAT_RESPONSE',
    status:  buf[1] === 0x00 ? 'OK' : 'ERROR',
    healthy: buf[1] === 0x00,
    raw:     buf.toString('hex').toUpperCase(),
  };
}

/**
 * IDENTIFY FRAME TYPE from first byte
 */
function identifyFrame(buf) {
  if (!buf || buf.length === 0) return null;

  if (buf[0] === 0xA1)                          return parseConnectResponse(buf);
  if (buf[0] === 0xF1 && buf[1] === 0x00)       return parseRxFrame(buf);
  if (buf[0] === 0xD1)                          return parseHeartbeatResponse(buf);

  return { type: 'UNKNOWN', raw: buf.toString('hex').toUpperCase() };
}

module.exports = { parseConnectResponse, parseRxFrame, parseHeartbeatResponse, identifyFrame };