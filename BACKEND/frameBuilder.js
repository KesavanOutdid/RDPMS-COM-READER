// ─────────────────────────────────────────────────────────────
// frameBuilder.js
// Builds binary frames to SEND to the CAN USB device
// Based on PDF spec
// ─────────────────────────────────────────────────────────────

/**
 * BUILD CONNECT FRAME (PC → Device)
 * Spec: Byte0=0xA0, Byte1=0x01(USB), Byte2=channel,
 *       Byte3=nominalBaud, Byte4=mode/dataBaud, Byte5=flags, Byte6=0x00
 *
 * Example Classic CAN 500kbps Normal:  A0 01 00 08 00 00 00
 * Example CAN FD 500k/2M BRS ON:      A0 01 00 08 02 03 00
 */
function buildConnectFrame({ channel = 0x00, baudRate = 0x08, mode = 0x00, isFD = false, brs = false, nonISO = false } = {}) {
  // Byte 5 flags bitfield:
  // Bit0 = CAN type (0=Classic, 1=FD)
  // Bit1 = BRS
  // Bit2 = ISO/Non-ISO
  let flags = 0x00;
  if (isFD)    flags |= 0x01;
  if (brs)     flags |= 0x02;
  if (nonISO)  flags |= 0x04;

  return Buffer.from([
    0xA0,       // Byte 0: CONNECT command
    0x01,       // Byte 1: USB interface
    channel,    // Byte 2: channel (0x00=Ch1, 0x01=Ch2)
    baudRate,   // Byte 3: nominal baud rate
    mode,       // Byte 4: mode (Classic: 0=Normal,1=Loopback,2=Silent | FD: data baud)
    flags,      // Byte 5: CAN type + flags
    0x00,       // Byte 6: reserved
  ]);
}

/**
 * BUILD TX FRAME (PC → Device)
 * Spec: Byte0=0xF1, Byte1=0x01, Byte2-5=CANID, Byte6=DLC+Channel, Byte7-N=Data
 *
 * Example: F1 01 21 03 00 00 08 AA BB CC DD EE FF 00 11
 */
function buildTxFrame({ canId, data = [], channel = 0, isExtended = false }) {
  // CAN ID — 4 bytes little-endian
  // If extended, set bit 31
  let idValue = canId;
  if (isExtended) idValue = idValue | 0x80000000;

  const idBuf = Buffer.alloc(4);
  idBuf.writeUInt32LE(idValue >>> 0, 0);

  const dlc = data.length & 0x0F;
  const dlcChannel = ((channel & 0x0F) << 4) | dlc;  // upper 4 = channel, lower 4 = dlc

  const dataBuf = Buffer.from(data);

  return Buffer.concat([
    Buffer.from([0xF1, 0x01]),  // Prefix + TX type
    idBuf,                       // CAN ID (4 bytes)
    Buffer.from([dlcChannel]),   // DLC + Channel
    dataBuf,                     // Data payload
  ]);
}

/**
 * BUILD HEARTBEAT REQUEST (PC → Device)
 * Spec: D0 00
 */
function buildHeartbeatFrame() {
  return Buffer.from([0xD0, 0x00]);
}

module.exports = { buildConnectFrame, buildTxFrame, buildHeartbeatFrame };