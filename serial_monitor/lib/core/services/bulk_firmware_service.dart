import 'dart:async';
import 'dart:typed_data';
import 'serial_port_service.dart';
import 'firmware_upload_service.dart'; // crc16Modbus

// ═══════════════════════════════════════════════════════════════
//  BOARD TYPES
// ═══════════════════════════════════════════════════════════════

enum BoardType {
  all(0x00, 'All Boards'),
  acVoltage(0x01, 'AC Voltage'),
  acCurrent(0x02, 'AC Current'),
  dcHighVoltage(0x03, 'DC High Voltage'),
  dcLowVoltage(0x04, 'DC Low Voltage'),
  dcHighCurrent(0x05, 'DC High Current'),
  dcLowCurrent(0x06, 'DC Low Current'),
  accelerometer(0x07, 'Accelerometer'),
  digital(0x08, 'Digital');

  final int value;
  final String label;
  const BoardType(this.value, this.label);

  static BoardType? fromValue(int val) {
    for (final bt in BoardType.values) {
      if (bt.value == val) return bt;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════
//  DISCOVERED BOARD
// ═══════════════════════════════════════════════════════════════

enum BoardOtaStatus { discovered, uploading, success, error }

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
  //  SCAN MODE (0x01)
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

      // New C firmware response format:
      // tx_buffer[0] = Board Type (0x01–0x08)
      // tx_buffer[1] = DEVICE_CAN_ID (DIP switch value, 1–80)
      // tx_buffer[2+] = BOOT_VERSION string (ASCII, null-terminated, e.g. "2.0.0")
      if (hexParts.length > 2) {
        final canIdStr = frame['canId']?.toString() ?? '';
        final canIdNum = int.tryParse(
          canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
          radix: 16,
        ) ?? 0;

        // Byte 0: Board Type
        final boardType = int.tryParse(hexParts[0], radix: 16) ?? 0;

        // Byte 1: Device CAN ID (DIP switch value)
        final deviceId = int.tryParse(hexParts[1], radix: 16) ?? 0;

        // Byte 2+: Version string (ASCII, null-terminated)
        String version = '';
        for (int i = 2; i < hexParts.length; i++) {
          final byte = int.tryParse(hexParts[i], radix: 16) ?? 0;
          if (byte == 0) break;
          if (byte >= 32 && byte <= 126) {
            version += String.fromCharCode(byte);
          } else {
            break;
          }
        }

        // Validate: boardType must be 1–8 and version should contain '.'
        if (boardType >= 1 && boardType <= 8 && version.contains('.')) {
          // Avoid duplicates by deviceId
          if (!boards.any((b) => b.deviceId == deviceId)) {
            boards.add(DiscoveredBoard(
              canId: canIdNum,
              deviceId: deviceId,
              boardTypeValue: boardType,
              version: version.isEmpty ? 'Unknown' : version,
              rawHex: hexParts.join(' '),
            ));
          }
        }
      }
    };

    // Send scan request: byte[0] = 0x01, byte[1] = 0x01, byte[2] = targetBoardType, rest = 0x00
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

      final headerSent = _send8ByteFrame(
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
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingHeaderAck,
          totalFrames: file.frameCount,
          message: ack.success
              ? 'Node #${ack.deviceId} ACK ✓ (RX: ${ack.rawHex})'
              : 'Node #${ack.deviceId} NACK ✗ (RX: ${ack.rawHex})',
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
      completionPayload[0] = 0x46; // Completion mode
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

      yield BulkUploadProgress(
        status: BulkUploadStatus.sendingCompletion,
        currentFrame: file.frameCount,
        totalFrames: file.frameCount,
        message: 'Sending Completion Signal: $completionHex',
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
        message: 'Completion Signal sent. Waiting for boards to ACK and report new versions...',
      );

      final completionAcks = await _waitForCompletionAcks(
        expectedCanIds: selectedCanIds,
        maxTimeoutSeconds: 30,
        graceTimeoutSeconds: 5,
      );

      if (_cancelled) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.cancelled,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: 'Upload cancelled during completion phase.',
        );
        return;
      }

      // Report ACK results back to the UI
      for (final ack in completionAcks) {
        yield BulkUploadProgress(
          status: BulkUploadStatus.waitingCompletionAck,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: ack.success
              ? 'Node #${ack.canId} ACK ✓ (New Version: ${ack.newVersion})'
              : 'Node #${ack.canId} NACK ✗ (RX: ${ack.rawHex})',
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

  List<int> _buildHeaderPayload(BulkFirmwareFile file, int boardType) {
    // New broadcast header format matching C firmware:
    // Byte 0: Mode (0x02)
    // Byte 1: Target ID (Now sending Board Type instead of 0xFF)
    // Byte 2-3: BIN Size (LE)
    // Byte 4-5: Total Frames (LE)
    // Byte 6-7: Total File CRC-16 (LE)
    final payload = List<int>.filled(8, 0x00);
    payload[0] = 0x02;                          // Mode: Header
    payload[1] = boardType & 0xFF;               // Broadcast Target is now Board Type
    payload[2] = file.fileSize & 0xFF;           // File Size LE low
    payload[3] = (file.fileSize >> 8) & 0xFF;    // File Size LE high
    payload[4] = file.frameCount & 0xFF;         // Frame Count LE low
    payload[5] = (file.frameCount >> 8) & 0xFF;  // Frame Count LE high
    
    // Store Total File CRC Little Endian
    payload[6] = file.fileCrc & 0xFF;            // CRC LSB
    payload[7] = (file.fileCrc >> 8) & 0xFF;     // CRC MSB
    
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
      // ACK: 0x79, Errors: 0xE1 (wrong target), 0xE2 (size error), 0xE3 (frame error)
      if (firstByte == '79' || firstByte == 'E1' || firstByte == 'E2' || firstByte == 'E3' || firstByte == 'E4') {
        final canIdStr = frame['canId']?.toString() ?? '';
        final canIdNum = int.tryParse(
          canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
          radix: 16,
        ) ?? 0;

        // Byte 1: Board Type, Byte 2: Device CAN ID
        final deviceId = hexParts.length > 2 ? (int.tryParse(hexParts[2], radix: 16) ?? 0) : 0;

        // Ensure we don't add duplicates if a board spams ACKs
        if (!acks.any((a) => a.deviceId == deviceId)) {
          acks.add(_BoardAck(
            canId: canIdNum,
            deviceId: deviceId,
            success: firstByte == '79',
            rawHex: hexParts.join(' '),
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
      if (firstByte == '79' || firstByte == 'E1') {
        final canIdStr = frame['canId']?.toString() ?? '';
        final canIdNum = int.tryParse(
          canIdStr.replaceAll('0x', '').replaceAll(' ', ''),
          radix: 16,
        ) ?? 0;

        // Only parse if it's one of our expected CAN IDs
        if (expectedCanIds.contains(canIdNum)) {
          // Parse version if success
          String newVersion = '';
          if (firstByte == '79') {
            for (int i = 3; i < hexParts.length; i++) {
              final byte = int.tryParse(hexParts[i], radix: 16) ?? 0;
              if (byte == 0) break;
              if (byte >= 32 && byte <= 126) {
                newVersion += String.fromCharCode(byte);
              } else {
                break;
              }
            }
          }

          if (!acks.any((a) => a.canId == canIdNum)) {
            acks.add(_CompletionAck(
              canId: canIdNum,
              success: firstByte == '79',
              newVersion: newVersion.isEmpty ? 'Unknown' : newVersion,
              rawHex: hexParts.join(' '),
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
}

// ── Internal ACK models ──

class _BoardAck {
  final int canId;
  final int deviceId;
  final bool success;
  final String rawHex;
  _BoardAck({required this.canId, required this.deviceId, required this.success, required this.rawHex});
  String get canIdHex => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
}

class _CompletionAck {
  final int canId;
  final bool success;
  final String newVersion;
  final String rawHex;
  _CompletionAck({
    required this.canId,
    required this.success,
    required this.newVersion,
    required this.rawHex,
  });
  String get canIdHex => '0x${canId.toRadixString(16).toUpperCase().padLeft(3, '0')}';
}
