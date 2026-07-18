import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/bulk_firmware_service.dart';
import '../services/serial_port_service.dart';

// ═══════════════════════════════════════════════════════════════
//  LOG ENTRY
// ═══════════════════════════════════════════════════════════════

enum LogLevel { info, tx, rx, success, warning, error }

class LogEntry {
  final String timestamp;
  final String message;
  final LogLevel level;
  LogEntry({required this.timestamp, required this.message, required this.level});
}

// ═══════════════════════════════════════════════════════════════
//  BULK FIRMWARE CONTROLLER (ChangeNotifier)
// ═══════════════════════════════════════════════════════════════

class BulkFirmwareController extends ChangeNotifier {
  BulkFirmwareService? _service;

  // Connection params — updated each time dialog opens
  int _channel = 0;
  bool _isExtended = false;

  // State
  bool isMockMode = false;
  bool isScanning = false;
  bool isUploading = false;
  bool isManualMode = false;
  bool waitingForManualTrigger = false;

  // Mock upload manual states
  int _mockCurrentFrame = 0;
  int _mockTotalFrames = 0;
  List<DiscoveredBoard> _mockSelectedBoards = [];

  List<DiscoveredBoard> boards = [];
  BulkFirmwareFile? firmwareFile;

  double progress = 0.0;
  String statusMessage = 'Idle';

  // Target board type
  BoardType selectedBoardType = BoardType.all;

  // Fake timer for mock mode
  Timer? _mockTimer;

  // Inter-frame delay (stored as string for TextEditingController)
  String delayMs = '1';

  // Log
  final List<LogEntry> log = [];

  /// Called each time the Bulk OTA dialog is opened to update connection params.
  void updateConnection({
    required SerialPortService serialService,
    required int channel,
    required bool isExtended,
  }) {
    _channel = channel;
    _isExtended = isExtended;
    _service = BulkFirmwareService(serialService);
  }

  int get channel => _channel;
  bool get isExtended => _isExtended;

  void addLog(String message, LogLevel level) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    log.add(LogEntry(timestamp: ts, message: message, level: level));
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  void setSelectedBoardType(BoardType type) {
    selectedBoardType = type;
    notifyListeners();
  }

  void setMockMode(bool value) {
    isMockMode = value;
    notifyListeners();
  }

  void setManualMode(bool value) {
    if (!isUploading) {
      isManualMode = value;
      notifyListeners();
    }
  }

  void setDelayMs(String value) {
    delayMs = value;
  }

  void toggleBoardSelection(int index, bool value) {
    if (index >= 0 && index < boards.length) {
      boards[index].selected = value;
      notifyListeners();
    }
  }

  // ── Mock Helpers ──

  void startMockScan() {
    addLog('Starting mock CAN bus scan for ${selectedBoardType.label}...', LogLevel.info);

    String typeCode = selectedBoardType.code;
    addLog('→ TX: 01 01 $typeCode 00 00 00 00 00', LogLevel.tx);

    isScanning = true;
    boards.clear();
    statusMessage = 'Scanning for nodes (Mock)...';
    notifyListeners();

    Future.delayed(const Duration(seconds: 2), () {
      int count = Random().nextInt(5) + 2;
      List<DiscoveredBoard> mocks = [];

      if (selectedBoardType == BoardType.all) {
        final testTypes = [
          BoardType.digital,
          BoardType.acVoltage,
          BoardType.dcHighVoltage,
          BoardType.acCurrent,
        ];
        final testBoardNos = [1, 1, 2, 3];
        final testCanIds = [0x31, 0x32, 0x33, 0x34];

        for (int i = 0; i < testTypes.length; i++) {
          final bt = testTypes[i];
          final boardNo = testBoardNos[i];
          final canId = testCanIds[i];
          final verStr = '1.0.0';

          final char1Hex = bt.code.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase();
          final char2Hex = bt.code.codeUnitAt(1).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardNoMsbHex =
              ((boardNo >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardNoLsbHex =
              (boardNo & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final canIdHex = canId.toRadixString(16).padLeft(2, '0').toUpperCase();
          final verHex = verStr.codeUnits
              .map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');

          final rawHex =
              '$char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex $canIdHex $verHex';
          mocks.add(DiscoveredBoard(
            canId: canId,
            deviceId: boardNo,
            boardTypeValue: bt.value,
            version: verStr,
            rawHex: rawHex,
          ));
        }
      } else {
        for (int i = 0; i < count; i++) {
          final bt = selectedBoardType;
          final boardNo = i + 1;
          final canId = 0x31 + i;
          final verStr = '1.0.0';

          final char1Hex = bt.code.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase();
          final char2Hex = bt.code.codeUnitAt(1).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardNoMsbHex =
              ((boardNo >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardNoLsbHex =
              (boardNo & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final canIdHex = canId.toRadixString(16).padLeft(2, '0').toUpperCase();
          final verHex = verStr.codeUnits
              .map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');

          final rawHex =
              '$char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex $canIdHex $verHex';
          mocks.add(DiscoveredBoard(
            canId: canId,
            deviceId: boardNo,
            boardTypeValue: bt.value,
            version: verStr,
            rawHex: rawHex,
          ));
        }
      }

      isScanning = false;
      boards = mocks;
      statusMessage = 'Found ${boards.length} nodes.';
      addLog('Found ${boards.length} nodes on CAN bus.', LogLevel.success);
      for (var b in boards) {
        addLog('← RX [Node ${b.deviceIdStr}]: ${b.rawHex}', LogLevel.rx);
      }
      notifyListeners();
    });
  }

  void startMockUpload() {
    if (boards.isEmpty || firmwareFile == null) return;

    final selectedBoards = boards.where((b) => b.selected).toList();
    if (selectedBoards.isEmpty) {
      addLog('❌ Please select at least one board.', LogLevel.error);
      return;
    }

    addLog('Starting Mock Bulk OTA for ${selectedBoards.length} boards...', LogLevel.info);

    if (isManualMode) {
      isUploading = true;
      waitingForManualTrigger = true;
      progress = 0.0;
      _mockCurrentFrame = 0;
      _mockTotalFrames = firmwareFile!.frameCount;
      _mockSelectedBoards = selectedBoards;
      statusMessage =
          'Manual Mode: Ready to send Broadcast Header (Mock). Click "Send Frame" to transmit.';
      for (var b in boards) {
        if (b.selected) {
          b.status = BoardOtaStatus.discovered;
          b.statusMessage = 'Waiting';
          b.progress = 0.0;
        }
      }
      notifyListeners();
      addLog('Manual Mode: Ready to send Broadcast Header (Mock).', LogLevel.info);
      return;
    }

    final selectedBoard = selectedBoards.first;
    final bt = BoardType.fromValue(selectedBoard.boardTypeValue) ?? BoardType.all;
    final file = firmwareFile!;
    final sizeLow =
        (file.fileSize & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final sizeHigh =
        ((file.fileSize >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final framesLow =
        (file.frameCount & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final framesHigh =
        ((file.frameCount >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final crcLow =
        (file.fileCrc & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final crcHigh =
        ((file.fileCrc >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final char1Hex =
        bt.code.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase();
    final char2Hex =
        bt.code.codeUnitAt(1).toRadixString(16).padLeft(2, '0').toUpperCase();
    final mockHeaderHex =
        '02 $char1Hex $char2Hex $sizeLow $sizeHigh $framesLow $framesHigh $crcLow $crcHigh';

    addLog('→ TX: $mockHeaderHex (Header)', LogLevel.tx);

    isUploading = true;
    progress = 0.0;
    statusMessage = 'Starting Bulk OTA (Mock)...';
    for (var b in boards) {
      if (b.selected) {
        b.status = BoardOtaStatus.discovered;
        b.statusMessage = 'Waiting';
        b.progress = 0.0;
      }
    }
    notifyListeners();

    int currentFrame = 0;
    int totalFrames = firmwareFile!.frameCount;

    _mockTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (currentFrame == 0) {
        for (var b in selectedBoards) {
          b.status = BoardOtaStatus.uploading;
          b.statusMessage = 'Header OK';

          final boardNoMsbHex =
              ((b.deviceId >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardNoLsbHex =
              (b.deviceId & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardType = BoardType.fromValue(b.boardTypeValue) ?? BoardType.all;
          final char1Hex =
              boardType.code.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase();
          final char2Hex =
              boardType.code.codeUnitAt(1).toRadixString(16).padLeft(2, '0').toUpperCase();

          addLog(
              '← RX [Node ${b.canIdHex}]: 79 $char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex 00 (Header ACK)',
              LogLevel.success);
        }
      }

      currentFrame++;
      progress = currentFrame / (totalFrames + 1);
      statusMessage = 'Sending Data $currentFrame / $totalFrames';

      String frameHex =
          (currentFrame & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      String frameHex2 =
          ((currentFrame >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      addLog(
          '→ TX: $frameHex $frameHex2 [60 bytes data...] (Frame $currentFrame)', LogLevel.tx);

      for (var b in selectedBoards) {
        b.progress = progress;
        b.statusMessage = 'Frame $currentFrame/$totalFrames';
      }

      if (currentFrame >= totalFrames) {
        timer.cancel();
        progress = totalFrames / (totalFrames + 1);
        statusMessage = 'All frames sent. Waiting 3 seconds before completion signal...';
        addLog(
            'All frames sent. Waiting 3 seconds before completion signal...', LogLevel.info);

        Timer(const Duration(seconds: 3), () {
          statusMessage = 'Sending Completion Signal (Mock)...';
          addLog('→ TX: 46 00 00 ... (Completion Signal)', LogLevel.tx);
          notifyListeners();

          Timer(const Duration(milliseconds: 1500), () {
            progress = 1.0;
            isUploading = false;
            statusMessage = 'Bulk OTA Complete!';

            for (int i = 0; i < selectedBoards.length; i++) {
              final b = selectedBoards[i];
              final boardNoMsbHex = ((b.deviceId >> 8) & 0xFF)
                  .toRadixString(16)
                  .padLeft(2, '0')
                  .toUpperCase();
              final boardNoLsbHex =
                  (b.deviceId & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
              final boardType = BoardType.fromValue(b.boardTypeValue) ?? BoardType.all;
              final char1Hex = boardType.code
                  .codeUnitAt(0)
                  .toRadixString(16)
                  .padLeft(2, '0')
                  .toUpperCase();
              final char2Hex = boardType.code
                  .codeUnitAt(1)
                  .toRadixString(16)
                  .padLeft(2, '0')
                  .toUpperCase();

              if (i > 0 && Random().nextInt(10) > 7) {
                b.status = BoardOtaStatus.error;
                b.statusMessage = 'Failed (0xE1)';
                addLog(
                    '← RX [Node ${b.canIdHex}]: E1 $char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex 00 (Error)',
                    LogLevel.error);
              } else {
                b.status = BoardOtaStatus.success;
                b.statusMessage = 'Success';
                b.progress = 1.0;

                final oldVer = b.version;
                String newVer = oldVer;
                final reg = RegExp(r'v?(\d+)\.(\d+)\.(\d+)');
                final match = reg.firstMatch(oldVer);
                if (match != null) {
                  final major = int.parse(match.group(1)!);
                  final minor = int.parse(match.group(2)!);
                  final patch = int.parse(match.group(3)!);
                  newVer = '$major.${minor + 1}.$patch';
                } else {
                  newVer = '1.1.0';
                }
                b.version = newVer;

                String verHex = newVer.codeUnits
                    .map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase())
                    .join(' ');
                addLog(
                    '← RX [Node ${b.canIdHex}]: 79 $char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex 00 00 00 $verHex (Complete + Ver: $newVer)',
                    LogLevel.success);
              }
            }
            addLog('Mock Bulk OTA Complete', LogLevel.success);
            notifyListeners();
          });
        });
      }
      notifyListeners();
    });
  }

  void sendManualNextFrame() {
    if (isMockMode) {
      triggerNextMockFrame();
    } else {
      _service?.triggerNextFrame();
    }
  }

  void triggerNextMockFrame() {
    if (!isUploading || !waitingForManualTrigger) return;

    if (_mockCurrentFrame == 0) {
      final selectedBoard = _mockSelectedBoards.first;
      final bt = BoardType.fromValue(selectedBoard.boardTypeValue) ?? BoardType.all;
      final file = firmwareFile!;
      final sizeLow =
          (file.fileSize & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      final sizeHigh =
          ((file.fileSize >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      final framesLow =
          (file.frameCount & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      final framesHigh =
          ((file.frameCount >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      final crcLow =
          (file.fileCrc & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      final crcHigh =
          ((file.fileCrc >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      final char1Hex =
          bt.code.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase();
      final char2Hex =
          bt.code.codeUnitAt(1).toRadixString(16).padLeft(2, '0').toUpperCase();
      final mockHeaderHex =
          '02 $char1Hex $char2Hex $sizeLow $sizeHigh $framesLow $framesHigh $crcLow $crcHigh';

      addLog('→ TX: $mockHeaderHex (Header)', LogLevel.tx);

      for (var b in _mockSelectedBoards) {
        b.status = BoardOtaStatus.uploading;
        b.statusMessage = 'Header OK';

        final boardNoMsbHex =
            ((b.deviceId >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        final boardNoLsbHex =
            (b.deviceId & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        final boardType = BoardType.fromValue(b.boardTypeValue) ?? BoardType.all;
        final c1Hex =
            boardType.code.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase();
        final c2Hex =
            boardType.code.codeUnitAt(1).toRadixString(16).padLeft(2, '0').toUpperCase();

        addLog(
            '← RX [Node ${b.canIdHex}]: 79 $c1Hex $c2Hex $boardNoMsbHex $boardNoLsbHex 00 (Header ACK)',
            LogLevel.success);
      }

      _mockCurrentFrame = 1;
      if (_mockTotalFrames > 0) {
        statusMessage =
            'Manual Mode: Ready to send frame 1/$_mockTotalFrames (Mock). Click "Send Frame" to transmit.';
      } else {
        statusMessage =
            'Manual Mode: Ready to send Completion Signal (Mock). Click "Send Frame" to transmit.';
        _mockCurrentFrame = _mockTotalFrames + 1;
      }
    } else if (_mockCurrentFrame >= 1 && _mockCurrentFrame <= _mockTotalFrames) {
      final k = _mockCurrentFrame;
      progress = k / (_mockTotalFrames + 1);
      statusMessage = 'Sending Data $k / $_mockTotalFrames';

      String frameHex = (k & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      String frameHex2 =
          ((k >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      addLog('→ TX: $frameHex $frameHex2 [60 bytes data...] (Frame $k)', LogLevel.tx);

      for (var b in _mockSelectedBoards) {
        b.progress = progress;
        b.statusMessage = 'Frame $k/$_mockTotalFrames';
      }

      _mockCurrentFrame++;
      if (_mockCurrentFrame > _mockTotalFrames) {
        statusMessage =
            'Manual Mode: Ready to send Completion Signal (Mock). Click "Send Frame" to transmit.';
      } else {
        statusMessage =
            'Manual Mode: Ready to send frame $_mockCurrentFrame/$_mockTotalFrames (Mock). Click "Send Frame" to transmit.';
      }
    } else if (_mockCurrentFrame == _mockTotalFrames + 1) {
      waitingForManualTrigger = false;
      statusMessage = 'Sending Completion Signal (Mock)...';
      addLog('→ TX: 46 00 00 ... (Completion Signal)', LogLevel.tx);

      Timer(const Duration(milliseconds: 500), () {
        progress = 1.0;
        isUploading = false;
        statusMessage = 'Bulk OTA Complete!';

        for (int i = 0; i < _mockSelectedBoards.length; i++) {
          final b = _mockSelectedBoards[i];
          final boardNoMsbHex =
              ((b.deviceId >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardNoLsbHex =
              (b.deviceId & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
          final boardType = BoardType.fromValue(b.boardTypeValue) ?? BoardType.all;
          final char1Hex = boardType.code
              .codeUnitAt(0)
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase();
          final char2Hex = boardType.code
              .codeUnitAt(1)
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase();

          if (i > 0 && Random().nextInt(10) > 7) {
            b.status = BoardOtaStatus.error;
            b.statusMessage = 'Failed (0xE1)';
            addLog(
                '← RX [Node ${b.canIdHex}]: E1 $char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex 00 (Error)',
                LogLevel.error);
          } else {
            b.status = BoardOtaStatus.success;
            b.statusMessage = 'Success';
            b.progress = 1.0;

            final oldVer = b.version;
            String newVer = oldVer;
            final reg = RegExp(r'v?(\d+)\.(\d+)\.(\d+)');
            final match = reg.firstMatch(oldVer);
            if (match != null) {
              final major = int.parse(match.group(1)!);
              final minor = int.parse(match.group(2)!);
              final patch = int.parse(match.group(3)!);
              newVer = '$major.${minor + 1}.$patch';
            } else {
              newVer = '1.1.0';
            }
            b.version = newVer;

            String verHex = newVer.codeUnits
                .map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase())
                .join(' ');
            addLog(
                '← RX [Node ${b.canIdHex}]: 79 $char1Hex $char2Hex $boardNoMsbHex $boardNoLsbHex 00 00 00 $verHex (Complete + Ver: $newVer)',
                LogLevel.success);
          }
        }
        addLog('Mock Bulk OTA Complete', LogLevel.success);
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ── Real Logic ──

  Future<void> pickFile() async {
    try {
      final result = await Process.run('powershell', [
        '-Command',
        r'''
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "Binary Files (*.bin)|*.bin|All Files (*.*)|*.*"
        $dialog.Title = "Select Firmware Binary File"
        if ($dialog.ShowDialog() -eq 'OK') { $dialog.FileName }
        '''
      ]);

      final path = result.stdout.toString().trim();
      if (path.isEmpty) return;

      final file = File(path);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      final fileName = path.split(RegExp(r'[/\\]')).last;
      final firmware = _service!.prepareFile(fileName, bytes);

      addLog('Loaded firmware: $fileName (${firmware.fileSize} bytes)', LogLevel.info);

      firmwareFile = firmware;
      notifyListeners();
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> sendForceJump() async {
    if (isMockMode) {
      addLog('Sending Force Jump command (Mock): 41 80 80', LogLevel.tx);
      statusMessage = 'Sending Force Jump...';
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      addLog('\u2190 RX: B0 (Force jump accepted \u2014 jumping to application)',
          LogLevel.success);
      statusMessage = 'Force jump sent \u2014 boards jumping to application';
      notifyListeners();
      return;
    }

    addLog('Sending Force Jump command: 41 80 80', LogLevel.tx);
    statusMessage = 'Sending Force Jump...';
    notifyListeners();

    final result = await _service!.sendForceJump(
      txCanId: '0x01',
      channel: _channel,
      isExtended: _isExtended,
    );

    if (result.success) {
      addLog('\u2190 RX: ${result.rawHex} (${result.message})', LogLevel.success);
      statusMessage = result.message;
    } else {
      addLog('\u274c ${result.message}', LogLevel.error);
      statusMessage = result.message;
    }
    notifyListeners();
  }

  Future<void> scanNodes() async {
    if (isMockMode) {
      startMockScan();
      return;
    }

    addLog(
        'Scanning CAN Bus (Tx ID: 0x01) for ${selectedBoardType.label}...', LogLevel.info);
    String typeHex =
        selectedBoardType.value.toRadixString(16).padLeft(2, '0').toUpperCase();
    addLog('\u2192 TX: 01 01 $typeHex 00 00 00 00 00', LogLevel.tx);
    isScanning = true;
    boards.clear();
    statusMessage = 'Scanning CAN Bus for ${selectedBoardType.label}...';
    notifyListeners();

    try {
      final results = await _service!.scanBoards(
        txCanId: '0x01',
        channel: _channel,
        isExtended: _isExtended,
        targetBoardType: selectedBoardType.value,
      );

      addLog('Scan complete: Found ${results.length} nodes.', LogLevel.success);
      for (var b in results) {
        addLog(
            '\u2190 RX [Node ${b.deviceIdStr}]: ${b.rawHex} (${b.boardTypeName}, Ver: ${b.version})',
            LogLevel.rx);
      }
      boards = results;
      isScanning = false;
      statusMessage = 'Found ${boards.length} nodes.';
      notifyListeners();
    } catch (e) {
      addLog('Scan error: $e', LogLevel.error);
      isScanning = false;
      statusMessage = 'Scan error: $e';
      notifyListeners();
    }
  }

  void startUpload() {
    if (isMockMode) {
      startMockUpload();
      return;
    }

    if (firmwareFile == null || boards.isEmpty) return;

    final selectedBoards = boards.where((b) => b.selected).toList();
    if (selectedBoards.isEmpty) {
      addLog('❌ Please select at least one board.', LogLevel.error);
      return;
    }

    final firstType = selectedBoards.first.boardTypeValue;
    final mixedTypes = selectedBoards.any((b) => b.boardTypeValue != firstType);
    if (mixedTypes) {
      addLog(
          '❌ Cannot broadcast to mixed board types. Select only one type of board.',
          LogLevel.error);
      return;
    }

    final delayMsInt = int.tryParse(delayMs) ?? 0;

    isUploading = true;
    progress = 0.0;
    statusMessage = 'Starting Bulk OTA...';
    waitingForManualTrigger = false;
    for (var b in boards) {
      if (b.selected) {
        b.status = BoardOtaStatus.discovered;
        b.statusMessage = 'Starting...';
      }
    }
    notifyListeners();

    addLog('Starting Bulk OTA...', LogLevel.info);

    _service!
        .startBulkUpload(
      firmwareFile!,
      txCanId: '0x01',
      channel: _channel,
      isExtended: _isExtended,
      boardTypeValue: firstType,
      interFrameDelayMs: delayMsInt,
      selectedBoards: selectedBoards,
      manualMode: isManualMode,
    )
        .listen(
      (progressEvent) {
        final isData = progressEvent.status == BulkUploadStatus.sendingData;

        if (progressEvent.status == BulkUploadStatus.sendingHeader ||
            progressEvent.status == BulkUploadStatus.sendingCompletion) {
          addLog('→ ${progressEvent.message}', LogLevel.tx);
        } else if (isData) {
          addLog('→ ${progressEvent.message}', LogLevel.tx);
        } else if (progressEvent.status == BulkUploadStatus.waitingManualTrigger) {
          addLog('⏳ ${progressEvent.message}', LogLevel.info);
        } else if (progressEvent.boardCanId != null) {
          final isBoardSelected =
              boards.any((b) => b.canId == progressEvent.boardCanId && b.selected);
          if (progressEvent.boardSuccess == false) {
            final suffix = isBoardSelected ? '' : ' (Ignored)';
            addLog('← ${progressEvent.message}$suffix', LogLevel.error);
          } else {
            if (!isBoardSelected) {
              addLog('← ${progressEvent.message} (Ignored)', LogLevel.info);
            } else {
              addLog('← ${progressEvent.message}', LogLevel.success);
            }
          }
        } else if (progressEvent.status == BulkUploadStatus.complete) {
          addLog('✅ ${progressEvent.message}', LogLevel.success);
        } else if (progressEvent.status == BulkUploadStatus.error) {
          addLog('❌ ${progressEvent.message}', LogLevel.error);
        }

        progress = progressEvent.percent;
        statusMessage = progressEvent.message;
        waitingForManualTrigger =
            progressEvent.status == BulkUploadStatus.waitingManualTrigger;

        if (progressEvent.status == BulkUploadStatus.sendingData) {
          for (var b in boards) {
            if (b.selected && b.status == BoardOtaStatus.uploading) {
              b.progress = progressEvent.percent;
              b.statusMessage =
                  'Frame ${progressEvent.currentFrame}/${progressEvent.totalFrames}';
            }
          }
        }

        if (progressEvent.status == BulkUploadStatus.complete) {
          for (var b in boards) {
            if (b.selected && b.status == BoardOtaStatus.uploading) {
              b.status = BoardOtaStatus.success;
              b.statusMessage = 'Success';
              b.progress = 1.0;
            }
          }
        }

        if (progressEvent.boardCanId != null) {
          final idx = boards.indexWhere((b) => b.canId == progressEvent.boardCanId);
          if (idx != -1 && boards[idx].selected) {
            if (progressEvent.status == BulkUploadStatus.waitingHeaderAck ||
                progressEvent.status == BulkUploadStatus.waitingCompletionAck) {
              if (progressEvent.boardSuccess == true) {
                boards[idx].status =
                    progressEvent.status == BulkUploadStatus.waitingCompletionAck
                        ? BoardOtaStatus.success
                        : BoardOtaStatus.uploading;
                boards[idx].statusMessage =
                    progressEvent.status == BulkUploadStatus.waitingCompletionAck
                        ? 'Success'
                        : 'Header ACKed';
                if (progressEvent.status == BulkUploadStatus.waitingCompletionAck) {
                  boards[idx].progress = 1.0;
                  if (progressEvent.boardNewVersion != null) {
                    boards[idx].version = progressEvent.boardNewVersion!;
                  }
                }
              } else if (progressEvent.boardSuccess == false) {
                boards[idx].status = BoardOtaStatus.error;
                boards[idx].statusMessage = 'Error/NACK';
              }
            }
          }
        }

        if (progressEvent.status == BulkUploadStatus.complete ||
            progressEvent.status == BulkUploadStatus.error ||
            progressEvent.status == BulkUploadStatus.cancelled) {
          isUploading = false;
          waitingForManualTrigger = false;
        }

        notifyListeners();
      },
      onError: (error) {
        isUploading = false;
        waitingForManualTrigger = false;
        statusMessage = 'Error: $error';
        notifyListeners();
      },
    );
  }

  void cancelUpload() {
    _service?.cancel();
    _mockTimer?.cancel();
    addLog('Cancellation requested by user.', LogLevel.warning);
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }
}
