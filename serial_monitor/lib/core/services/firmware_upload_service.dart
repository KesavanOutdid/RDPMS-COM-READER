import 'dart:async';
import 'dart:typed_data';
import 'serial_port_service.dart';
import 'bulk_firmware_service.dart'; // BoardType, errorDescription

// ═══════════════════════════════════════════════════════════════
//  CRC-16/MODBUS
// ═══════════════════════════════════════════════════════════════

int crc16Modbus(List<int> data) {
  int crc = 0xFFFF;
  for (int byte in data) {
    crc ^= byte & 0xFF;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x0001) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc = crc >> 1;
      }
    }
  }
  return crc & 0xFFFF;
}

// ═══════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════

class FirmwareFile {
  final String fileName;
  final Uint8List bytes;
  final int fileSize;
  final int frameCount;
  final int fileCrc;

  FirmwareFile({
    required this.fileName,
    required this.bytes,
    required this.fileSize,
    required this.frameCount,
    required this.fileCrc,
  });
}

enum UploadStatus {
  idle,
  sendingHeader,
  waitingHeaderAck,
  sendingFrame,
  sendingCompletion,
  waitingCompletionAck,
  complete,
  error,
  cancelled,
}

class UploadProgress {
  final UploadStatus status;
  final int currentFrame;
  final int totalFrames;
  final String message;
  final DateTime timestamp;

  UploadProgress({
    required this.status,
    this.currentFrame = 0,
    this.totalFrames = 0,
    this.message = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  double get percent {
    if (totalFrames == 0) return 0;
    if (status == UploadStatus.complete) return 1.0;
    return currentFrame / (totalFrames + 1);
  }
}

// ═══════════════════════════════════════════════════════════════
//  CONSTANTS
// ═══════════════════════════════════════════════════════════════

const int _chunkSize = 60;       // Bytes 2–61 in a 64-byte data frame
const int _frameSize = 64;       // CAN FD frame size
const Duration _ackTimeout = Duration(seconds: 30);

// ═══════════════════════════════════════════════════════════════
//  FIRMWARE UPLOAD SERVICE
// ═══════════════════════════════════════════════════════════════

/// Handles single-device firmware binary upload over CAN FD bus.
///
/// Protocol (STM32H503 CAN OTA Bootloader Command Reference v1.0):
///   1. Send OTA Header (0x02) — §2.2
///   2. Wait for ACK (0x79) — §3.2
///   3. Send Binary Data Frames (0x42+0x49) × N — §2.3
///   4. Send Final ACK / End-of-Transmission (0x46) — §2.4
///   5. Wait for OTA Complete ACK (0x79) — §3.2
class FirmwareUploadService {
  final SerialPortService _serialService;
  bool _cancelled = false;
  Timer? _cancelCheckTimer;

  FirmwareUploadService(this._serialService);

  /// Prepare a firmware file for upload.
  FirmwareFile prepareFile(String fileName, Uint8List fileBytes) {
    final fileSize = fileBytes.length;
    final frameCount = (fileSize + _chunkSize - 1) ~/ _chunkSize;
    final fileCrc = crc16Modbus(fileBytes.toList());
    return FirmwareFile(
      fileName: fileName,
      bytes: fileBytes,
      fileSize: fileSize,
      frameCount: frameCount,
      fileCrc: fileCrc,
    );
  }

  // ── Build frames (matching spec §2.2, §2.3, §2.4) ──

  /// Build OTA Header Frame (§2.2)
  /// Byte[0] = 0x02, Byte[1] = board_type,
  /// Bytes[2–3] = bin_size (LE), Bytes[4–5] = total_frames (LE),
  /// Bytes[6–7] = whole_file_crc (LE)
  Uint8List buildHeaderFrame(FirmwareFile file, int boardType) {
    final header = Uint8List(8);
    header[0] = 0x02;                         // Command identifier (§2.2)
    header[1] = boardType & 0xFF;             // Target board type
    header[2] = file.fileSize & 0xFF;         // Bin size LSB
    header[3] = (file.fileSize >> 8) & 0xFF;  // Bin size MSB
    header[4] = file.frameCount & 0xFF;       // Total frames LSB
    header[5] = (file.frameCount >> 8) & 0xFF;// Total frames MSB
    header[6] = file.fileCrc & 0xFF;          // Whole-file CRC LSB
    header[7] = (file.fileCrc >> 8) & 0xFF;   // Whole-file CRC MSB
    return header;
  }

  /// Build Binary Data Frame (§2.3)
  /// Byte[0] = 0x42, Byte[1] = 0x49,
  /// Bytes[2–61] = 60 bytes firmware data,
  /// Bytes[62–63] = CRC16-Modbus of bytes[0–61] (LE)
  Uint8List buildDataFrame(FirmwareFile file, int frameIndex) {
    final frame = Uint8List(_frameSize);
    frame[0] = 0x42;  // Frame identifier byte 1 (§2.3)
    frame[1] = 0x49;  // Frame identifier byte 2 (§2.3)

    // Binary payload: bytes 2–61
    final dataStart = frameIndex * _chunkSize;
    final dataEnd = (dataStart + _chunkSize).clamp(0, file.fileSize);
    final actualLen = dataEnd - dataStart;
    for (int i = 0; i < actualLen; i++) {
      frame[2 + i] = file.bytes[dataStart + i];
    }

    // CRC16-Modbus of bytes[0]–[61] (§2.3)
    final crc = crc16Modbus(frame.sublist(0, 62).toList());
    frame[62] = crc & 0xFF;          // CRC LSB
    frame[63] = (crc >> 8) & 0xFF;   // CRC MSB

    return frame;
  }

  /// Build Final ACK / End-of-Transmission frame (§2.4)
  /// Byte[0] = 0x4F, Byte[1] = 0x4B
  Uint8List buildCompletionFrame() {
    final frame = Uint8List(_frameSize);
    frame[0] = 0x4F;  // 'O'
    frame[1] = 0x4B;  // 'K'
    return frame;
  }

  // ── Send via CAN frames ──

  bool _sendViaCan(
    List<int> payload, {
    required String canId,
    required int channel,
    required bool isExtended,
    required bool isFD,
  }) {
    final maxPayload = isFD ? 64 : 8;

    for (int offset = 0; offset < payload.length; offset += maxPayload) {
      final end = (offset + maxPayload).clamp(0, payload.length);
      final chunk = payload.sublist(offset, end);

      final success = _serialService.sendCanFrame(
        canId: canId,
        data: chunk,
        channel: channel,
        isExtended: isExtended,
        isFD: isFD,
      );
      if (!success) return false;
    }
    return true;
  }

  // ── Upload logic ──

  void cancel() {
    _cancelled = true;
  }

  // Saved callbacks — suppressed during upload so firmware
  // TX/RX doesn't flood the main console.
  Function(Map<String, dynamic>)? _savedRxCallback;
  Function(Map<String, dynamic>)? _savedTxCallback;

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

  /// Start firmware upload via CAN FD frames (full spec protocol).
  Stream<UploadProgress> startUpload(
    FirmwareFile file, {
    required String canId,
    required int channel,
    required bool isExtended,
    required bool isFD,
    required int boardType,
    required int interFrameDelayMs,
  }) async* {
    _cancelled = false;
    _suppressConsoleLogging();

    try {
      // ── STEP 1: Send OTA Header (§2.2) ──
      yield UploadProgress(
        status: UploadStatus.sendingHeader,
        totalFrames: file.frameCount,
        message: 'Sending OTA header (${file.fileSize} bytes, ${file.frameCount} frames, board type: 0x${boardType.toRadixString(16).toUpperCase()})...',
      );

      final headerBytes = buildHeaderFrame(file, boardType);
      final headerHex = _bytesToHexDisplay(headerBytes);
      final headerSent = _sendViaCan(
        headerBytes.toList(),
        canId: canId, channel: channel, isExtended: isExtended, isFD: isFD,
      );

      if (!headerSent) {
        yield UploadProgress(status: UploadStatus.error, totalFrames: file.frameCount, message: 'Failed to send header — port not available.');
        return;
      }

      yield UploadProgress(
        status: UploadStatus.waitingHeaderAck,
        totalFrames: file.frameCount,
        message: 'Header sent ($headerHex). Waiting for ACK...',
      );

      final headerResult = await _waitForAck();
      if (_cancelled) {
        yield UploadProgress(status: UploadStatus.cancelled, totalFrames: file.frameCount, message: 'Upload cancelled by user.');
        return;
      }
      if (headerResult.result == _AckCode.error) {
        yield UploadProgress(status: UploadStatus.error, totalFrames: file.frameCount, message: 'Device rejected header: ${headerResult.errorDetail} (0x${headerResult.rawByte})');
        return;
      }
      if (headerResult.result == _AckCode.timeout) {
        yield UploadProgress(status: UploadStatus.error, totalFrames: file.frameCount, message: 'No ACK for header (timeout ${_ackTimeout.inSeconds}s).');
        return;
      }

      yield UploadProgress(status: UploadStatus.sendingFrame, totalFrames: file.frameCount, message: 'Header acknowledged ✓ — flash erased, ready for data');

      if (interFrameDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: interFrameDelayMs));
      }

      // ── STEP 2: Send Binary Data Frames (§2.3) ──
      for (int i = 0; i < file.frameCount; i++) {
        if (_cancelled) {
          yield UploadProgress(status: UploadStatus.cancelled, currentFrame: i, totalFrames: file.frameCount, message: 'Upload cancelled at frame $i.');
          return;
        }

        final frameBytes = buildDataFrame(file, i);
        final frameHex = _bytesToHexDisplay(frameBytes);
        yield UploadProgress(
          status: UploadStatus.sendingFrame,
          currentFrame: i + 1,
          totalFrames: file.frameCount,
          message: 'Sending frame ${i + 1}/${file.frameCount} ($frameHex)...',
        );

        final frameSent = _sendViaCan(
          frameBytes.toList(),
          canId: canId, channel: channel, isExtended: isExtended, isFD: isFD,
        );

        if (!frameSent) {
          yield UploadProgress(status: UploadStatus.error, currentFrame: i + 1, totalFrames: file.frameCount, message: 'Failed to send frame ${i + 1}.');
          return;
        }

        if (interFrameDelayMs > 0) {
          await Future.delayed(Duration(milliseconds: interFrameDelayMs));
        } else {
          await Future.delayed(const Duration(milliseconds: 1)); // small yield to keep UI responsive
        }
      }

      // ── STEP 3: Send Final ACK / End-of-Transmission (§2.4) ──
      _AckResponse? completionResult;
      
      for (int attempt = 1; attempt <= 1; attempt++) {
        yield UploadProgress(
          status: UploadStatus.sendingCompletion,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: attempt == 1
              ? 'All frames sent. Sending completion signal (0x4F 0x4B)...'
              : 'Retry $attempt/3: Resending completion signal...',
        );

        final completionBytes = buildCompletionFrame();
        final completionSent = _sendViaCan(
          completionBytes.toList(),
          canId: canId, channel: channel, isExtended: isExtended, isFD: isFD,
        );

        if (!completionSent) {
          yield UploadProgress(status: UploadStatus.error, currentFrame: file.frameCount, totalFrames: file.frameCount, message: 'Failed to send completion signal.');
          return;
        }

        yield UploadProgress(
          status: UploadStatus.waitingCompletionAck,
          currentFrame: file.frameCount,
          totalFrames: file.frameCount,
          message: attempt == 1 
            ? 'Completion signal sent. Waiting for final validation ACK...'
            : 'Retry $attempt/3: Waiting for validation ACK...',
        );

        // Wait up to 5 seconds for the response
        completionResult = await _waitForAck(timeoutOverride: const Duration(seconds: 5));
        
        if (_cancelled) {
          yield UploadProgress(status: UploadStatus.cancelled, currentFrame: file.frameCount, totalFrames: file.frameCount, message: 'Upload cancelled during validation.');
          return;
        }

        if (completionResult.result == _AckCode.ok) {
          break; // We got a successful ACK, stop retrying
        }
        
        // If timeout, the loop will continue and retry
      }

      if (completionResult == null || completionResult.result == _AckCode.timeout) {
        yield UploadProgress(status: UploadStatus.error, currentFrame: file.frameCount, totalFrames: file.frameCount, message: 'No ACK for completion (timeout after 3 attempts).');
        return;
      }
      
      if (completionResult.result == _AckCode.error) {
        yield UploadProgress(status: UploadStatus.error, currentFrame: file.frameCount, totalFrames: file.frameCount, message: 'Validation failed: ${completionResult.errorDetail} (0x${completionResult.rawByte})');
        return;
      }

      yield UploadProgress(
        status: UploadStatus.complete,
        currentFrame: file.frameCount,
        totalFrames: file.frameCount,
        message: 'Firmware upload complete! (${file.frameCount} frames sent, CRC verified ✓)',
      );
    } finally {
      _restoreConsoleLogging();
    }
  }

  // ── Wait for ACK / NACK (§3.2, §3.3) ──

  Future<_AckResponse> _waitForAck({Duration? timeoutOverride}) async {
    final completer = Completer<_AckResponse>();

    // Intercept CAN RX
    _serialService.onCanFrameRx = (Map<String, dynamic> frame) {
      if (!completer.isCompleted) {
        final dataHex = frame['dataHex'] as String? ?? '';
        final hexParts = dataHex.split(' ').where((s) => s.isNotEmpty).toList();
        if (hexParts.isEmpty) return;

        final firstByte = hexParts[0].toUpperCase();
        final secondByte = hexParts.length >= 2 ? hexParts[1].toUpperCase() : '';

        // ACK: 0x79 or 0x4F4B (OK) (§3.2)
        if (firstByte == '79' || (firstByte == '4F' && secondByte == '4B')) {
          // Extract version string if present (completion ACK)
          String versionStr = '';
          if (hexParts.length > 8) {
            for (int i = 8; i < hexParts.length; i++) {
              final byte = int.tryParse(hexParts[i], radix: 16) ?? 0;
              if (byte == 0) break;
              if (byte >= 32 && byte <= 126) {
                versionStr += String.fromCharCode(byte);
              } else {
                break;
              }
            }
            if (versionStr.endsWith('.')) {
              versionStr += '0';
            }
          }
          completer.complete(_AckResponse(
            result: _AckCode.ok,
            rawByte: firstByte,
            versionString: versionStr,
          ));
        }
        // NACK: 0xE1–0xE7
        else if (firstByte == 'E1' || firstByte == 'E2' || firstByte == 'E3' || firstByte == 'E4' || firstByte == 'E5' || firstByte == 'E6' || firstByte == 'E7') {
          final errCode = int.tryParse(firstByte, radix: 16) ?? 0;
          completer.complete(_AckResponse(
            result: _AckCode.error,
            rawByte: firstByte,
            errorDetail: errorDescription(errCode),
          ));
        }
      }
    };

    _cancelCheckTimer?.cancel();
    _cancelCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_cancelled && !completer.isCompleted) {
        completer.complete(_AckResponse(result: _AckCode.timeout, rawByte: ''));
        timer.cancel();
      }
    });

    try {
      return await completer.future.timeout(timeoutOverride ?? _ackTimeout);
    } on TimeoutException {
      return _AckResponse(result: _AckCode.timeout, rawByte: '');
    } finally {
      _cancelCheckTimer?.cancel();
      _cancelCheckTimer = null;
    }
  }

  String _bytesToHexDisplay(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
  }
}

// ═══════════════════════════════════════════════════════════════
//  INTERNAL MODELS
// ═══════════════════════════════════════════════════════════════

enum _AckCode { ok, error, timeout }

class _AckResponse {
  final _AckCode result;
  final String rawByte;
  final String errorDetail;
  final String versionString;

  _AckResponse({
    required this.result,
    required this.rawByte,
    this.errorDetail = '',
    this.versionString = '',
  });
}
