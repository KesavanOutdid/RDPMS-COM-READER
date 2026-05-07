import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart' as sp;
import '../config/can_config.dart';
import '../config/models.dart';
import 'frame_builder.dart';
import 'frame_parser.dart';

/// Fully offline CAN serial port service.
///
/// All frame parsing, frame building, heartbeat tracking, and USB I/O
/// happen natively in Dart — no backend server required.
class SerialPortService {
  // ── Native serial port state ──
  sp.SerialPort? _port;
  sp.SerialPortReader? _reader;
  StreamSubscription? _readerSubscription;

  bool _isConnected = false;
  String _connectedPort = '';
  List<String> _availablePorts = const [];

  // ── Local frame parser ──
  final CanFrameParser _frameParser = CanFrameParser();
  Completer<bool>? _connectAckCompleter;

  // ── Heartbeat tracking ──
  Timer? _heartbeatTimer;
  bool _heartbeatWaiting = false;
  int _heartbeatMissCount = 0;
  static const int _heartbeatMaxMiss = 3;

  // ── Port polling ──
  Timer? _pollingTimer;

  // ── Callback API (identical to the previous version) ──
  Function(Uint8List data)? onDataReceived;
  Function(Map<String, dynamic> frame)? onCanFrameRx;
  Function(Map<String, dynamic> frame)? onCanFrameTx;
  Function(String error)? onError;
  Function()? onDisconnected;
  Function(List<String> ports)? onPortsChanged;
  Function(String port)? onConnected;
  Function(String port, String status, DateTime? timestamp)? onHeartbeatAck;
  Function(String port, int missCount)? onHeartbeatMiss;
  Function(String port)? onHeartbeatTimeout;

  // ── Getters ──
  bool get isConnected => _isConnected;
  String get portName => _connectedPort;
  List<String> get availablePorts => List.unmodifiable(_availablePorts);

  static List<String> getAvailablePorts() => sp.SerialPort.availablePorts.toSet().toList();
  static String getPortDescription(String portName) {
    sp.SerialPort? port;
    try {
      port = sp.SerialPort(portName);
      return port.description ?? portName;
    } catch (_) {
      return portName;
    } finally {
      port?.dispose();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  INITIALIZE — just start port polling (no backend needed)
  // ═══════════════════════════════════════════════════════════════

  Future<void> initialize({String? serverUrl}) async {
    // Initialize ports immediately
    _availablePorts = sp.SerialPort.availablePorts.toSet().toList();
    onPortsChanged?.call(_availablePorts);
    _startLocalPortPolling();
  }

  void _startLocalPortPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final ports = sp.SerialPort.availablePorts.toSet().toList();

      // Detect physical unplug
      if (_isConnected && !ports.contains(_connectedPort)) {
        disconnect();
      }

      if (listEquals(_availablePorts, ports)) return;
      _availablePorts = ports;
      onPortsChanged?.call(_availablePorts);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  CONNECT — open USB, send A0, wait for A1 ACK, start heartbeat
  // ═══════════════════════════════════════════════════════════════

  Future<bool> connect(SerialPortConfig config, {CanConfig? canConfig}) async {
    try {
      await initialize();
      if (_isConnected) await disconnect();

      // 1. Open USB port natively
      _port = sp.SerialPort(config.portName);
      if (!_port!.openReadWrite()) {
        onError?.call('Failed to open port: ${sp.SerialPort.lastError}');
        return false;
      }

      final pConfig = _port!.config;
      pConfig.baudRate = config.baudRate;
      pConfig.bits = config.dataBits;
      pConfig.stopBits = config.stopBits;
      _port!.config = pConfig;

      _isConnected = true;
      _connectedPort = config.portName;
      _frameParser.clear();

      // 2. Start the native byte reader
      _reader = sp.SerialPortReader(_port!);
      _readerSubscription = _reader!.stream.listen(
        (Uint8List data) => _onRawBytesReceived(data),
        onError: (err) {
          final errorString = err.toString();
          if (errorString.contains('errno = 0') || errorString.contains('operation completed successfully')) {
            onError?.call('Connection to USB device lost.');
          } else {
            onError?.call('USB read error: $err');
          }
          disconnect();
        },
        onDone: () => disconnect(),
      );

      // 3. CAN handshake: send A0 CONNECT frame, wait for A1 ACK
      if (canConfig != null) {
        _connectAckCompleter = Completer<bool>();
        final connectFrame = canConfig.buildConnectFrame();
        _writeLocalBytes(Uint8List.fromList(connectFrame));

        try {
          final ackSuccess = await _connectAckCompleter!.future
              .timeout(const Duration(milliseconds: 3000));
          if (!ackSuccess) {
            onError?.call('Device rejected CAN configuration.');
            await disconnect();
            return false;
          }
        } catch (e) {
          onError?.call('No CAN hardware responded (Timeout).');
          await disconnect();
          return false;
        }

        // 4. Start heartbeat loop (device expects D0 00 every ~1s)
        _startHeartbeat();
      }

      onConnected?.call(config.portName);
      return true;
    } catch (error) {
      onError?.call('Connect error: $error');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  DISCONNECT
  // ═══════════════════════════════════════════════════════════════

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatWaiting = false;
    _heartbeatMissCount = 0;
    _readerSubscription?.cancel();
    _reader?.close();

    if (_port != null && _port!.isOpen) {
      try { _port!.close(); } catch (_) {}
    }
    _port?.dispose();
    _port = null;
    _frameParser.clear();

    final p = _connectedPort;
    _isConnected = false;
    _connectedPort = '';

    if (p.isNotEmpty) {
      onDisconnected?.call();
    }
  }

  void dispose() {
    disconnect();
    _pollingTimer?.cancel();
  }

  // ═══════════════════════════════════════════════════════════════
  //  RAW BYTE HANDLER — feed bytes into parser, dispatch frames
  // ═══════════════════════════════════════════════════════════════

  void _onRawBytesReceived(Uint8List data) {
    _frameParser.addBytes(data);
    final frames = _frameParser.parseAll();

    for (final frame in frames) {
      switch (frame.type) {
        case FrameType.connectResponse:
          _handleConnectAck(frame.data);
          break;
        case FrameType.rxFrame:
          onCanFrameRx?.call(frame.data);
          break;
        case FrameType.heartbeatResponse:
          _handleHeartbeatAck(frame.data);
          break;
        case FrameType.unknown:
          break;
      }
    }
  }

  void _handleConnectAck(Map<String, dynamic> frame) {
    if (_connectAckCompleter != null && !_connectAckCompleter!.isCompleted) {
      _connectAckCompleter!.complete(frame['success'] == true);
    }
  }

  void _handleHeartbeatAck(Map<String, dynamic> frame) {
    _heartbeatWaiting = false;
    _heartbeatMissCount = 0;
    onHeartbeatAck?.call(
      _connectedPort,
      frame['status']?.toString() ?? 'OK',
      DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  HEARTBEAT — send D0 00 every 1s, track D1 replies
  // ═══════════════════════════════════════════════════════════════

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatMissCount = 0;
    _heartbeatWaiting = false;

    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!_isConnected) return;

      if (_heartbeatWaiting) {
        // Previous heartbeat was not acknowledged
        _heartbeatMissCount++;
        onHeartbeatMiss?.call(_connectedPort, _heartbeatMissCount);

        if (_heartbeatMissCount >= _heartbeatMaxMiss) {
          onHeartbeatTimeout?.call(_connectedPort);
          disconnect();
          return;
        }
      }

      _writeLocalBytes(CanFrameBuilder.buildHeartbeatFrame());
      _heartbeatWaiting = true;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEND DATA
  // ═══════════════════════════════════════════════════════════════

  bool _writeLocalBytes(Uint8List bytes) {
    if (_port == null || !_port!.isOpen) {
      onError?.call('Port is closed or not available.');
      return false;
    }
    try {
      _port!.write(bytes);
      return true;
    } catch (e) {
      final errorString = e.toString();
      if (errorString.contains('errno = 0') || errorString.contains('operation completed successfully')) {
        onError?.call('Connection to USB device lost.');
      } else {
        onError?.call('USB write error: $e');
      }
      disconnect();
      return false;
    }
  }

  bool sendData(Uint8List data) {
    if (!_isConnected) return false;
    return _writeLocalBytes(data);
  }

  /// Send a raw hex message — parses it and writes bytes to USB.
  bool sendMessage(String message) {
    if (!_isConnected || _connectedPort.isEmpty) {
      onError?.call('Not connected');
      return false;
    }
    try {
      final bytes = parseSequenceInput(message, DisplayFormat.hex);
      if (bytes.isEmpty) {
        onError?.call('Empty message.');
        return false;
      }
      return _writeLocalBytes(bytes);
    } catch (e) {
      onError?.call('Send error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEND CAN FRAME — build F1 01 locally, write to USB
  // ═══════════════════════════════════════════════════════════════

  int _getDlcCode(int length, bool isFD) {
    if (!isFD || length <= 8) return length <= 8 ? length : 8;
    if (length <= 12) return 9;
    if (length <= 16) return 10;
    if (length <= 20) return 11;
    if (length <= 24) return 12;
    if (length <= 32) return 13;
    if (length <= 48) return 14;
    return 15;
  }

  int _getPaddedLength(int length, bool isFD) {
    if (!isFD || length <= 8) return length <= 8 ? length : 8;
    if (length <= 12) return 12;
    if (length <= 16) return 16;
    if (length <= 20) return 20;
    if (length <= 24) return 24;
    if (length <= 32) return 32;
    if (length <= 48) return 48;
    return 64;
  }

  bool sendCanFrame({
    required String canId,
    required List<int> data,
    required int channel,
    required bool isExtended,
    required bool isFD,
  }) {
    if (!_isConnected || _connectedPort.isEmpty) {
      onError?.call('Not connected');
      return false;
    }

    int numericCanId = int.tryParse(
          canId.replaceAll('0x', '').replaceAll(RegExp(r'\s+'), ''),
          radix: 16,
        ) ??
        0;

    int dlcCode = _getDlcCode(data.length, isFD);
    int paddedLength = _getPaddedLength(data.length, isFD);

    List<int> paddedData = List.from(data);
    if (paddedData.length > paddedLength) {
      paddedData = paddedData.sublist(0, paddedLength);
    } else {
      while (paddedData.length < paddedLength) {
        paddedData.add(0);
      }
    }

    // Build the TX frame locally and write to USB
    final txFrame = CanFrameBuilder.buildTxFrame(
      canId: numericCanId,
      data: paddedData,
      channel: channel,
      isExtended: isExtended,
    );
    if (!_writeLocalBytes(txFrame)) return false;

    // Notify UI of the sent frame
    final hexData = paddedData
        .map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    final canIdStr =
        '0x${numericCanId.toRadixString(16).padLeft(isExtended ? 8 : 3, '0').toUpperCase()}';

    onCanFrameTx?.call({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'canId': canIdStr,
      'isExtended': isExtended,
      'channel': channel + 1,
      'dlc': dlcCode,
      'dataHex': hexData,
    });

    return true;
  }
}
