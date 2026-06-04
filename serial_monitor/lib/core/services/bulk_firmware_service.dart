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
  digital(0x08, 'Digital', 'DC');

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

  // ── Send CAN frames ──

  bool _send8ByteFrame(
    List<int> payload, {
    required String canId,
    required int channel,
    required bool isExtended,
  }) {
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
    _serialService.onCanFrameRx = (Map<String, dynamic> frame) {
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
      // Byte 0-1: Board Type (2 ASCII characters, e.g. 'AV' or 'AC')
      // Byte 2-3: Board Number (MSB, LSB)
      // Byte 4: CAN ID
      // Byte 5-9: Firmware Version (5 Bytes ASCII)
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

            // Byte 4: CAN ID
            final canIdVal = int.tryParse(hexParts[4], radix: 16) ?? 0;

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
            // if targetBoardType == BoardType.all.value (0), we accept all.
            // otherwise, only if boardType.value == targetBoardType.
            if (targetBoardType == BoardType.all.value || boardType.value == targetBoardType) {
              // Avoid duplicates by combination of boardNo (deviceId) and boardTypeValue
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
          }
        }
      }
    };

    // Send scan request: byte[0] = 0x01, byte[1] = 0x01 (§2.1)
    _send8ByteFrame(
      [0x01, 0x01, targetBoardType],
      canId: txCanId,
      channel: channel,
      isExtended: isExtended,
    );

    // Wait for responses
    Timer(_scanTimeout, () {
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;

    // Restore original callback
    _serialService.onCanFrameRx = savedRx;

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
      final headerAcks = await _waitForAcks(
        expectedCanIds: selectedCanIds,
        timeoutSeconds: 15,
      );
      
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
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingHeaderAck,
          totalFrames: file.frameCount,
          message: ack.success
              ? 'Node #${ack.deviceId} (${ack.boardTypeCode}, CAN ID: $canIdHex) ACK \u2713 (RX: ${ack.rawHex})'
              : 'Node #${ack.deviceId} (${ack.boardTypeCode}, CAN ID: $canIdHex) NACK \u2717: ${ack.errorDetail} (RX: ${ack.rawHex})',
          boardCanId: ack.canId,
          boardSuccess: ack.success,
        );
      }

      final allHeaderAcks = headerAcks;

      if (allHeaderAcks.isEmpty) {
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
    // New broadcast header format (9 bytes):
    // Byte 0: Mode (0x02)
    // Byte 1-2: Board Type (2 ASCII characters, e.g. 'AV' or 'AC')
    // Byte 3-4: BIN Size (LE)
    // Byte 5-6: Total Frames (LE)
    // Byte 7-8: Total File CRC-16 (LE)
    final payload = List<int>.filled(9, 0x00);
    payload[0] = 0x02; // Mode: Header
    
    final boardType = BoardType.fromValue(boardTypeValue) ?? BoardType.all;
    final code = boardType.code;
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

    _serialService.onCanFrameRx = (Map<String, dynamic> frame) {
      final dataHex = frame['dataHex'] as String? ?? '';
      final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
      if (hexParts.isEmpty) return;

      final firstByte = hexParts[0].toUpperCase();
      // ACK: 0x79, Errors: 0xE1–0xE7
      if (firstByte == '79' || firstByte == 'E1' || firstByte == 'E2' || firstByte == 'E3' || firstByte == 'E4' || firstByte == 'E6' || firstByte == 'E7') {
        final canIdStr = frame['canId']?.toString() ?? '';
        final canIdNum = int.tryParse(
          canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
          radix: 16,
        ) ?? 0;

        // Byte 1-2: Board Type, Byte 3-4: Board Number (MSB, LSB), Byte 5: CAN ID
        String boardTypeCode = 'UNKNOWN';
        int deviceId = 0;
        if (hexParts.length >= 6) {
          final char1 = int.tryParse(hexParts[1], radix: 16) ?? 0;
          final char2 = int.tryParse(hexParts[2], radix: 16) ?? 0;
          if (char1 >= 32 && char1 <= 126 && char2 >= 32 && char2 <= 126) {
            boardTypeCode = String.fromCharCodes([char1, char2]);
          }
          final boardNoMsb = int.tryParse(hexParts[3], radix: 16) ?? 0;
          final boardNoLsb = int.tryParse(hexParts[4], radix: 16) ?? 0;
          deviceId = (boardNoMsb << 8) | boardNoLsb;
        }

        // Build error description for NACK codes
        final errorCode = int.tryParse(firstByte, radix: 16) ?? 0;
        final errDesc = firstByte != '79' ? errorDescription(errorCode) : '';

        // Ensure we don't add duplicates if a board spams ACKs
        if (deviceId > 0 && !acks.any((a) => a.canId == canIdNum)) {
          acks.add(_BoardAck(
            canId: canIdNum,
            deviceId: deviceId,
            boardTypeCode: boardTypeCode,
            success: firstByte == '79',
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
    };

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

    void complete() {
      if (!completer.isCompleted) {
        completer.complete();
      }
      maxTimeoutTimer?.cancel();
      graceTimer?.cancel();
      cancelTimer?.cancel();
    }

    _serialService.onCanFrameRx = (Map<String, dynamic> frame) {
      final dataHex = frame['dataHex'] as String? ?? '';
      final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
      if (hexParts.isEmpty) return;

      final firstByte = hexParts[0].toUpperCase();
      // ACK: 0x79, All NACK codes: 0xE1–0xE7
      if (firstByte == '79' || firstByte == 'E1' || firstByte == 'E2' || firstByte == 'E3' || firstByte == 'E4' || firstByte == 'E6' || firstByte == 'E7') {
        final canIdStr = frame['canId']?.toString() ?? '';
        final canIdNum = int.tryParse(
          canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
          radix: 16,
        ) ?? 0;

        // Only parse if it's one of our expected CAN IDs
        if (expectedCanIds.contains(canIdNum)) {
          // Byte 1-2: Board Type, Byte 3-4: Board Number, Byte 5: CAN ID
          String boardTypeCode = 'UNKNOWN';
          int boardNo = 0;
          if (hexParts.length >= 5) {
            final char1 = int.tryParse(hexParts[1], radix: 16) ?? 0;
            final char2 = int.tryParse(hexParts[2], radix: 16) ?? 0;
            if (char1 >= 32 && char1 <= 126 && char2 >= 32 && char2 <= 126) {
              boardTypeCode = String.fromCharCodes([char1, char2]);
            }
            final boardNoMsb = int.tryParse(hexParts[3], radix: 16) ?? 0;
            final boardNoLsb = int.tryParse(hexParts[4], radix: 16) ?? 0;
            boardNo = (boardNoMsb << 8) | boardNoLsb;
          }

          // Parse version if success: starts at byte 8 in new ACK format
          String newVersion = '';
          if (firstByte == '79') {
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
          final errDesc = firstByte != '79' ? errorDescription(errorCode) : '';

          if (!acks.any((a) => a.canId == canIdNum)) {
            acks.add(_CompletionAck(
              canId: canIdNum,
              boardNo: boardNo,
              boardTypeCode: boardTypeCode,
              success: firstByte == '79',
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
    };

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
      return result;
    } on TimeoutException {
      _serialService.onCanFrameRx = savedRx;
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
