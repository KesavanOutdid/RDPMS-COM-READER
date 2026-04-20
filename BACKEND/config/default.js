module.exports = {
  SERVER_PORT:        3001,
  POLL_INTERVAL:      1500,   // scan for new USB devices every 1.5s
  DEFAULT_BAUD:       0x08,   // 500 kbps
  HEARTBEAT_INTERVAL: 1000,   // send D0 every 1 second
  HEARTBEAT_TIMEOUT:  3000,   // 3s no reply → disconnect
  HEARTBEAT_MAX_MISS: 3,      // max missed heartbeats
  BUFFER_LIMIT:       500,    // max RX frames to keep in memory

  // Baud rate map — byte value → human label
  BAUD_RATES: {
    0x01: '10 kbps',
    0x02: '20 kbps',
    0x03: '50 kbps',
    0x04: '80 kbps',
    0x05: '100 kbps',
    0x06: '125 kbps',
    0x07: '250 kbps',
    0x08: '500 kbps',
    0x09: '800 kbps',
    0x0A: '1 Mbps',
  },

  // CAN FD DLC → actual data length
  DLC_MAP: {
    0: 0, 1: 1, 2: 2,  3: 3,  4: 4,  5: 5,  6: 6,  7: 7,
    8: 8, 9: 12, 10: 16, 11: 20, 12: 24, 13: 32, 14: 48, 15: 64,
  },
};