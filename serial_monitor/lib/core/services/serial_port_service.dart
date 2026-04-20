import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/can_config.dart';
import '../config/models.dart';

/// Frontend bridge for the current CAN backend:
/// - Socket.io for live events
/// - REST APIs for commands/connect/send
class SerialPortService {
  static const String defaultBackendUrl = 'http://192.168.0.16:3001';

  io.Socket? _socket;
  String _backendUrl = defaultBackendUrl;
  bool _isConnected = false;
  String _connectedPort = '';
  List<String> _availablePorts = const [];
  bool _isInitialized = false;
  Completer<void>? _socketReadyCompleter;

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

  bool get isConnected => _isConnected;
  String get portName => _connectedPort;
  List<String> get availablePorts => List.unmodifiable(_availablePorts);
  bool get isSocketConnected => _socket?.connected ?? false;

  static List<String> getAvailablePorts() => const [];
  static String getPortDescription(String portName) => portName;

  Future<void> initialize({String serverUrl = defaultBackendUrl}) async {
    _backendUrl = serverUrl;

    if (_isInitialized) {
      if (!isSocketConnected) {
        _socketReadyCompleter ??= Completer<void>();
        _socket?.connect();
        await _waitForSocketReady();
      }
      await _loadInitialState(serverUrl);
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
      debugPrint('Socket connected to $serverUrl');
      if (!(_socketReadyCompleter?.isCompleted ?? true)) {
        _socketReadyCompleter!.complete();
      }
      await _loadInitialState(serverUrl);
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _connectedPort = '';
      onDisconnected?.call();
      _socketReadyCompleter = Completer<void>();
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

    _socket!.on('port_detected', (payload) {
      final port = _extractPort(payload);
      if (port == null) return;
      if (!_availablePorts.contains(port)) {
        _availablePorts = [..._availablePorts, port];
        onPortsChanged?.call(_availablePorts);
      }
    });

    _socket!.on('port_removed', (payload) {
      final port = _extractPort(payload);
      if (port == null) return;
      _availablePorts = _availablePorts.where((item) => item != port).toList();
      if (_connectedPort == port) {
        _isConnected = false;
        _connectedPort = '';
        onDisconnected?.call();
      }
      onPortsChanged?.call(_availablePorts);
    });

    _socket!.on('device_connected', (payload) {
      if (payload is! Map) return;
      final port = payload['port']?.toString() ?? '';
      if (port.isEmpty) return;
      _isConnected = true;
      _connectedPort = port;
      onConnected?.call(port);
    });

    _socket!.on('device_disconnected', (payload) {
      final port = _extractPort(payload);
      if (port != null && port == _connectedPort) {
        _isConnected = false;
        _connectedPort = '';
        onDisconnected?.call();
      }
    });

    _socket!.on('can_rx', (payload) {
      if (payload is! Map) return;
      final port = payload['port']?.toString() ?? '';
      if (_connectedPort.isNotEmpty && port != _connectedPort) {
        return;
      }

      final frame = payload['frame'];
      if (frame is Map) {
        onCanFrameRx?.call(Map<String, dynamic>.from(frame));
      } else {
        // Legacy fallback
        final decoded = _decodeCanRxFrame(frame);
        if (decoded.isNotEmpty) {
          onDataReceived?.call(decoded);
        }
      }
    });

    _socket!.on('can_tx', (payload) {
      if (payload is! Map) return;
      final port = payload['port']?.toString() ?? '';
      if (_connectedPort.isNotEmpty && port != _connectedPort) {
        return;
      }

      final frame = payload['frame'];
      if (frame is Map) {
        onCanFrameTx?.call(Map<String, dynamic>.from(frame));
      }
    });

    _socket!.on('can_error', (payload) {
      if (payload is! Map) return;
      final error = payload['error']?.toString() ?? 'CAN error';
      onError?.call(error);
    });

    _socket!.on('heartbeat_ack', (payload) {
      if (payload is! Map) return;
      final port = payload['port']?.toString() ?? '';
      if (port.isEmpty) return;
      if (_connectedPort.isNotEmpty && port != _connectedPort) {
        return;
      }

      final status = payload['status']?.toString() ?? 'ok';
      final rawTimestamp = payload['timestamp']?.toString();
      final timestamp = rawTimestamp == null
          ? null
          : DateTime.tryParse(rawTimestamp)?.toLocal();
      onHeartbeatAck?.call(port, status, timestamp);
    });

    _socket!.on('heartbeat_miss', (payload) {
      if (payload is! Map) return;
      final port = payload['port']?.toString() ?? '';
      if (port.isEmpty) return;
      if (_connectedPort.isNotEmpty && port != _connectedPort) {
        return;
      }

      final missCount = payload['missCount'] is num
          ? (payload['missCount'] as num).toInt()
          : int.tryParse(payload['missCount']?.toString() ?? '') ?? 0;
      onHeartbeatMiss?.call(port, missCount);
    });

    _socket!.on('heartbeat_timeout', (payload) {
      if (payload is! Map) return;
      final port = payload['port']?.toString() ?? '';
      if (port.isEmpty) return;
      if (_connectedPort.isNotEmpty && port != _connectedPort) {
        return;
      }

      _isConnected = false;
      _connectedPort = '';
      onHeartbeatTimeout?.call(port);
      onDisconnected?.call();
    });

    _socket!.connect();
    _isInitialized = true;
    await _waitForSocketReady();
    await _loadInitialState(serverUrl);
  }

  Future<bool> connect(SerialPortConfig config, {CanConfig? canConfig}) async {
    try {
      await initialize();

      final can = canConfig ?? CanConfig();
      final response = await _postJson(
        '/api/connect',
        {
          'port': config.portName,
          'channel': can.channel.value,
          'baudRate': can.nominalBaudRate.value,
          'mode': can.modeByte,
          'isFD': can.canType == CanType.canFd,
          'brs': can.brsEnabled,
          'nonISO': can.nonIso,
        },
      );

      final success = response['success'] == true;
      if (success) {
        _isConnected = true;
        _connectedPort = config.portName;
        onConnected?.call(config.portName);
      } else {
        onError?.call(
          response['error']?.toString() ??
              response['message']?.toString() ??
              'Failed to connect',
        );
      }
      return success;
    } on SocketException catch (error) {
      onError?.call(
        'Backend unreachable at $_backendUrl. Please check whether the backend server is running. Details: ${error.message}',
      );
      return false;
    } catch (error) {
      onError?.call('Connect error: $error');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedPort.isNotEmpty) {
      await _postJson('/api/disconnect', {'port': _connectedPort});
    }
    _isConnected = false;
    _connectedPort = '';
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

    try {
      final payload = {
        'port': _connectedPort,
        'canId': canId,
        'data': data,
        'channel': channel,
        'isExtended': isExtended,
        'isFD': isFD,
      };

      debugPrint('\n=== FRONTEND SENDING CAN FRAME ===');
      debugPrint('Port: $_connectedPort');
      debugPrint('CAN ID: $canId');
      debugPrint('Channel: $channel');
      debugPrint('Extended: $isExtended | FD: $isFD');
      debugPrint('Data: $data');
      debugPrint('==================================\n');

      unawaited(
        _postJson('/api/send', payload).catchError((error) {
          onError?.call('Send error: $error');
        }),
      );
      return true;
    } catch (error) {
      onError?.call('Send error: $error');
      return false;
    }
  }

  bool sendMessage(String message) {
    if (!_isConnected || _connectedPort.isEmpty) {
      onError?.call('Not connected');
      return false;
    }

    try {
      final bytes = parseSequenceInput(message, DisplayFormat.hex);
      if (bytes.length < 7 || bytes[0] != 0xF1 || bytes[1] != 0x01) {
        onError?.call(
          'Invalid legacy raw CAN frame format. Use the send popup CAN fields (CAN ID, Format, Channel) for normal sending.',
        );
        return false;
      }

      final canId = bytes[2] |
          (bytes[3] << 8) |
          (bytes[4] << 16) |
          (bytes[5] << 24);
      final dlcChannel = bytes[6];
      final channel = (dlcChannel >> 4) & 0x0F;
      final dataBytes = bytes.skip(7).toList();

      final payload = {
        'port': _connectedPort,
        'canId': canId,
        'data': dataBytes,
        'channel': channel,
        'isExtended': (canId & 0x80000000) != 0,
      };

      debugPrint('\n=== FRONTEND SENDING LEGACY FRAME ===');
      debugPrint('Port: $_connectedPort');
      debugPrint('CAN ID: $canId');
      debugPrint('Channel: $channel');
      debugPrint('Extended: ${(canId & 0x80000000) != 0}');
      debugPrint('Data: $dataBytes');
      debugPrint('=====================================\n');

      unawaited(
        _postJson('/api/send', payload).catchError((error) {
          onError?.call('Send error: $error');
        }),
      );
      return true;
    } catch (e) {
      onError?.call('Send error: $e');
      return false;
    }
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _isInitialized = false;
    _socketReadyCompleter = null;
  }

  Future<void> _loadInitialState(String serverUrl) async {
    try {
      final portsResult = await _getJson('/api/ports');
      final ports = portsResult['ports'];
      if (ports is List) {
        _availablePorts = ports
            .map((item) {
              if (item is Map) {
                return item['path']?.toString() ?? item['port']?.toString() ?? '';
              }
              return item.toString();
            })
            .where((item) => item.isNotEmpty)
            .toList();
        onPortsChanged?.call(_availablePorts);
      }

      final statusResult = await _getJson('/api/status');
      final connections = statusResult['connections'];
      if (connections is List) {
        final connected = connections.cast<Map?>().firstWhere(
          (item) => item != null && item['status']?.toString() == 'connected',
          orElse: () => null,
        );
        if (connected != null) {
          final port = connected['port']?.toString() ?? '';
          if (port.isNotEmpty) {
            _isConnected = true;
            _connectedPort = port;
            onConnected?.call(port);
          }
        }
      }
    } catch (error) {
      onError?.call('Backend init error: $error');
    }
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_backendUrl$path');
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _decodeJsonResponse(
        method: 'GET',
        path: path,
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_backendUrl$path');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _decodeJsonResponse(
        method: 'POST',
        path: path,
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _decodeJsonResponse({
    required String method,
    required String path,
    required int statusCode,
    required String body,
  }) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw HttpException(
        '$method $path returned an empty response body (HTTP $statusCode) from $_backendUrl',
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw FormatException('Expected a JSON object response');
    } on FormatException catch (error) {
      final preview = trimmed.length > 200
          ? '${trimmed.substring(0, 200)}...'
          : trimmed;
      throw FormatException(
        '$method $path returned invalid JSON (HTTP $statusCode): $preview',
        error.source,
        error.offset,
      );
    }
  }

  String? _extractPort(dynamic payload) {
    if (payload is Map) {
      final port = payload['port']?.toString();
      if (port != null && port.isNotEmpty) {
        return port;
      }
    }
    return null;
  }

  Uint8List _decodeCanRxFrame(dynamic framePayload) {
    if (framePayload is! Map) {
      return Uint8List(0);
    }

    final raw = framePayload['raw']?.toString() ?? '';
    if (raw.isNotEmpty) {
      return _hexStringToBytes(raw);
    }

    final dataHex = framePayload['dataHex']?.toString() ?? '';
    if (dataHex.isNotEmpty) {
      return _hexStringToBytes(dataHex);
    }

    return Uint8List(0);
  }

  Uint8List _hexStringToBytes(String text) {
    final normalized = text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (normalized.isEmpty || normalized.length.isOdd) {
      return Uint8List(0);
    }

    final bytes = <int>[];
    for (var index = 0; index < normalized.length; index += 2) {
      bytes.add(int.parse(normalized.substring(index, index + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> _waitForSocketReady() async {
    final completer = _socketReadyCompleter;
    if (completer == null) {
      return;
    }

    if (isSocketConnected) {
      if (!completer.isCompleted) {
        completer.complete();
      }
      return;
    }

    try {
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Timed out waiting for backend socket');
        },
      );
    } catch (error) {
      onError?.call('Backend connection error: $error');
    }
  }
}
