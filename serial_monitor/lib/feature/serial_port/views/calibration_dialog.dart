import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/serial_port_service.dart';
import '../../../utils/theme/app_theme.dart';

enum CalibrationType {
  lowVoltage('Low Voltage'),
  highVoltage('High Voltage'),
  acCurrent('AC Current'),
  acVoltage('AC Voltage'),
  lowCurrent('Low Current'),
  highCurrent('High Current'),
  digital('Digital'),
  accelerometer('Accelerometer');

  final String label;
  const CalibrationType(this.label);
}

class CalibrationCommand {
  final String name;
  final int hexValue;
  final String description;

  const CalibrationCommand({
    required this.name,
    required this.hexValue,
    required this.description,
  });
}

class CalibrationDialog extends StatefulWidget {
  final SerialPortService serialService;
  final bool isFD;
  final int channel;

  const CalibrationDialog({
    super.key,
    required this.serialService,
    required this.isFD,
    required this.channel,
  });

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  final TextEditingController _canIdController = TextEditingController(text: '00 00 00 01');
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _decInputController = TextEditingController();
  final TextEditingController _numberToSendController = TextEditingController(text: '1');
  final TextEditingController _sendCycleController = TextEditingController(text: '0');

  bool _isExtended = false;
  CalibrationType _selectedBoardType = CalibrationType.acVoltage;
  bool _isBigEndian = true;

  final List<_LogEntry> _log = [];
  final ScrollController _logScrollController = ScrollController();
  Function(Map<String, dynamic>)? _oldCanFrameRx;
  Function(Uint8List)? _oldDataReceived;
  CalibrationCommand? _lastSentCmd;
  int _rxResponseCount = 0;

  // Command lists map
  static final Map<CalibrationType, List<CalibrationCommand>> _boardCommands = {
    CalibrationType.lowVoltage: [
      const CalibrationCommand(name: 'CMD_ENTER_CALIBRATION', hexValue: 0xF0, description: 'Enter calibration mode'),
      const CalibrationCommand(name: 'CMD_OFFSET_REQUEST', hexValue: 0xF1, description: 'Capture & calculate baseline zero offsets'),
      const CalibrationCommand(name: 'CMD_SET_MIN', hexValue: 0xF2, description: 'Configure & store min calibration ref value'),
      const CalibrationCommand(name: 'CMD_SET_MAX', hexValue: 0xF3, description: 'Configure & store max calibration ref value'),
      const CalibrationCommand(name: 'CMD_GET_OFFSET', hexValue: 0xF4, description: 'Read stored offset factors'),
      const CalibrationCommand(name: 'CMD_GET_SLOPE', hexValue: 0xF5, description: 'Read calculated sensor slope characteristics'),
      const CalibrationCommand(name: 'CMD_GET_CONSTANT', hexValue: 0xF6, description: 'Read internal constant factors'),
      const CalibrationCommand(name: 'CMD_EXIT_CALIBRATION', hexValue: 0xF7, description: 'Save calibration matrices & exit to normal mode'),
      const CalibrationCommand(name: 'CMD_TX_REQUEST', hexValue: 0xF8, description: 'Request real-time data transmission'),
      const CalibrationCommand(name: 'CMD_SET_PERCENTAGE', hexValue: 0xF9, description: 'Configure percentage protection limits'),
      const CalibrationCommand(name: 'CMD_GET_RAW_DATA', hexValue: 0xFA, description: 'Read uncalibrated raw register values'),
      const CalibrationCommand(name: 'CMD_GET_VERSION', hexValue: 0xFB, description: 'Read firmware version information'),
    ],
    CalibrationType.highVoltage: [
      const CalibrationCommand(name: 'CMD_ENTER_CALIBRATION', hexValue: 0xE0, description: 'Enter calibration mode'),
      const CalibrationCommand(name: 'CMD_OFFSET_REQUEST', hexValue: 0xE1, description: 'Capture & calculate baseline zero offsets'),
      const CalibrationCommand(name: 'CMD_SET_MIN', hexValue: 0xE2, description: 'Configure & store min calibration ref value'),
      const CalibrationCommand(name: 'CMD_SET_MAX', hexValue: 0xE3, description: 'Configure & store max calibration ref value'),
      const CalibrationCommand(name: 'CMD_GET_OFFSET', hexValue: 0xE4, description: 'Read stored offset factors'),
      const CalibrationCommand(name: 'CMD_GET_SLOPE', hexValue: 0xE5, description: 'Read calculated sensor slope characteristics'),
      const CalibrationCommand(name: 'CMD_GET_CONSTANT', hexValue: 0xE6, description: 'Read internal constant factors'),
      const CalibrationCommand(name: 'CMD_EXIT_CALIBRATION', hexValue: 0xE7, description: 'Save calibration matrices & exit to normal mode'),
      const CalibrationCommand(name: 'CMD_TX_REQUEST', hexValue: 0xE8, description: 'Request real-time data transmission'),
      const CalibrationCommand(name: 'CMD_SET_PERCENTAGE', hexValue: 0xE9, description: 'Configure percentage protection limits'),
      const CalibrationCommand(name: 'CMD_GET_RAW_DATA', hexValue: 0xEA, description: 'Read uncalibrated raw register values'),
      const CalibrationCommand(name: 'CMD_GET_VERSION', hexValue: 0xEB, description: 'Read firmware version information'),
    ],
    CalibrationType.acCurrent: [
      const CalibrationCommand(name: 'CMD_ENTER_CALIBRATION', hexValue: 0xB0, description: 'Enter calibration mode'),
      const CalibrationCommand(name: 'CMD_OFFSET_REQUEST', hexValue: 0xB1, description: 'Capture and store offset values'),
      const CalibrationCommand(name: 'CMD_REFERENCE_VOLTAGE', hexValue: 0xB2, description: 'Reference voltage calibration'),
      const CalibrationCommand(name: 'CMD_GET_PERCENTAGE', hexValue: 0xB3, description: 'Get percentage configuration'),
      const CalibrationCommand(name: 'CMD_GET_OFFSET', hexValue: 0xB4, description: 'Read stored offset values'),
      const CalibrationCommand(name: 'CMD_GET_GAINVALUE', hexValue: 0xB5, description: 'Read gain values'),
      const CalibrationCommand(name: 'CMD_GET_VERSION', hexValue: 0xB6, description: 'Read firmware version'),
      const CalibrationCommand(name: 'CMD_EXIT_CALIBRATION', hexValue: 0xB7, description: 'Exit calibration mode and save calibration data'),
      const CalibrationCommand(name: 'CMD_TX_REQUEST', hexValue: 0xB8, description: 'Request voltage/current transmission'),
      const CalibrationCommand(name: 'CMD_SET_PERCENTAGE', hexValue: 0xB9, description: 'Configure percentage threshold'),
    ],
    CalibrationType.acVoltage: [
      const CalibrationCommand(name: 'CMD_ENTER_CALIBRATION', hexValue: 0xA0, description: 'Enter calibration mode'),
      const CalibrationCommand(name: 'CMD_OFFSET_REQUEST', hexValue: 0xA1, description: 'Capture and store offset values'),
      const CalibrationCommand(name: 'CMD_REFERENCE_VOLTAGE', hexValue: 0xA2, description: 'Reference voltage calibration'),
      const CalibrationCommand(name: 'CMD_GET_PERCENTAGE', hexValue: 0xA3, description: 'Get percentage configuration'),
      const CalibrationCommand(name: 'CMD_GET_OFFSET', hexValue: 0xA4, description: 'Read stored offset values'),
      const CalibrationCommand(name: 'CMD_GET_GAINVALUE', hexValue: 0xA5, description: 'Read gain values'),
      const CalibrationCommand(name: 'CMD_GET_VERSION', hexValue: 0xA6, description: 'Read firmware version'),
      const CalibrationCommand(name: 'CMD_EXIT_CALIBRATION', hexValue: 0xA7, description: 'Exit calibration mode and save calibration data'),
      const CalibrationCommand(name: 'CMD_TX_REQUEST', hexValue: 0xA8, description: 'Request voltage/current transmission'),
      const CalibrationCommand(name: 'CMD_SET_PERCENTAGE', hexValue: 0xA9, description: 'Configure percentage threshold'),
    ],
    CalibrationType.lowCurrent: [
      const CalibrationCommand(name: 'CMD_ENTER_CALIBRATION', hexValue: 0xC0, description: 'Enter calibration mode'),
      const CalibrationCommand(name: 'CMD_OFFSET_REQUEST', hexValue: 0xC1, description: 'Capture & calculate baseline zero offsets'),
      const CalibrationCommand(name: 'CMD_SET_MIN', hexValue: 0xC2, description: 'Configure & store min calibration ref value'),
      const CalibrationCommand(name: 'CMD_SET_MAX', hexValue: 0xC3, description: 'Configure & store max calibration ref value'),
      const CalibrationCommand(name: 'CMD_GET_OFFSET', hexValue: 0xC4, description: 'Read stored offset factors'),
      const CalibrationCommand(name: 'CMD_GET_SLOPE', hexValue: 0xC5, description: 'Read calculated sensor slope characteristics'),
      const CalibrationCommand(name: 'CMD_GET_CONSTANT', hexValue: 0xC6, description: 'Read internal constant factors'),
      const CalibrationCommand(name: 'CMD_EXIT_CALIBRATION', hexValue: 0xC7, description: 'Save calibration matrices & exit to normal mode'),
      const CalibrationCommand(name: 'CMD_TX_REQUEST', hexValue: 0xC8, description: 'Request real-time data transmission'),
      const CalibrationCommand(name: 'CMD_SET_PERCENTAGE', hexValue: 0xC9, description: 'Configure percentage protection limits'),
      const CalibrationCommand(name: 'CMD_GET_RAW_DATA', hexValue: 0xCA, description: 'Read uncalibrated raw register values'),
      const CalibrationCommand(name: 'CMD_GET_VERSION', hexValue: 0xCB, description: 'Read firmware version information'),
    ],
    CalibrationType.highCurrent: [
      const CalibrationCommand(name: 'CMD_ENTER_CALIBRATION', hexValue: 0xD0, description: 'Enter calibration mode'),
      const CalibrationCommand(name: 'CMD_OFFSET_REQUEST', hexValue: 0xD1, description: 'Capture & calculate baseline zero offsets'),
      const CalibrationCommand(name: 'CMD_SET_MIN', hexValue: 0xD2, description: 'Configure & store min calibration ref value'),
      const CalibrationCommand(name: 'CMD_SET_MAX', hexValue: 0xD3, description: 'Configure & store max calibration ref value'),
      const CalibrationCommand(name: 'CMD_GET_OFFSET', hexValue: 0xD4, description: 'Read stored offset factors'),
      const CalibrationCommand(name: 'CMD_GET_SLOPE', hexValue: 0xD5, description: 'Read calculated sensor slope characteristics'),
      const CalibrationCommand(name: 'CMD_GET_CONSTANT', hexValue: 0xD6, description: 'Read internal constant factors'),
      const CalibrationCommand(name: 'CMD_EXIT_CALIBRATION', hexValue: 0xD7, description: 'Save calibration matrices & exit to normal mode'),
      const CalibrationCommand(name: 'CMD_TX_REQUEST', hexValue: 0xD8, description: 'Request real-time data transmission'),
      const CalibrationCommand(name: 'CMD_SET_PERCENTAGE', hexValue: 0xD9, description: 'Configure percentage protection limits'),
      const CalibrationCommand(name: 'CMD_GET_RAW_DATA', hexValue: 0xDA, description: 'Read uncalibrated raw register values'),
      const CalibrationCommand(name: 'CMD_GET_VERSION', hexValue: 0xDB, description: 'Read firmware version information'),
    ],
    CalibrationType.digital: [
      const CalibrationCommand(name: 'CMD_GET_GAINVALUE', hexValue: 0x1A, description: 'Read Channels Values'),
    ],
    CalibrationType.accelerometer: [
      const CalibrationCommand(name: 'CMD_GET_GAINVALUE', hexValue: 0x1B, description: 'Read X,Y,Z axes Values'),
    ],
  };

  @override
  void initState() {
    super.initState();
    // Intercept RX frames to show response events in the activity log
    _oldCanFrameRx = widget.serialService.onCanFrameRx;
    _oldDataReceived = widget.serialService.onDataReceived;

    if (!widget.serialService.isCanMode) {
      widget.serialService.onDataReceived = (data) {
        if (_oldDataReceived != null) {
          _oldDataReceived!(data);
        }
        final dataHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        _handleIncomingCanFrame({
          'canId': '0x000',
          'dataHex': dataHex,
        });
      };
    } else {
      widget.serialService.onCanFrameRx = (frame) {
        if (_oldCanFrameRx != null) {
          _oldCanFrameRx!(frame);
        }
        _handleIncomingCanFrame(frame);
      };
    }
    _addLog('System initialized. Ready to perform calibration operations.', _LogLevel.info);
  }

  @override
  void dispose() {
    widget.serialService.onCanFrameRx = _oldCanFrameRx;
    widget.serialService.onDataReceived = _oldDataReceived;
    _canIdController.dispose();
    _payloadController.dispose();
    _decInputController.dispose();
    _numberToSendController.dispose();
    _sendCycleController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _handleIncomingCanFrame(Map<String, dynamic> frame) {
    if (!mounted) return;

    final canId = frame['canId']?.toString() ?? '';
    final dataHex = frame['dataHex']?.toString() ?? '';
    final rawBytes = _parseDataHex(dataHex);

    int readInt(List<int> bytes, int start, int length, bool bigEndian) {
      if (start + length > bytes.length) return 0;
      int val = 0;
      if (bigEndian) {
        for (int i = 0; i < length; i++) {
          val = (val << 8) | bytes[start + i];
        }
      } else {
        for (int i = 0; i < length; i++) {
          val = (val << 8) | bytes[start + length - 1 - i];
        }
      }
      return val;
    }

    double readFloat(List<int> bytes, int start, bool bigEndian) {
      if (start + 4 > bytes.length) return 0.0;
      final list = Uint8List.fromList(bytes.sublist(start, start + 4));
      final byteData = ByteData.view(list.buffer);
      return byteData.getFloat32(0, bigEndian ? Endian.big : Endian.little);
    }

    if (frame['type'] == 'heartbeat' || frame['type'] == 'HEARTBEAT_RESPONSE') {
      return;
    }

    String decodedMsg = '';
    _LogLevel level = _LogLevel.rx;

    final isSlopeResponse = rawBytes.length == 8 && 
        (_lastSentCmd?.name == 'CMD_GET_SLOPE' || 
         _lastSentCmd?.hexValue == 0xF5 || 
         _lastSentCmd?.hexValue == 0xE5 || 
         _lastSentCmd?.hexValue == 0xC5 || 
         _lastSentCmd?.hexValue == 0xD5);

    final isConstantResponse = rawBytes.length == 8 && 
        (_lastSentCmd?.name == 'CMD_GET_CONSTANT' || 
         _lastSentCmd?.hexValue == 0xF6 || 
         _lastSentCmd?.hexValue == 0xE6 || 
         _lastSentCmd?.hexValue == 0xC6 || 
         _lastSentCmd?.hexValue == 0xD6);

    if (isSlopeResponse) {
      final m1Int = readInt(rawBytes, 0, 4, true);
      final m2Int = readInt(rawBytes, 4, 4, true);
      final m1Float = readFloat(rawBytes, 0, true);
      final m2Float = readFloat(rawBytes, 4, true);

      final cmdLabel = _lastSentCmd?.name ?? 'CMD_GET_SLOPE';
      decodedMsg = '$cmdLabel — M1: ${m1Float.toStringAsFixed(4)} (Raw: $m1Int), M2: ${m2Float.toStringAsFixed(4)} (Raw: $m2Int)';
      level = _LogLevel.info;
      _lastSentCmd = null;
    } else if (isConstantResponse) {
      final c1Int = readInt(rawBytes, 0, 4, true);
      final c2Int = readInt(rawBytes, 4, 4, true);
      final c1Float = readFloat(rawBytes, 0, true);
      final c2Float = readFloat(rawBytes, 4, true);

      final cmdLabel = _lastSentCmd?.name ?? 'CMD_GET_CONSTANT';
      decodedMsg = '$cmdLabel — C1: ${c1Float.toStringAsFixed(4)} (Raw: $c1Int), C2: ${c2Float.toStringAsFixed(4)} (Raw: $c2Int)';
      level = _LogLevel.info;
      _lastSentCmd = null;
    } else {
      bool isSuccess = false;
      bool isError = false;

      if (rawBytes.length >= 2 && rawBytes[0] == 0x4F && rawBytes[1] == 0x4B) {
        isSuccess = true;
      } else if (rawBytes.length >= 3 && rawBytes[1] == 0x4F && rawBytes[2] == 0x4B) {
        isSuccess = true;
      }

      if (rawBytes.length >= 3 && rawBytes[0] == 0x45 && rawBytes[1] == 0x52 && rawBytes[2] == 0x52) {
        isError = true;
      } else if (rawBytes.length >= 4 && rawBytes[1] == 0x45 && rawBytes[2] == 0x52 && rawBytes[3] == 0x52) {
        isError = true;
      }

      final isMeasurementCmd = rawBytes.isNotEmpty &&
          (rawBytes[0] == 0xF8 ||
              rawBytes[0] == 0xE8 ||
              rawBytes[0] == 0xB8 ||
              rawBytes[0] == 0xA8 ||
              rawBytes[0] == 0xC8 ||
              rawBytes[0] == 0xD8);

      final isOffsetOrRawDataCmd = rawBytes.isNotEmpty &&
          (rawBytes[0] == 0xF4 ||
              rawBytes[0] == 0xE4 ||
              rawBytes[0] == 0xB4 ||
              rawBytes[0] == 0xA4 ||
              rawBytes[0] == 0xC4 ||
              rawBytes[0] == 0xD4 ||
              rawBytes[0] == 0xFA ||
              rawBytes[0] == 0xEA ||
              rawBytes[0] == 0xCA ||
              rawBytes[0] == 0xDA);

      final isSingleDecimalCmd = rawBytes.isNotEmpty &&
          (rawBytes[0] == 0xF5 ||
              rawBytes[0] == 0xE5 ||
              rawBytes[0] == 0xC5 ||
              rawBytes[0] == 0xD5 ||
              rawBytes[0] == 0xF6 ||
              rawBytes[0] == 0xE6 ||
              rawBytes[0] == 0xC6 ||
              rawBytes[0] == 0xD6 ||
              rawBytes[0] == 0xB3 ||
              rawBytes[0] == 0xA3 ||
              rawBytes[0] == 0xB5 ||
              rawBytes[0] == 0xA5);

      final isVersionCmd = rawBytes.isNotEmpty &&
          (rawBytes[0] == 0xFB ||
              rawBytes[0] == 0xEB ||
              rawBytes[0] == 0xB6 ||
              rawBytes[0] == 0xA6 ||
              rawBytes[0] == 0xCB ||
              rawBytes[0] == 0xDB);

      final isDigitalCmd = rawBytes.isNotEmpty && rawBytes[0] == 0x1A;
      final isAccelCmd = rawBytes.isNotEmpty && rawBytes[0] == 0x1B;

      if (isSuccess) {
        String cmdName = '';
        if (rawBytes.length >= 3 && rawBytes[1] == 0x4F && rawBytes[2] == 0x4B) {
          final cmdByte = rawBytes[0];
          for (final list in _boardCommands.values) {
            final found = list.firstWhere(
              (c) => c.hexValue == cmdByte,
              orElse: () => const CalibrationCommand(name: '', hexValue: 0, description: ''),
            );
            if (found.name.isNotEmpty) {
              cmdName = found.name;
              break;
            }
          }
        }
        decodedMsg = cmdName.isNotEmpty ? 'Success Handshake (OK) — $cmdName' : 'Success Handshake (OK)';
        level = _LogLevel.success;
      } else if (isError) {
        String cmdName = '';
        if (rawBytes.length >= 4 && rawBytes[1] == 0x45 && rawBytes[2] == 0x52 && rawBytes[3] == 0x52) {
          final cmdByte = rawBytes[0];
          for (final list in _boardCommands.values) {
            final found = list.firstWhere(
              (c) => c.hexValue == cmdByte,
              orElse: () => const CalibrationCommand(name: '', hexValue: 0, description: ''),
            );
            if (found.name.isNotEmpty) {
              cmdName = found.name;
              break;
            }
          }
        }
        decodedMsg = cmdName.isNotEmpty ? 'Error Handshake (ERR) — $cmdName' : 'Error Handshake (ERR)';
        level = _LogLevel.error;
      } else if (isMeasurementCmd && rawBytes.length >= 5) {
        final ch1Val = readInt(rawBytes, 1, 2, true); // Always Big-Endian
        final ch2Val = readInt(rawBytes, 3, 2, true); // Always Big-Endian

        String unit = 'V';
        double divisor = 100.0;
        int fractionDigits = 2;
        if (rawBytes[0] == 0xB8 || rawBytes[0] == 0xC8 || rawBytes[0] == 0xD8) {
          unit = 'A';
          divisor = 1000.0;
          fractionDigits = 3;
        }

        final ch1 = ch1Val / divisor;
        final ch2 = ch2Val / divisor;

        decodedMsg = 'Measurements — Ch1: ${ch1.toStringAsFixed(fractionDigits)}$unit, Ch2: ${ch2.toStringAsFixed(fractionDigits)}$unit';
        level = _LogLevel.info;
      } else if (isOffsetOrRawDataCmd && rawBytes.length >= 4) {
        final List<String> channelParts = [];
        int i = 1;
        while (i + 2 < rawBytes.length) {
          final chIndicator = rawBytes[i];
          if (chIndicator == 0) {
            break;
          }
          final val = readInt(rawBytes, i + 1, 2, true); // Big-Endian 2-byte value
          channelParts.add('Ch$chIndicator: $val');
          i += 3;
        }
        
        String cmdLabel = '';
        final cmdByte = rawBytes[0];
        for (final list in _boardCommands.values) {
          final found = list.firstWhere(
            (c) => c.hexValue == cmdByte,
            orElse: () => const CalibrationCommand(name: '', hexValue: 0, description: ''),
          );
          if (found.name.isNotEmpty) {
            cmdLabel = found.name;
            break;
          }
        }

        if (channelParts.isNotEmpty) {
          decodedMsg = cmdLabel.isNotEmpty 
              ? '$cmdLabel — ${channelParts.join(", ")}'
              : 'Channels — ${channelParts.join(", ")}';
        } else {
          final val = readInt(rawBytes, 1, rawBytes.length - 1, true);
          decodedMsg = cmdLabel.isNotEmpty ? '$cmdLabel: $val' : 'Decimal: $val';
        }
        level = _LogLevel.info;
      } else if (isSingleDecimalCmd && rawBytes.length >= 3) {
        final val = readInt(rawBytes, 1, rawBytes.length - 1, true); // Always Big-Endian
        String cmdLabel = '';
        final cmdByte = rawBytes[0];
        for (final list in _boardCommands.values) {
          final found = list.firstWhere(
            (c) => c.hexValue == cmdByte,
            orElse: () => const CalibrationCommand(name: '', hexValue: 0, description: ''),
          );
          if (found.name.isNotEmpty) {
            cmdLabel = found.name;
            break;
          }
        }
        decodedMsg = cmdLabel.isNotEmpty ? '$cmdLabel: $val' : 'Decimal: $val';
        level = _LogLevel.info;
      } else if (isDigitalCmd && rawBytes.length >= 2) {
        decodedMsg = 'Channels — Ch1: ${rawBytes[1]}';
        level = _LogLevel.info;
      } else if (isAccelCmd && rawBytes.length >= 13) {
        final xMin = readInt(rawBytes, 1, 2, true); // Always Big-Endian
        final xMax = readInt(rawBytes, 3, 2, true); // Always Big-Endian
        final yMin = readInt(rawBytes, 5, 2, true); // Always Big-Endian
        final yMax = readInt(rawBytes, 7, 2, true); // Always Big-Endian
        final zMin = readInt(rawBytes, 9, 2, true); // Always Big-Endian
        final zMax = readInt(rawBytes, 11, 2, true); // Always Big-Endian
        decodedMsg = 'Accelerometer — X Min: $xMin, X Max: $xMax, Y Min: $yMin, Y Max: $yMax, Z Min: $zMin, Z Max: $zMax';
        level = _LogLevel.info;
      } else if (isVersionCmd && rawBytes.length >= 2) {
        int offset = 1;
        if (rawBytes.length >= 6 + offset) {
          final boardType = rawBytes[0 + offset];
          final hwRev = rawBytes[1 + offset];
          final prodId = (rawBytes[2 + offset] << 8) | rawBytes[3 + offset];
          final nodeId = rawBytes[4 + offset];
          final versionBytes = rawBytes.sublist(5 + offset);
          final versionStr = String.fromCharCodes(versionBytes.where((b) => b >= 32 && b <= 126));

          decodedMsg = 'Board Info: Type 0x${boardType.toRadixString(16).toUpperCase()}, Rev $hwRev, Prod ID $prodId, Node $nodeId, Version: "$versionStr"';
        } else {
          final asciiBytes = rawBytes.sublist(1);
          final asciiStr = String.fromCharCodes(asciiBytes.where((b) => b >= 32 && b <= 126));
          decodedMsg = 'Version: $asciiStr';
        }
        level = _LogLevel.info;
      } else {
        // Check for version response format where command byte is NOT echoed (offset = 0)
        if (rawBytes.length >= 6) {
          final boardType = rawBytes[0];
          final hwRev = rawBytes[1];
          final prodId = (rawBytes[2] << 8) | rawBytes[3];
          final nodeId = rawBytes[4];
          final versionBytes = rawBytes.sublist(5);
          final versionStr = String.fromCharCodes(versionBytes.where((b) => b >= 32 && b <= 126));

          decodedMsg = 'Board Info: Type 0x${boardType.toRadixString(16).toUpperCase()}, Rev $hwRev, Prod ID $prodId, Node $nodeId, Version: "$versionStr"';
          level = _LogLevel.info;
        }
      }
    }

    final bitCount = rawBytes.length * 8;
    String message;
    if (decodedMsg.isNotEmpty) {
      _rxResponseCount++;
      message = '← [$_rxResponseCount] RX [$canId] $dataHex ($decodedMsg, $bitCount bits)';
    } else {
      message = '← RX [$canId] $dataHex ($bitCount bits)';
    }

    _addLog(message, level);
  }

  List<int> _parseDataHex(String? dataHex) {
    if (dataHex == null || dataHex.isEmpty) return [];
    try {
      return dataHex
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((p) => int.parse(p, radix: 16))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _addLog(String message, _LogLevel level) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    setState(() {
      _log.add(_LogEntry(timestamp: ts, message: message, level: level));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _applyPayloadHelper() {
    final text = _decInputController.text.trim();
    if (text.isEmpty) return;

    final value = int.tryParse(text);
    if (value == null) {
      _addLog('❌ Invalid decimal value: "$text"', _LogLevel.error);
      return;
    }

    // Determine the number of bytes needed to represent the value
    // Minimum of 2 bytes (16-bit) to represent endianness correctly
    int byteLength = 2;
    if (value >= 0x100000000000000) {
      byteLength = 8;
    } else if (value >= 0x1000000000000) {
      byteLength = 7;
    } else if (value >= 0x10000000000) {
      byteLength = 6;
    } else if (value >= 0x100000000) {
      byteLength = 5;
    } else if (value >= 0x1000000) {
      byteLength = 4;
    } else if (value >= 0x10000) {
      byteLength = 3;
    }

    final bytes = List<int>.filled(8, 0);
    if (_isBigEndian) {
      for (int i = 0; i < byteLength; i++) {
        bytes[i] = (value >> ((byteLength - 1 - i) * 8)) & 0xFF;
      }
    } else {
      for (int i = 0; i < byteLength; i++) {
        bytes[i] = (value >> (i * 8)) & 0xFF;
      }
    }

    final hexStr = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    setState(() {
      _payloadController.text = hexStr;
    });

    _addLog('✓ Converted decimal $value to 64-bit ${_isBigEndian ? "MSB" : "LSB"} Hex: $hexStr', _LogLevel.info);
  }

  Future<void> _sendCommand(CalibrationCommand cmd) async {
    final rawCanId = _canIdController.text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (rawCanId.isEmpty) {
      _addLog('❌ CAN ID cannot be empty', _LogLevel.error);
      return;
    }
    final canIdStr = '0x$rawCanId';

    List<int> payloadBytes = [];
    final payloadText = _payloadController.text.trim();
    if (payloadText.isNotEmpty) {
      try {
        final cleanPayload = payloadText.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
        if (cleanPayload.length % 2 != 0) {
          throw Exception('Payload hex must have an even number of characters');
        }
        for (var i = 0; i < cleanPayload.length; i += 2) {
          payloadBytes.add(int.parse(cleanPayload.substring(i, i + 2), radix: 16));
        }
      } catch (e) {
        _addLog('❌ Payload format error: ${e.toString()}', _LogLevel.error);
        return;
      }
    }

    // Combine Command Hex + Payload
    List<int> frameData = [cmd.hexValue, ...payloadBytes];

    // Enforce standard CAN frame size of exactly 8 bytes (64 bits)
    int paddedLength = 8;
    if (frameData.length > paddedLength) {
      frameData = frameData.sublist(0, paddedLength);
    } else {
      while (frameData.length < paddedLength) {
        frameData.add(0);
      }
    }

    final cycles = int.tryParse(_numberToSendController.text) ?? 1;
    final delayMs = int.tryParse(_sendCycleController.text) ?? 0;

    setState(() {
      _rxResponseCount = 0;
    });

    for (int i = 0; i < cycles; i++) {
      if (i > 0 && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      final success = widget.serialService.isCanMode
          ? widget.serialService.sendCanFrame(
              canId: canIdStr,
              data: frameData,
              channel: widget.channel,
              isExtended: _isExtended,
              isFD: widget.isFD,
            )
          : widget.serialService.sendData(Uint8List.fromList(frameData));

      if (success) {
        _lastSentCmd = cmd;
        final hexDataStr = frameData
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        final bitCount = frameData.length * 8;

        final txPrefix = cycles > 1 ? '→ [${i + 1}] TX' : '→ TX';
        _addLog('$txPrefix [$canIdStr] $hexDataStr (Cmd: ${cmd.name}, $bitCount bits)', _LogLevel.tx);
      } else {
        final cycleStr = cycles > 1 ? ' (Cycle ${i + 1}/$cycles)' : '';
        _addLog('❌ Failed to send command: ${cmd.name}$cycleStr', _LogLevel.error);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final commands = _boardCommands[_selectedBoardType] ?? [];

    return Scaffold(
      backgroundColor: AppTheme.bgDarkest,
      appBar: AppBar(
        backgroundColor: AppTheme.panelHeader,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Bolt Calibration Tools',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textBright,
          ),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 15),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.successColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Connected (${widget.isFD ? "CAN FD" : "Classic CAN"})',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.successColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Pane: Controls & Commands
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildConfigSection(),
                                  const SizedBox(height: 12),
                                  _buildPayloadSection(),
                                  const SizedBox(height: 12),
                                  _buildCommandsSection(commands),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Right Pane: Activity Console Log
                    Expanded(
                      flex: 4,
                      child: _buildLogSection(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Divider(height: 1, color: AppTheme.borderColor),
              const SizedBox(height: 15),
              _buildFooterRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Target CAN ID
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target CAN ID',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _canIdController,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '00 00 00 01',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        onChanged: (value) {
                          final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
                          final buffer = StringBuffer();
                          for (var i = 0; i < compact.length; i++) {
                            if (i > 0 && i % 2 == 0) buffer.write(' ');
                            buffer.write(compact[i]);
                          }
                          final normalized = buffer.toString();
                          if (normalized != value) {
                            _canIdController.value = TextEditingValue(
                              text: normalized,
                              selection: TextSelection.collapsed(offset: normalized.length),
                            );
                          }
                          
                          // Auto toggle extended based on value
                          final parsed = int.tryParse(compact, radix: 16) ?? 0;
                          setState(() {
                            _isExtended = parsed > 0x7FF;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(width: 1, height: 56, color: AppTheme.borderColor),
              const SizedBox(width: 14),
              // Bot Type Dropdown
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Board / Bot Type Selection',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: DropdownButtonFormField<CalibrationType>(
                        initialValue: _selectedBoardType,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedBoardType = val;
                            });
                            _addLog('✓ Switched board calibration profile to: ${val.label}', _LogLevel.info);
                          }
                        },
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                        dropdownColor: AppTheme.bgElevated,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        items: CalibrationType.values.map((ct) => DropdownMenuItem(
                          value: ct,
                          child: Text(ct.label),
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppTheme.borderColor),
          const SizedBox(height: 12),
          Row(
            children: [
              // Number to send
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Number to send',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _numberToSendController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'e.g. 1',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Send cycle (ms)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send cycle (ms)',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _sendCycleController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'e.g. 0',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Manual Hex payload input
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Optional Command Payload (Space-separated Hex bytes)',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _payloadController,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. 3A 98 (for 150.00V), 02 (for percentage), or leave empty',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        onChanged: (value) {
                          final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
                          final buffer = StringBuffer();
                          for (var i = 0; i < compact.length; i++) {
                            if (i > 0 && i % 2 == 0) buffer.write(' ');
                            buffer.write(compact[i]);
                          }
                          final normalized = buffer.toString();
                          if (normalized != value) {
                            _payloadController.value = TextEditingValue(
                              text: normalized,
                              selection: TextSelection.collapsed(offset: normalized.length),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_payloadController.text.isNotEmpty) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 22.0),
                  child: SizedBox(
                    height: 38,
                    child: IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.errorColor, size: 18),
                      onPressed: () {
                        setState(() {
                          _payloadController.clear();
                        });
                      },
                      tooltip: 'Clear payload',
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Payload Helper
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.bgMedium,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payload Calculator Helper',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 16,
                              width: 22,
                              child: Radio<bool>(
                                value: true,
                                groupValue: _isBigEndian,
                                activeColor: AppTheme.accentCyan,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _isBigEndian = val);
                                    _applyPayloadHelper();
                                  }
                                },
                              ),
                            ),
                            Text(
                              'MSB (Big Endian)',
                              style: GoogleFonts.inter(fontSize: 9.5, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 16,
                              width: 22,
                              child: Radio<bool>(
                                value: false,
                                groupValue: _isBigEndian,
                                activeColor: AppTheme.accentCyan,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _isBigEndian = val);
                                    _applyPayloadHelper();
                                  }
                                },
                              ),
                            ),
                            Text(
                              'LSB (Little Endian)',
                              style: GoogleFonts.inter(fontSize: 9.5, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: TextField(
                          controller: _decInputController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Dec value (e.g. 15000)',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 34,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.calculate, size: 14),
                        label: Text('Set Payload', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: AppTheme.accentCyan,
                        ),
                        onPressed: _applyPayloadHelper,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandsSection(List<CalibrationCommand> commands) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on, size: 14, color: AppTheme.accentOrange),
              const SizedBox(width: 6),
              Text(
                'Calibration Commands (Profile: ${_selectedBoardType.label})',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (commands.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No commands defined for this profile.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: commands.length,
              itemBuilder: (context, idx) {
                final cmd = commands[idx];
                return _buildCommandButton(cmd);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCommandButton(CalibrationCommand cmd) {
    final hexStr = '0x${cmd.hexValue.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    return Material(
      color: AppTheme.bgDark.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => _sendCommand(cmd),
        borderRadius: BorderRadius.circular(6),
        hoverColor: AppTheme.primaryColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cmd.name,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.panelHeader,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Text(
                      hexStr,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                cmd.description,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text(
                  'Calibration Trace / Activity Log',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text('${_log.length} entries', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: const Color(0xFF64748B))),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => setState(() => _log.clear()),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Text(
                        'Clear',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _logScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                itemCount: _log.length,
                itemBuilder: (context, index) {
                  final entry = _log[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.timestamp, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF64748B))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(entry.message, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: entry.color)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow() {
    return Row(
      children: [
        Text(
          'Ensure the target node is powered on and connected to the CAN network.',
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
        ),
        const Spacer(),
        SizedBox(
          height: 36,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text('Close', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

enum _LogLevel { info, tx, rx, success, error }

class _LogEntry {
  final String timestamp;
  final String message;
  final _LogLevel level;

  _LogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  Color get color {
    switch (level) {
      case _LogLevel.tx:
        return const Color(0xFFF87171); // Light Red/Coral for TX
      case _LogLevel.rx:
        return const Color(0xFF4ADE80); // Light Green for RX
      case _LogLevel.success:
        return const Color(0xFF22C55E); // Rich Green for Success
      case _LogLevel.error:
        return const Color(0xFFEF4444); // Bright Red for Error
      case _LogLevel.info:
        return const Color(0xFFE2E8F0); // Off-white for Info
    }
  }
}
