import 'dart:typed_data';

/// CAN FD DLC code → actual data byte length
const Map<int, int> dlcToLength = {
  0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7,
  8: 8, 9: 12, 10: 16, 11: 20, 12: 24, 13: 32, 14: 48, 15: 64,
};

/// Parsed frame types
enum FrameType { connectResponse, rxFrame, heartbeatResponse, unknown }

/// Result of parsing a single frame from the byte buffer
class ParsedFrame {
  final FrameType type;
  final Map<String, dynamic> data;

  ParsedFrame(this.type, this.data);
}

/// Stateful CAN frame parser — accumulates raw USB bytes and extracts complete frames.
///
/// Protocol spec:
///   CONNECT ACK:  A1 [status] [channel] [canType] [reserved]   (5 bytes)
///   RX FRAME:     F1 00 [4‑byte timestamp LE] [4‑byte canId LE] [dlc+ch] [data…]
///   HEARTBEAT:    D1 [status]   (2 bytes)
class CanFrameParser {
  final List<int> _buffer = [];

  /// Feed raw bytes from the USB reader into the internal buffer.
  void addBytes(Uint8List bytes) {
    _buffer.addAll(bytes);
  }

  /// Extract every complete frame currently available in the buffer.
  List<ParsedFrame> parseAll() {
    final frames = <ParsedFrame>[];

    while (_buffer.isNotEmpty) {
      final first = _buffer[0];

      // ── CONNECT ACK: A1 xx xx xx xx (5 bytes) ──
      if (first == 0xA1) {
        if (_buffer.length < 5) break;
        final raw = Uint8List.fromList(_buffer.sublist(0, 5));
        _buffer.removeRange(0, 5);
        final p = _parseConnectResponse(raw);
        if (p != null) frames.add(p);
        continue;
      }

      // ── HEARTBEAT RESPONSE: D1 xx (2 bytes) ──
      if (first == 0xD1) {
        if (_buffer.length < 2) break;
        final raw = Uint8List.fromList(_buffer.sublist(0, 2));
        _buffer.removeRange(0, 2);
        final p = _parseHeartbeatResponse(raw);
        if (p != null) frames.add(p);
        continue;
      }

      // ── RX FRAME: F1 00 … (variable length) ──
      if (first == 0xF1 && _buffer.length > 1 && _buffer[1] == 0x00) {
        if (_buffer.length < 11) break; // header not complete yet
        final dlcByte = _buffer[10];
        final dlc = dlcByte & 0x0F;
        final dataLen = dlcToLength[dlc] ?? dlc;
        final totalLen = 11 + dataLen;
        if (_buffer.length < totalLen) break; // payload not complete yet
        final raw = Uint8List.fromList(_buffer.sublist(0, totalLen));
        _buffer.removeRange(0, totalLen);
        final p = _parseRxFrame(raw);
        if (p != null) frames.add(p);
        continue;
      }

      // Unknown / garbage byte — skip
      _buffer.removeAt(0);
    }

    return frames;
  }

  /// Reset the internal buffer (e.g. on disconnect).
  void clear() => _buffer.clear();

  // ───────────────────────────────────────────────
  //  Individual frame parsers
  // ───────────────────────────────────────────────

  ParsedFrame? _parseConnectResponse(Uint8List buf) {
    if (buf.length < 5 || buf[0] != 0xA1) return null;
    const statusMap = {
      0x00: 'SUCCESS',
      0x01: 'FAILURE',
      0x02: 'INVALID_BAUD',
      0x03: 'HARDWARE_ERROR',
    };
    return ParsedFrame(FrameType.connectResponse, {
      'type': 'CONNECT_RESPONSE',
      'status': statusMap[buf[1]] ?? 'UNKNOWN',
      'success': buf[1] == 0x00,
      'channel': buf[2],
      'canType': buf[3] == 0x01 ? 'CAN_FD' : 'CLASSIC_CAN',
      'raw': _hex(buf),
    });
  }

  ParsedFrame? _parseRxFrame(Uint8List buf) {
    if (buf.length < 11 || buf[0] != 0xF1 || buf[1] != 0x00) return null;

    // Timestamp: 4 bytes little-endian (microseconds counter from device)
    final timestamp =
        buf[2] | (buf[3] << 8) | (buf[4] << 16) | (buf[5] << 24);

    // CAN ID: 4 bytes little-endian; bit 31 = extended flag
    final rawId =
        buf[6] | (buf[7] << 8) | (buf[8] << 16) | (buf[9] << 24);
    final isExtended = (rawId & 0x80000000) != 0;
    final canId = rawId & 0x7FFFFFFF;

    // DLC + Channel
    final dlcByte = buf[10];
    final dlc = dlcByte & 0x0F;
    final channel = (dlcByte >> 4) & 0x0F;
    final dataLen = dlcToLength[dlc] ?? dlc;

    final data = buf.sublist(11, 11 + dataLen);
    final canIdStr = '0x${canId.toRadixString(16).toUpperCase().padLeft(isExtended ? 8 : 3, '0')}';
    final dataHex = data
        .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join(' ');

    return ParsedFrame(FrameType.rxFrame, {
      'type': 'RX_FRAME',
      'timestamp': timestamp,
      'canId': canIdStr,
      'canIdRaw': canId,
      'isExtended': isExtended,
      'channel': channel + 1, // 0 → Ch1, 1 → Ch2
      'dlc': dlc,
      'dataLength': dataLen,
      'dataHex': dataHex,
      'raw': _hex(buf),
    });
  }

  ParsedFrame? _parseHeartbeatResponse(Uint8List buf) {
    if (buf.length < 2 || buf[0] != 0xD1) return null;
    return ParsedFrame(FrameType.heartbeatResponse, {
      'type': 'HEARTBEAT_RESPONSE',
      'status': buf[1] == 0x00 ? 'OK' : 'ERROR',
      'healthy': buf[1] == 0x00,
      'raw': _hex(buf),
    });
  }

  String _hex(Uint8List buf) =>
      buf.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join('');
}
