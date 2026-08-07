import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/services/serial_port_service.dart';
import '../../../utils/theme/app_theme.dart';
import 'calibration_dialog.dart';
import 'reports_screen.dart';
import 'change_serial_no_dialog.dart';


class DeviceTestDialog extends StatefulWidget {
  final SerialPortService serialService;
  final bool isFD;
  final int channel;
  final bool isEmbedded;

  const DeviceTestDialog({
    super.key,
    required this.serialService,
    required this.isFD,
    required this.channel,
    this.isEmbedded = false,
  });

  @override
  State<DeviceTestDialog> createState() => _DeviceTestDialogState();
}

class _DeviceTestDialogState extends State<DeviceTestDialog> {
  // Config & Input Controllers
  final TextEditingController _canIdController = TextEditingController(text: 'FF');
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _decInputController = TextEditingController();
  final TextEditingController _numberToSendController = TextEditingController(text: '1');
  final TextEditingController _sendCycleController = TextEditingController(text: '0');

  // QC Controllers
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _targetController = TextEditingController(text: '100');
  final TextEditingController _toleranceController = TextEditingController(text: '1');
  final TextEditingController _valueController = TextEditingController();

  // Multi-Ref Verification Table Rows
  final List<_TestRefRow> _refRows = [
    _TestRefRow(),
  ];
  int _activeRowIndex = 0;

  bool _isExtended = false;
  CalibrationType _selectedBoardType = CalibrationType.acVoltage;
  bool _isBigEndian = true;
  bool _isSaving = false;

  final List<_LogEntry> _log = [];
  final ScrollController _logScrollController = ScrollController();
  
  Function(Map<String, dynamic>)? _oldCanFrameRx;
  Function(Uint8List)? _oldDataReceived;

  // Show only Voltage & Current board profiles
  static const List<CalibrationType> _testBoardTypes = [
    CalibrationType.lowVoltage,
    CalibrationType.highVoltage,
    CalibrationType.acVoltage,
    CalibrationType.lowCurrent,
    CalibrationType.highCurrent,
    CalibrationType.acCurrent,
  ];

  // Test commands — only GET VALUES + READ SERIAL NUMBER per profile
  static final Map<CalibrationType, List<CalibrationCommand>> _testCommands = {
    CalibrationType.lowVoltage: [
      const CalibrationCommand(name: 'READ SERIAL NUMBER', hexValue: 0x01, description: 'Get device serial number'),
      const CalibrationCommand(name: 'GET VALUES', hexValue: 0xF8, description: 'Request real-time Low Voltage data'),
    ],
    CalibrationType.highVoltage: [
      const CalibrationCommand(name: 'READ SERIAL NUMBER', hexValue: 0x01, description: 'Get device serial number'),
      const CalibrationCommand(name: 'GET VALUES', hexValue: 0xE8, description: 'Request real-time High Voltage data'),
    ],
    CalibrationType.acVoltage: [
      const CalibrationCommand(name: 'READ SERIAL NUMBER', hexValue: 0x01, description: 'Get device serial number'),
      const CalibrationCommand(name: 'GET VALUES', hexValue: 0xA8, description: 'Request real-time AC Voltage data'),
    ],
    CalibrationType.acCurrent: [
      const CalibrationCommand(name: 'READ SERIAL NUMBER', hexValue: 0x01, description: 'Get device serial number'),
      const CalibrationCommand(name: 'GET VALUES', hexValue: 0xB8, description: 'Request real-time AC Current data'),
    ],
    CalibrationType.lowCurrent: [
      const CalibrationCommand(name: 'READ SERIAL NUMBER', hexValue: 0x01, description: 'Get device serial number'),
      const CalibrationCommand(name: 'GET VALUES', hexValue: 0xC8, description: 'Request real-time Low Current data'),
    ],
    CalibrationType.highCurrent: [
      const CalibrationCommand(name: 'READ SERIAL NUMBER', hexValue: 0x01, description: 'Get device serial number'),
      const CalibrationCommand(name: 'GET VALUES', hexValue: 0xD8, description: 'Request real-time High Current data'),
    ],
  };

  @override
  void initState() {
    super.initState();
    
    // Intercept RX frames to show in log console + auto-populate measured value
    _oldCanFrameRx = widget.serialService.onCanFrameRx;
    _oldDataReceived = widget.serialService.onDataReceived;

    if (!widget.serialService.isCanMode) {
      widget.serialService.onDataReceived = (data) {
        if (_oldDataReceived != null) _oldDataReceived!(data);
        _handleIncomingRawSerial(data);
      };
    } else {
      widget.serialService.onCanFrameRx = (frame) {
        if (_oldCanFrameRx != null) _oldCanFrameRx!(frame);
        _handleIncomingCanFrame(frame);
      };
    }

    // Restore persistent session state if available
    if (_DeviceTestSession.savedRowsData != null && _DeviceTestSession.savedRowsData!.isNotEmpty) {
      _refRows.clear();
      for (final d in _DeviceTestSession.savedRowsData!) {
        final r = _TestRefRow(
          initialRef: d.ref,
          initialTol: d.tol,
          useCh1: d.useCh1,
          useCh2: d.useCh2,
        );
        r.ch1Val = d.ch1Val;
        r.ch2Val = d.ch2Val;
        r.ch1Pass = d.ch1Pass;
        r.ch2Pass = d.ch2Pass;
        _refRows.add(r);
      }
      _activeRowIndex = _DeviceTestSession.activeRowIndex;
      _serialController.text = _DeviceTestSession.serialNumber;
      _canIdController.text = _DeviceTestSession.canId;
      _selectedBoardType = _DeviceTestSession.boardType;
      _log.addAll(_DeviceTestSession.savedLogs);
    } else {
      _addLog('System initialized. Ready for device verification tests.', _LogLevel.info);
    }
  }

  void _saveSessionState() {
    _DeviceTestSession.serialNumber = _serialController.text;
    _DeviceTestSession.canId = _canIdController.text;
    _DeviceTestSession.boardType = _selectedBoardType;
    _DeviceTestSession.activeRowIndex = _activeRowIndex;
    _DeviceTestSession.savedLogs = List.from(_log);

    _DeviceTestSession.savedRowsData = _refRows.map((r) => _TestRefRowData(
      ref: r.refController.text,
      tol: r.tolController.text,
      useCh1: r.useCh1,
      useCh2: r.useCh2,
      ch1Val: r.ch1Val,
      ch2Val: r.ch2Val,
      ch1Pass: r.ch1Pass,
      ch2Pass: r.ch2Pass,
    )).toList();
  }

  @override
  void dispose() {
    _saveSessionState();
    widget.serialService.onCanFrameRx = _oldCanFrameRx;
    widget.serialService.onDataReceived = _oldDataReceived;
    _canIdController.dispose();
    _payloadController.dispose();
    _decInputController.dispose();
    _numberToSendController.dispose();
    _sendCycleController.dispose();
    _serialController.dispose();
    _targetController.dispose();
    _toleranceController.dispose();
    _valueController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String msg, _LogLevel level) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    if (!mounted) return;
    setState(() {
      _log.add(_LogEntry(timestamp: ts, message: msg, level: level));
      // Evict oldest 10 entries whenever limit of 100 is exceeded to maintain high-performance rendering during bulk data reception
      if (_log.length > 100) {
        _log.removeRange(0, 10);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _handleIncomingRawSerial(Uint8List data) {
    try {
      if (data.isEmpty) return;

      // 1. Check for Serial Number response (starts with 0x01 0x02 OR contains printable ASCII serial string)
      bool isSerialResponse = false;
      List<int> asciiBytes = [];

      if (data.length >= 2 && data[0] == 0x01 && data[1] == 0x02) {
        isSerialResponse = true;
        asciiBytes = data.sublist(2).where((b) => b >= 32 && b <= 126).toList();
      } else {
        final printable = data.where((b) => b >= 32 && b <= 126).toList();
        if (data.length >= 3 && printable.length >= data.length - 1) {
          final str = String.fromCharCodes(printable).trim();
          if (str.length >= 3 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(str)) {
            isSerialResponse = true;
            asciiBytes = printable;
          }
        }
      }

      if (isSerialResponse) {
        String sn = String.fromCharCodes(asciiBytes).trim();
        if (sn.isEmpty || sn.length < 2) {
          int val = 0;
          final startIdx = (data[0] == 0x01 && data[1] == 0x02) ? 2 : 0;
          for (int i = startIdx; i < data.length; i++) {
            val = (val << 8) | data[i];
          }
          sn = val.toString();
        }
        _addLog('✓ Received Serial Number from USB (Hex → ASCII): "$sn"', _LogLevel.success);
        setState(() {
          _serialController.text = sn;
        });
        _checkIfSerialTested(sn);
        return;
      }

      final asciiStr = String.fromCharCodes(data).trim();
      if (asciiStr.isEmpty) return;

      _addLog('← RX (USB): "$asciiStr"', _LogLevel.rx);

      // Try to parse a decimal/float from the serial line to auto-populate the value
      final numberRegExp = RegExp(r'[-+]?\d*\.\d+|\d+');
      final match = numberRegExp.firstMatch(asciiStr);
      if (match != null) {
        final parsedValue = double.tryParse(match.group(0)!);
        if (parsedValue != null) {
          setState(() {
            _valueController.text = parsedValue.toStringAsFixed(3);
          });
          _addLog('✓ Auto-populated measured value from USB: $parsedValue', _LogLevel.success);
        }
      }
    } catch (_) {}
  }

  void _handleIncomingCanFrame(Map<String, dynamic> frame) {
    final canId = frame['canId']?.toString() ?? '';
    final dataHex = frame['dataHex']?.toString() ?? '';
    final rawBytes = _parseDataHex(dataHex);

    if (rawBytes.isEmpty) return;

    _addLog('← RX CAN [$canId]: $dataHex', _LogLevel.rx);

    // 2. Check for standard measurement frames: 0xF8, 0xE8, 0xB8, 0xA8, 0xC8, 0xD8
    final isMeasurement = rawBytes[0] == 0xF8 || 
                          rawBytes[0] == 0xE8 || 
                          rawBytes[0] == 0xB8 || 
                          rawBytes[0] == 0xA8 || 
                          rawBytes[0] == 0xC8 || 
                          rawBytes[0] == 0xD8;

    // 1. Check for Serial Number response
    bool isSerialResponse = false;
    List<int> asciiBytes = [];

    if (rawBytes.length >= 2 && rawBytes[0] == 0x01 && rawBytes[1] == 0x02) {
      isSerialResponse = true;
      asciiBytes = rawBytes.sublist(2).where((b) => b >= 32 && b <= 126).toList();
    } else if (!isMeasurement && rawBytes.length >= 2) {
      // Check if bytes are valid printable ASCII characters (e.g. 53 54 32 35 32 38 41 56 30 38 35 37 -> ST2528AV0857)
      final printable = rawBytes.where((b) => b >= 32 && b <= 126).toList();
      if (printable.length >= 3 && printable.length >= rawBytes.length - 1) {
        isSerialResponse = true;
        asciiBytes = printable;
      }
    }

    if (isSerialResponse) {
      String sn = String.fromCharCodes(asciiBytes).trim();
      if (sn.isEmpty || sn.length < 2) {
        int val = 0;
        final startIdx = (rawBytes[0] == 0x01 && rawBytes[1] == 0x02) ? 2 : 0;
        for (int i = startIdx; i < rawBytes.length; i++) {
          val = (val << 8) | rawBytes[i];
        }
        sn = val.toString();
      }
      _addLog('✓ Decoded Serial Number from device (Hex → ASCII): "$sn"', _LogLevel.success);

      // Auto-fill Target CAN ID from the incoming response CAN ID
      final cleanRxCanId = canId.replaceAll('0x', '').replaceAll(' ', '').trim().toUpperCase();

      setState(() {
        _serialController.text = sn;
        if (cleanRxCanId.isNotEmpty) {
          _canIdController.text = cleanRxCanId;
        }
      });
      if (cleanRxCanId.isNotEmpty) {
        _addLog('✓ Auto-filled Target CAN ID from response: "$cleanRxCanId"', _LogLevel.success);
      }
      _checkIfSerialTested(sn);
      return;
    }

    if (isMeasurement && rawBytes.length >= 5) {
      // Big-Endian 2-byte parsing for Ch1 and Ch2 values
      int ch1Raw = (rawBytes[1] << 8) | rawBytes[2];
      int ch2Raw = (rawBytes[3] << 8) | rawBytes[4];
      
      // Determine unit and divisor
      double divisor = 100.0;
      String chLabel = 'V';
      if (rawBytes[0] == 0xB8 || rawBytes[0] == 0xC8 || rawBytes[0] == 0xD8) {
        divisor = 1000.0; // Current is usually in mA
        chLabel = 'A';
      }

      double ch1Val = ch1Raw / divisor;
      double ch2Val = ch2Raw / divisor;
      
      if (_activeRowIndex >= _refRows.length) {
        _activeRowIndex = 0;
      }
      
      final targetRow = _refRows.isNotEmpty ? _refRows[_activeRowIndex] : null;
      final target = targetRow != null ? (double.tryParse(targetRow.refController.text) ?? 0.0) : 0.0;
      final tolerancePct = targetRow != null ? (double.tryParse(targetRow.tolController.text) ?? 1.0) : 1.0;
      final lowerBound = target - (target * tolerancePct / 100.0);
      final upperBound = target + (target * tolerancePct / 100.0);
      
      final ch1Pass = (targetRow?.useCh1 ?? true) ? (ch1Val >= lowerBound && ch1Val <= upperBound) : null;
      final ch2Pass = (targetRow?.useCh2 ?? true) ? (ch2Val >= lowerBound && ch2Val <= upperBound) : null;

      setState(() {
        _valueController.text = ch1Val.toStringAsFixed(3);
        if (targetRow != null) {
          targetRow.ch1Val = targetRow.useCh1 ? ch1Val : null;
          targetRow.ch2Val = targetRow.useCh2 ? ch2Val : null;
          targetRow.ch1Pass = ch1Pass;
          targetRow.ch2Pass = ch2Pass;
        }
      });

      final overallPass = targetRow?.overallPass;

      final ch1Str = (targetRow?.useCh1 ?? true) ? '${ch1Val.toStringAsFixed(3)} $chLabel ${ch1Pass == true ? "✅ PASS" : "❌ FAIL"}' : 'OFF';
      final ch2Str = (targetRow?.useCh2 ?? true) ? '${ch2Val.toStringAsFixed(3)} $chLabel ${ch2Pass == true ? "✅ PASS" : "❌ FAIL"}' : 'OFF';

      final overallStatusText = overallPass == true ? "✅ OVERALL PASS" : (overallPass == false ? "❌ OVERALL FAIL" : "---");

      _addLog(
        '📊 [Row #${_activeRowIndex + 1}] CH1: $ch1Str  |  CH2: $ch2Str',
        overallPass == true ? _LogLevel.success : (overallPass == false ? _LogLevel.error : _LogLevel.info),
      );
      _addLog(
        '   Ref: $target $chLabel ± $tolerancePct% → Range: [${lowerBound.toStringAsFixed(3)} – ${upperBound.toStringAsFixed(3)}]  →  $overallStatusText',
        overallPass == true ? _LogLevel.success : (overallPass == false ? _LogLevel.error : _LogLevel.info),
      );

    }
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

  Future<void> _fetchSerialNumberFromDevice() async {
    if (!widget.serialService.isConnected) {
      _addLog('❌ Cannot request serial: port not connected.', _LogLevel.error);
      return;
    }

    _addLog('→ Sending Serial Number Request (0x01 0x02) with default CAN ID (FF)...', _LogLevel.tx);

    final List<int> frameData = [0x01, 0x02, 0, 0, 0, 0, 0, 0];

    if (widget.serialService.isCanMode) {
      // Always use default CAN ID 0x000000FF (FF) for serial number request regardless of manual edits
      const canIdStr = '0x000000FF';
      final success = widget.serialService.sendCanFrame(
        canId: canIdStr,
        data: frameData,
        channel: widget.channel,
        isExtended: _isExtended,
        isFD: widget.isFD,
      );
      if (!success) {
        _addLog('❌ Failed to send CAN frame for serial request.', _LogLevel.error);
      }
    } else {
      final success = widget.serialService.sendData(Uint8List.fromList(frameData));
      if (!success) {
        _addLog('❌ Failed to send USB serial request.', _LogLevel.error);
      }
    }
  }

  Future<void> _checkIfSerialTested(String serial) async {
    if (serial.isEmpty) return;
    
    _addLog('Checking if serial "$serial" has been tested in DB...', _LogLevel.info);
    final client = HttpClient();
    try {
      final url = Uri.parse('http://localhost:3001/api/tests?serialNumber=${Uri.encodeComponent(serial)}&limit=1');
      final request = await client.getUrl(url).timeout(const Duration(seconds: 3));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (json['success'] == true) {
          final List<dynamic> records = json['records'];
          if (records.isNotEmpty) {
            _addLog('⚠️ Alert: Serial "$serial" has ALREADY been tested in the database.', _LogLevel.error);
            if (mounted) {
              _showAlreadyTestedDialog(serial);
            }
          } else {
            _addLog('✓ Serial "$serial" is new (no existing database records).', _LogLevel.success);
          }
        }
      }
    } catch (_) {
      // Ignore network errors on check
    } finally {
      client.close();
    }
  }

  void _showAlreadyTestedDialog(String serial) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgMedium,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.accentOrange),
            const SizedBox(width: 10),
            Text(
              'Already Test Complete',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.textBright, fontSize: 15),
            ),
          ],
        ),
        content: Text(
          'Serial Number "$serial" has already been tested. Do you want to test again or not? (User\'s choice)',
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _addLog('User chose to proceed with re-testing serial "$serial".', _LogLevel.info);
            },
            child: Text('Test Again', style: GoogleFonts.inter(color: AppTheme.successColor, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _serialController.clear();
              });
              _addLog('User chose not to re-test serial "$serial". Cleared field.', _LogLevel.info);
            },
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
  }

  void _setCalculatedPayload() {
    final text = _decInputController.text.trim();
    if (text.isEmpty) return;

    final val = int.tryParse(text);
    if (val == null) {
      _addLog('❌ Invalid decimal value inside Payload Calculator Helper', _LogLevel.error);
      return;
    }

    // Convert to 2-byte hex
    final highByte = (val >> 8) & 0xFF;
    final lowByte = val & 0xFF;

    final bytes = _isBigEndian ? [highByte, lowByte] : [lowByte, highByte];
    final formatted = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

    setState(() {
      _payloadController.text = formatted;
    });

    _addLog('✓ Set payload from helper: $formatted ($text Dec)', _LogLevel.info);
  }

  String get _calculatedResult {
    final targetText = _targetController.text.trim();
    final toleranceText = _toleranceController.text.trim();
    final valueText = _valueController.text.trim();

    if (targetText.isEmpty || toleranceText.isEmpty || valueText.isEmpty) {
      return 'PENDING';
    }

    final target = double.tryParse(targetText);
    final tolerance = double.tryParse(toleranceText);
    final value = double.tryParse(valueText);

    if (target == null || tolerance == null || value == null) {
      return 'INVALID';
    }

    final minVal = target * (1.0 - (tolerance / 100.0));
    final maxVal = target * (1.0 + (tolerance / 100.0));

    // To prevent rounding issues, round to 4 decimal places
    final minRounded = double.parse(minVal.toStringAsFixed(4));
    final maxRounded = double.parse(maxVal.toStringAsFixed(4));
    final valRounded = double.parse(value.toStringAsFixed(4));

    if (valRounded >= minRounded && valRounded <= maxRounded) {
      return 'PASS';
    } else {
      return 'FAIL';
    }
  }

  Future<void> _saveRecord() async {
    final serial = _serialController.text.trim();

    if (serial.isEmpty) {
      _addLog('❌ Validation error: Serial Number cannot be empty.', _LogLevel.error);
      return;
    }

    if (_refRows.isEmpty) {
      _addLog('❌ Validation error: Add at least one Reference Point to save.', _LogLevel.error);
      return;
    }

    // Build multi-ref row payloads
    final testRowsData = _refRows.map((r) {
      final refVal = double.tryParse(r.refController.text) ?? 0.0;
      final ch1Res = r.useCh1 ? (r.ch1Pass == true ? 'PASS' : (r.ch1Pass == false ? 'FAIL' : 'PENDING')) : 'OFF';
      final ch2Res = r.useCh2 ? (r.ch2Pass == true ? 'PASS' : (r.ch2Pass == false ? 'FAIL' : 'PENDING')) : 'OFF';
      final rowPass = r.overallPass == true ? 'PASS' : (r.overallPass == false ? 'FAIL' : 'PENDING');
      return {
        'ref': refVal,
        'tolerance': double.tryParse(r.tolController.text) ?? 1.0,
        'useCh1': r.useCh1,
        'ch1Value': r.useCh1 ? (r.ch1Val ?? 0.0) : null,
        'ch1Result': ch1Res,
        'useCh2': r.useCh2,
        'ch2Value': r.useCh2 ? (r.ch2Val ?? 0.0) : null,
        'ch2Result': ch2Res,
        'result': rowPass,
      };
    }).toList();

    // Determine overall result
    final hasFailures = _refRows.any((r) => r.ch1Pass == false || r.ch2Pass == false);
    final isOverallSuccess = !hasFailures && _refRows.any((r) => r.ch1Pass == true && r.ch2Pass == true);

    final activeRow = _refRows.length > _activeRowIndex ? _refRows[_activeRowIndex] : _refRows.first;
    final primaryTarget = double.tryParse(activeRow.refController.text) ?? 0.0;

    setState(() {
      _isSaving = true;
    });

    _addLog('Saving QC record for serial "$serial" to database...', _LogLevel.info);

    final client = HttpClient();
    try {
      final url = Uri.parse('${AppConstants.apiBaseUrl}/tests');
      final request = await client.postUrl(url).timeout(const Duration(seconds: 4));
      request.headers.contentType = ContentType.json;
      
      final payload = {
        'serialNumber': serial,
        'boardType': _selectedBoardType.label,
        'paramType': (_selectedBoardType == CalibrationType.acCurrent || 
                      _selectedBoardType == CalibrationType.lowCurrent || 
                      _selectedBoardType == CalibrationType.highCurrent) 
                      ? 'current' : 'voltage',
        'result': isOverallSuccess ? 'success' : 'fail',
        'testRows': testRowsData,
      };

      request.write(json.encode(payload));
      
      final response = await request.close();
      if (response.statusCode == 200 || response.statusCode == 201) {
        _addLog('✅ Success: QC Record saved to DB (Replaced previous entry for serial "$serial").', _LogLevel.success);
      } else {
        final body = await response.transform(utf8.decoder).join();
        _addLog('❌ Failed to save: $body', _LogLevel.error);
      }
    } catch (e) {
      _addLog('❌ Network error: Could not contact local backend API.', _LogLevel.error);
    } finally {
      client.close();
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _openReportsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ReportsScreen(),
      ),
    );
  }

  void _openChangeSerialNoDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeSerialNoScreen(
          serialService: widget.serialService,
          channel: widget.channel,
          isFD: widget.isFD,
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final commands = _testCommands[_selectedBoardType] ?? [];
    
    return Scaffold(
      backgroundColor: AppTheme.bgDarkest,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              backgroundColor: AppTheme.panelHeader,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Bolt Quality Control & Testing',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textBright,
                ),
              ),
              actions: [
                ElevatedButton.icon(
                  onPressed: _openChangeSerialNoDialog,
                  icon: const Icon(Icons.edit_note_rounded, size: 14),
                  label: Text('Change Serial No', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.print_rounded, color: AppTheme.primaryColor),
                  tooltip: 'Print Reports',
                  onPressed: _openReportsScreen,
                ),
                const SizedBox(width: 10),
              ],
            ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main content row
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Pane: Config + QC Panel + Calibration Commands
                    Expanded(
                      flex: 5,
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
                                  _buildQCThresholdSection(),
                                  _buildTestActionsSection(),
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
                    // Right Pane: Calibration Trace Activity Log
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
              // Target CAN ID — only shown in CAN mode
              if (widget.serialService.isCanMode) ...[
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Target CAN ID'),
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
                        decoration: const InputDecoration(
                          hintText: 'FF',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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
              ],
              // Bot Type Dropdown
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Board / Bot Type Selection'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: DropdownButtonFormField<CalibrationType>(
                        value: _selectedBoardType,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedBoardType = val;
                            });
                            _addLog('✓ Switched test calibration profile to: ${val.label}', _LogLevel.info);
                          }
                        },
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                        dropdownColor: AppTheme.bgElevated,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        // Only show Voltage & Current related board options
                        items: _testBoardTypes.map((ct) => DropdownMenuItem(
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
        ],
      ),
    );
  }

  Widget _buildQCThresholdSection() {
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
          Text(
            'QC Verification Values',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          // Serial Number / ID — auto-filled by CMD_GET_SERIAL
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Serial Number / ID'),
              const SizedBox(height: 6),
              SizedBox(
                height: 38,
                child: TextField(
                  controller: _serialController,
                  readOnly: true,
                  style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppTheme.textBright),
                  decoration: const InputDecoration(
                    hintText: 'Auto-filled by READ SERIAL NUMBER',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildTestActionsSection() {
    final isCurrent = _selectedBoardType == CalibrationType.acCurrent ||
        _selectedBoardType == CalibrationType.lowCurrent ||
        _selectedBoardType == CalibrationType.highCurrent;
    final unit = isCurrent ? 'A' : 'V';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title & Add Button Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.table_chart_rounded, size: 16, color: AppTheme.accentOrange),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multi-Ref Verification Table',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'Select active row to receive live CAN/UART measurements',
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _DeviceTestSession.reset();
                          _refRows.clear();
                          _refRows.add(_TestRefRow());
                          _activeRowIndex = 0;
                        });
                        _addLog('🧹 Reset all measurement values. Active selection reset to Row #1.', _LogLevel.info);
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: Text('Reset Values', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textMuted,
                        side: const BorderSide(color: AppTheme.borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _refRows.add(_TestRefRow());
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
                      label: Text('+ Add Ref Point', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(color: AppTheme.primaryColor, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Multi-Ref Data Table Container
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgDarkest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(7), topRight: Radius.circular(7)),
                    border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 44, child: Text('#', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textMuted))),
                      Expanded(flex: 3, child: Text('Ref ($unit)', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
                      Expanded(flex: 2, child: Text('Tol (%)', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
                      Expanded(flex: 4, child: Text('CH1 Value', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
                      Expanded(flex: 2, child: Center(child: Text('CH1 Status', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)))),
                      Expanded(flex: 4, child: Text('CH2 Value', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
                      Expanded(flex: 2, child: Center(child: Text('CH2 Status', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)))),
                      Expanded(flex: 2, child: Center(child: Text('Overall', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)))),
                      const SizedBox(width: 32),
                    ],
                  ),
                ),
                // Table Rows
                if (_refRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No Reference points added yet. Click "+ Add Ref Point" above.', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _refRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    padding: const EdgeInsets.all(4),
                    itemBuilder: (context, idx) {
                      final row = _refRows[idx];
                      final isActive = idx == _activeRowIndex;

                      return Container(
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.primaryColor.withValues(alpha: 0.12) : AppTheme.bgInput.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive ? AppTheme.primaryColor : AppTheme.borderColor.withValues(alpha: 0.5),
                            width: isActive ? 1.5 : 1.0,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            // Active Row Radio / Selector #
                            SizedBox(
                              width: 44,
                              child: InkWell(
                                onTap: () => setState(() => _activeRowIndex = idx),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isActive ? AppTheme.primaryColor : AppTheme.bgInput,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isActive)
                                        const Icon(Icons.play_arrow_rounded, size: 10, color: Colors.white)
                                      else
                                        const SizedBox(width: 2),
                                      Text(
                                        '#${idx + 1}',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? Colors.white : AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Ref Target Field
                            Expanded(
                              flex: 3,
                              child: SizedBox(
                                height: 28,
                                child: TextField(
                                  controller: row.refController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: AppTheme.textBright, fontWeight: FontWeight.bold),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    filled: true,
                                    fillColor: AppTheme.bgCard,
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: AppTheme.borderColor)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: AppTheme.borderColor)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: AppTheme.primaryColor)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            // Tol (%) Field
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 28,
                                child: TextField(
                                  controller: row.tolController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: AppTheme.textBright, fontWeight: FontWeight.bold),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    filled: true,
                                    fillColor: AppTheme.bgCard,
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: AppTheme.borderColor)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: AppTheme.borderColor)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: AppTheme.primaryColor)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                             // CH1 Checkbox + Value Container
                            Expanded(
                              flex: 4,
                              child: Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: row.useCh1 ? AppTheme.bgCard : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: row.useCh1 ? AppTheme.borderColor : Colors.transparent),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: row.useCh1,
                                        activeColor: AppTheme.primaryColor,
                                        onChanged: (val) {
                                          setState(() {
                                            row.useCh1 = val ?? true;
                                            if (!row.useCh1) {
                                              row.ch1Val = null;
                                              row.ch1Pass = null;
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        row.useCh1
                                            ? (row.ch1Val != null ? '${row.ch1Val!.toStringAsFixed(3)} $unit' : '---')
                                            : 'OFF',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          fontWeight: row.useCh1 && row.ch1Val != null ? FontWeight.bold : FontWeight.normal,
                                          color: row.useCh1 ? AppTheme.textBright : AppTheme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // CH1 Pass/Fail Badge
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: row.useCh1 ? _buildPassFailBadge(row.ch1Pass) : _buildOffBadge(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // CH2 Checkbox + Value Container
                            Expanded(
                              flex: 4,
                              child: Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: row.useCh2 ? AppTheme.bgCard : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: row.useCh2 ? AppTheme.borderColor : Colors.transparent),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: row.useCh2,
                                        activeColor: AppTheme.primaryColor,
                                        onChanged: (val) {
                                          setState(() {
                                            row.useCh2 = val ?? true;
                                            if (!row.useCh2) {
                                              row.ch2Val = null;
                                              row.ch2Pass = null;
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        row.useCh2
                                            ? (row.ch2Val != null ? '${row.ch2Val!.toStringAsFixed(3)} $unit' : '---')
                                            : 'OFF',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          fontWeight: row.useCh2 && row.ch2Val != null ? FontWeight.bold : FontWeight.normal,
                                          color: row.useCh2 ? AppTheme.textBright : AppTheme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // CH2 Pass/Fail Badge
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: row.useCh2 ? _buildPassFailBadge(row.ch2Pass) : _buildOffBadge(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Overall Status Badge
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: _buildPassFailBadge(row.overallPass),
                              ),
                            ),
                            // Delete Row Action
                            SizedBox(
                              width: 32,
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.errorColor),
                                tooltip: 'Remove Row',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: _refRows.length > 1
                                    ? () {
                                        setState(() {
                                          _refRows.removeAt(idx);
                                          if (_activeRowIndex >= _refRows.length) {
                                            _activeRowIndex = _refRows.length - 1;
                                          }
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassFailBadge(bool? isPass) {
    if (isPass == null) {
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Text('---', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.textMuted)),
      );
    }
    final bg = isPass ? AppTheme.successColor.withValues(alpha: 0.15) : AppTheme.errorColor.withValues(alpha: 0.15);
    final fg = isPass ? AppTheme.successColor : AppTheme.errorColor;
    final icon = isPass ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final text = isPass ? 'PASS' : 'FAIL';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: fg.withValues(alpha: 0.4), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildOffBadge() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.bgDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        'OFF',
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
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
                'Device Test Commands (Profile: ${_selectedBoardType.label})',
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
    final isGetSerial = cmd.hexValue == 0x01 || cmd.name == 'READ SERIAL NUMBER' || cmd.name == 'CMD_GET_SERIAL';
    final hasSerial = _serialController.text.trim().isNotEmpty;
    final isEnabled = isGetSerial || hasSerial;

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.35,
      child: Material(
        color: isGetSerial
            ? AppTheme.primaryColor.withValues(alpha: 0.1)
            : AppTheme.bgDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: isEnabled
              ? () {
                  if (isGetSerial) {
                    _fetchSerialNumberFromDevice();
                  } else {
                    _sendCommand(cmd);
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isGetSerial
                    ? AppTheme.primaryColor.withValues(alpha: 0.4)
                    : AppTheme.borderColor.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cmd.name,
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textBright),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cmd.description,
                        style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Text(
                    hexStr,
                    style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Calibration Test Trace / Activity Log',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _log.clear()),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.borderLight),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              controller: _logScrollController,
              itemCount: _log.length,
              itemBuilder: (context, idx) {
                final entry = _log[idx];
                Color color = AppTheme.textPrimary;
                if (entry.level == _LogLevel.error) color = AppTheme.errorColor;
                if (entry.level == _LogLevel.success) color = AppTheme.successColor;
                if (entry.level == _LogLevel.tx) color = AppTheme.accentOrange;
                if (entry.level == _LogLevel.rx) color = AppTheme.accentCyan;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${entry.timestamp}] ',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      Expanded(
                        child: Text(
                          entry.message,
                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: color, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow() {
    final canSave = _serialController.text.trim().isNotEmpty && _refRows.isNotEmpty && !_isSaving;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.successColor),
            ),
            const SizedBox(width: 8),
            Text(
              'Connected (${widget.serialService.isCanMode ? (widget.isFD ? "CAN FD" : "Classic CAN") : "USB/Serial"})',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successColor),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: canSave ? _saveRecord : null,
                icon: _isSaving
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 14),
                label: Text('Save Result', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _openReportsScreen,
                icon: const Icon(Icons.history_rounded, size: 14),
                label: Text('History', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
            if (!widget.isEmbedded) ...[
              const SizedBox(width: 12),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.bgInput,
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Text('Close', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
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
}

class _TestRefRow {
  final TextEditingController refController;
  final TextEditingController tolController;
  bool useCh1;
  bool useCh2;
  double? ch1Val;
  double? ch2Val;
  bool? ch1Pass;
  bool? ch2Pass;

  _TestRefRow({
    String initialRef = '',
    String initialTol = '',
    bool? useCh1,
    bool? useCh2,
  })  : useCh1 = useCh1 ?? true,
        useCh2 = useCh2 ?? true,
        refController = TextEditingController(text: initialRef),
        tolController = TextEditingController(text: initialTol);

  bool? get overallPass {
    if (!useCh1 && !useCh2) return null;
    if (useCh1 && ch1Pass == null) return null;
    if (useCh2 && ch2Pass == null) return null;

    bool p1 = useCh1 ? (ch1Pass ?? false) : true;
    bool p2 = useCh2 ? (ch2Pass ?? false) : true;
    return p1 && p2;
  }
}

class _DeviceTestSession {
  static String serialNumber = '';
  static String canId = 'FF';
  static CalibrationType boardType = CalibrationType.acVoltage;
  static int activeRowIndex = 0;
  static List<_TestRefRowData>? savedRowsData;
  static List<_LogEntry> savedLogs = [];

  static void reset() {
    serialNumber = '';
    canId = 'FF';
    boardType = CalibrationType.acVoltage;
    activeRowIndex = 0;
    savedRowsData = null;
    savedLogs.clear();
  }
}

class _TestRefRowData {
  String ref;
  String tol;
  bool useCh1;
  bool useCh2;
  double? ch1Val;
  double? ch2Val;
  bool? ch1Pass;
  bool? ch2Pass;

  _TestRefRowData({
    required this.ref,
    required this.tol,
    required this.useCh1,
    required this.useCh2,
    this.ch1Val,
    this.ch2Val,
    this.ch1Pass,
    this.ch2Pass,
  });
}
