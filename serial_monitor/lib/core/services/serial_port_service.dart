import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart' as sp;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/can_config.dart';
import '../config/models.dart';

/// Distributed Architecture: Flutter handles physical USB natively, but routes all logic to Node backend
class SerialPortService {
  static const String defaultBackendUrl = 'http://192.168.0.24:3001';

  io.Socket? _socket;
  String _backendUrl = defaultBackendUrl;
  
  // Local native serial variables
  sp.SerialPort? _port;
  sp.SerialPortReader? _reader;
  StreamSubscription? _readerSubscription;

  bool _isConnected = false;
  String _connectedPort = '';
  List<String> _availablePorts = const [];
  
  bool _isInitialized = false;
  Completer<void>? _socketReadyCompleter;

  // Exact same callback API to keep PortController happy
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

  Timer? _pollingTimer;

  bool get isConnected => _isConnected;
  String get portName => _connectedPort;
  List<String> get availablePorts => List.unmodifiable(_availablePorts);
  bool get isSocketConnected => _socket?.connected ?? false;

  static List<String> getAvailablePorts() => sp.SerialPort.availablePorts;
  static String getPortDescription(String portName) =>
      sp.SerialPort(portName).description ?? portName;

  Future<void> initialize({String serverUrl = defaultBackendUrl}) async {
    _backendUrl = serverUrl;
    
    // Start polling the local Windows internal hardware ports
    _startLocalPortPolling();

    if (_isInitialized) {
      if (!isSocketConnected) {
        _socketReadyCompleter ??= Completer<void>();
        _socket?.connect();
        await _waitForSocketReady();
      }
      return;
    }

    _socketReadyCompleter = Completer<void>();
    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) async {
      debugPrint('Socket connected to $_backendUrl (Cloud Backend Attached)');
      if (!(_socketReadyCompleter?.isCompleted ?? true)) {
        _socketReadyCompleter!.complete();
      }
    });

    _socket!.onDisconnect((_) {
      _socketReadyCompleter = Completer<void>();
      // Backend disconnected, we could optionally close USB locally here or stay connected natively
    });

    _socket!.onConnectError((error) {
      onError?.call('Backend connection error: $error');
      if (!(_socketReadyCompleter?.isCompleted ?? true)) {
        _socketReadyCompleter!.completeError(error);
      }
    });

    _socket!.onError((error) {
      onError?.call('Backend socket error: $error');
    });

    // We no longer rely on 'port_detected' or 'port_removed' from backend
    // since we do local USB scanning, but we still listen for CAN data!

    _socket!.on('can_rx', (payload) {
      if (payload is! Map) return;
      final frame = payload['frame'];
      if (frame is Map) {
        onCanFrameRx?.call(Map<String, dynamic>.from(frame));
      } else {
        final decoded = _decodeCanRxFrame(frame);
        if (decoded.isNotEmpty) {
          onDataReceived?.call(decoded);
        }
      }
    });

    _socket!.on('tx_binary_response', (payload) {
      // Backend built the byte array for us! Write it natively to our USB
      if (payload is Map && payload['binary'] is String) {
        final hexStr = payload['binary'] as String;
        _writeLocalBytes(_hexStringToBytes(hexStr));
      }
    });

    _socket!.on('can_error', (payload) {
      if (payload is! Map) return;
      final error = payload['error']?.toString() ?? 'CAN error';
      onError?.call(error);
    });
    
    _socket!.connect();
    _isInitialized = true;
    await _waitForSocketReady();
  }

  void _startLocalPortPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final ports = sp.SerialPort.availablePorts;
      if (_isConnected && !ports.contains(_connectedPort)) {
        // Physical Unplug detected locally!
        disconnect();
      }
      
      if (listEquals(_availablePorts, ports)) return;
      _availablePorts = ports;
      onPortsChanged?.call(_availablePorts);
    });
  }

  Timer? _heartbeatTimer;

  Future<bool> connect(SerialPortConfig config, {CanConfig? canConfig}) async {
    try {
      await initialize();

      if (!isSocketConnected) {
         onError?.call('Cannot connect hardware: Cloud Backend disconnected at $_backendUrl');
         return false;
      }
      
      if (_isConnected) await disconnect();

      // Open USB Port Natively on Windows/Mac
      _port = sp.SerialPort(config.portName);
      if (!_port!.openReadWrite()) {
        onError?.call('Failed to open local USB port: ${sp.SerialPort.lastError}');
        return false;
      }

      final pConfig = _port!.config;
      pConfig.baudRate = config.baudRate;
      pConfig.bits = config.dataBits;
      pConfig.stopBits = config.stopBits;
      _port!.config = pConfig;

      _isConnected = true;
      _connectedPort = config.portName;

      // Start asynchronous low-level reader loop
      _reader = sp.SerialPortReader(_port!);
      _readerSubscription = _reader!.stream.listen((Uint8List data) {
         // Stream literal raw bytes to Cloud Backend (Step 6)
         _socket?.emit('remote_raw_stream', {
            'sessionId': 'Laptop1_User',
            'rawBytes': data.toList(),
         });
      }, onError: (err) {
        onError?.call('Local USB Stream Error: $err');
        disconnect();
      }, onDone: () {
        disconnect();
      });

      // To complete the connection sequence (Step 1), send A0 frame locally?
      if (canConfig != null) {
         final connectFrame = canConfig.buildConnectFrame();
         _writeLocalBytes(Uint8List.fromList(connectFrame));
         
         // Start Local Heartbeat (Hardware drops connection if no D0 00 every 2s)
         _heartbeatTimer?.cancel();
         _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
           if (_isConnected) {
             _writeLocalBytes(Uint8List.fromList([0xD0, 0x00]));
           }
         });
      }

      onConnected?.call(config.portName);
      return true;

    } catch (error) {
      onError?.call('Connect error: $error');
      return false;
    }
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _readerSubscription?.cancel();
    _reader?.close();
    
    if (_port != null && _port!.isOpen) {
      try { _port!.close(); } catch (_) {}
    }
    _port?.dispose();
    _port = null;
    
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
    _socket?.dispose();
    _socket = null;
    _isInitialized = false;
    _socketReadyCompleter = null;
  }

  void _writeLocalBytes(Uint8List bytes) {
    if (_port == null || !_port!.isOpen) return;
    try {
      _port!.write(bytes);
    } catch (e) {
      debugPrint('Local USB Write Error: $e');
      disconnect();
    }
  }
  
  bool sendData(Uint8List data) {
    if (!_isConnected) return false;
    _writeLocalBytes(data);
    return true;
  }

  bool sendMessage(String message) {
    if (!_isConnected || _connectedPort.isEmpty) {
      onError?.call('Not connected');
      return false;
    }
    try {
      final bytes = parseSequenceInput(message, DisplayFormat.hex);
      if (bytes.length < 7 || bytes[0] != 0xF1 || bytes[1] != 0x01) {
        onError?.call('Invalid raw CAN frame.');
        return false;
      }

      final canId = bytes[2] | (bytes[3] << 8) | (bytes[4] << 16) | (bytes[5] << 24);
      final dlcChannel = bytes[6];
      final channel = (dlcChannel >> 4) & 0x0F;
      final dataBytes = bytes.skip(7).toList();

      // Defer to backend for TX generation (Step 5)
      _socket?.emit('request_tx_binary', {
        'canId': canId,
        'frameData': dataBytes,
        'channel': channel,
        'isExtended': (canId & 0x80000000) != 0,
      });

      return true;
    } catch (e) {
      onError?.call('Send error: $e');
      return false;
    }
  }

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

    int numericCanId = int.tryParse(canId.replaceAll('0x', ''), radix: 16) ?? 0;

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

    // Send logic to backend Cloud to let it build the F1 01 frame (Step 5)
    _socket?.emit('request_tx_binary', {
      'canId': numericCanId,
      'frameData': paddedData,
      'channel': channel,
      'isExtended': isExtended,
    });
    
    // Broadcast success to UI
    final hexData = paddedData.map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    final canIdStr = '0x${numericCanId.toRadixString(16).padLeft(isExtended ? 8 : 3, '0').toUpperCase()}';
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

  Future<void> _waitForSocketReady() async {
    final completer = _socketReadyCompleter;
    if (completer == null) return;
    if (isSocketConnected) {
      if (!completer.isCompleted) completer.complete();
      return;
    }
    try {
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Timed out waiting for backend socket'),
      );
    } catch (error) {
      onError?.call('Backend connection error: $error');
    }
  }
  
  Uint8List _decodeCanRxFrame(dynamic framePayload) {
    if (framePayload is! Map) return Uint8List(0);
    final raw = framePayload['raw']?.toString() ?? '';
    if (raw.isNotEmpty) return _hexStringToBytes(raw);
    final dataHex = framePayload['dataHex']?.toString() ?? '';
    if (dataHex.isNotEmpty) return _hexStringToBytes(dataHex);
    return Uint8List(0);
  }

  Uint8List _hexStringToBytes(String text) {
    final normalized = text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (normalized.isEmpty || normalized.length.isOdd) return Uint8List(0);
    final bytes = <int>[];
    for (var index = 0; index < normalized.length; index += 2) {
      bytes.add(int.parse(normalized.substring(index, index + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}
