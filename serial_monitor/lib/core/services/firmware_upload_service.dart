import 'dart:async';
import 'dart:typed_data';
import 'serial_port_service.dart';

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
  waitingFrameAck,
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

const int _chunkSize = 60;
const Duration _ackTimeout = Duration(seconds: 30);

// ═══════════════════════════════════════════════════════════════
//  FIRMWARE UPLOAD SERVICE
// ═══════════════════════════════════════════════════════════════

/// Handles firmware binary upload over CAN bus.
///
/// Protocol:
///   1. Send HEADER [4B size][2B count][2B CRC] as CAN frame payload
///   2. Wait for "OK" CAN frame response (30s)
///   3. For each chunk: [2B serial][60B data][2B CRC] split into CAN frames
///   4. Wait for "OK" after each chunk
///
/// Data is sent via sendCanFrame() so the USB-CAN adapter properly
/// transmits it on the CAN bus.
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

  // ── Build frames ──

  Uint8List buildHeaderFrame(FirmwareFile file, bool includeCrc) {
    final header = Uint8List(includeCrc ? 8 : 6);
    
    // Explicit "00 00" Header ID
    header[0] = 0x00;
    header[1] = 0x00;
    
    // 16-bit File Size (Little-Endian)
    header[2] = file.fileSize & 0xFF;
    header[3] = (file.fileSize >> 8) & 0xFF;
    
    // 16-bit Frame Count (Little-Endian)
    header[4] = file.frameCount & 0xFF;
    header[5] = (file.frameCount >> 8) & 0xFF;
    
    if (includeCrc) {
      // 16-bit CRC (Little-Endian)
      header[6] = file.fileCrc & 0xFF;
      header[7] = (file.fileCrc >> 8) & 0xFF;
    }
    
    return header;
  }

  Uint8List buildDataFrame(FirmwareFile file, int frameIndex, bool includeCrc) {
    final frameLength = includeCrc ? 64 : 62;
    final frame = Uint8List(frameLength);
    // Little-Endian
    frame[0] = frameIndex & 0xFF;
    frame[1] = (frameIndex >> 8) & 0xFF;

    final dataStart = frameIndex * _chunkSize;
    final dataEnd = (dataStart + _chunkSize).clamp(0, file.fileSize);
    final actualLen = dataEnd - dataStart;
    for (int i = 0; i < actualLen; i++) {
      frame[2 + i] = file.bytes[dataStart + i];
    }

    if (includeCrc) {
      final crc = crc16Modbus(frame.sublist(0, 62).toList());
      // Little-Endian
      frame[62] = crc & 0xFF;
      frame[63] = (crc >> 8) & 0xFF;
    }
    return frame;
  }

  // ── Send via CAN frames ──

  /// Send raw bytes as one or more CAN frames.
  /// For Classic CAN (8B max), splits into multiple 8-byte CAN frames.
  /// For CAN FD (64B max), sends in larger chunks.
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

  /// Start firmware upload via CAN frames.
  Stream<UploadProgress> startUpload(
    FirmwareFile file, {
    required String canId,
    required int channel,
    required bool isExtended,
    required bool isFD,
    required bool sendCrcInHeader,
    required bool sendCrcInData,
    required int interFrameDelayMs,
  }) async* {
    _cancelled = false;
    _suppressConsoleLogging();

    try {
      // ── STEP 1: Send Header ──
      yield UploadProgress(
        status: UploadStatus.sendingHeader,
        totalFrames: file.frameCount,
        message: 'Sending header (${file.fileSize} bytes, ${file.frameCount} frames)...',
      );

      final headerBytes = buildHeaderFrame(file, sendCrcInHeader);
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
      if (headerResult == _AckResult.error) {
        yield UploadProgress(status: UploadStatus.error, totalFrames: file.frameCount, message: 'Device returned ERROR (0xE1) for header.');
        return;
      }
      if (headerResult == _AckResult.timeout) {
        yield UploadProgress(status: UploadStatus.error, totalFrames: file.frameCount, message: 'No ACK for header (timeout ${_ackTimeout.inSeconds}s).');
        return;
      }

      yield UploadProgress(status: UploadStatus.sendingFrame, totalFrames: file.frameCount, message: 'Header acknowledged ✓');

      if (interFrameDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: interFrameDelayMs));
      }

      // ── STEP 2: Send Data Frames ──
      for (int i = 0; i < file.frameCount; i++) {
        if (_cancelled) {
          yield UploadProgress(status: UploadStatus.cancelled, currentFrame: i, totalFrames: file.frameCount, message: 'Upload cancelled at frame $i.');
          return;
        }

        final frameBytes = buildDataFrame(file, i, sendCrcInData);
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

      yield UploadProgress(
        status: UploadStatus.complete,
        currentFrame: file.frameCount,
        totalFrames: file.frameCount,
        message: 'Firmware upload complete! (${file.frameCount} frames sent)',
      );
    } finally {
      _restoreConsoleLogging();
    }
  }

  // ── Wait for ACK / ERROR ──

  Future<_AckResult> _waitForAck() async {
    final completer = Completer<_AckResult>();

    // Intercept CAN RX — don't forward to main console
    _serialService.onCanFrameRx = (Map<String, dynamic> frame) {
      if (!completer.isCompleted) {
        final dataHex = frame['dataHex'] as String? ?? '';
        if (dataHex.startsWith('79')) {
          completer.complete(_AckResult.ok);
        } else if (dataHex.startsWith('E1')) {
          completer.complete(_AckResult.error);
        }
      }
    };

    _cancelCheckTimer?.cancel();
    _cancelCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_cancelled && !completer.isCompleted) {
        completer.complete(_AckResult.timeout);
        timer.cancel();
      }
    });

    try {
      return await completer.future.timeout(_ackTimeout);
    } on TimeoutException {
      return _AckResult.timeout;
    } finally {
      _cancelCheckTimer?.cancel();
      _cancelCheckTimer = null;
    }
  }

  String _bytesToHexDisplay(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
  }
}

enum _AckResult { ok, error, timeout }
