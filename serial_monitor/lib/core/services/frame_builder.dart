import 'dart:typed_data';

/// Builds binary CAN frames to send to the USB-CAN device.
///
/// Protocol spec:
///   TX FRAME:   F1 01 [4‑byte canId LE] [dlc+channel] [data…]
///   HEARTBEAT:  D0 00
class CanFrameBuilder {
  /// Data length → DLC code (CAN FD mapping)
  static const Map<int, int> _lengthToDlc = {
    0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8,
    12: 9, 16: 10, 20: 11, 24: 12, 32: 13, 48: 14, 64: 15,
  };

  /// Build a CAN TX frame ready to write to USB.
  ///
  /// Returns the complete binary frame:
  ///   `F1 01 [canId 4B LE] [dlcChannel 1B] [data…]`
  static Uint8List buildTxFrame({
    required int canId,
    required List<int> data,
    int channel = 0,
    bool isExtended = false,
  }) {
    // CAN ID — 4 bytes little-endian; set bit 31 for extended
    int idValue = canId;
    if (isExtended) idValue = idValue | 0x80000000;

    // DLC from data length
    final dataLen = data.length;
    final dlc = _lengthToDlc[dataLen] ?? (dataLen > 8 ? 8 : dataLen);
    final dlcChannel = ((channel & 0x0F) << 4) | (dlc & 0x0F);

    final frame = <int>[
      0xF1, 0x01,                   // Prefix + TX marker
      idValue & 0xFF,               // CAN ID byte 0 (LSB)
      (idValue >> 8) & 0xFF,        // CAN ID byte 1
      (idValue >> 16) & 0xFF,       // CAN ID byte 2
      (idValue >> 24) & 0xFF,       // CAN ID byte 3 (MSB)
      dlcChannel,                   // DLC (low nibble) + Channel (high nibble)
      ...data,                      // Data payload
    ];

    return Uint8List.fromList(frame);
  }

  /// Build a heartbeat request frame: `D0 00`
  static Uint8List buildHeartbeatFrame() {
    return Uint8List.fromList([0xD0, 0x00]);
  }
}
