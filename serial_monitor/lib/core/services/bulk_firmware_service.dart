import 'dart:async';
import 'dart:typed_data';
import 'serial_port_service.dart';
import 'firmware_upload_service.dart'; // crc16Modbus

// ═══════════════════════════════════════════════════════════════
//  BOARD TYPES
// ═══════════════════════════════════════════════════════════════

enum BoardType {
  all(0x00, 'All Boards', 'ALL'),
  acVoltage(0x01, 'AC Voltage', 'AV'),
  acCurrent(0x02, 'AC Current', 'AC'),
  dcHighVoltage(0x03, 'DC High Voltage', 'DH'),
  dcLowVoltage(0x04, 'DC Low Voltage', 'DL'),
  dcHighCurrent(0x05, 'DC High Current', 'HI'),
  dcLowCurrent(0x06, 'DC Low Current', 'LI'),
  accelerometer(0x07, 'Accelerometer', 'AM'),
  digital(0x08, 'Digital', 'DC'),
  bh(0x09, 'BH', 'BH'),
  ax(0x0A, 'AX Board', 'AX');

  final int value;
  final String label;
  final String code;
  const BoardType(this.value, this.label, this.code);

  static BoardType? fromValue(int val) {
    for (final bt in BoardType.values) {
      if (bt.value == val) return bt;
    }
    return null;
  }

  static BoardType? fromCode(String code) {
    for (final bt in BoardType.values) {
      if (bt.code.toUpperCase() == code.toUpperCase()) return bt;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════
//  DISCOVERED BOARD
// ═══════════════════════════════════════════════════════════════

enum BoardOtaStatus { discovered, uploading, success, error }

/// Boot status codes sent by the bootloader at power-on (§3.1)
enum BootStatus {
  noUpdate(0xA0, 'No update — jumping to app'),
  waitingForBin(0xA1, 'Waiting for .bin (boot flag set)'),
  waitingForNewBin(0xA2, 'Waiting for new .bin (update requested)'),
  blankFlash(0xA3, 'Initial wait — blank flash'),
  unknown(0x00, 'Unknown');

  final int code;
  final String description;
  const BootStatus(this.code, this.description);

  static BootStatus fromCode(int code) {
    for (final s in BootStatus.values) {
      if (s.code == code) return s;
    }
    return BootStatus.unknown;
  }
}

/// Human-readable error descriptions for bootloader NACK codes (§3.3)
String errorDescription(int code) {
  switch (code) {
    case 0xE1: return 'Missing frames — byte count mismatch';
    case 0xE2: return 'CRC error — frame or whole-file CRC mismatch';
    case 0xE3: return 'Board type mismatch';
    case 0xE4: return 'Bin file size mismatch';
    case 0xE5: return 'Total frames mismatch';
    case 0xE6: return 'All frames not received';
    case 0xE7: return 'Waiting for board selection';
    default:   return 'Unknown error (0x${code.toRadixString(16).toUpperCase()})';
  }
}

class DiscoveredBoard {
  final int canId;       // Hardware CAN ID from the frame header
  final int deviceId;    // Device ID from tx_buffer[1] (DIP switch value)
  final int boardTypeValue; // Board type from tx_buffer[0]
  String version;
  BoardOtaStatus status;
  String statusMessage;
  String rawHex;
  bool selected;         // Whether this board is selected for OTA
  double progress;       // Individual upload progress (0.0 to 1.0)
  final String originalVersion; // Store original version before OTA
  BootStatus bootStatus; // Boot status code from power-on (§3.1)

  DiscoveredBoard({
    required this.canId,
    required this.deviceId,
    required this.boardTypeValue,
    required this.version,
    this.status = BoardOtaStatus.discovered,
    this.statusMessage = 'Connected',
    this.rawHex = '',
    this.selected = true,
    this.progress = 0.0,
    this.bootStatus = BootStatus.unknown,
    String? originalVersion,
  }) : originalVersion = originalVersion ?? version;

  String get boardTypeName {
    return BoardType.fromValue(boardTypeValue)?.label ?? 'Unknown (0x${boardTypeValue.toRadixString(16).toUpperCase()})';
  }

  String get canIdHex => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
  String get deviceIdStr => '#$deviceId';
}

// ═══════════════════════════════════════════════════════════════
//  BULK UPLOAD PROGRESS
// ═══════════════════════════════════════════════════════════════

enum BulkUploadStatus {
  idle,
  scanning,
  sendingHeader,
  waitingHeaderAck,
  sendingData,
  sendingCompletion,
  waitingCompletionAck,
  complete,
  error,
  cancelled,
  waitingManualTrigger,
}

class BulkUploadProgress {
  final BulkUploadStatus status;
  final int currentFrame;
  final int totalFrames;
  final String message;
  final int? boardCanId;
  final bool? boardSuccess;
  final String? boardNewVersion;

  BulkUploadProgress({
    required this.status,
    this.currentFrame = 0,
    this.totalFrames = 0,
    this.message = '',
    this.boardCanId,
    this.boardSuccess,
    this.boardNewVersion,
  });

  double get percent {
    if (totalFrames == 0) return 0;
    if (status == BulkUploadStatus.complete) return 1.0;
    return currentFrame / (totalFrames + 1);
  }
}

// ═══════════════════════════════════════════════════════════════
//  BULK FIRMWARE FILE
// ═══════════════════════════════════════════════════════════════

class BulkFirmwareFile {
  final String fileName;
  final Uint8List bytes;
  final int fileSize;
  final int frameCount;
  final int fileCrc;

  BulkFirmwareFile({
    required this.fileName,
    required this.bytes,
    required this.fileSize,
    required this.frameCount,
    required this.fileCrc,
  });
}

// ═══════════════════════════════════════════════════════════════
//  CONSTANTS
// ═══════════════════════════════════════════════════════════════

const int _bulkChunkSize = 60; // bytes 2–61 in a 64-byte frame after frame index
const int _frameSize = 64;
const Duration _scanTimeout = Duration(seconds: 5);
const Duration _ackTimeout = Duration(seconds: 30);

// ═══════════════════════════════════════════════════════════════
//  BULK FIRMWARE SERVICE
// ═══════════════════════════════════════════════════════════════

class BulkFirmwareService {
  final SerialPortService _serialService;
  bool _cancelled = false;
  Completer<void>? _nextFrameCompleter;

  // Saved callbacks — suppressed during OTA
  Function(Map<String, dynamic>)? _savedRxCallback;
  Function(Map<String, dynamic>)? _savedTxCallback;

  BulkFirmwareService(this._serialService);

  void triggerNextFrame() {
    if (_nextFrameCompleter != null && !_nextFrameCompleter!.isCompleted) {
      _nextFrameCompleter!.complete();
    }
  }

  // ── File preparation ──

  BulkFirmwareFile prepareFile(String fileName, Uint8List fileBytes) {
    final fileSize = fileBytes.length;
    final frameCount = (fileSize + _bulkChunkSize - 1) ~/ _bulkChunkSize;
    final fileCrc = crc16Modbus(fileBytes.toList());
    return BulkFirmwareFile(
      fileName: fileName,
      bytes: fileBytes,
      fileSize: fileSize,
      frameCount: frameCount,
      fileCrc: fileCrc,
    );
  }

  void cancel() {
    _cancelled = true;
    if (_nextFrameCompleter != null && !_nextFrameCompleter!.isCompleted) {
      _nextFrameCompleter!.complete();
    }
  }

  // ── Console suppression ──

  void _suppressConsoleLogging() {
    _savedRxCallback = _serialService.onCanFrameRx;
    _savedTxCallback = _serialService.onCanFrameTx;
    _serialService.onCanFrameTx = null;
  }

  void _restoreConsoleLogging() {
    _serialService.onCanFrameRx = _savedRxCallback;
    _serialService.onCanFrameTx = _savedTxCallback;
    _savedRxCallback = null;
    _savedTxCallback = null;
  }

  bool _send8ByteFrame(
    List<int> payload, {
    required String canId,
    required int channel,
    required bool isExtended,
  }) {
    if (!_serialService.isCanMode) {
      return _serialService.sendData(Uint8List.fromList(payload));
    }
    final frame = List<int>.filled(8, 0x00);
    for (int i = 0; i < payload.length && i < 8; i++) {
      frame[i] = payload[i];
    }
    return _serialService.sendCanFrame(
      canId: canId,
      data: frame,
      channel: channel,
      isExtended: isExtended,
      isFD: false, // Standard 8-byte CAN
    );
  }

  bool _send64ByteFrame(
    List<int> payload, {
    required String canId,
    required int channel,
    required bool isExtended,
  }) {
    // Pad/truncate to exactly 64 bytes
    final frame = List<int>.filled(_frameSize, 0x00);
    for (int i = 0; i < payload.length && i < _frameSize; i++) {
      frame[i] = payload[i];
    }

    if (!_serialService.isCanMode) {
      return _serialService.sendData(Uint8List.fromList(frame));
    }

    return _serialService.sendCanFrame(
      canId: canId,
      data: frame,
      channel: channel,
      isExtended: isExtended,
      isFD: true, // Always CAN FD for 64-byte frames
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SCAN MODE (0x01) — Firmware Version Request (§2.1)
  // ═══════════════════════════════════════════════════════════════

  Future<List<DiscoveredBoard>> scanBoards({
    required String txCanId,
    required int channel,
    required bool isExtended,
    required int targetBoardType,
  }) async {
    final boards = <DiscoveredBoard>[];
    final completer = Completer<void>();

    // Intercept RX frames during scan
    final savedRx = _serialService.onCanFrameRx;
    final savedData = _serialService.onDataReceived;

    void handleIncomingFrame(Map<String, dynamic> frame) {
      final dataHex = frame['dataHex'] as String? ?? '';
      final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
      if (hexParts.isEmpty) return;

      final canIdStr = frame['canId']?.toString() ?? '';
      final canIdNum = int.tryParse(
        canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
        radix: 16,
      ) ?? 0;

      final firstByte = int.tryParse(hexParts[0], radix: 16) ?? 0;

      // ── Boot Status Codes (§3.1): 0xA0, 0xA1, 0xA2, 0xA3 ──
      // Sent once at power-on. We capture them during scan so the
      // UI can show each board's startup condition.
      if (firstByte >= 0xA0 && firstByte <= 0xA3) {
        // Boot status frames may not include version info,
        // just record the status for any board that sends it.
        // We'll merge with the version response if it comes later.
        return; // Boot status noted but board will reply with version next
      }

      // ── Firmware Version Response ──
      bool parsed = false;

      // Format A (Standard): Byte 0-1 are Board Type (2 ASCII chars), Byte 2-3 are Board Number (MSB, LSB), Byte 4 is CAN ID, Byte 5-9 is Firmware Version (5 Bytes ASCII)
      if (hexParts.length >= 10) {
        final char1 = int.tryParse(hexParts[0], radix: 16) ?? 0;
        final char2 = int.tryParse(hexParts[1], radix: 16) ?? 0;
        
        if (char1 >= 32 && char1 <= 126 && char2 >= 32 && char2 <= 126) {
          final boardTypeCode = String.fromCharCodes([char1, char2]);
          final boardType = BoardType.fromCode(boardTypeCode);

          if (boardType != null) {
            // Byte 2-3: Board Number (MSB & LSB)
            final boardNoMsb = int.tryParse(hexParts[2], radix: 16) ?? 0;
            final boardNoLsb = int.tryParse(hexParts[3], radix: 16) ?? 0;
            final boardNo = (boardNoMsb << 8) | boardNoLsb;

            // Byte 5-9: Version string (exactly 5 bytes)
            String version = '';
            for (int i = 5; i < 10; i++) {
              final byte = int.tryParse(hexParts[i], radix: 16) ?? 0;
              if (byte >= 32 && byte <= 126) {
                version += String.fromCharCode(byte);
              }
            }
            if (version.endsWith('.')) {
              version += '0';
            }

            // Filter by targetBoardType:
            if (targetBoardType == BoardType.all.value || boardType.value == targetBoardType) {
              if (!boards.any((b) => b.deviceId == boardNo && b.boardTypeValue == boardType.value)) {
                boards.add(DiscoveredBoard(
                  canId: canIdNum,
                  deviceId: boardNo,
                  boardTypeValue: boardType.value,
                  version: version.isEmpty ? 'Unknown' : version,
                  rawHex: hexParts.join(' '),
                ));
              }
            }
            parsed = true;
          }
        }
      }

      // Format B (New): Byte 0-1 are Board Number (MSB, LSB), Byte 2-3 are Board Type (2 ASCII chars, e.g. 'BH'), Byte 4-5 are Serial / Version information
      if (!parsed && hexParts.length >= 6) {
        final char1 = int.tryParse(hexParts[2], radix: 16) ?? 0;
        final char2 = int.tryParse(hexParts[3], radix: 16) ?? 0;

        if (char1 >= 32 && char1 <= 126 && char2 >= 32 && char2 <= 126) {
          final boardTypeCode = String.fromCharCodes([char1, char2]);
          final boardType = BoardType.fromCode(boardTypeCode);

          if (boardType != null) {
            // Byte 0-1: Board Number (MSB & LSB)
            final boardNoMsb = int.tryParse(hexParts[0], radix: 16) ?? 0;
            final boardNoLsb = int.tryParse(hexParts[1], radix: 16) ?? 0;
            final boardNo = (boardNoMsb << 8) | boardNoLsb;

            // Byte 4-5: Serial / Version information (e.g. 00 01 -> 0.1.0 or 0.0.1)
            final verMajor = int.tryParse(hexParts[4], radix: 16) ?? 0;
            final verMinor = int.tryParse(hexParts[5], radix: 16) ?? 0;
            final version = "$verMajor.$verMinor.0";

            // Filter by targetBoardType:
            if (targetBoardType == BoardType.all.value || boardType.value == targetBoardType) {
              if (!boards.any((b) => b.deviceId == boardNo && b.boardTypeValue == boardType.value)) {
                boards.add(DiscoveredBoard(
                  canId: canIdNum,
                  deviceId: boardNo,
                  boardTypeValue: boardType.value,
                  version: version,
                  rawHex: hexParts.join(' '),
                ));
              }
            }
            parsed = true;
          }
        }
      }
    }

    if (!_serialService.isCanMode) {
      final List<int> rxBuffer = [];
      _serialService.onDataReceived = (Uint8List data) {
        rxBuffer.addAll(data);
        
        while (rxBuffer.isNotEmpty) {
          // Look for 12-byte Format: e.g. "ST2528AX0001"
          if (rxBuffer.length >= 12) {
            final char1 = rxBuffer[6];
            final char2 = rxBuffer[7];
            
            // Check if char1 & char2 form a valid board type
            if (char1 >= 32 && char1 <= 126 && char2 >= 32 && char2 <= 126) {
              final boardTypeCode = String.fromCharCodes([char1, char2]);
              final boardType = BoardType.fromCode(boardTypeCode);
              
              if (boardType != null) {
                // Parse board number from bytes 8-11 as ASCII digits
                String boardNoStr = '';
                for (int i = 8; i < 12; i++) {
                  if (rxBuffer[i] >= 48 && rxBuffer[i] <= 57) {
                    boardNoStr += String.fromCharCode(rxBuffer[i]);
                  }
                }
                final boardNo = int.tryParse(boardNoStr) ?? 0;
                
                final hexParts = rxBuffer.sublist(0, 12).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).toList();
                
                if (targetBoardType == BoardType.all.value || boardType.value == targetBoardType) {
                  if (!boards.any((b) => b.deviceId == boardNo && b.boardTypeValue == boardType.value)) {
                    boards.add(DiscoveredBoard(
                      canId: 0,
                      deviceId: boardNo,
                      boardTypeValue: boardType.value,
                      version: '1.0.0',
                      rawHex: hexParts.join(' '),
                    ));
                  }
                }
                
                rxBuffer.removeRange(0, 12);
                continue;
              }
            }
          }
          
          // Look for 4-byte Format: e.g. "AX" + [0x00, 0x01]
          if (rxBuffer.length >= 4) {
            final char1 = rxBuffer[0];
            final char2 = rxBuffer[1];
            
            if (char1 >= 32 && char1 <= 126 && char2 >= 32 && char2 <= 126) {
              final boardTypeCode = String.fromCharCodes([char1, char2]);
              final boardType = BoardType.fromCode(boardTypeCode);
              
              if (boardType != null) {
                final boardNo = (rxBuffer[2] << 8) | rxBuffer[3];
                final hexParts = rxBuffer.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).toList();
                
                if (targetBoardType == BoardType.all.value || boardType.value == targetBoardType) {
                  if (!boards.any((b) => b.deviceId == boardNo && b.boardTypeValue == boardType.value)) {
                    boards.add(DiscoveredBoard(
                      canId: 0,
                      deviceId: boardNo,
                      boardTypeValue: boardType.value,
                      version: '1.0.0',
                      rawHex: hexParts.join(' '),
                    ));
                  }
                }
                
                rxBuffer.removeRange(0, 4);
                continue;
              }
            }
          }
          
          // Shift buffer by 1 byte if no patterns match
          rxBuffer.removeAt(0);
        }
      };
    } else {
      _serialService.onCanFrameRx = handleIncomingFrame;
    }

    if (!_serialService.isCanMode) {
      // In Raw Serial mode, send query command 01 01 first (short status)
      _serialService.sendData(Uint8List.fromList([0x01, 0x01]));
      
      // Send 01 02 (long status query) shortly after to ensure discovery of boards responding to both
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!completer.isCompleted) {
          _serialService.sendData(Uint8List.fromList([0x01, 0x02]));
        }
      });
    } else {
      _send8ByteFrame(
        [0x01, 0x01, targetBoardType],
        canId: txCanId,
        channel: channel,
        isExtended: isExtended,
      );
    }

    // Wait for responses
    Timer(_scanTimeout, () {
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;

    // Restore original callback
    _serialService.onCanFrameRx = savedRx;
    _serialService.onDataReceived = savedData;

    return boards;
  }

  // ═══════════════════════════════════════════════════════════════
  //  BULK UPLOAD (Header → Bin → Completion)
  // ═══════════════════════════════════════════════════════════════

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  Stream<BulkUploadProgress> startBulkUpload(
    BulkFirmwareFile file, {
    required String txCanId,
    required int channel,
    required bool isExtended,
    required int boardTypeValue,
    required int interFrameDelayMs,
    required List<DiscoveredBoard> selectedBoards,
    bool manualMode = false,
  }) async* {
    _cancelled = false;
    _suppressConsoleLogging();

    try {
      // ── STEP 1: Send Single Broadcast Header (0x02) ──
      final headerPayload = _buildHeaderPayload(file, boardTypeValue);
      final headerHex = _bytesToHex(headerPayload);

      if (manualMode) {
        _nextFrameCompleter = Completer<void>();
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingManualTrigger,
          totalFrames: file.frameCount,
          message: 'Manual Mode: Ready to send Broadcast Header. Click "Send Frame" to transmit: $headerHex',
        );
        await _nextFrameCompleter!.future;
        if (_cancelled) {
          yield BulkUploadProgress(
            status: BulkUploadStatus.cancelled,
            totalFrames: file.frameCount,
            message: 'Upload cancelled by user.',
          );
          return;
        }
      }



      yield BulkUploadProgress(
        status: BulkUploadStatus.sendingHeader,
        totalFrames: file.frameCount,
        message: 'Sending Broadcast Header: $headerHex',
      );

      final headerSent = _send64ByteFrame(
        headerPayload,
        canId: txCanId,
        channel: channel,
        isExtended: isExtended,
      );

      if (!headerSent) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          totalFrames: file.frameCount,
          message: 'Failed to send Broadcast Header — port not available.',
        );
        return;
      }

      yield BulkUploadProgress(
        status: BulkUploadStatus.waitingHeaderAck,
        totalFrames: file.frameCount,
        message: 'Broadcast Header sent. Waiting for boards to ACK...',
      );

      final selectedCanIds = selectedBoards.map((board) => board.canId).toSet();

      // Wait to collect all staggered ACKs from the bus
      var headerAcks = await _waitForAcks(
        expectedCanIds: selectedCanIds,
        timeoutSeconds: 3,
      );

      // If no ACKs received via CAN FD header, fallback to Standard CAN 8-byte Header
      if (headerAcks.isEmpty && !_cancelled) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.sendingHeader,
          totalFrames: file.frameCount,
          message: 'No ACK on CAN FD header. Retrying Broadcast Header via Standard CAN (8-byte)...',
        );

        _send8ByteFrame(
          headerPayload,
          canId: txCanId,
          channel: channel,
          isExtended: isExtended,
        );

        headerAcks = await _waitForAcks(
          expectedCanIds: selectedCanIds,
          timeoutSeconds: 12,
        );
      }
      
      if (_cancelled) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.cancelled,
          totalFrames: file.frameCount,
          message: 'Upload cancelled by user.',
        );
        return;
      }

      // Report ACK results back to the UI
      for (final ack in headerAcks) {
        final canIdHex = '0x${ack.canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
        final errText = ack.errorDetail.isNotEmpty ? ack.errorDetail : 'Unexpected Header Response';
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingHeaderAck,
          totalFrames: file.frameCount,
          message: ack.success
              ? 'Node #${ack.deviceId} (${ack.boardTypeCode}, CAN ID: $canIdHex) Header ACK \u2713 (RX: ${ack.rawHex})'
              : 'Node #${ack.deviceId} (${ack.boardTypeCode}, CAN ID: $canIdHex) Header Response NOT as expected! Expected: [0x79 or 0x4F 0x4B Header ACK], Received: [${ack.rawHex}] ($errText)',
          boardCanId: ack.canId,
          boardSuccess: ack.success,
        );
      }

      // Check for selected boards that did NOT respond at all (timeout)
      final respondedCanIds = headerAcks.map((a) => a.canId).toSet();
      final noResponseBoards = selectedBoards.where((b) => !respondedCanIds.contains(b.canId)).toList();

      for (final board in noResponseBoards) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingHeaderAck,
          totalFrames: file.frameCount,
          message: 'Node #${board.deviceId} (${board.boardTypeName}, CAN ID: ${board.canIdHex}) Header Response NOT received! Expected: [0x79 or 0x4F 0x4B Header ACK], Received: [NONE / Timeout]',
          boardCanId: board.canId,
          boardSuccess: false,
        );
      }

      final allHeaderAcks = headerAcks;

      if (allHeaderAcks.isEmpty && noResponseBoards.isNotEmpty) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          totalFrames: file.frameCount,
          message: 'No response received from any board for Header packet (Timeout 15s).',
        );
        return;
      } else if (allHeaderAcks.isEmpty) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          totalFrames: file.frameCount,
          message: 'No board acknowledged the header (timeout ${_ackTimeout.inSeconds}s).',
        );
        return;
      }

      final hasAnyOk = allHeaderAcks.any((a) => a.success);
      if (!hasAnyOk) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          totalFrames: file.frameCount,
          message: 'All boards rejected the header.',
        );
        return;
      }

      final ackedCanIds = allHeaderAcks
          .where((ack) => ack.success)
          .map((ack) => ack.canId)
          .toSet();
      final targetCanIds = ackedCanIds.intersection(selectedCanIds);

      if (targetCanIds.isEmpty) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          totalFrames: file.frameCount,
          message: 'No selected board acknowledged the header.',
        );
        return;
      }

      if (!manualMode) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingHeaderAck,
          totalFrames: file.frameCount,
          message: 'Header ACK received. Waiting 5 seconds before first data frame...',
        );

        await Future.delayed(const Duration(seconds: 5));
      }

      if (_cancelled) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.cancelled,
          totalFrames: file.frameCount,
          message: 'Upload cancelled before data transfer started.',
        );
        return;
      }

      // ── STEP 2: Send Bin Data Frames (0x03) ──
      for (int i = 0; i < file.frameCount; i++) {
        if (_cancelled) {
          yield BulkUploadProgress(
            status: BulkUploadStatus.cancelled,
            currentFrame: i,
            totalFrames: file.frameCount,
            message: 'Upload cancelled at frame $i.',
          );
          return;
        }

        final dataPayload = _buildDataPayload(file, i);
        final dataHex = _bytesToHex(dataPayload);
        
        if (manualMode) {
          _nextFrameCompleter = Completer<void>();
          yield BulkUploadProgress(
            status: BulkUploadStatus.waitingManualTrigger,
            currentFrame: i,
            totalFrames: file.frameCount,
            message: 'Manual Mode: Ready to send frame ${i + 1}/${file.frameCount}. Click "Send Frame" to transmit: $dataHex',
          );
          await _nextFrameCompleter!.future;

          if (_cancelled) {
            yield BulkUploadProgress(
              status: BulkUploadStatus.cancelled,
              currentFrame: i,
              totalFrames: file.frameCount,
              message: 'Upload cancelled at frame $i.',
            );
            return;
          }
        }

        // User requested to see every single frame in the UI
        yield BulkUploadProgress(
          status: BulkUploadStatus.sendingData,
          currentFrame: i + 1,
          totalFrames: file.frameCount,
          message: 'Sending frame ${i + 1}/${file.frameCount}: $dataHex',
        );

        final sent = _send64ByteFrame(
          dataPayload,
          canId: txCanId,
          channel: channel,
          isExtended: isExtended,
        );

        if (!sent) {
          yield BulkUploadProgress(
            status: BulkUploadStatus.error,
            currentFrame: i + 1,
            totalFrames: file.frameCount,
            message: 'Failed to send frame ${i + 1}.',
          );
          return;
        }

        if (!manualMode) {
          if (interFrameDelayMs > 0) {
            await Future.delayed(Duration(milliseconds: interFrameDelayMs));
          } else {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
      }

      if (!manualMode) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.sendingData,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'All frames sent. Waiting 3 seconds before completion signal...',
        );

        await Future.delayed(const Duration(seconds: 3));
      }

      if (_cancelled) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.cancelled,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'Upload cancelled during wait delay.',
        );
        return;
      }

      // ── STEP 3: Send Completion Frame (0x46) ──
      if (_cancelled) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.cancelled,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'Upload cancelled before completion signal.',
        );
        return;
      }

      final completionPayload = List<int>.filled(_frameSize, 0x00);
      completionPayload[0] = 0x4F; // 'O'
      completionPayload[1] = 0x4B; // 'K'
      final completionHex = _bytesToHex(completionPayload);

      if (manualMode) {
        _nextFrameCompleter = Completer<void>();
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingManualTrigger,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'Manual Mode: Ready to send Completion Signal (0x46). Click "Send Frame" to transmit: $completionHex',
        );
        await _nextFrameCompleter!.future;

        if (_cancelled) {
          yield BulkUploadProgress(
            status: BulkUploadStatus.cancelled,
            currentFrame: file.frameCount,
            totalFrames: file.frameCount,
            message: 'Upload cancelled before completion signal.',
          );
          return;
        }
      }

      final allCompletionAcksMap = <int, _CompletionAck>{};
      
      for (int attempt = 1; attempt <= 3; attempt++) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.sendingCompletion,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: attempt == 1 
            ? 'Sending Completion Signal: $completionHex'
            : 'Retry $attempt/3: Resending Completion Signal...',
        );

        final completionSent = _send64ByteFrame(
          completionPayload,
          canId: txCanId,
          channel: channel,
          isExtended: isExtended,
        );

        if (!completionSent) {
          yield BulkUploadProgress(
            status: BulkUploadStatus.error,
            currentFrame: file.frameCount,
            totalFrames: file.frameCount,
            message: 'Failed to send Completion Signal — port not available.',
          );
          return;
        }

        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingCompletionAck,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: attempt == 1
            ? 'Completion Signal sent. Waiting for boards to ACK and report new versions...'
            : 'Retry $attempt/3: Waiting for boards to ACK...',
        );

        // Figure out which ones we still need (only those that have not succeeded yet)
        final succeededIds = allCompletionAcksMap.values.where((a) => a.success).map((a) => a.canId).toSet();
        final remainingIds = selectedCanIds.difference(succeededIds);
        if (remainingIds.isEmpty) break; // We already have success for all of them

        final completionAcks = await _waitForCompletionAcks(
          expectedCanIds: remainingIds,
          maxTimeoutSeconds: 5,
          graceTimeoutSeconds: 5,
        );

        for (final ack in completionAcks) {
          allCompletionAcksMap[ack.canId] = ack;
        }

        if (_cancelled) {
          yield BulkUploadProgress(
            status: BulkUploadStatus.cancelled,
            currentFrame: file.frameCount,
            totalFrames: file.frameCount,
            message: 'Upload cancelled during completion phase.',
          );
          return;
        }

        final newSucceededIds = allCompletionAcksMap.values.where((a) => a.success).map((a) => a.canId).toSet();
        if (selectedCanIds.difference(newSucceededIds).isEmpty) {
          break; // Got all successful ACKs
        }
      }

      final completionAcks = allCompletionAcksMap.values.toList();

      // Report ACK results back to the UI
      for (final ack in completionAcks) {
        final canIdHex = '0x${ack.canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingCompletionAck,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: ack.success
              ? 'Node #${ack.boardNo} (${ack.boardTypeCode}, CAN ID: $canIdHex) ACK \u2713 (New Version: ${ack.newVersion}, RX: ${ack.rawHex})'
              : 'Node #${ack.boardNo} (${ack.boardTypeCode}, CAN ID: $canIdHex) NACK \u2717: ${ack.errorDetail} (RX: ${ack.rawHex})',
          boardCanId: ack.canId,
          boardSuccess: ack.success,
          boardNewVersion: ack.success ? ack.newVersion : null,
        );
      }

      final hasAnyCompOk = completionAcks.any((a) => a.success);
      if (completionAcks.isEmpty) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'No board acknowledged the completion signal (timeout).',
        );
        return;
      } else if (!hasAnyCompOk) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.error,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'All boards rejected the completion signal.',
        );
        return;
      }

      yield BulkUploadProgress(
        status: BulkUploadStatus.complete,
        currentFrame: file.frameCount,
        totalFrames: file.frameCount,
        message: 'Bulk firmware upload complete! (${file.frameCount} frames sent)',
      );
    } finally {
      _restoreConsoleLogging();
    }
  }

  // ── Frame Builders ──

  List<int> _buildHeaderPayload(BulkFirmwareFile file, int boardTypeValue) {
    final boardType = BoardType.fromValue(boardTypeValue) ?? BoardType.all;
    final code = boardType.code;
    
    if (file.fileSize > 65535) {
      // 10-byte header layout: 3-byte size field for files > 65K
      final payload = List<int>.filled(10, 0x00);
      payload[0] = 0x02; // Mode: Header
      
      if (code.length >= 2) {
        payload[1] = code.codeUnitAt(0);
        payload[2] = code.codeUnitAt(1);
      } else {
        payload[1] = 0x00;
        payload[2] = 0x00;
      }
      
      payload[3] = file.fileSize & 0xFF;           // File Size LE byte 0
      payload[4] = (file.fileSize >> 8) & 0xFF;    // File Size LE byte 1
      payload[5] = (file.fileSize >> 16) & 0xFF;   // File Size LE byte 2 (supports sizes > 65K)
      
      payload[6] = file.frameCount & 0xFF;         // Frame Count LE low
      payload[7] = (file.frameCount >> 8) & 0xFF;  // Frame Count LE high
      
      // Store Total File CRC Little Endian
      payload[8] = file.fileCrc & 0xFF;            // CRC LSB
      payload[9] = (file.fileCrc >> 8) & 0xFF;     // CRC MSB
      return payload;
    } else {
      // 9-byte header layout: 2-byte size field for files <= 65K
      final payload = List<int>.filled(9, 0x00);
      payload[0] = 0x02; // Mode: Header
      
      if (code.length >= 2) {
        payload[1] = code.codeUnitAt(0);
        payload[2] = code.codeUnitAt(1);
      } else {
        payload[1] = 0x00;
        payload[2] = 0x00;
      }
      
      payload[3] = file.fileSize & 0xFF;           // File Size LE low
      payload[4] = (file.fileSize >> 8) & 0xFF;    // File Size LE high
      
      payload[5] = file.frameCount & 0xFF;         // Frame Count LE low
      payload[6] = (file.frameCount >> 8) & 0xFF;  // Frame Count LE high
      
      // Store Total File CRC Little Endian
      payload[7] = file.fileCrc & 0xFF;            // CRC LSB
      payload[8] = (file.fileCrc >> 8) & 0xFF;     // CRC MSB
      return payload;
    }
  }

  List<int> _buildDataPayload(BulkFirmwareFile file, int frameIndex) {
    final payload = List<int>.filled(_frameSize, 0x00);

    // Bytes 0-1: fixed protocol bytes for all data frames
    payload[0] = 0x42;
    payload[1] = 0x49;

    // Binary data (bytes 2–61)
    final dataStart = frameIndex * _bulkChunkSize;
    final dataEnd = (dataStart + _bulkChunkSize).clamp(0, file.fileSize);
    final actualLen = dataEnd - dataStart;
    for (int i = 0; i < actualLen; i++) {
      payload[2 + i] = file.bytes[dataStart + i];
    }

    // Modbus CRC-16 over bytes 0-61
    int crc = 0xFFFF;
    for (int i = 0; i < 62; i++) {
      crc ^= payload[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    
    // Store CRC Little Endian
    payload[62] = crc & 0xFF;         // CRC LSB
    payload[63] = (crc >> 8) & 0xFF;  // CRC MSB
    
    return payload;
  }

  // ── Wait for ACKs ──

  Future<List<_BoardAck>> _waitForAcks({
    Set<int>? expectedCanIds,
    int timeoutSeconds = 2,
  }) async {
    final acks = <_BoardAck>[];
    final completer = Completer<void>();
    Timer? cancelTimer;

    final savedRx = _serialService.onCanFrameRx;
    final savedData = _serialService.onDataReceived;

    void handleIncomingFrame(Map<String, dynamic> frame) {
      final dataHex = frame['dataHex'] as String? ?? '';
      final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
      if (hexParts.isEmpty) return;

      final firstByte = hexParts[0].toUpperCase();
      final secondByte = hexParts.length >= 2 ? hexParts[1].toUpperCase() : '';
      final isAck = firstByte == '79' || (firstByte == '4F' && secondByte == '4B');
      // ACK: 0x79 or 0x4F4B (OK), Errors: 0xE1–0xE7
      final canIdStr = frame['canId']?.toString() ?? '';
      final canIdNum = int.tryParse(
        canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
        radix: 16,
      ) ?? 0;

      // Process if this is from an expected board or any board
      if (expectedCanIds == null || expectedCanIds.isEmpty || expectedCanIds.contains(canIdNum)) {
        // Try parsing using both Format A and Format B
        String boardTypeCode = 'UNKNOWN';
        int deviceId = 0;
        final offset = (firstByte == '4F' && secondByte == '4B') ? 2 : 1;
        if (hexParts.length >= offset + 4) {
          // Format A (Standard): Byte offset..offset+1 are Board Type, Byte offset+2..offset+3 are Board Number
          final char1A = int.tryParse(hexParts[offset], radix: 16) ?? 0;
          final char2A = int.tryParse(hexParts[offset + 1], radix: 16) ?? 0;
          final codeA = String.fromCharCodes([char1A, char2A]);
          final typeA = BoardType.fromCode(codeA);

          if (typeA != null) {
            boardTypeCode = codeA;
            final boardNoMsb = int.tryParse(hexParts[offset + 2], radix: 16) ?? 0;
            final boardNoLsb = int.tryParse(hexParts[offset + 3], radix: 16) ?? 0;
            deviceId = (boardNoMsb << 8) | boardNoLsb;
          } else {
            // Format B (New): Byte offset+2..offset+3 are Board Type, Byte offset..offset+1 are Board Number
            final char1B = int.tryParse(hexParts[offset + 2], radix: 16) ?? 0;
            final char2B = int.tryParse(hexParts[offset + 3], radix: 16) ?? 0;
            final codeB = String.fromCharCodes([char1B, char2B]);
            final typeB = BoardType.fromCode(codeB);

            if (typeB != null) {
              boardTypeCode = codeB;
              final boardNoMsb = int.tryParse(hexParts[offset], radix: 16) ?? 0;
              final boardNoLsb = int.tryParse(hexParts[offset + 1], radix: 16) ?? 0;
              deviceId = (boardNoMsb << 8) | boardNoLsb;
            } else {
              if (char1A >= 32 && char1A <= 126 && char2A >= 32 && char2A <= 126) {
                boardTypeCode = codeA;
                final boardNoMsb = int.tryParse(hexParts[offset + 2], radix: 16) ?? 0;
                final boardNoLsb = int.tryParse(hexParts[offset + 3], radix: 16) ?? 0;
                deviceId = (boardNoMsb << 8) | boardNoLsb;
              }
            }
          }
        }

        // Build error description for NACK codes or unexpected opcodes
        final errorCode = int.tryParse(firstByte, radix: 16) ?? 0;
        String errDesc = '';
        if (!isAck) {
          if (errorCode >= 0xE1 && errorCode <= 0xE7) {
            errDesc = errorDescription(errorCode);
          } else {
            errDesc = 'Unexpected response opcode (0x$firstByte). Expected ACK (0x79 or 0x4F4B)';
          }
        }

        // Ensure we don't add duplicates if a board spams ACKs
        if (!acks.any((a) => a.canId == canIdNum)) {
          acks.add(_BoardAck(
            canId: canIdNum,
            deviceId: deviceId,
            boardTypeCode: boardTypeCode,
            success: isAck,
            rawHex: hexParts.join(' '),
            errorDetail: errDesc,
          ));
        }

        // If we have received ACKs from all expected boards, complete immediately
        if (expectedCanIds != null && expectedCanIds.isNotEmpty) {
          final receivedCanIds = acks.map((a) => a.canId).toSet();
          if (receivedCanIds.containsAll(expectedCanIds)) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        }
      }
    }

    if (!_serialService.isCanMode) {
      final List<int> rxBuffer = [];
      _serialService.onDataReceived = (Uint8List data) {
        rxBuffer.addAll(data);
        
        while (rxBuffer.isNotEmpty) {
          final firstByte = rxBuffer[0];
          
          // Check if first byte is a single-byte ACK (0x79)
          if (firstByte == 0x79) {
            final dataHex = rxBuffer.sublist(0, 1).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
            int boardCanIdNum = 0;
            if (expectedCanIds != null && expectedCanIds.isNotEmpty) {
              boardCanIdNum = expectedCanIds.first;
            }
            acks.add(_BoardAck(
              canId: boardCanIdNum,
              deviceId: 0,
              boardTypeCode: 'AX',
              success: true,
              rawHex: dataHex,
            ));
            rxBuffer.removeAt(0);
            if (!completer.isCompleted) completer.complete();
            return;
          }
          
          // Check if first byte is a NACK error code (0xE1 to 0xE7)
          if (firstByte >= 0xE1 && firstByte <= 0xE7) {
            final dataHex = rxBuffer.sublist(0, 1).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
            int boardCanIdNum = 0;
            if (expectedCanIds != null && expectedCanIds.isNotEmpty) {
              boardCanIdNum = expectedCanIds.first;
            }
            acks.add(_BoardAck(
              canId: boardCanIdNum,
              deviceId: 0,
              boardTypeCode: 'AX',
              success: false,
              rawHex: dataHex,
              errorDetail: errorDescription(firstByte),
            ));
            rxBuffer.removeAt(0);
            if (!completer.isCompleted) completer.complete();
            return;
          }
          
          // Check if first 2 bytes are OK (0x4F, 0x4B)
          if (rxBuffer.length >= 2 && rxBuffer[0] == 0x4F && rxBuffer[1] == 0x4B) {
            // Wait until we have at least 6 bytes (since the board sends [0x4F, 0x4B] + 4 bytes of board selection = 6 bytes!)
            if (rxBuffer.length < 6) {
              // Wait for more bytes to arrive
              return;
            }
            
            final dataHex = rxBuffer.sublist(0, 6).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
            int boardCanIdNum = 0;
            if (expectedCanIds != null && expectedCanIds.isNotEmpty) {
              boardCanIdNum = expectedCanIds.first;
            }
            acks.add(_BoardAck(
              canId: boardCanIdNum,
              deviceId: 0,
              boardTypeCode: 'AX',
              success: true,
              rawHex: dataHex,
            ));
            rxBuffer.removeRange(0, 6);
            if (!completer.isCompleted) completer.complete();
            return;
          }
          
          // If the byte is not recognized (e.g. leading \r or \n or garbage), skip it
          rxBuffer.removeAt(0);
        }
      };
    } else {
      _serialService.onCanFrameRx = handleIncomingFrame;
    }

    cancelTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_cancelled && !completer.isCompleted) {
        completer.complete();
        timer.cancel();
      }
    });

    // Wait full timeout window for all staggered ACKs to arrive
    Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    cancelTimer.cancel();

    _serialService.onCanFrameRx = savedRx;
    _serialService.onDataReceived = savedData;

    return acks;
  }

  // ── Wait for Completion ACKs ──

  Future<List<_CompletionAck>> _waitForCompletionAcks({
    required Set<int> expectedCanIds,
    int maxTimeoutSeconds = 30,
    int graceTimeoutSeconds = 5,
  }) async {
    final acks = <_CompletionAck>[];
    final completer = Completer<void>();
    Timer? maxTimeoutTimer;
    Timer? graceTimer;
    Timer? cancelTimer;

    final savedRx = _serialService.onCanFrameRx;
    final savedData = _serialService.onDataReceived;

    void complete() {
      if (!completer.isCompleted) {
        completer.complete();
      }
      maxTimeoutTimer?.cancel();
      graceTimer?.cancel();
      cancelTimer?.cancel();
      _serialService.onCanFrameRx = savedRx;
      _serialService.onDataReceived = savedData;
    }

    void handleIncomingFrame(Map<String, dynamic> frame) {
      final dataHex = frame['dataHex'] as String? ?? '';
      final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
      if (hexParts.isEmpty) return;

      final firstByte = hexParts[0].toUpperCase();
      final secondByte = hexParts.length >= 2 ? hexParts[1].toUpperCase() : '';
      final isAck = firstByte == '79' || (firstByte == '4F' && secondByte == '4B');
      // ACK: 0x79 or 0x4F4B (OK), All NACK codes: 0xE1–0xE7
      if (isAck || firstByte == 'E1' || firstByte == 'E2' || firstByte == 'E3' || firstByte == 'E4' || firstByte == 'E6' || firstByte == 'E7') {
        final canIdStr = frame['canId']?.toString() ?? '';
        final canIdNum = int.tryParse(
          canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
          radix: 16,
        ) ?? 0;

        // Only parse if it's one of our expected CAN IDs
        if (expectedCanIds.contains(canIdNum)) {
          // Try parsing using both Format A and Format B
          String boardTypeCode = 'UNKNOWN';
          int boardNo = 0;
          if (hexParts.length >= 5) {
            // Format A (Standard): Byte 1-2 are Board Type, Byte 3-4 are Board Number
            final char1A = int.tryParse(hexParts[1], radix: 16) ?? 0;
            final char2A = int.tryParse(hexParts[2], radix: 16) ?? 0;
            final codeA = String.fromCharCodes([char1A, char2A]);
            final typeA = BoardType.fromCode(codeA);

            if (typeA != null) {
              boardTypeCode = codeA;
              final boardNoMsb = int.tryParse(hexParts[3], radix: 16) ?? 0;
              final boardNoLsb = int.tryParse(hexParts[4], radix: 16) ?? 0;
              boardNo = (boardNoMsb << 8) | boardNoLsb;
            } else {
              // Format B (New): Byte 3-4 are Board Type, Byte 1-2 are Board Number
              final char1B = int.tryParse(hexParts[3], radix: 16) ?? 0;
              final char2B = int.tryParse(hexParts[4], radix: 16) ?? 0;
              final codeB = String.fromCharCodes([char1B, char2B]);
              final typeB = BoardType.fromCode(codeB);

              if (typeB != null) {
                boardTypeCode = codeB;
                final boardNoMsb = int.tryParse(hexParts[1], radix: 16) ?? 0;
                final boardNoLsb = int.tryParse(hexParts[2], radix: 16) ?? 0;
                boardNo = (boardNoMsb << 8) | boardNoLsb;
              } else {
                // Fallback to Format A if it is still valid ASCII but type is unknown
                if (char1A >= 32 && char1A <= 126 && char2A >= 32 && char2A <= 126) {
                  boardTypeCode = codeA;
                  final boardNoMsb = int.tryParse(hexParts[3], radix: 16) ?? 0;
                  final boardNoLsb = int.tryParse(hexParts[4], radix: 16) ?? 0;
                  boardNo = (boardNoMsb << 8) | boardNoLsb;
                }
              }
            }
          }

          // Parse version if success: starts at byte 8 in new ACK format
          String newVersion = '';
          if (isAck) {
            for (int i = 8; i < hexParts.length; i++) {
              final byte = int.tryParse(hexParts[i], radix: 16) ?? 0;
              if (byte == 0) break;
              if (byte >= 32 && byte <= 126) {
                newVersion += String.fromCharCode(byte);
              } else {
                break;
              }
            }
            if (newVersion.endsWith('.')) {
              newVersion += '0';
            }
          }

          // Build error description for NACK codes
          final errorCode = int.tryParse(firstByte, radix: 16) ?? 0;
          final errDesc = !isAck ? errorDescription(errorCode) : '';

          if (!acks.any((a) => a.canId == canIdNum)) {
            acks.add(_CompletionAck(
              canId: canIdNum,
              boardNo: boardNo,
              boardTypeCode: boardTypeCode,
              success: isAck,
              newVersion: newVersion.isEmpty ? 'Unknown' : newVersion,
              rawHex: hexParts.join(' '),
              errorDetail: errDesc,
            ));

            // Start grace timer on first response if not already active
            graceTimer ??= Timer(Duration(seconds: graceTimeoutSeconds), () {
              complete();
            });

            // Check if all expected boards have responded
            final receivedCanIds = acks.map((a) => a.canId).toSet();
            if (receivedCanIds.containsAll(expectedCanIds)) {
              complete();
            }
          }
        }
      }
    }

    if (!_serialService.isCanMode) {
      final List<int> rxBuffer = [];
      _serialService.onDataReceived = (Uint8List data) {
        rxBuffer.addAll(data);
        
        while (rxBuffer.isNotEmpty) {
          final firstByte = rxBuffer[0];
          
          // Check if first byte is a single-byte ACK (0x79)
          if (firstByte == 0x79) {
            final dataHex = rxBuffer.sublist(0, 1).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
            int boardCanIdNum = 0;
            if (expectedCanIds.isNotEmpty) {
              boardCanIdNum = expectedCanIds.first;
            }
            if (!acks.any((a) => a.canId == boardCanIdNum)) {
              acks.add(_CompletionAck(
                canId: boardCanIdNum,
                boardNo: 0,
                boardTypeCode: 'AX',
                success: true,
                newVersion: 'Unknown',
                rawHex: dataHex,
              ));
              graceTimer ??= Timer(Duration(seconds: graceTimeoutSeconds), () {
                complete();
              });
              final receivedCanIds = acks.map((a) => a.canId).toSet();
              if (receivedCanIds.containsAll(expectedCanIds)) {
                complete();
              }
            }
            rxBuffer.removeAt(0);
            continue;
          }
          
          // Check if first byte is a NACK error code (0xE1 to 0xE7)
          if (firstByte >= 0xE1 && firstByte <= 0xE7) {
            final dataHex = rxBuffer.sublist(0, 1).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
            int boardCanIdNum = 0;
            if (expectedCanIds.isNotEmpty) {
              boardCanIdNum = expectedCanIds.first;
            }
            if (!acks.any((a) => a.canId == boardCanIdNum)) {
              acks.add(_CompletionAck(
                canId: boardCanIdNum,
                boardNo: 0,
                boardTypeCode: 'AX',
                success: false,
                newVersion: 'Unknown',
                rawHex: dataHex,
                errorDetail: errorDescription(firstByte),
              ));
              graceTimer ??= Timer(Duration(seconds: graceTimeoutSeconds), () {
                complete();
              });
              final receivedCanIds = acks.map((a) => a.canId).toSet();
              if (receivedCanIds.containsAll(expectedCanIds)) {
                complete();
              }
            }
            rxBuffer.removeAt(0);
            continue;
          }
          
          // Check if first 2 bytes are OK (0x4F, 0x4B)
          if (rxBuffer.length >= 2 && rxBuffer[0] == 0x4F && rxBuffer[1] == 0x4B) {
            // Wait until we have at least 6 bytes (since the board sends [0x4F, 0x4B] + 4 bytes of board selection = 6 bytes!)
            if (rxBuffer.length < 6) {
              return; // wait for more bytes
            }
            
            // Parse new version string from completion ACK in raw serial if appended after the 6-byte header
            String newVersion = 'Unknown';
            if (rxBuffer.length >= 10) {
              String verStr = '';
              for (int i = 6; i < rxBuffer.length; i++) {
                final byte = rxBuffer[i];
                if (byte == 0 || byte == 10 || byte == 13) break;
                if (byte >= 32 && byte <= 126) {
                  verStr += String.fromCharCode(byte);
                } else {
                  break;
                }
              }
              if (verStr.isNotEmpty) {
                if (verStr.endsWith('.')) {
                  verStr += '0';
                }
                newVersion = verStr;
              }
            }
            
            final dataHex = rxBuffer.sublist(0, 6).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
            int boardCanIdNum = 0;
            if (expectedCanIds.isNotEmpty) {
              boardCanIdNum = expectedCanIds.first;
            }
            if (!acks.any((a) => a.canId == boardCanIdNum)) {
              acks.add(_CompletionAck(
                canId: boardCanIdNum,
                boardNo: 0,
                boardTypeCode: 'AX',
                success: true,
                newVersion: newVersion,
                rawHex: dataHex,
              ));
              graceTimer ??= Timer(Duration(seconds: graceTimeoutSeconds), () {
                complete();
              });
              final receivedCanIds = acks.map((a) => a.canId).toSet();
              if (receivedCanIds.containsAll(expectedCanIds)) {
                complete();
              }
            }
            rxBuffer.removeRange(0, 6);
            continue;
          }
          
          // Discard unknown byte
          rxBuffer.removeAt(0);
        }
      };
    } else {
      _serialService.onCanFrameRx = handleIncomingFrame;
    }

    // Periodic check for cancellation
    cancelTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_cancelled) {
        complete();
      }
    });

    // Max timeout
    maxTimeoutTimer = Timer(Duration(seconds: maxTimeoutSeconds), () {
      complete();
    });

    await completer.future;
    return acks;
  }
  // ═══════════════════════════════════════════════════════════════
  //  FORCE APPLICATION JUMP (§2.5)
  // ═══════════════════════════════════════════════════════════════

  /// Send Force Application Jump command: [0x41, 0x80, 0x80]
  /// Clears OTA flag and jumps to application.
  /// Bootloader responds with 0xB0 (§3.2).
  Future<ForceJumpResult> sendForceJump({
    required String txCanId,
    required int channel,
    required bool isExtended,
  }) async {
    final completer = Completer<ForceJumpResult>();

    final savedRx = _serialService.onCanFrameRx;
    final savedData = _serialService.onDataReceived;

    if (!_serialService.isCanMode) {
      _serialService.onDataReceived = (Uint8List data) {
        if (completer.isCompleted || data.isEmpty) return;
        final firstByte = data[0];
        if (firstByte == 0xB0) {
          final dataHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
          completer.complete(ForceJumpResult(
            success: true,
            message: 'Force jump accepted — board jumping to application',
            rawHex: dataHex,
          ));
        }
      };
    } else {
      _serialService.onCanFrameRx = (Map<String, dynamic> frame) {
        if (completer.isCompleted) return;
        final dataHex = frame['dataHex'] as String? ?? '';
        final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
        if (hexParts.isEmpty) return;

        final firstByte = hexParts[0].toUpperCase();
        if (firstByte == 'B0') {
          completer.complete(ForceJumpResult(
            success: true,
            message: 'Force jump accepted — board jumping to application',
            rawHex: hexParts.join(' '),
          ));
        }
      };
    }

    // Send force jump command: 0x41 0x80 0x80 (§2.5)
    _send8ByteFrame(
      [0x41, 0x80, 0x80],
      canId: txCanId,
      channel: channel,
      isExtended: isExtended,
    );

    // Wait for 0xB0 response with timeout
    try {
      final result = await completer.future.timeout(const Duration(seconds: 5));
      _serialService.onCanFrameRx = savedRx;
      _serialService.onDataReceived = savedData;
      return result;
    } on TimeoutException {
      _serialService.onCanFrameRx = savedRx;
      _serialService.onDataReceived = savedData;
      return ForceJumpResult(
        success: false,
        message: 'No response to force jump command (timeout 5s)',
        rawHex: '',
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  INTERNAL MODELS
// ═══════════════════════════════════════════════════════════════

class ForceJumpResult {
  final bool success;
  final String message;
  final String rawHex;
  ForceJumpResult({required this.success, required this.message, required this.rawHex});
}

class _BoardAck {
  final int canId;
  final int deviceId;
  final String boardTypeCode;
  final bool success;
  final String rawHex;
  final String errorDetail;
  _BoardAck({
    required this.canId,
    required this.deviceId,
    required this.boardTypeCode,
    required this.success,
    required this.rawHex,
    this.errorDetail = '',
  });
  String get canIdHex => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
}

class _CompletionAck {
  final int canId;
  final int boardNo;
  final String boardTypeCode;
  final bool success;
  final String newVersion;
  final String rawHex;
  final String errorDetail;
  _CompletionAck({
    required this.canId,
    required this.boardNo,
    required this.boardTypeCode,
    required this.success,
    required this.newVersion,
    required this.rawHex,
    this.errorDetail = '',
  });
  String get canIdHex => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
}
