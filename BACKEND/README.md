# CAN USB Backend

This backend provides a USB-CAN dongle interface for a browser frontend. It:

- scans USB serial ports for CAN devices
- sends the USB-CAN CONNECT handshake (0xA0)
- receives CONNECT ACK (0xA1)
- sends CAN TX frames (0xF1 0x01)
- parses CAN RX frames (0xF1 0x00)
- runs heartbeat keep-alive (D0/D1)
- exposes Socket.io events and REST API endpoints

## Run

```bash
cd BACKEND
npm install
npm start
```

The server listens on port `3000` by default.

## Backend events for frontend

### Events sent by backend

- `available_ports`
  - Payload: `Array`
  - Each item:
    - `port` — string, e.g. `COM3`
    - `manufacturer` — string
    - `serialNumber` — string
    - `vendorId` — string
    - `productId` — string

- `initial_ports`
  - Payload: `Any`
  - Value: `getActiveConnections()` result
  - Use to render currently active or connected ports on page load

- `connect_response`
  - Payload:
    - `port` — string
    - `success` — boolean
    - `message` — string (optional)
    - `error` — string (optional)

- `disconnect_response`
  - Payload:
    - `port` — string
    - `success` — boolean
    - `message` — string (optional)
    - `error` — string (optional)

- `send_response`
  - Payload:
    - `port` — string
    - `success` — boolean
    - `frame` — object (optional)
    - `error` — string (optional)

- `device_connected`
  - Payload:
    - `port` — string
    - `canType` — string
    - `channel` — number
    - `config` — object

- `device_disconnected`
  - Payload:
    - `port` — string

- `can_rx`
  - Payload:
    - `port` — string
    - `frame` — object with parsed CAN RX frame

- `can_tx`
  - Payload:
    - `port` — string
    - `frame` — object with TX frame metadata

- `heartbeat_sent`
- `heartbeat_ack`
- `heartbeat_miss`
- `heartbeat_timeout`
- `can_error`

## Frontend events to backend

- `connect_port`
  - Payload:
    - `port` — string    - `baudRate` (number, default 0x08) — e.g. 0x08 for 500 kbps
    - `channel` (number, default 0) — 0 for Channel 1, 1 for Channel 2
    - `mode` (number, default 0) — 0=Normal, 1=Loopback, 2=Silent
    - `isFD` (boolean, default false) — true for CAN FD
    - `brs` (boolean, default false) — Bit Rate Switching
    - `nonISO` (boolean, default false) — Non-ISO CAN FD
- `disconnect_port`
  - Payload:
    - `port` — string

- `send_data`
  - Payload:
    - `port` — string
    - `message` — string or bytes payload

## Example frontend code

```js
socket.on('available_ports', (ports) => {
  console.log('available_ports', ports);
});

socket.on('initial_ports', (connections) => {
  console.log('initial_ports', connections);
});

socket.on('connect_response', (res) => {
  console.log('connect_response', res);
});

socket.on('disconnect_response', (res) => {
  console.log('disconnect_response', res);
});

socket.on('send_response', (res) => {
  console.log('send_response', res);
});

// Connect with CAN settings
socket.emit('connect_port', {
  port: 'COM3',
  baudRate: 0x08,   // 500 kbps
  channel: 0,       // Channel 1
  mode: 0,          // Normal
  isFD: false,      // Classic CAN
  brs: false,
  nonISO: false
});

socket.emit('disconnect_port', { port: 'COM3' });
socket.emit('send_data', { port: 'COM3', message: 'AA BB CC DD' });
```

## Protocol mapping

- `available_ports` = list of detected USB serial ports
- `initial_ports` = current active connections
- `connect_port` = request backend to connect to the dongle
- `disconnect_port` = request backend to disconnect
- `send_data` = request backend to send a CAN frame
- `connect_response` / `disconnect_response` / `send_response` = response status

## Notes

- The backend is designed to detect a device, then perform the handshake and heartbeat automatically.
- If port 3000 is already occupied, stop the conflicting process or change the port in `config/default.js`.
