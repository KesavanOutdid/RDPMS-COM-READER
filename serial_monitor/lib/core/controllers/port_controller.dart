import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../config/can_config.dart';
import '../config/models.dart';
import '../services/serial_port_service.dart';

/// Main state management controller for the serial monitor
class PortController extends ChangeNotifier {
  final SerialPortService _service = SerialPortService();

  // Connection state
  final SerialPortConfig _config = SerialPortConfig();
  final CanConfig _canConfig = CanConfig();
  bool _isConnecting = false;
  String _statusMessage = 'Disconnected';
  List<String> _availablePorts = [];
  DateTime? _lastHeartbeatAckAt;
  int _heartbeatMissCount = 0;

  // Tabs
  final List<SerialTab> _tabs = [];
  int _activeTabIndex = 0;

  // Getters
  SerialPortConfig get config => _config;
  CanConfig get canConfig => _canConfig;
  bool get isConnected => _service.isConnected;
  bool get isConnecting => _isConnecting;
  String get statusMessage => _statusMessage;
  List<String> get availablePorts => _availablePorts;
  DateTime? get lastHeartbeatAckAt => _lastHeartbeatAckAt;
  int get heartbeatMissCount => _heartbeatMissCount;
  List<SerialTab> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  SerialTab? get activeTab => _tabs.isNotEmpty && _activeTabIndex < _tabs.length
      ? _tabs[_activeTabIndex]
      : null;

  // Byte counters
  int _totalBytesSent = 0;
  int _totalBytesReceived = 0;
  int get totalBytesSent => _totalBytesSent;
  int get totalBytesReceived => _totalBytesReceived;

  PortController() {
    // Create initial tab
    _tabs.add(SerialTab(name: 'Tab 1'));
    _ensureTrailingPlaceholder(0);

    // Set up callbacks
    _service.onDataReceived = _handleDataReceived;
    _service.onCanFrameRx = _handleCanFrameRx;
    _service.onCanFrameTx = _handleCanFrameTx;
    _service.onError = _handleError;
    _service.onDisconnected = _handleDisconnected;
    _service.onPortsChanged = _handlePortsChanged;
    _service.onConnected = _handleConnected;
    _service.onHeartbeatAck = _handleHeartbeatAck;
    _service.onHeartbeatMiss = _handleHeartbeatMiss;
    _service.onHeartbeatTimeout = _handleHeartbeatTimeout;

    // Start local USB port polling.
    _service.initialize();

    // Load saved config
    _loadConfig();
  }

  /// Refresh list of available serial ports
  void refreshPorts() {
    _service.initialize();
    _availablePorts = _service.availablePorts;
    if (_availablePorts.isNotEmpty && _config.portName.isEmpty) {
      _config.portName = _availablePorts.first;
    }
    notifyListeners();
  }

  /// Update port configuration
  void updateConfig({
    String? portName,
    int? baudRate,
    int? dataBits,
    int? stopBits,
    int? parity,
    int? flowControl,
  }) {
    if (portName != null) _config.portName = portName;
    if (baudRate != null) _config.baudRate = baudRate;
    if (dataBits != null) _config.dataBits = dataBits;
    if (stopBits != null) _config.stopBits = stopBits;
    if (parity != null) _config.parity = parity;
    if (flowControl != null) _config.flowControl = flowControl;
    notifyListeners();
  }

  /// Update CAN bus configuration
  void updateCanConfig({
    CanChannel? channel,
    CanNominalBaudRate? nominalBaudRate,
    CanType? canType,
    ClassicCanMode? classicMode,
    CanFdDataBaud? fdDataBaud,
    bool? brsEnabled,
    bool? nonIso,
  }) {
    if (channel != null) _canConfig.channel = channel;
    if (nominalBaudRate != null) _canConfig.nominalBaudRate = nominalBaudRate;
    if (canType != null) _canConfig.canType = canType;
    if (classicMode != null) _canConfig.classicMode = classicMode;
    if (fdDataBaud != null) _canConfig.fdDataBaud = fdDataBaud;
    if (brsEnabled != null) _canConfig.brsEnabled = brsEnabled;
    if (nonIso != null) _canConfig.nonIso = nonIso;
    notifyListeners();
  }

  /// Connect to the configured serial port
  Future<bool> connect() async {
    if (_config.portName.isEmpty) {
      _statusMessage = 'No port selected';
      notifyListeners();
      return false;
    }

    _isConnecting = true;
    _statusMessage = 'Connecting to ${_config.portName}...';
    notifyListeners();

    bool success = false;
    try {
      success = await _service.connect(_config, canConfig: _canConfig);
    } catch (error) {
      _statusMessage = 'Error: $error';
      _isConnecting = false;
      notifyListeners();
      return false;
    }

    _isConnecting = false;
    if (success) {
      _statusMessage = 'Connected to ${_config.portName}';
      _totalBytesSent = 0;
      _totalBytesReceived = 0;
      _heartbeatMissCount = 0;
      _lastHeartbeatAckAt = null;
      _saveConfig();
    } else {
      _statusMessage = 'Failed to connect to ${_config.portName}';
    }
    notifyListeners();
    return success;
  }

  /// Disconnect from the serial port
  Future<void> disconnect() async {
    await _service.disconnect();
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  /// Toggle connection
  Future<void> toggleConnection() async {
    if (isConnected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  // ─── TAB MANAGEMENT ───────────────────────────────

  /// Add a new tab
  void addTab({String? canId}) {
    if (_tabs.length >= AppConstants.maxTabs) return;
    final index = _tabs.length + 1;
    _tabs.add(SerialTab(name: canId != null && canId.isNotEmpty ? 'Tab $index ($canId)' : 'Tab $index', tabCanId: canId));
    _activeTabIndex = _tabs.length - 1;
    _ensureTrailingPlaceholder(_activeTabIndex);
    notifyListeners();
  }

  /// Remove a tab by index
  void removeTab(int index) {
    if (_tabs.length <= 1) return;
    if (index < 0 || index >= _tabs.length) return;

    _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  /// Set the active tab
  void setActiveTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeTabIndex = index;
    notifyListeners();
  }

  /// Rename a tab
  void renameTab(int index, String name) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs[index].name = name;
    notifyListeners();
  }

  // ─── TAB SETTINGS ─────────────────────────────────

  /// Set display format for a tab
  void setDisplayFormat(int tabIndex, DisplayFormat format) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    _tabs[tabIndex].displayFormat = format;
    notifyListeners();
  }

  /// Set send format for a tab
  void setSendFormat(int tabIndex, DisplayFormat format) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    _tabs[tabIndex].sendFormat = format;
    notifyListeners();
  }

  /// Set line ending for a tab
  void setLineEnding(int tabIndex, String lineEnding) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    _tabs[tabIndex].lineEnding = lineEnding;
    notifyListeners();
  }

  /// Select a saved send sequence row
  void selectSendSequence(int tabIndex, int sequenceIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    if (sequenceIndex < 0 || sequenceIndex >= tab.sendSequences.length) return;
    tab.selectedSendSequenceIndex = sequenceIndex;
    notifyListeners();
  }

  /// Update a saved send sequence
  void updateSendSequence(
    int tabIndex,
    int sequenceIndex, {
    String? name,
    String? sequence,
    DisplayFormat? format,
    String? documentation,
    CanFrameFormat? canFrameFormat,
    CanFrameType? canFrameType,
    String? canIdHex,
    int? channel,
    int? repeatCount,
    int? sendCycleMs,
    bool? idIncrementEnabled,
    bool? dataIncrementEnabled,
  }) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    if (sequenceIndex < 0 || sequenceIndex >= tab.sendSequences.length) return;

    final sendSequence = tab.sendSequences[sequenceIndex];
    if (name != null) sendSequence.name = name;
    if (sequence != null) sendSequence.sequence = sequence;
    if (format != null) sendSequence.format = format;
    if (documentation != null) sendSequence.documentation = documentation;
    if (canFrameFormat != null) {
      sendSequence.canFrameFormat = canFrameFormat;
    }
    if (canFrameType != null) sendSequence.canFrameType = canFrameType;
    if (canIdHex != null) sendSequence.canIdHex = canIdHex;
    if (channel != null) sendSequence.channel = channel;
    if (repeatCount != null) sendSequence.repeatCount = repeatCount;
    if (sendCycleMs != null) sendSequence.sendCycleMs = sendCycleMs;
    if (idIncrementEnabled != null) {
      sendSequence.idIncrementEnabled = idIncrementEnabled;
    }
    if (dataIncrementEnabled != null) {
      sendSequence.dataIncrementEnabled = dataIncrementEnabled;
    }
    _ensureTrailingPlaceholder(tabIndex);
    notifyListeners();
  }

  void addSendSequence(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    tab.sendSequences.add(SendSequence(name: tab.tabCanId != null && tab.tabCanId!.isNotEmpty ? 'Msg (${tab.tabCanId})' : '', canIdHex: tab.tabCanId ?? ''));
    tab.selectedSendSequenceIndex = tab.sendSequences.length - 1;
    notifyListeners();
  }

  void deleteSendSequence(int tabIndex, int sequenceIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    if (sequenceIndex < 0 || sequenceIndex >= tab.sendSequences.length) return;

    tab.sendSequences.removeAt(sequenceIndex);
    if (tab.sendSequences.isEmpty) {
      tab.sendSequences.add(SendSequence(name: tab.tabCanId != null && tab.tabCanId!.isNotEmpty ? 'Msg (${tab.tabCanId})' : 'message 1', canIdHex: tab.tabCanId ?? ''));
    }
    _ensureTrailingPlaceholder(tabIndex);
    if (tab.selectedSendSequenceIndex >= tab.sendSequences.length) {
      tab.selectedSendSequenceIndex = tab.sendSequences.length - 1;
    }
    notifyListeners();
  }

  /// Send a saved sequence by row index
  Future<bool> sendSavedSequence(int tabIndex, int sequenceIndex) async {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return false;
    final tab = _tabs[tabIndex];
    if (sequenceIndex < 0 || sequenceIndex >= tab.sendSequences.length) {
      return false;
    }

    final sendSequence = tab.sendSequences[sequenceIndex];
    final hasCanId = sendSequence.canIdHex.trim().isNotEmpty;
    final needsPayload = sendSequence.canFrameType != CanFrameType.remote;

    if (needsPayload && sendSequence.sequence.trim().isEmpty) {
      _handleError('Selected send sequence is empty');
      return false;
    }

    if (_activeTabIndex != tabIndex) {
      _activeTabIndex = tabIndex;
    }
    tab.selectedSendSequenceIndex = sequenceIndex;

    if (hasCanId) {
      return await _sendSequenceAsCanFrame(sendSequence);
    }

    _handleError(
      'CAN ID is required for CAN send. Open the send popup and fill CAN ID, Format, and Channel.',
    );
    return false;
  }

  /// Toggle auto-scroll for a tab
  void toggleAutoScroll(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    _tabs[tabIndex].autoScroll = !_tabs[tabIndex].autoScroll;
    notifyListeners();
  }

  /// Clear messages in a tab
  void clearMessages(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    _tabs[tabIndex].clearMessages();
    notifyListeners();
  }

  /// Clear all messages in all tabs
  void clearAllMessages() {
    for (final tab in _tabs) {
      tab.clearMessages();
    }
    _totalBytesSent = 0;
    _totalBytesReceived = 0;
    notifyListeners();
  }

  // ─── DATA SEND/RECEIVE ────────────────────────────

  /// Send data from the active tab
  bool sendData(String input) {
    return _sendDataInternal(input);
  }

  bool _sendDataInternal(String input, {DisplayFormat? format}) {
    if (!isConnected || activeTab == null) return false;

    final tab = activeTab!;
    final selectedFormat = format ?? tab.sendFormat;
    Uint8List bytes;

    // Validate and normalize the input locally so the UI log stays accurate.
    try {
      bytes = parseSequenceInput(input, selectedFormat);
    } catch (e) {
      _handleError('Invalid input format: $e');
      return false;
    }

    // Convert to hex format for the serial service.
    final outboundMessage = selectedFormat == DisplayFormat.ascii
        ? input
        : formatSequenceBytes(bytes, DisplayFormat.hex);

    final success = _service.sendMessage(outboundMessage);
    if (success) {
      _totalBytesSent += bytes.length;

      // Create message for the sending tab
      final message = SerialMessage(
        text: input,
        rawBytes: bytes,
        direction: MessageDirection.sent,
        timestamp: DateTime.now(),
        tabIndex: _activeTabIndex,
      );

      tab.addMessage(message);
      notifyListeners();
    }
    return success;
  }

  Future<bool> _sendSequenceAsCanFrame(SendSequence sequence) async {
    if (!isConnected || activeTab == null) return false;

    if (sequence.canFrameType == CanFrameType.remote) {
      _handleError(
        'Remote CAN frames are not wired in the frontend send flow yet',
      );
      return false;
    }

    Uint8List baseBytes;
    try {
      baseBytes = parseSequenceInput(sequence.sequence, sequence.format);
    } catch (error) {
      _handleError('Invalid input format: $error');
      return false;
    }

    final normalizedCanId = _normalizeCanIdHex(sequence.canIdHex);
    if (normalizedCanId == null) {
      _handleError('Invalid CAN ID. Please enter a hex CAN ID in the send popup');
      return false;
    }

    int currentCanId = int.tryParse(normalizedCanId.replaceAll('0x', ''), radix: 16) ?? 0;
    Uint8List currentBytes = Uint8List.fromList(baseBytes);

    final channelValue = sequence.channel == 2 ? 1 : 0;
    final isExtended = sequence.canFrameFormat == CanFrameFormat.extended;
    final isFD = _canConfig.canType == CanType.canFd;

    final int repeats = sequence.repeatCount > 0 ? sequence.repeatCount : 1;
    final int delayMs = sequence.sendCycleMs > 0 ? sequence.sendCycleMs : 0;

    bool allSuccess = true;

    for (int i = 0; i < repeats; i++) {
      if (!isConnected || activeTab == null) {
        allSuccess = false;
        break;
      }

      String canIdStr = '0x${currentCanId.toRadixString(16).toUpperCase()}';

      final success = _service.sendCanFrame(
        canId: canIdStr,
        data: currentBytes.toList(),
        channel: channelValue,
        isExtended: isExtended,
        isFD: isFD,
      );

      if (success) {
        _totalBytesSent += currentBytes.length;
      } else {
        allSuccess = false;
        break;
      }

      // Handle Increments
      if (sequence.idIncrementEnabled) {
        currentCanId++;
        // Keep within bounds
        if (isExtended && currentCanId > 0x1FFFFFFF) currentCanId = 0;
        if (!isExtended && currentCanId > 0x7FF) currentCanId = 0;
      }

      if (sequence.dataIncrementEnabled && currentBytes.isNotEmpty) {
        int index = currentBytes.length - 1;
        while (index >= 0) {
          currentBytes[index] = (currentBytes[index] + 1) & 0xFF;
          if (currentBytes[index] != 0) break; // no carry
          index--;
        }
      }

      if (i < repeats - 1 && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    return allSuccess;
  }

  String? _normalizeCanIdHex(String value) {
    final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (compact.isEmpty) {
      return null;
    }
    return '0x$compact';
  }

  /// Handle received data from the serial port
  void _handleDataReceived(Uint8List data) {
    _totalBytesReceived += data.length;

    final message = SerialMessage(
      text: String.fromCharCodes(data),
      rawBytes: data,
      direction: MessageDirection.received,
      timestamp: DateTime.now(),
      tabIndex: -1, // Received by all tabs
    );

    // Add to ALL tabs (received data goes to every tab)
    for (final tab in _tabs) {
      tab.addMessage(message);
    }
    notifyListeners();
  }

  Uint8List _parseDataHex(String? dataHex) {
    if (dataHex == null || dataHex.isEmpty) return Uint8List(0);
    final parts = dataHex.split(' ').where((s) => s.isNotEmpty);
    return Uint8List.fromList(parts.map((p) => int.parse(p, radix: 16)).toList());
  }

  void _handleCanFrameRx(Map<String, dynamic> frame) {
    // Filter out system control frames
    if (frame['type'] == 'heartbeat' || frame['type'] == 'connect_ack' ||
        frame['type'] == 'HEARTBEAT_RESPONSE' || frame['type'] == 'CONNECT_RESPONSE') {
      return;
    }

    final rawBytes = _parseDataHex(frame['dataHex']?.toString());
    _totalBytesReceived += rawBytes.length;

    final ts = frame['timestamp'];
    final timeStampHex = (ts is num)
        ? '0x${ts.toInt().toRadixString(16).toUpperCase().padLeft(8, '0')}'
        : ts?.toString();

    final message = SerialMessage(
      text: '', 
      rawBytes: rawBytes,
      direction: MessageDirection.received,
      timestamp: DateTime.now(),
      tabIndex: -1,
      canId: frame['canId']?.toString(),
      channel: frame['channel'] is int ? frame['channel'] as int : int.tryParse(frame['channel']?.toString() ?? ''),
      dlc: frame['dlc'] is int ? frame['dlc'] as int : int.tryParse(frame['dlc']?.toString() ?? ''),
      type: 'Data', 
      canFormat: frame['canId']?.toString().length == 10 ? 'Extended' : 'Standard', 
      timeStampHex: timeStampHex, 
    );

    for (final tab in _tabs) {
      if (tab.tabCanId != null && tab.tabCanId!.isNotEmpty) {
        final rawCanId = frame['canId']?.toString();
        if (rawCanId != null && !rawCanId.toLowerCase().contains(tab.tabCanId!.toLowerCase().replaceAll('0x', '').replaceAll(' ', ''))) {
          continue;
        }
      }
      tab.addMessage(message);
    }
    notifyListeners();
  }

  void _handleCanFrameTx(Map<String, dynamic> frame) {
    final rawBytes = _parseDataHex(frame['dataHex']?.toString());
    
    final ts = frame['timestamp'];
    final timeStampHex = (ts is num)
        ? '0x${ts.toInt().toRadixString(16).toUpperCase().padLeft(8, '0')}'
        : ts?.toString();

    final message = SerialMessage(
      text: '', 
      rawBytes: rawBytes,
      direction: MessageDirection.sent,
      timestamp: DateTime.now(),
      tabIndex: -1,
      canId: frame['canId']?.toString(),
      channel: frame['channel'] is int ? frame['channel'] as int : int.tryParse(frame['channel']?.toString() ?? ''),
      dlc: frame['dlc'] is int ? frame['dlc'] as int : int.tryParse(frame['dlc']?.toString() ?? ''),
      type: 'Data',
      canFormat: frame['canId']?.toString().length == 10 ? 'Extended' : 'Standard',
      timeStampHex: timeStampHex,
    );

    for (final tab in _tabs) {
      if (tab.tabCanId != null && tab.tabCanId!.isNotEmpty) {
        final rawCanId = frame['canId']?.toString();
        if (rawCanId != null && !rawCanId.toLowerCase().contains(tab.tabCanId!.toLowerCase().replaceAll('0x', '').replaceAll(' ', ''))) {
          continue;
        }
      }
      tab.addMessage(message);
    }
    notifyListeners();
  }

  /// Handle errors from the service
  void _handleError(String error) {
    _statusMessage = 'Error: $error';
    notifyListeners();
  }

  /// Handle disconnection event
  void _handleDisconnected() {
    _statusMessage = 'Disconnected';
    _heartbeatMissCount = 0;
    _lastHeartbeatAckAt = null;
    notifyListeners();
  }

  void _handleConnected(String port) {
    _config.portName = port;
    if (_config.baudRate <= 0) {
      _config.baudRate = AppConstants.defaultBaudRate;
    }
    _statusMessage = 'Connected to $port';
    _heartbeatMissCount = 0;
    notifyListeners();
  }

  void _handleHeartbeatAck(String port, String status, DateTime? timestamp) {
    _heartbeatMissCount = 0;
    _lastHeartbeatAckAt = timestamp ?? DateTime.now();
    _statusMessage = 'Connected to $port';
    notifyListeners();
  }

  void _handleHeartbeatMiss(String port, int missCount) {
    _heartbeatMissCount = missCount;
    // Hidden from UI
    notifyListeners();
  }

  void _handleHeartbeatTimeout(String port) {
    _heartbeatMissCount = 0;
    _lastHeartbeatAckAt = null;
    _statusMessage = 'Disconnected from $port (Timeout)';
    notifyListeners();
  }

  void _handlePortsChanged(List<String> ports) {
    _availablePorts = ports;
    if (_availablePorts.isNotEmpty &&
        (!_availablePorts.contains(_config.portName) ||
            _config.portName.isEmpty)) {
      _config.portName = _availablePorts.first;
    }
    notifyListeners();
  }

  // ─── PERSISTENCE ──────────────────────────────────

  /// Save configuration to shared preferences
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastPort', _config.portName);
      await prefs.setInt('lastBaudRate', _config.baudRate);
      await prefs.setInt('lastDataBits', _config.dataBits);
      await prefs.setInt('lastStopBits', _config.stopBits);
      await prefs.setInt('lastParity', _config.parity);
    } catch (e) {
      debugPrint('Error saving config: $e');
    }
  }

  /// Load configuration from shared preferences
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _config.portName = prefs.getString('lastPort') ?? '';
      _config.baudRate =
          prefs.getInt('lastBaudRate') ?? AppConstants.defaultBaudRate;
      _config.dataBits = prefs.getInt('lastDataBits') ?? 8;
      _config.stopBits = prefs.getInt('lastStopBits') ?? 1;
      _config.parity = prefs.getInt('lastParity') ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading config: $e');
    }
  }

  /// Reset byte counters
  void resetCounters() {
    _totalBytesSent = 0;
    _totalBytesReceived = 0;
    notifyListeners();
  }

  void _ensureTrailingPlaceholder(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    for (var index = tab.sendSequences.length - 2; index >= 0; index--) {
      if (tab.sendSequences[index].isPlaceholder) {
        tab.sendSequences.removeAt(index);
      }
    }

    if (tab.sendSequences.isEmpty || !tab.sendSequences.last.isPlaceholder) {
      tab.sendSequences.add(SendSequence(name: '', canIdHex: tab.tabCanId ?? ''));
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
