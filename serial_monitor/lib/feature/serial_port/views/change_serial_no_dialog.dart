import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../../core/config/can_config.dart';
import '../../../core/services/serial_port_service.dart';
import '../../../utils/theme/app_theme.dart';

typedef ChangeSerialNoDialog = ChangeSerialNoScreen;

class ChangeSerialNoScreen extends StatefulWidget {
  final SerialPortService serialService;
  final int channel;
  final bool isFD;

  const ChangeSerialNoScreen({
    super.key,
    required this.serialService,
    required this.channel,
    required this.isFD,
  });

  @override
  State<ChangeSerialNoScreen> createState() => _ChangeSerialNoScreenState();
}

class _ChangeSerialNoScreenState extends State<ChangeSerialNoScreen> {
  final TextEditingController _last4DigitsController = TextEditingController();
  final TextEditingController _canId100kController = TextEditingController(text: '000000FF');
  final TextEditingController _canId250kController = TextEditingController(text: '00000001');
  final ScrollController _logScrollController = ScrollController();

  String _selectedDeviceBaudCode = '03'; // Default 100 kbps (0x03)
  String _lastDetectedDeviceBaud = '';

  static const Map<String, CanNominalBaudRate> _baudCodeToAdapterBaud = {
    '01': CanNominalBaudRate.kbps20,
    '02': CanNominalBaudRate.kbps50,
    '03': CanNominalBaudRate.kbps100,
    '04': CanNominalBaudRate.kbps250,
  };

  static const Map<String, String> _baudCodeLabels = {
    '01': '20 kbps',
    '02': '50 kbps',
    '03': '100 kbps',
    '04': '250 kbps',
  };

  final TextEditingController _boardDecNumberController = TextEditingController(text: '161');
  String _selectedWriteBoardCode = 'DL';

  List<int> get _writeBoardNumberBytes {
    final decVal = int.tryParse(_boardDecNumberController.text.trim()) ?? 0;
    final clamped = decVal.clamp(0, 65535);
    final highByte = (clamped >> 8) & 0xFF;
    final lowByte = clamped & 0xFF;
    return [highByte, lowByte];
  }

  String get _writeBoardNumberHexPreview {
    final bytes = _writeBoardNumberBytes;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  String _selectedBoardCode = 'DI';

  static const Map<String, String> _boardCodeLabels = {
    'AC': 'Analog AC Current (AC)',
    'DL': 'Analog DC Voltage Low (DL)',
    'CL': 'Analog DC Current Low (CL)',
    'DH': 'Analog DC Voltage High (DH)',
    'CH': 'Analog DC Current High (CH)',
    'DI': 'Digital DC Input (DI)',
    'AX': 'Accelerometer (AX)',
  };

  String get _finalSerialNumber {
    final last4 = _last4DigitsController.text.trim().padLeft(4, '0');
    return 'ST2528$_selectedBoardCode$last4';
  }

  // Selected Mode display configuration
  bool _isBootloaderModeSelected = false;
  String _activeBaudText = '100 kbps';
  String _activeModeText = 'Application Mode';
  CanNominalBaudRate? _currentHardwareBaudRate;

  // Execution states
  final List<String> _logs = [];
  String _lastDetectedSn = '';
  String _lastDetectedBoardInfo = '';
  Completer<bool>? _okCompleter;

  // Interceptors to restore on dispose
  void Function(Map<String, dynamic>)? _oldCanFrameRx;
  void Function(Uint8List)? _oldDataReceived;

  // Action status mapping
  final Map<int, bool> _stepLoading = {
    1: false, // App Scan Board
    2: false, // App Scan Serial
    3: false, // App Go to Bootloader
    4: false, // Boot Scan Board
    5: false, // Boot Scan Serial
    6: false, // Boot Write SN
    7: false, // Boot Go to App
    8: false, // Boot Write Board Num
    9: false, // Get Device Baud
    10: false, // Write Device Baud
    11: false, // Auto Detect Device
  };

  final Map<int, bool?> _stepSuccess = {
    1: null,
    2: null,
    3: null,
    4: null,
    5: null,
    6: null,
    7: null,
    8: null,
    9: null,
    10: null,
    11: null,
  };

  bool get _isExecuting => _stepLoading.values.any((loading) => loading);

  @override
  void initState() {
    super.initState();
    _setupRxInterceptors();
    _addLog('System initialized. Mode default: Application (100 kbps).', AppTheme.primaryColor);
  }

  void _setupRxInterceptors() {
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
  }

  @override
  void dispose() {
    widget.serialService.onCanFrameRx = _oldCanFrameRx;
    widget.serialService.onDataReceived = _oldDataReceived;
    _last4DigitsController.dispose();
    _canId100kController.dispose();
    _canId250kController.dispose();
    _boardDecNumberController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String msg, [Color? color]) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    if (!mounted) return;
    setState(() {
      _logs.add('[$ts] $msg');
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

  void _handleIncomingRawSerial(Uint8List data) {
    if (data.isEmpty) return;
    final printable = data.where((b) => b >= 32 && b <= 126).toList();
    if (printable.isNotEmpty) {
      final sn = String.fromCharCodes(printable).trim();
      if (sn.length >= 2) {
        _onSerialNumberDetected(sn);
      }
    }
  }

  Future<bool> _waitForOkResponse({Duration timeout = const Duration(seconds: 4)}) async {
    _okCompleter = Completer<bool>();
    try {
      return await _okCompleter!.future.timeout(timeout);
    } catch (_) {
      return false;
    } finally {
      _okCompleter = null;
    }
  }

  void _handleIncomingCanFrame(Map<String, dynamic> frame) {
    final canId = frame['canId']?.toString() ?? '';
    final dataHex = frame['dataHex']?.toString() ?? '';
    final rawBytes = _parseDataHex(dataHex);

    if (rawBytes.isEmpty) return;

    // Check for OK response (4F 4B)
    bool isOk = false;
    for (int i = 0; i < rawBytes.length - 1; i++) {
      if (rawBytes[i] == 0x4F && rawBytes[i + 1] == 0x4B) {
        isOk = true;
        break;
      }
    }
    if (!isOk) {
      final asciiStr = String.fromCharCodes(rawBytes).trim().toUpperCase();
      if (asciiStr.contains('OK')) {
        isOk = true;
      }
    }

    if (isOk) {
      _addLog('← RX CAN [$canId]: 4F 4B (OK)', AppTheme.successColor);
      if (_okCompleter != null && !_okCompleter!.isCompleted) {
        _okCompleter!.complete(true);
      }
    } else {
      final asciiChars = rawBytes.map((b) {
        return (b >= 32 && b <= 126) ? String.fromCharCode(b) : ' ';
      }).join().trim();
      final cleanAscii = asciiChars.replaceAll(RegExp(r'\s+'), ' ');
      if (cleanAscii.isNotEmpty) {
        _addLog('← RX CAN [$canId]: $dataHex ("$cleanAscii")', AppTheme.textSecondary);
      } else {
        _addLog('← RX CAN [$canId]: $dataHex', AppTheme.textSecondary);
      }
    }

    // Check for mixed binary-ASCII Board ID response
    bool isParsedBoard = false;
    if (rawBytes.length >= 4 &&
        rawBytes[0] >= 65 && rawBytes[0] <= 90 && // ASCII 'A'-'Z'
        rawBytes[1] >= 65 && rawBytes[1] <= 90) { // ASCII 'A'-'Z'
      
      final firstTwo = String.fromCharCodes(rawBytes.sublist(0, 2));
      const knownCodes = {'AV', 'AC', 'DH', 'DL', 'HI', 'LI', 'DC', 'AM', 'CL', 'CH', 'DI', 'AX'};
      if (knownCodes.contains(firstTwo)) {
        isParsedBoard = true;
        final boardNum = (rawBytes[2] << 8) | rawBytes[3];
        
        String extraInfo = '';
        if (rawBytes.length >= 11) {
          final specVal = rawBytes[4];
          final specUnit = String.fromCharCode(rawBytes[5]);
          final verBytes = rawBytes.sublist(6).where((b) => b >= 32 && b <= 126).toList();
          final version = String.fromCharCodes(verBytes).trim();
          extraInfo = ' (Spec: $specVal$specUnit, Version: $version)';
        } else if (rawBytes.length >= 6) {
          final verBytes = rawBytes.sublist(4).where((b) => b >= 32 && b <= 126).toList();
          if (verBytes.isNotEmpty) {
            extraInfo = ' (Version: ${String.fromCharCodes(verBytes).trim()})';
          }
        }
        
        _onBoardInfoDetected('$firstTwo, Board Number: $boardNum$extraInfo');
      }
    }

    // Check for Get Baud Rate response (contains 47 43 / 'G' 'C')
    bool isBaudResponse = false;
    for (int i = 0; i < rawBytes.length - 2; i++) {
      if (rawBytes[i] == 0x47 && rawBytes[i + 1] == 0x43) {
        isBaudResponse = true;
        final responseBaudCode = rawBytes[i + 2].toRadixString(16).padLeft(2, '0').toUpperCase();
        final baudLabel = _baudCodeLabels[responseBaudCode] ?? 'Unknown';
        _onDeviceBaudDetected(baudLabel);
        break;
      }
    }

    if (!isParsedBoard && !isBaudResponse) {
      bool isBoardResponse = rawBytes.length >= 2 && rawBytes[0] == 0x01 && rawBytes[1] == 0x01;
      bool isSerialResponse = rawBytes.length >= 2 && rawBytes[0] == 0x01 && rawBytes[1] == 0x02;

      if (isBoardResponse) {
        final asciiBytes = rawBytes.sublist(2).where((b) => b >= 32 && b <= 126).toList();
        String boardInfo = String.fromCharCodes(asciiBytes).trim();
        _onBoardInfoDetected(boardInfo);
      } else if (isSerialResponse) {
        final asciiBytes = rawBytes.sublist(2).where((b) => b >= 32 && b <= 126).toList();
        String sn = String.fromCharCodes(asciiBytes).trim();
        _onSerialNumberDetected(sn);
      } else {
        // General ASCII text fallback check for serial numbers
        final printable = rawBytes.where((b) => b >= 32 && b <= 126).toList();
        if (printable.length >= 3 && printable.length >= rawBytes.length - 1) {
          String sn = String.fromCharCodes(printable).trim();
          if (sn.isNotEmpty && sn.length >= 2) {
            _onSerialNumberDetected(sn);
          }
        }
      }
    }
  }

  void _parseScannedSerialNumber(String sn) {
    final regex = RegExp(r'^ST2528([A-Z]{2})([0-9]{4})$', caseSensitive: false);
    final match = regex.firstMatch(sn.trim().toUpperCase());
    if (match != null) {
      final boardCode = match.group(1)!;
      final last4 = match.group(2)!;
      setState(() {
        _selectedBoardCode = boardCode;
        _last4DigitsController.text = last4;
      });
    } else {
      if (sn.trim().length == 4 && int.tryParse(sn.trim()) != null) {
        setState(() {
          _last4DigitsController.text = sn.trim();
        });
      } else {
        final digitReg = RegExp(r'([0-9]{4})$');
        final digitMatch = digitReg.firstMatch(sn.trim());
        if (digitMatch != null) {
          setState(() {
            _last4DigitsController.text = digitMatch.group(1)!;
          });
          final codeReg = RegExp(r'ST2528([A-Z]{2})', caseSensitive: false);
          final codeMatch = codeReg.firstMatch(sn.trim());
          if (codeMatch != null) {
            setState(() {
              _selectedBoardCode = codeMatch.group(1)!.toUpperCase();
            });
          }
        }
      }
    }
  }

  void _onSerialNumberDetected(String sn) {
    if (_lastDetectedSn != sn) {
      _lastDetectedSn = sn;
      _addLog('✓ RX Serial Number from Device: "$sn"', AppTheme.successColor);
    }
    if (mounted) {
      setState(() {
        _parseScannedSerialNumber(sn);
        if (_stepLoading[2] == true) {
          _stepSuccess[2] = true;
          _stepLoading[2] = false;
        }
        if (_stepLoading[5] == true) {
          _stepSuccess[5] = true;
          _stepLoading[5] = false;
        }
      });
    }
  }

  void _onBoardInfoDetected(String info) {
    if (_lastDetectedBoardInfo != info) {
      _lastDetectedBoardInfo = info;
      _addLog('✓ RX Board ID Info from Device: "$info"', AppTheme.successColor);
    }
    if (mounted) {
      setState(() {
        if (_stepLoading[1] == true) {
          _stepSuccess[1] = true;
          _stepLoading[1] = false;
        }
        if (_stepLoading[4] == true) {
          _stepSuccess[4] = true;
          _stepLoading[4] = false;
        }
      });
    }
  }

  bool _checkIsExtended(String canIdStr) {
    final clean = canIdStr.replaceAll('0x', '').trim();
    final val = int.tryParse(clean, radix: 16) ?? 0;
    return val > 0x7FF;
  }

  Future<bool> _switchBaudRate(CanNominalBaudRate baudRate, String baudLabel, String modeLabel) async {
    if (!widget.serialService.isConnected) {
      _addLog('❌ USB port not connected.', AppTheme.errorColor);
      return false;
    }
    
    if (_currentHardwareBaudRate == baudRate) {
      return true;
    }

    _addLog('--- Switching CAN Baud Rate to $baudLabel ---', AppTheme.accentOrange);
    final ok = await widget.serialService.setCanBaudRate(
      baudRate,
      activeCanConfig: CanConfig(
        channel: widget.channel == 1 ? CanChannel.channel2 : CanChannel.channel1,
        canType: widget.isFD ? CanType.canFd : CanType.classicCan,
      ),
    );

    if (ok) {
      _currentHardwareBaudRate = baudRate;
      setState(() {
        _activeBaudText = baudLabel;
        _activeModeText = modeLabel;
      });
      _addLog('✓ Switched CAN Baud Rate to $baudLabel successfully.', AppTheme.successColor);
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } else {
      _addLog('❌ Failed to switch CAN Baud Rate to $baudLabel.', AppTheme.errorColor);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  APPLICATION MODE ACTIONS (100 kbps)
  // ═══════════════════════════════════════════════════════════════

  Future<void> _appScanBoard() async {
    setState(() {
      _stepLoading[1] = true;
      _stepSuccess[1] = null;
    });
    try {
      final activeBaud = _isBootloaderModeSelected
          ? CanNominalBaudRate.kbps250
          : (_currentHardwareBaudRate ?? CanNominalBaudRate.kbps100);
      final baudLabel = _isBootloaderModeSelected ? '250 kbps' : _activeBaudText;
      final modeLabel = _isBootloaderModeSelected ? 'Bootloader Mode' : 'Application Mode';

      final baudOk = await _switchBaudRate(activeBaud, baudLabel, modeLabel);
      if (!baudOk) {
        setState(() => _stepSuccess[1] = false);
        return;
      }

      final canIdStr = _canId100kController.text.trim();
      final fullCanId = '0x$canIdStr';
      _addLog('→ Sending App Scan Board (01 01) to $fullCanId at $baudLabel...', AppTheme.accentCyan);

      _lastDetectedBoardInfo = '';
      final frameData = [0x01, 0x01, 0, 0, 0, 0, 0, 0];
      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: frameData,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );
      
      int retry = 0;
      while (_lastDetectedBoardInfo.isEmpty && retry < 40 && _stepLoading[1] == true) {
        await Future.delayed(const Duration(milliseconds: 100));
        retry++;
      }
      
      if (_lastDetectedBoardInfo.isEmpty) {
        _addLog('❌ Timeout: No Board ID response received at $baudLabel.', AppTheme.errorColor);
        setState(() => _stepSuccess[1] = false);
      } else {
        setState(() => _stepSuccess[1] = true);
      }
    } catch (e) {
      _addLog('❌ App Scan Board Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[1] = false);
    } finally {
      setState(() => _stepLoading[1] = false);
    }
  }

  Future<void> _appScanSerial() async {
    setState(() {
      _stepLoading[2] = true;
      _stepSuccess[2] = null;
    });
    try {
      final activeBaud = _isBootloaderModeSelected
          ? CanNominalBaudRate.kbps250
          : (_currentHardwareBaudRate ?? CanNominalBaudRate.kbps100);
      final baudLabel = _isBootloaderModeSelected ? '250 kbps' : _activeBaudText;
      final modeLabel = _isBootloaderModeSelected ? 'Bootloader Mode' : 'Application Mode';

      final baudOk = await _switchBaudRate(activeBaud, baudLabel, modeLabel);
      if (!baudOk) {
        setState(() => _stepSuccess[2] = false);
        return;
      }

      final canIdStr = _canId100kController.text.trim();
      final fullCanId = '0x$canIdStr';
      _addLog('→ Sending App Scan Serial (01 02) to $fullCanId at $baudLabel...', AppTheme.accentCyan);

      final frameData = [0x01, 0x02, 0, 0, 0, 0, 0, 0];
      _lastDetectedSn = '';
      _last4DigitsController.clear();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: frameData,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      int retry = 0;
      while (_lastDetectedSn.isEmpty && retry < 100 && _stepLoading[2] == true) {
        await Future.delayed(const Duration(milliseconds: 100));
        retry++;
      }
      
      if (_lastDetectedSn.isEmpty) {
        _addLog('❌ Timeout: No Serial Number response received at $baudLabel.', AppTheme.errorColor);
        setState(() => _stepSuccess[2] = false);
      } else {
        setState(() => _stepSuccess[2] = true);
      }
    } catch (e) {
      _addLog('❌ App Scan Serial Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[2] = false);
    } finally {
      setState(() => _stepLoading[2] = false);
    }
  }

  Future<void> _appGoToBootloader() async {
    setState(() {
      _stepLoading[3] = true;
      _stepSuccess[3] = null;
    });
    try {
      final activeBaud = _currentHardwareBaudRate ?? CanNominalBaudRate.kbps100;
      final baudLabel = _activeBaudText;
      final baudOk = await _switchBaudRate(activeBaud, baudLabel, 'Application Mode');
      if (!baudOk) {
        setState(() => _stepSuccess[3] = false);
        return;
      }

      final canIdStr = _canId100kController.text.trim();
      final fullCanId = '0x$canIdStr';
      _addLog('→ Sending Enter Bootloader command (65 72 65) to $fullCanId at $baudLabel...', AppTheme.primaryColor);

      final frameData = [0x65, 0x72, 0x65, 0, 0, 0, 0, 0];
      _okCompleter = Completer<bool>();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: frameData,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response from $fullCanId...', AppTheme.accentOrange);
      final ok = await _waitForOkResponse(timeout: const Duration(seconds: 4));
      
      setState(() {
        _stepSuccess[3] = ok;
      });
      
      if (ok) {
        _addLog('✓ Jump to Bootloader SUCCESS: Device is in bootloader mode.', AppTheme.successColor);
        await Future.delayed(const Duration(milliseconds: 500));
        final switchOk = await _switchBaudRate(CanNominalBaudRate.kbps250, '250 kbps', 'Bootloader Mode');
        if (switchOk) {
          setState(() {
            _isBootloaderModeSelected = true;
          });
        }
      } else {
        _addLog('❌ Jump to Bootloader FAILED: No OK response received.', AppTheme.errorColor);
      }
    } catch (e) {
      _addLog('❌ Jump to Bootloader Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[3] = false);
    } finally {
      setState(() => _stepLoading[3] = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  BOOTLOADER MODE ACTIONS (250 kbps)
  // ═══════════════════════════════════════════════════════════════

  Future<void> _bootScanBoard() async {
    setState(() {
      _stepLoading[4] = true;
      _stepSuccess[4] = null;
    });
    try {
      final activeBaud = _isBootloaderModeSelected
          ? CanNominalBaudRate.kbps250
          : (_currentHardwareBaudRate ?? CanNominalBaudRate.kbps100);
      final baudLabel = _isBootloaderModeSelected ? '250 kbps' : _activeBaudText;
      final modeLabel = _isBootloaderModeSelected ? 'Bootloader Mode' : 'Application Mode';

      final baudOk = await _switchBaudRate(activeBaud, baudLabel, modeLabel);
      if (!baudOk) {
        setState(() => _stepSuccess[4] = false);
        return;
      }

      final canIdStr = _isBootloaderModeSelected ? _canId250kController.text.trim() : _canId100kController.text.trim();
      final fullCanId = '0x$canIdStr';
      _addLog('→ Sending Boot Scan Board (01 01) to $fullCanId at $baudLabel...', AppTheme.accentCyan);

      _lastDetectedBoardInfo = '';
      final frameData = [0x01, 0x01, 0, 0, 0, 0, 0, 0];
      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: frameData,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );
      
      int retry = 0;
      while (_lastDetectedBoardInfo.isEmpty && retry < 40 && _stepLoading[4] == true) {
        await Future.delayed(const Duration(milliseconds: 100));
        retry++;
      }
      
      if (_lastDetectedBoardInfo.isEmpty) {
        _addLog('❌ Timeout: No Board ID response received at $baudLabel.', AppTheme.errorColor);
        setState(() => _stepSuccess[4] = false);
      } else {
        setState(() => _stepSuccess[4] = true);
      }
    } catch (e) {
      _addLog('❌ Boot Scan Board Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[4] = false);
    } finally {
      setState(() => _stepLoading[4] = false);
    }
  }

  Future<void> _bootScanSerial() async {
    setState(() {
      _stepLoading[5] = true;
      _stepSuccess[5] = null;
    });
    try {
      final activeBaud = _isBootloaderModeSelected
          ? CanNominalBaudRate.kbps250
          : (_currentHardwareBaudRate ?? CanNominalBaudRate.kbps100);
      final baudLabel = _isBootloaderModeSelected ? '250 kbps' : _activeBaudText;
      final modeLabel = _isBootloaderModeSelected ? 'Bootloader Mode' : 'Application Mode';

      final baudOk = await _switchBaudRate(activeBaud, baudLabel, modeLabel);
      if (!baudOk) {
        setState(() => _stepSuccess[5] = false);
        return;
      }

      final canIdStr = _isBootloaderModeSelected ? _canId250kController.text.trim() : _canId100kController.text.trim();
      final fullCanId = '0x$canIdStr';
      _addLog('→ Sending Boot Scan Serial (01 02) to $fullCanId at $baudLabel...', AppTheme.accentCyan);

      final frameData = [0x01, 0x02, 0, 0, 0, 0, 0, 0];
      _lastDetectedSn = '';
      _last4DigitsController.clear();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: frameData,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      int retry = 0;
      while (_lastDetectedSn.isEmpty && retry < 100 && _stepLoading[5] == true) {
        await Future.delayed(const Duration(milliseconds: 100));
        retry++;
      }
      
      if (_lastDetectedSn.isEmpty) {
        _addLog('❌ Timeout: No Serial Number response received at $baudLabel.', AppTheme.errorColor);
        setState(() => _stepSuccess[5] = false);
      } else {
        setState(() => _stepSuccess[5] = true);
      }
    } catch (e) {
      _addLog('❌ Boot Scan Serial Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[5] = false);
    } finally {
      setState(() => _stepLoading[5] = false);
    }
  }

  Future<void> _bootWriteSn() async {
    final finalSn = _finalSerialNumber;
    if (_last4DigitsController.text.trim().isEmpty) {
      _addLog('❌ Validation error: Serial Number digits cannot be empty.', AppTheme.errorColor);
      return;
    }

    setState(() {
      _stepLoading[6] = true;
      _stepSuccess[6] = null;
    });
    try {
      final baudOk = await _switchBaudRate(CanNominalBaudRate.kbps250, '250 kbps', 'Bootloader Mode');
      if (!baudOk) {
        setState(() => _stepSuccess[6] = false);
        return;
      }

      final canIdStr = _canId250kController.text.trim();
      final fullCanId = '0x$canIdStr';
      
      final payloadStr = 'SN$finalSn';
      _addLog('→ Transmitting Serial Number "$payloadStr" payload to $fullCanId at 250 kbps...', AppTheme.primaryColor);

      List<int> snPayload = payloadStr.codeUnits;
      _okCompleter = Completer<bool>();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: snPayload,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response from $fullCanId...', AppTheme.accentOrange);
      final ok = await _waitForOkResponse(timeout: const Duration(seconds: 4));
      
      setState(() => _stepSuccess[6] = ok);
      
      if (ok) {
        _addLog('✓ Write SN SUCCESS: Serial Number verified and written by device!', AppTheme.successColor);
      } else {
        _addLog('❌ Write SN FAILED: No OK response received.', AppTheme.errorColor);
      }
    } catch (e) {
      _addLog('❌ Write SN Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[6] = false);
    } finally {
      setState(() => _stepLoading[6] = false);
    }
  }

  Future<void> _bootWriteBoardNumber() async {
    final decStr = _boardDecNumberController.text.trim();
    if (decStr.isEmpty) {
      _addLog('❌ Validation error: Board Number cannot be empty.', AppTheme.errorColor);
      return;
    }

    setState(() {
      _stepLoading[8] = true;
      _stepSuccess[8] = null;
    });
    try {
      final baudOk = await _switchBaudRate(CanNominalBaudRate.kbps250, '250 kbps', 'Bootloader Mode');
      if (!baudOk) {
        setState(() => _stepSuccess[8] = false);
        return;
      }

      final canIdStr = _canId250kController.text.trim();
      final fullCanId = '0x$canIdStr';
      
      final codeBytes = _selectedWriteBoardCode.codeUnits;
      final numBytes = _writeBoardNumberBytes;
      final payload = [0x49, 0x44, codeBytes[0], codeBytes[1], numBytes[0], numBytes[1], 0, 0];

      final payloadHexStr = payload.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      _addLog('→ Transmitting Write Board Number payload [$payloadHexStr] to $fullCanId at 250 kbps...', AppTheme.primaryColor);

      _okCompleter = Completer<bool>();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: payload,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response from $fullCanId...', AppTheme.accentOrange);
      final ok = await _waitForOkResponse(timeout: const Duration(seconds: 4));
      
      setState(() => _stepSuccess[8] = ok);
      
      if (ok) {
        _addLog('✓ Write Board Number SUCCESS: Configuration verified and written!', AppTheme.successColor);
      } else {
        _addLog('❌ Write Board Number FAILED: No OK response received.', AppTheme.errorColor);
      }
    } catch (e) {
      _addLog('❌ Write Board Number Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[8] = false);
    } finally {
      setState(() => _stepLoading[8] = false);
    }
  }

  void _onDeviceBaudDetected(String baudLabel) {
    if (_lastDetectedDeviceBaud != baudLabel) {
      _lastDetectedDeviceBaud = baudLabel;
      _addLog('✓ Scanned Device CAN Baud Rate: "$baudLabel"', AppTheme.successColor);
    }
    if (mounted) {
      setState(() {
        if (_stepLoading[9] == true) {
          _stepSuccess[9] = true;
          _stepLoading[9] = false;
        }
      });
    }
  }

  Future<void> _deviceGetBaud() async {
    setState(() {
      _stepLoading[9] = true;
      _stepSuccess[9] = null;
    });
    try {
      // List of baud rates to try in order
      final probeSpeeds = [
        (CanNominalBaudRate.kbps100, '100 kbps', '000000FF', false),
        (CanNominalBaudRate.kbps20, '20 kbps', '000000FF', false),
        (CanNominalBaudRate.kbps50, '50 kbps', '000000FF', false),
        (CanNominalBaudRate.kbps250, '250 kbps', '00000001', true),
      ];

      for (final (baudRate, baudLabel, canIdStr, isBootloader) in probeSpeeds) {
        // Force hardware switch
        _currentHardwareBaudRate = null;
        final modeLabel = isBootloader ? 'Bootloader Mode' : 'Application Mode';
        
        final baudOk = await _switchBaudRate(baudRate, baudLabel, modeLabel);
        if (!baudOk) continue;

        final fullCanId = '0x$canIdStr';
        _addLog('→ Querying Device CAN Baud Rate (47 43 / GC) from $fullCanId at $baudLabel...', AppTheme.accentCyan);

        final payload = [0x47, 0x43, 0, 0, 0, 0, 0, 0];
        _lastDetectedDeviceBaud = '';

        widget.serialService.sendCanFrame(
          canId: fullCanId,
          data: payload,
          channel: widget.channel,
          isExtended: _checkIsExtended(canIdStr),
          isFD: widget.isFD,
        );

        int retry = 0;
        while (_lastDetectedDeviceBaud.isEmpty && retry < 40 && _stepLoading[9] == true) {
          await Future.delayed(const Duration(milliseconds: 100));
          retry++;
        }

        if (_lastDetectedDeviceBaud.isNotEmpty) {
          _addLog('⭐ Device is connected at $baudLabel in ${isBootloader ? "Bootloader" : "Application"} Mode!', AppTheme.successColor);
          setState(() {
            _isBootloaderModeSelected = isBootloader;
            _activeBaudText = baudLabel;
            _activeModeText = modeLabel;
            _stepSuccess[9] = true;
          });
          return;
        } else {
          _addLog('  No response at $baudLabel.', AppTheme.textSecondary);
        }
      }

      _addLog('❌ No response for Get Baud Rate from device at any speed.', AppTheme.errorColor);
      setState(() => _stepSuccess[9] = false);
    } catch (e) {
      _addLog('❌ Get Device Baud Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[9] = false);
    } finally {
      setState(() => _stepLoading[9] = false);
    }
  }

  Future<void> _deviceWriteBaud() async {
    setState(() {
      _stepLoading[10] = true;
      _stepSuccess[10] = null;
    });
    try {
      final activeBaud = _isBootloaderModeSelected
          ? CanNominalBaudRate.kbps250
          : (_currentHardwareBaudRate ?? CanNominalBaudRate.kbps100);
      final currentBaudLabel = _isBootloaderModeSelected ? '250 kbps' : _activeBaudText;
      final modeLabel = _isBootloaderModeSelected ? 'Bootloader Mode' : 'Application Mode';
      
      final baudOk = await _switchBaudRate(activeBaud, currentBaudLabel, modeLabel);
      if (!baudOk) {
        setState(() => _stepSuccess[10] = false);
        return;
      }

      final canIdStr = _isBootloaderModeSelected ? _canId250kController.text.trim() : _canId100kController.text.trim();
      final fullCanId = '0x$canIdStr';

      final codeInt = int.parse(_selectedDeviceBaudCode);
      final payload = [0x43, 0x41, 0x4E, 0x42, codeInt, 0, 0, 0];
      
      final targetBaudLabel = _baudCodeLabels[_selectedDeviceBaudCode] ?? 'Unknown';
      _addLog('→ Sending Write CAN Baud Rate ($targetBaudLabel) command [43 41 4E 42 ${codeInt.toRadixString(16).padLeft(2, '0').toUpperCase()}] to $fullCanId...', AppTheme.primaryColor);

      _okCompleter = Completer<bool>();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: payload,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response from $fullCanId...', AppTheme.accentOrange);
      final ok = await _waitForOkResponse(timeout: const Duration(seconds: 4));
      
      setState(() => _stepSuccess[10] = ok);

      if (ok) {
        _addLog('✓ Write Baud Rate SUCCESS: Device accepted the new speed configuration.', AppTheme.successColor);
        
        final targetAdapterBaud = _baudCodeToAdapterBaud[_selectedDeviceBaudCode];
        if (targetAdapterBaud != null) {
          _addLog('🔄 Auto switching local USB adapter CAN rate to $targetBaudLabel to match device...', AppTheme.accentCyan);
          await Future.delayed(const Duration(milliseconds: 500));
          final switchOk = await _switchBaudRate(targetAdapterBaud, targetBaudLabel, modeLabel);
          if (switchOk) {
            _addLog('✓ Speed Match COMPLETE: App and Device are now synchronized at $targetBaudLabel!', AppTheme.successColor);
          } else {
            _addLog('⚠ Warning: Failed to automatically switch local adapter baud rate.', AppTheme.errorColor);
          }
        }
      } else {
        _addLog('❌ Write Baud Rate FAILED: No OK response received.', AppTheme.errorColor);
      }
    } catch (e) {
      _addLog('❌ Write Baud Rate Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[10] = false);
    } finally {
      setState(() => _stepLoading[10] = false);
    }
  }

  Future<void> _bootGoToApp() async {
    setState(() {
      _stepLoading[7] = true;
      _stepSuccess[7] = null;
    });
    try {
      final baudOk = await _switchBaudRate(CanNominalBaudRate.kbps250, '250 kbps', 'Bootloader Mode');
      if (!baudOk) {
        setState(() => _stepSuccess[7] = false);
        return;
      }

      final canIdStr = _canId250kController.text.trim();
      final fullCanId = '0x$canIdStr';
      _addLog('→ Sending Jump to App command (46 4A 41 / FJA) to $fullCanId at 250 kbps...', AppTheme.accentCyan);

      final backToAppData = [0x46, 0x4A, 0x41, 0, 0, 0, 0, 0];
      _okCompleter = Completer<bool>();

      widget.serialService.sendCanFrame(
        canId: fullCanId,
        data: backToAppData,
        channel: widget.channel,
        isExtended: _checkIsExtended(canIdStr),
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response from $fullCanId...', AppTheme.accentOrange);
      final ok = await _waitForOkResponse(timeout: const Duration(seconds: 4));
      
      setState(() {
        _stepSuccess[7] = ok;
      });
      
      if (ok) {
        _addLog('✓ Jump to App SUCCESS: Device is in application mode.', AppTheme.successColor);
        await Future.delayed(const Duration(milliseconds: 500));
        final switchOk = await _switchBaudRate(CanNominalBaudRate.kbps100, '100 kbps', 'Application Mode');
        if (switchOk) {
          setState(() {
            _isBootloaderModeSelected = false;
          });
        }
      } else {
        _addLog('❌ Jump to App FAILED: No OK response received.', AppTheme.errorColor);
      }
    } catch (e) {
      _addLog('❌ Jump to App Error: $e', AppTheme.errorColor);
      setState(() => _stepSuccess[7] = false);
    } finally {
      setState(() => _stepLoading[7] = false);
    }
  }

  void _resetStates() {
    setState(() {
      _logs.clear();
      _last4DigitsController.clear();
      _selectedBoardCode = 'DI';
      _boardDecNumberController.text = '161';
      _selectedWriteBoardCode = 'DL';
      _selectedDeviceBaudCode = '03'; // Default 100 kbps
      _lastDetectedDeviceBaud = '';
      _lastDetectedSn = '';
      _lastDetectedBoardInfo = '';
      _isBootloaderModeSelected = false;
      _activeBaudText = '100 kbps';
      _activeModeText = 'Application Mode';
      _currentHardwareBaudRate = null;
      _stepSuccess.keys.forEach((k) => _stepSuccess[k] = null);
      _stepLoading.keys.forEach((k) => _stepLoading[k] = false);
    });
    _addLog('System reset: Configuration flushes and state variables restored to default.', AppTheme.accentCyan);
  }

  Future<bool> _runAutoDetection({bool showLogs = true}) async {
    if (showLogs) {
      _addLog('🔍 Starting Device Auto-Detection Routine...', AppTheme.accentCyan);
    }
    
    // Save current state to restore if detection fails
    final savedBaudText = _activeBaudText;
    final savedModeText = _activeModeText;
    final savedHardwareBaud = _currentHardwareBaudRate;
    
    final testConfigs = [
      // 1. App Mode 100k (Default)
      _AutoDetectConfig(CanNominalBaudRate.kbps100, '100 kbps', '000000FF', false),
      // 2. App Mode 20k
      _AutoDetectConfig(CanNominalBaudRate.kbps20, '20 kbps', '000000FF', false),
      // 3. App Mode 50k
      _AutoDetectConfig(CanNominalBaudRate.kbps50, '50 kbps', '000000FF', false),
      // 4. Bootloader Mode 250k
      _AutoDetectConfig(CanNominalBaudRate.kbps250, '250 kbps', '00000001', true),
    ];

    for (final cfg in testConfigs) {
      if (showLogs) {
        _addLog('Probing: ${cfg.baudLabel} (${cfg.isBootloader ? "Bootloader" : "Application"} ID: 0x${cfg.canIdStr})...', AppTheme.textSecondary);
      }
      
      // Force hardware switch by clearing cached rate so _switchBaudRate always runs
      _currentHardwareBaudRate = null;
      
      final modeLabel = cfg.isBootloader ? 'Bootloader Mode' : 'Application Mode';
      final baudOk = await _switchBaudRate(cfg.baudRate, cfg.baudLabel, modeLabel);
      if (!baudOk) {
        if (showLogs) {
          _addLog('⚠ Could not switch to ${cfg.baudLabel}, skipping...', AppTheme.accentOrange);
        }
        continue;
      }
      
      _lastDetectedBoardInfo = '';
      _lastDetectedSn = '';
      
      final payload = [0x01, 0x01, 0, 0, 0, 0, 0, 0];
      final fullCanId = '0x${cfg.canIdStr}';
      
      try {
        widget.serialService.sendCanFrame(
          canId: fullCanId,
          data: payload,
          channel: widget.channel,
          isExtended: _checkIsExtended(cfg.canIdStr),
          isFD: widget.isFD,
        );
      } catch (_) {}
      
      // Wait up to 800ms for a response
      int waitMs = 0;
      while (waitMs < 800) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitMs += 50;
        if (_lastDetectedBoardInfo.isNotEmpty || _lastDetectedSn.isNotEmpty) {
          _addLog('⭐ SUCCESS: Device detected at ${cfg.baudLabel} in ${cfg.isBootloader ? "Bootloader" : "Application"} Mode!', AppTheme.successColor);
          
          setState(() {
            _isBootloaderModeSelected = cfg.isBootloader;
            _activeBaudText = cfg.baudLabel;
            _activeModeText = modeLabel;
            if (cfg.isBootloader) {
              _canId250kController.text = cfg.canIdStr;
            } else {
              _canId100kController.text = cfg.canIdStr;
            }
            if (cfg.baudLabel == '20 kbps') _selectedDeviceBaudCode = '01';
            if (cfg.baudLabel == '50 kbps') _selectedDeviceBaudCode = '02';
            if (cfg.baudLabel == '100 kbps') _selectedDeviceBaudCode = '03';
            if (cfg.baudLabel == '250 kbps') _selectedDeviceBaudCode = '04';
          });
          return true;
        }
      }
      
      if (showLogs) {
        _addLog('  No response at ${cfg.baudLabel}.', AppTheme.textSecondary);
      }
    }
    
    // Restore previous state since nothing was found
    setState(() {
      _activeBaudText = savedBaudText;
      _activeModeText = savedModeText;
    });
    _currentHardwareBaudRate = savedHardwareBaud;
    
    if (showLogs) {
      _addLog('❌ Auto-Detection: No responding device found on any speed/mode profile.', AppTheme.errorColor);
    }
    return false;
  }

  Future<void> _handleAutoDetectClick() async {
    setState(() {
      _stepLoading[11] = true;
      _stepSuccess[11] = null;
    });
    final success = await _runAutoDetection(showLogs: true);
    setState(() {
      _stepLoading[11] = false;
      _stepSuccess[11] = success;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  UI WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatusHeader() {
    final statusColor = widget.serialService.isConnected ? AppTheme.successColor : AppTheme.errorColor;
    final connLabel = widget.serialService.isConnected ? 'CONNECTED' : 'DISCONNECTED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgMedium,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: AppTheme.bgDarkest,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.settings_input_composite_rounded,
                  size: 14,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Active Mode: ',
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      ),
                      Text(
                        _activeModeText,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textBright),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'CAN Baud Rate: ',
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      ),
                      Text(
                        _activeBaudText,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentOrange),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  connLabel,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Target CAN ID (depends on mode)
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isBootloaderModeSelected ? 'Boot CAN ID (250k)' : 'App CAN ID (100k)',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _isBootloaderModeSelected ? _canId250kController : _canId100kController,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(width: 1, height: 56, color: AppTheme.borderColor),
              const SizedBox(width: 14),
              // Mode Selection Dropdown
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode / State Selection',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: DropdownButtonFormField<bool>(
                        value: _isBootloaderModeSelected,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _isBootloaderModeSelected = val;
                            });
                            if (val) {
                              _switchBaudRate(CanNominalBaudRate.kbps250, '250 kbps', 'Bootloader Mode');
                            } else {
                              _switchBaudRate(CanNominalBaudRate.kbps100, '100 kbps', 'Application Mode');
                            }
                          }
                        },
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                        dropdownColor: AppTheme.bgElevated,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: Text('Application Mode (100 kbps)'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Bootloader Mode (250 kbps)'),
                          ),
                        ],
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
          // Target Device CAN Baud Rate dropdown row (always visible)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Device CAN Baud Rate',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: DropdownButtonFormField<String>(
                        value: _selectedDeviceBaudCode,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedDeviceBaudCode = val;
                            });
                          }
                        },
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                        dropdownColor: AppTheme.bgElevated,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        items: const [
                          DropdownMenuItem(value: '01', child: Text('20 kbps (0x01)')),
                          DropdownMenuItem(value: '02', child: Text('50 kbps (0x02)')),
                          DropdownMenuItem(value: '03', child: Text('100 kbps (0x03)')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Command Code',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgDarkest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'CANB 0x$_selectedDeviceBaudCode',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isBootloaderModeSelected) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.borderColor),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Board Code Dropdown (full names, maps to code)
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Board / Module Type',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 38,
                        child: DropdownButtonFormField<String>(
                          value: _selectedBoardCode,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedBoardCode = val;
                              });
                            }
                          },
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                          dropdownColor: AppTheme.bgElevated,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          ),
                          items: () {
                            final list = _boardCodeLabels.entries.map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            )).toList();
                            if (!_boardCodeLabels.containsKey(_selectedBoardCode)) {
                              list.add(DropdownMenuItem(
                                value: _selectedBoardCode,
                                child: Text('Custom Board ($_selectedBoardCode)'),
                              ));
                            }
                            return list;
                          }(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 4-Digit Sequence input with prefix label
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sequence Number',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.bgDarkest,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
                            ),
                            child: Text(
                              _finalSerialNumber,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.bgInput,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: const BoxDecoration(
                                color: AppTheme.bgDarkest,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(5),
                                  bottomLeft: Radius.circular(5),
                                ),
                                border: Border(
                                  right: BorderSide(color: AppTheme.borderColor),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'ST2528$_selectedBoardCode',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _last4DigitsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textBright,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0000',
                                  hintStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Write Board Type',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 38,
                        child: DropdownButtonFormField<String>(
                          value: _selectedWriteBoardCode,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedWriteBoardCode = val;
                              });
                            }
                          },
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                          dropdownColor: AppTheme.bgElevated,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'AV', child: Text('AC Voltage (AV)')),
                            DropdownMenuItem(value: 'AC', child: Text('AC Current (AC)')),
                            DropdownMenuItem(value: 'DH', child: Text('DC High Voltage (DH)')),
                            DropdownMenuItem(value: 'DL', child: Text('DC Low Voltage (DL)')),
                            DropdownMenuItem(value: 'HI', child: Text('DC High Current (HI)')),
                            DropdownMenuItem(value: 'LI', child: Text('DC Low Current (LI)')),
                            DropdownMenuItem(value: 'DC', child: Text('Digital Board (DC)')),
                            DropdownMenuItem(value: 'AM', child: Text('Accelerometer (AM)')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Board Number',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.bgDarkest,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
                            ),
                            child: Text(
                              'Hex: $_writeBoardNumberHexPreview',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 38,
                        child: TextField(
                          controller: _boardDecNumberController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textBright,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. 161',
                            hintStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: AppTheme.borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: AppTheme.borderColor),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommandsSection() {
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
                'Routine Commands (Profile: $_activeModeText)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_isBootloaderModeSelected)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 3.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _buildCommandCard(
                  name: 'Scan Board ID',
                  description: 'Request board identification query',
                  hexStr: '01 01',
                  onTap: _appScanBoard,
                  isLoading: _stepLoading[1] ?? false,
                  isSuccess: _stepSuccess[1],
                ),
                _buildCommandCard(
                  name: 'Scan Device Serial',
                  description: 'Request device serial number query',
                  hexStr: '01 02',
                  onTap: _appScanSerial,
                  isLoading: _stepLoading[2] ?? false,
                  isSuccess: _stepSuccess[2],
                ),
                _buildCommandCard(
                  name: 'Get CAN Baud Rate',
                  description: 'Query current CAN baud rate code from device',
                  hexStr: 'GC',
                  onTap: _deviceGetBaud,
                  isLoading: _stepLoading[9] ?? false,
                  isSuccess: _stepSuccess[9],
                ),
                _buildCommandCard(
                  name: 'Write CAN Baud Rate',
                  description: 'Configure device CAN baud rate',
                  hexStr: 'CANB',
                  onTap: _deviceWriteBaud,
                  isLoading: _stepLoading[10] ?? false,
                  isSuccess: _stepSuccess[10],
                  badgeColor: AppTheme.successColor,
                ),

                _buildCommandCard(
                  name: 'Jump to Bootloader',
                  description: 'Command device to enter bootloader mode',
                  hexStr: '65 72 65',
                  onTap: _appGoToBootloader,
                  isLoading: _stepLoading[3] ?? false,
                  isSuccess: _stepSuccess[3],
                  badgeColor: AppTheme.accentOrange,
                ),
              ],
            )
          else
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 3.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _buildCommandCard(
                  name: 'Scan Board ID',
                  description: 'Queries board info while in bootloader',
                  hexStr: '01 01',
                  onTap: _bootScanBoard,
                  isLoading: _stepLoading[4] ?? false,
                  isSuccess: _stepSuccess[4],
                ),
                _buildCommandCard(
                  name: 'Scan Device Serial',
                  description: 'Queries serial number while in bootloader',
                  hexStr: '01 02',
                  onTap: _bootScanSerial,
                  isLoading: _stepLoading[5] ?? false,
                  isSuccess: _stepSuccess[5],
                ),
                _buildCommandCard(
                  name: 'Write Serial Number',
                  description: 'Write target serial number to device',
                  hexStr: 'Write SN',
                  onTap: _bootWriteSn,
                  isLoading: _stepLoading[6] ?? false,
                  isSuccess: _stepSuccess[6],
                  badgeColor: AppTheme.successColor,
                ),
                _buildCommandCard(
                  name: 'Write Board Number',
                  description: 'Write module type & number to board',
                  hexStr: 'Write BD',
                  onTap: _bootWriteBoardNumber,
                  isLoading: _stepLoading[8] ?? false,
                  isSuccess: _stepSuccess[8],
                  badgeColor: AppTheme.successColor,
                ),

                _buildCommandCard(
                  name: 'Jump to Application',
                  description: 'Command bootloader to enter app mode',
                  hexStr: '46 4A 41',
                  onTap: _bootGoToApp,
                  isLoading: _stepLoading[7] ?? false,
                  isSuccess: _stepSuccess[7],
                  badgeColor: AppTheme.accentOrange,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCommandCard({
    required String name,
    required String description,
    required String hexStr,
    required VoidCallback? onTap,
    required bool isLoading,
    required bool? isSuccess,
    Color? badgeColor,
  }) {
    final actColor = badgeColor ?? AppTheme.primaryColor;
    
    Widget headerBadge = Container(
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
          color: isSuccess == true
              ? AppTheme.successColor
              : (isSuccess == false ? AppTheme.errorColor : actColor),
        ),
      ),
    );

    if (isLoading) {
      headerBadge = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentOrange),
      );
    }

    final isClickable = onTap != null && !isLoading && !_isExecuting;

    return Material(
      color: AppTheme.bgMedium.withOpacity(0.5),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: isClickable ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        hoverColor: AppTheme.primaryColor.withOpacity(0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSuccess == true
                  ? AppTheme.successColor.withOpacity(0.5)
                  : (isSuccess == false
                      ? AppTheme.errorColor.withOpacity(0.5)
                      : AppTheme.borderColor.withOpacity(0.7)),
            ),
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
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textBright,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  headerBadge,
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Change Serial Number',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textBright,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Pane: Dropdown selection + grid commands
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusHeader(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildConfigSection(),
                            const SizedBox(height: 12),
                            _buildCommandsSection(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isExecuting ? null : _resetStates,
                          icon: const Icon(Icons.restart_alt_rounded, size: 14),
                          label: Text(
                            'Reset States',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.errorColor,
                            side: const BorderSide(color: AppTheme.errorColor),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right Pane: Sequence Trace Log
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgMedium,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sequence Trace Log',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textBright,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppTheme.textMuted),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _logs.clear();
                              });
                            },
                            tooltip: 'Clear Logs',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: AppTheme.borderColor),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.bgDarkest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: _logs.isEmpty
                              ? Center(
                                  child: Text(
                                    'No logs yet. Execute steps to trace communication.',
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _logScrollController,
                                  itemCount: _logs.length,
                                  itemBuilder: (context, index) {
                                    final log = _logs[index];
                                    Color logColor = AppTheme.textPrimary;
                                    if (log.contains('❌') || log.contains('TIMEOUT')) {
                                      logColor = AppTheme.errorColor;
                                    } else if (log.contains('✓') || log.contains('SUCCESS') || log.contains('4F 4B')) {
                                      logColor = AppTheme.successColor;
                                    } else if (log.contains('→') || log.contains('Transmitting') || log.contains('Sending')) {
                                      logColor = AppTheme.primaryColor;
                                    } else if (log.contains('←')) {
                                      logColor = AppTheme.textSecondary;
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        log,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          height: 1.4,
                                          color: logColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoDetectConfig {
  final CanNominalBaudRate baudRate;
  final String baudLabel;
  final String canIdStr;
  final bool isBootloader;

  _AutoDetectConfig(this.baudRate, this.baudLabel, this.canIdStr, this.isBootloader);
}
