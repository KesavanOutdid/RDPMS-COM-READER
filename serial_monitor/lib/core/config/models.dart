import 'dart:typed_data';

/// Configuration for serial port connection
class SerialPortConfig {
  String portName;
  int baudRate;
  int dataBits;
  int stopBits;
  int parity;
  int flowControl;

  SerialPortConfig({
    this.portName = '',
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.flowControl = 0,
  });

  Map<String, dynamic> toJson() => {
    'portName': portName,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'stopBits': stopBits,
    'parity': parity,
    'flowControl': flowControl,
  };

  factory SerialPortConfig.fromJson(Map<String, dynamic> json) {
    return SerialPortConfig(
      portName: json['portName'] ?? '',
      baudRate: json['baudRate'] ?? 115200,
      dataBits: json['dataBits'] ?? 8,
      stopBits: json['stopBits'] ?? 1,
      parity: json['parity'] ?? 0,
      flowControl: json['flowControl'] ?? 0,
    );
  }
}

/// Enum for message direction
enum MessageDirection { sent, received }

/// Enum for display format
enum DisplayFormat { ascii, hex, decimal, binary }

/// Frontend-only CAN frame format selection for saved send sequences.
enum CanFrameFormat { standard, extended }

/// Frontend-only CAN frame type selection for saved send sequences.
enum CanFrameType { data, remote }

Uint8List parseSequenceInput(String input, DisplayFormat format) {
  switch (format) {
    case DisplayFormat.ascii:
      return Uint8List.fromList(input.codeUnits);
    case DisplayFormat.hex:
      final normalized = input
          .trim()
          .replaceAll(RegExp(r'[^0-9a-fA-F\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      final parts = normalized
          .split(' ')
          .where((part) => part.isNotEmpty)
          .toList();
      return Uint8List.fromList(
        parts.map((part) => int.parse(part, radix: 16)).toList(),
      );
    case DisplayFormat.decimal:
      final parts = input
          .split(RegExp(r'[\s,]+'))
          .where((part) => part.isNotEmpty)
          .toList();
      return Uint8List.fromList(parts.map(int.parse).toList());
    case DisplayFormat.binary:
      final parts = input
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      return Uint8List.fromList(
        parts.map((part) => int.parse(part, radix: 2)).toList(),
      );
  }
}

String formatSequenceBytes(Uint8List bytes, DisplayFormat format) {
  switch (format) {
    case DisplayFormat.ascii:
      return String.fromCharCodes(bytes);
    case DisplayFormat.hex:
      return bytes
          .map((byte) => byte.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(' ');
    case DisplayFormat.decimal:
      return bytes.map((byte) => byte.toString()).join(' ');
    case DisplayFormat.binary:
      return bytes
          .map((byte) => byte.toRadixString(2).padLeft(8, '0'))
          .join(' ');
  }
}

String convertSequenceInput(
  String input,
  DisplayFormat from,
  DisplayFormat to,
) {
  if (input.trim().isEmpty || from == to) {
    return input;
  }

  final bytes = parseSequenceInput(input, from);
  return formatSequenceBytes(bytes, to);
}

class SendSequence {
  String name;
  String sequence;
  DisplayFormat format;
  String documentation;
  CanFrameFormat canFrameFormat;
  CanFrameType canFrameType;
  String canIdHex;
  int channel;
  int repeatCount;
  int sendCycleMs;
  bool idIncrementEnabled;
  bool dataIncrementEnabled;

  SendSequence({
    required this.name,
    this.sequence = '',
    this.format = DisplayFormat.hex,
    this.documentation = '',
    this.canFrameFormat = CanFrameFormat.standard,
    this.canFrameType = CanFrameType.data,
    this.canIdHex = '',
    this.channel = 1,
    this.repeatCount = 1,
    this.sendCycleMs = 0,
    this.idIncrementEnabled = false,
    this.dataIncrementEnabled = false,
  });

  bool get isPlaceholder =>
      name.trim().isEmpty &&
      sequence.trim().isEmpty &&
      documentation.trim().isEmpty;

  String get sequencePreview {
    if (sequence.trim().isEmpty) {
      return '';
    }

    switch (format) {
      case DisplayFormat.ascii:
        return sequence;
      case DisplayFormat.hex:
        return sequence.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
      case DisplayFormat.decimal:
      case DisplayFormat.binary:
        return sequence.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
}

/// A single serial message with timestamp and raw data
class SerialMessage {
  final String text;
  final Uint8List rawBytes;
  final MessageDirection direction;
  final DateTime timestamp;
  final int tabIndex;

  // CAN-specific fields
  final String? canId;
  final int? channel;
  final int? dlc;
  final String? type;     // e.g., 'Data', 'Remote'
  final String? canFormat; // e.g., 'Standard', 'Extended'
  final String? timeStampHex; // e.g., '0x2074B6'

  SerialMessage({
    required this.text,
    required this.rawBytes,
    required this.direction,
    required this.timestamp,
    required this.tabIndex,
    this.canId,
    this.channel,
    this.dlc,
    this.type,
    this.canFormat,
    this.timeStampHex,
  });

  /// Get formatted text based on display format
  String getFormatted(DisplayFormat format) {
    if (rawBytes.isEmpty && text.isNotEmpty) return text;
    switch (format) {
      case DisplayFormat.ascii:
        return String.fromCharCodes(rawBytes);
      case DisplayFormat.hex:
        return rawBytes
            .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
            .join(' ');
      case DisplayFormat.decimal:
        return rawBytes.map((b) => b.toString().padLeft(3, '0')).join(' ');
      case DisplayFormat.binary:
        return rawBytes
            .map((b) => b.toRadixString(2).padLeft(8, '0'))
            .join(' ');
    }
  }

  /// Get direction label
  String get directionLabel => direction == MessageDirection.sent ? 'Send' : 'Receive';

  /// Get formatted timestamp (HH:mm:ss.SSS)
  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// Individual tab data
class SerialTab {
  String name;
  String? tabCanId;
  final List<SerialMessage> messages;
  final List<SendSequence> sendSequences;
  bool autoScroll;
  DisplayFormat displayFormat;
  DisplayFormat sendFormat;
  String lineEnding;
  String pendingInput;
  int selectedSendSequenceIndex;

  SerialTab({
    required this.name,
    this.tabCanId,
    List<SerialMessage>? messages,
    List<SendSequence>? sendSequences,
    this.autoScroll = true,
    this.displayFormat = DisplayFormat.hex,
    this.sendFormat = DisplayFormat.hex,
    this.lineEnding = 'CR+LF',
    this.pendingInput = '',
    this.selectedSendSequenceIndex = 0,
  }) : messages = messages ?? [],
       sendSequences = sendSequences ?? [SendSequence(name: tabCanId != null && tabCanId.isNotEmpty ? 'Msg ($tabCanId)' : 'message 1', canIdHex: tabCanId ?? '')];

  /// Add a message to this tab
  void addMessage(SerialMessage message) {
    messages.add(message);
  }

  /// Clear all messages in this tab
  void clearMessages() {
    messages.clear();
  }
}
