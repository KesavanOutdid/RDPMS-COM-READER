// CAN Bus connection configuration model
// Based on the CONNECT frame protocol specification
//
// CONNECT FRAME (7 bytes):
// Byte 0: Command (0xA0 = CONNECT)
// Byte 1: Interface (0x01 = USB)
// Byte 2: Channel (0x00 = Ch1, 0x01 = Ch2)
// Byte 3: Nominal Baud Rate
// Byte 4: Mode / Data Baud
// Byte 5: CAN Type + Flags
// Byte 6: Reserved (0x00)

/// CAN channel selection
enum CanChannel {
  channel1(0x00, 'Channel 1'),
  channel2(0x01, 'Channel 2');

  final int value;
  final String label;
  const CanChannel(this.value, this.label);
}

/// CAN nominal baud rate (Byte 3)
enum CanNominalBaudRate {
  kbps10(0x01, '10 kbps'),
  kbps20(0x02, '20 kbps'),
  kbps50(0x03, '50 kbps'),
  kbps80(0x04, '80 kbps'),
  kbps100(0x05, '100 kbps'),
  kbps125(0x06, '125 kbps'),
  kbps250(0x07, '250 kbps'),
  kbps500(0x08, '500 kbps'),
  kbps800(0x09, '800 kbps'),
  mbps1(0x0A, '1 Mbps');

  final int value;
  final String label;
  const CanNominalBaudRate(this.value, this.label);
}

/// CAN type selection
enum CanType {
  classicCan(0, 'Classic CAN'),
  canFd(1, 'CAN FD');

  final int value;
  final String label;
  const CanType(this.value, this.label);
}

/// Classic CAN mode (Byte 4 when Classic CAN is selected)
enum ClassicCanMode {
  normal(0x00, 'Normal'),
  loopback(0x01, 'Loopback'),
  silent(0x02, 'Silent');

  final int value;
  final String label;
  const ClassicCanMode(this.value, this.label);
}

/// CAN FD data baud rate (Byte 4 when CAN FD is selected)
enum CanFdDataBaud {
  mbps1(0x01, '1 Mbps'),
  mbps2(0x02, '2 Mbps'),
  mbps4(0x03, '4 Mbps'),
  mbps5(0x04, '5 Mbps'),
  mbps8(0x05, '8 Mbps');

  final int value;
  final String label;
  const CanFdDataBaud(this.value, this.label);
}

/// CAN bus connection configuration
class CanConfig {
  CanChannel channel;
  CanNominalBaudRate nominalBaudRate;
  CanType canType;

  // Classic CAN fields
  ClassicCanMode classicMode;

  // CAN FD fields
  CanFdDataBaud fdDataBaud;

  // Flags (Byte 5)
  bool brsEnabled; // Bit Rate Switching (Bit 1)
  bool nonIso;     // FD Format: false = ISO, true = Non-ISO (Bit 2)

  CanConfig({
    this.channel = CanChannel.channel1,
    this.nominalBaudRate = CanNominalBaudRate.kbps500,
    this.canType = CanType.classicCan,
    this.classicMode = ClassicCanMode.normal,
    this.fdDataBaud = CanFdDataBaud.mbps2,
    this.brsEnabled = false,
    this.nonIso = false,
  });

  /// Get Mode/Data Baud byte value (Byte 4)
  int get modeByte {
    if (canType == CanType.classicCan) {
      return classicMode.value;
    } else {
      return fdDataBaud.value;
    }
  }

  /// Get Flags byte value (Byte 5)
  /// Bit 0: CAN Type (0 = Classic, 1 = FD)
  /// Bit 1: BRS (0 = OFF, 1 = ON)
  /// Bit 2: FD Format (0 = ISO, 1 = Non-ISO)
  /// Bit 3–7: Reserved (0)
  int get flagsByte {
    int flags = 0;
    if (canType == CanType.canFd) flags |= 0x01;
    if (brsEnabled) flags |= 0x02;
    if (nonIso) flags |= 0x04;
    return flags;
  }

  /// Build the 7-byte CONNECT frame
  List<int> buildConnectFrame() {
    return [
      0xA0, // Byte 0: Command = CONNECT
      0x01, // Byte 1: Interface = USB
      channel.value, // Byte 2: Channel
      nominalBaudRate.value, // Byte 3: Nominal Baud Rate
      modeByte, // Byte 4: Mode / Data Baud
      flagsByte, // Byte 5: CAN Type + Flags
      0x00, // Byte 6: Reserved
    ];
  }

  /// Get connect frame as hex string for display
  String get connectFrameHex {
    return buildConnectFrame()
        .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join(' ');
  }

  /// Human-readable summary of the configuration
  String get summary {
    final type = canType == CanType.classicCan ? 'Classic' : 'CAN FD';
    final mode = canType == CanType.classicCan
        ? classicMode.label
        : fdDataBaud.label;
    return '${channel.label} | ${nominalBaudRate.label} | $type | $mode';
  }

  /// Copy with modifications
  CanConfig copyWith({
    CanChannel? channel,
    CanNominalBaudRate? nominalBaudRate,
    CanType? canType,
    ClassicCanMode? classicMode,
    CanFdDataBaud? fdDataBaud,
    bool? brsEnabled,
    bool? nonIso,
  }) {
    return CanConfig(
      channel: channel ?? this.channel,
      nominalBaudRate: nominalBaudRate ?? this.nominalBaudRate,
      canType: canType ?? this.canType,
      classicMode: classicMode ?? this.classicMode,
      fdDataBaud: fdDataBaud ?? this.fdDataBaud,
      brsEnabled: brsEnabled ?? this.brsEnabled,
      nonIso: nonIso ?? this.nonIso,
    );
  }
}
