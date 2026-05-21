import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/bulk_firmware_service.dart';
import '../../../core/services/serial_port_service.dart';
import '../../../utils/theme/app_theme.dart';

class BulkFirmwareDialog extends StatefulWidget {
  final SerialPortService serialService;
  final int channel;
  final bool isExtended;

  const BulkFirmwareDialog({
    super.key,
    required this.serialService,
    required this.channel,
    required this.isExtended,
  });

  @override
  State<BulkFirmwareDialog> createState() => _BulkFirmwareDialogState();
}

class _BulkFirmwareDialogState extends State<BulkFirmwareDialog> {
  late BulkFirmwareService _service;
  
  bool _isMockMode = false;
  bool _isScanning = false;
  bool _isUploading = false;
  bool _isManualMode = false;
  bool _waitingForManualTrigger = false;

  // Mock upload manual states
  int _mockCurrentFrame = 0;
  int _mockTotalFrames = 0;
  List<DiscoveredBoard> _mockSelectedBoards = [];
  
  List<DiscoveredBoard> _boards = [];
  BulkFirmwareFile? _firmwareFile;
  
  double _progress = 0.0;
  String _statusMessage = 'Idle';

  // Target board type
  BoardType _selectedBoardType = BoardType.all;
  
  // Fake timer for mock mode
  Timer? _mockTimer;

  // Inter-frame delay
  final TextEditingController _delayController = TextEditingController(text: '5');

  final List<_LogEntry> _log = [];
  final ScrollController _logScrollController = ScrollController();

  void _addLog(String message, _LogLevel level) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    setState(() {
      _log.add(_LogEntry(timestamp: ts, message: message, level: level));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _service = BulkFirmwareService(widget.serialService);
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _logScrollController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  // ── Mock Helpers ──
  
  void _startMockScan() {
    _addLog('Starting mock CAN bus scan for ${_selectedBoardType.label}...', _LogLevel.info);
    String typeHex = _selectedBoardType.value.toRadixString(16).padLeft(2, '0').toUpperCase();
    _addLog('→ TX: 01 01 $typeHex 00 00 00 00 00', _LogLevel.tx);
    setState(() {
      _isScanning = true;
      _boards.clear();
      _statusMessage = 'Scanning for nodes (Mock)...';
    });
    
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      
      int count = Random().nextInt(5) + 2; // 2 to 6 nodes
      List<DiscoveredBoard> mocks = [];
      final boardTypes = [0x01, 0x02, 0x03, 0x05, 0x06];
      for(int i=0; i<count; i++) {
        final bt = boardTypes[i % boardTypes.length];
        final devId = (bt - 1) * 10 + i + 1;
        mocks.add(DiscoveredBoard(
          canId: i + 1,
          deviceId: devId,
          boardTypeValue: bt,
          version: 'v2.${Random().nextInt(5)}.${Random().nextInt(9)}'
        ));
      }
      
      setState(() {
        _isScanning = false;
        _boards = mocks;
        _statusMessage = 'Found ${_boards.length} nodes.';
        _addLog('Found ${_boards.length} nodes on CAN bus.', _LogLevel.success);
        for(var b in _boards) {
          String typeHexB = b.boardTypeValue.toRadixString(16).padLeft(2, '0').toUpperCase();
          String devIdHexB = b.deviceId.toRadixString(16).padLeft(2, '0').toUpperCase();
          String versionHex = b.version.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
          _addLog('← RX [Node ${b.deviceIdStr}]: $typeHexB $devIdHexB $versionHex 00', _LogLevel.rx);
        }
      });
    });
  }

  void _startMockUpload() {
    if (_boards.isEmpty || _firmwareFile == null) return;
    
    final selectedBoards = _boards.where((b) => b.selected).toList();
    if (selectedBoards.isEmpty) {
      _addLog('❌ Please select at least one board.', _LogLevel.error);
      return;
    }
    
    _addLog('Starting Mock Bulk OTA for ${selectedBoards.length} boards...', _LogLevel.info);
    
    if (_isManualMode) {
      setState(() {
        _isUploading = true;
        _waitingForManualTrigger = true;
        _progress = 0.0;
        _mockCurrentFrame = 0;
        _mockTotalFrames = _firmwareFile!.frameCount;
        _mockSelectedBoards = selectedBoards;
        _statusMessage = 'Manual Mode: Ready to send Broadcast Header (Mock). Click "Send Frame" to transmit.';
        for (var b in _boards) {
          if (b.selected) {
            b.status = BoardOtaStatus.discovered;
            b.statusMessage = 'Waiting';
            b.progress = 0.0;
          }
        }
      });
      _addLog('Manual Mode: Ready to send Broadcast Header (Mock).', _LogLevel.info);
      return;
    }

    _addLog('→ TX: 02 00 00 [Size] [Frames] [CRC] [Board] ... (Header)', _LogLevel.tx);
    
    setState(() {
      _isUploading = true;
      _progress = 0.0;
      _statusMessage = 'Starting Bulk OTA (Mock)...';
      for (var b in _boards) {
        if (b.selected) {
          b.status = BoardOtaStatus.discovered;
          b.statusMessage = 'Waiting';
          b.progress = 0.0;
        }
      }
    });

    int currentFrame = 0;
    int totalFrames = _firmwareFile!.frameCount;

    _mockTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (currentFrame == 0) {
           for (var b in selectedBoards) {
             b.status = BoardOtaStatus.uploading;
             b.statusMessage = 'Header OK';
             _addLog('← RX [Node ${b.canIdHex}]: 79 00 ... (Header ACK)', _LogLevel.success);
           }
        }
        
        currentFrame++;
        _progress = currentFrame / (totalFrames + 1); // leave room for completion
        _statusMessage = 'Sending Data $currentFrame / $totalFrames';
        
        String frameHex = (currentFrame & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        String frameHex2 = ((currentFrame >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        _addLog('→ TX: $frameHex $frameHex2 [60 bytes data...] (Frame $currentFrame)', _LogLevel.tx);
        
        for (var b in selectedBoards) {
          b.progress = _progress;
          b.statusMessage = 'Frame $currentFrame/$totalFrames';
        }

        if (currentFrame >= totalFrames) {
          timer.cancel();
          _progress = totalFrames / (totalFrames + 1);
          _statusMessage = 'All frames sent. Waiting 3 seconds before completion signal...';
          _addLog('All frames sent. Waiting 3 seconds before completion signal...', _LogLevel.info);
          
          // Wait 3 seconds before sending completion signal
          Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() {
              _statusMessage = 'Sending Completion Signal (Mock)...';
              _addLog('→ TX: 46 00 00 ... (Completion Signal)', _LogLevel.tx);
            });
            
            // Wait 1.5 seconds to simulate node processing/CRC check and sending replies
            Timer(const Duration(milliseconds: 1500), () {
              if (!mounted) return;
              setState(() {
                _progress = 1.0;
                _isUploading = false;
                _statusMessage = 'Bulk OTA Complete!';
              
              for (int i = 0; i < selectedBoards.length; i++) {
                final b = selectedBoards[i];
                final btHex = b.boardTypeValue.toRadixString(16).padLeft(2, '0').toUpperCase();
                final devHex = b.deviceId.toRadixString(16).padLeft(2, '0').toUpperCase();

                if (i > 0 && Random().nextInt(10) > 7) { // ~20% chance to fail subsequent boards
                  b.status = BoardOtaStatus.error;
                  b.statusMessage = 'Failed (0xE1)';
                  _addLog('← RX [Node ${b.canIdHex}]: E1 $btHex $devHex 00 ... (Error)', _LogLevel.error);
                } else {
                  b.status = BoardOtaStatus.success;
                  b.statusMessage = 'Success';
                  b.progress = 1.0;
                  
                  // Bump version string
                  final oldVer = b.version;
                  String newVer = oldVer;
                  final reg = RegExp(r'v?(\d+)\.(\d+)\.(\d+)');
                  final match = reg.firstMatch(oldVer);
                  if (match != null) {
                    final major = int.parse(match.group(1)!);
                    final minor = int.parse(match.group(2)!);
                    final patch = int.parse(match.group(3)!);
                    newVer = 'v$major.${minor + 1}.$patch';
                  } else {
                    newVer = '$oldVer.1';
                  }
                  b.version = newVer;
                  
                  String verHex = newVer.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
                  _addLog('← RX [Node ${b.canIdHex}]: 79 $btHex $devHex $verHex 00 ... (Complete + Ver: $newVer)', _LogLevel.success);
                }
              }
              _addLog('Mock Bulk OTA Complete', _LogLevel.success);
            });
          });
        });
      }
    });
  });
}

  void _sendManualNextFrame() {
    if (_isMockMode) {
      _triggerNextMockFrame();
    } else {
      _service.triggerNextFrame();
    }
  }

  void _triggerNextMockFrame() {
    if (!_isUploading || !_waitingForManualTrigger) return;

    setState(() {
      if (_mockCurrentFrame == 0) {
        // Send Broadcast Header (Mock)
        _addLog('→ TX: 02 00 00 [Size] [Frames] [CRC] [Board] ... (Header)', _LogLevel.tx);
        
        for (var b in _mockSelectedBoards) {
          b.status = BoardOtaStatus.uploading;
          b.statusMessage = 'Header OK';
          _addLog('← RX [Node ${b.canIdHex}]: 79 00 ... (Header ACK)', _LogLevel.success);
        }
        
        _mockCurrentFrame = 1;
        if (_mockTotalFrames > 0) {
          _statusMessage = 'Manual Mode: Ready to send frame 1/$_mockTotalFrames (Mock). Click "Send Frame" to transmit.';
        } else {
          _statusMessage = 'Manual Mode: Ready to send Completion Signal (Mock). Click "Send Frame" to transmit.';
          _mockCurrentFrame = _mockTotalFrames + 1;
        }
      } else if (_mockCurrentFrame >= 1 && _mockCurrentFrame <= _mockTotalFrames) {
        // Send Data Frame (Mock)
        final k = _mockCurrentFrame;
        _progress = k / (_mockTotalFrames + 1);
        _statusMessage = 'Sending Data $k / $_mockTotalFrames';
        
        String frameHex = (k & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        String frameHex2 = ((k >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        _addLog('→ TX: $frameHex $frameHex2 [60 bytes data...] (Frame $k)', _LogLevel.tx);
        
        for (var b in _mockSelectedBoards) {
          b.progress = _progress;
          b.statusMessage = 'Frame $k/$_mockTotalFrames';
        }

        _mockCurrentFrame++;
        if (_mockCurrentFrame > _mockTotalFrames) {
          _statusMessage = 'Manual Mode: Ready to send Completion Signal (Mock). Click "Send Frame" to transmit.';
        } else {
          _statusMessage = 'Manual Mode: Ready to send frame $_mockCurrentFrame/$_mockTotalFrames (Mock). Click "Send Frame" to transmit.';
        }
      } else if (_mockCurrentFrame == _mockTotalFrames + 1) {
        // Send Completion (Mock)
        _waitingForManualTrigger = false;
        _statusMessage = 'Sending Completion Signal (Mock)...';
        _addLog('→ TX: 46 00 00 ... (Completion Signal)', _LogLevel.tx);
        
        Timer(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          setState(() {
            _progress = 1.0;
            _isUploading = false;
            _statusMessage = 'Bulk OTA Complete!';
            
            for (int i = 0; i < _mockSelectedBoards.length; i++) {
              final b = _mockSelectedBoards[i];
              final btHex = b.boardTypeValue.toRadixString(16).padLeft(2, '0').toUpperCase();
              final devHex = b.deviceId.toRadixString(16).padLeft(2, '0').toUpperCase();

              if (i > 0 && Random().nextInt(10) > 7) { // ~20% chance to fail subsequent boards
                b.status = BoardOtaStatus.error;
                b.statusMessage = 'Failed (0xE1)';
                _addLog('← RX [Node ${b.canIdHex}]: E1 $btHex $devHex 00 ... (Error)', _LogLevel.error);
              } else {
                b.status = BoardOtaStatus.success;
                b.statusMessage = 'Success';
                b.progress = 1.0;
                
                // Bump version string
                final oldVer = b.version;
                String newVer = oldVer;
                final reg = RegExp(r'v?(\d+)\.(\d+)\.(\d+)');
                final match = reg.firstMatch(oldVer);
                if (match != null) {
                  final major = int.parse(match.group(1)!);
                  final minor = int.parse(match.group(2)!);
                  final patch = int.parse(match.group(3)!);
                  newVer = 'v$major.${minor + 1}.$patch';
                } else {
                  newVer = '$oldVer.1';
                }
                b.version = newVer;
                
                String verHex = newVer.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
                _addLog('← RX [Node ${b.canIdHex}]: 79 $btHex $devHex $verHex 00 ... (Complete + Ver: $newVer)', _LogLevel.success);
              }
            }
            _addLog('Mock Bulk OTA Complete', _LogLevel.success);
          });
        });
      }
    });
  }

  // ── Real Logic ──

  Future<void> _pickFile() async {
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
      final firmware = _service.prepareFile(fileName, bytes);

      _addLog('Loaded firmware: $fileName (${firmware.fileSize} bytes)', _LogLevel.info);

      setState(() {
        _firmwareFile = firmware;
      });
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _scanNodes() async {
    if (_isMockMode) {
      _startMockScan();
      return;
    }

    _addLog('Scanning CAN Bus (Tx ID: 0x01) for ${_selectedBoardType.label}...', _LogLevel.info);
    String typeHex = _selectedBoardType.value.toRadixString(16).padLeft(2, '0').toUpperCase();
    _addLog('→ TX: 01 01 $typeHex 00 00 00 00 00', _LogLevel.tx);
    setState(() {
      _isScanning = true;
      _boards.clear();
      _statusMessage = 'Scanning CAN Bus for ${_selectedBoardType.label}...';
    });

    try {
      final results = await _service.scanBoards(
        txCanId: '0x01',
        channel: widget.channel,
        isExtended: widget.isExtended,
        targetBoardType: _selectedBoardType.value,
      );
      
      if (mounted) {
        _addLog('Scan complete: Found ${results.length} nodes.', _LogLevel.success);
        for(var b in results) {
          _addLog('← RX [Node ${b.deviceIdStr}]: ${b.rawHex} (${b.boardTypeName}, Ver: ${b.version})', _LogLevel.rx);
        }
        setState(() {
          _boards = results;
          _isScanning = false;
          _statusMessage = 'Found ${_boards.length} nodes.';
        });
      }
    } catch (e) {
      if (mounted) {
        _addLog('Scan error: $e', _LogLevel.error);
        setState(() {
          _isScanning = false;
          _statusMessage = 'Scan error: $e';
        });
      }
    }
  }

  void _startUpload() {
    if (_isMockMode) {
      _startMockUpload();
      return;
    }

    if (_firmwareFile == null || _boards.isEmpty) return;

    final selectedBoards = _boards.where((b) => b.selected).toList();
    if (selectedBoards.isEmpty) {
      _addLog('❌ Please select at least one board.', _LogLevel.error);
      return;
    }

    // Ensure all selected boards have the same type (for Broadcast OTA)
    final firstType = selectedBoards.first.boardTypeValue;
    final mixedTypes = selectedBoards.any((b) => b.boardTypeValue != firstType);
    if (mixedTypes) {
      _addLog('❌ Cannot broadcast to mixed board types. Select only one type of board.', _LogLevel.error);
      return;
    }

    final delayStr = _delayController.text.trim();
    final delayMs = int.tryParse(delayStr) ?? 0;

    setState(() {
      _isUploading = true;
      _progress = 0.0;
      _statusMessage = 'Starting Bulk OTA...';
      _waitingForManualTrigger = false;
      for (var b in _boards) {
        if (b.selected) {
          b.status = BoardOtaStatus.discovered;
          b.statusMessage = 'Starting...';
        }
      }
    });

    _addLog('Starting Bulk OTA...', _LogLevel.info);

    _service.startBulkUpload(
      _firmwareFile!,
      txCanId: '0x01',
      channel: widget.channel,
      isExtended: widget.isExtended,
      boardTypeValue: firstType, // Infer from the scanned board
      interFrameDelayMs: delayMs,
      selectedBoards: selectedBoards,
      manualMode: _isManualMode,
    ).listen(
      (progress) {
        if (!mounted) return;
        
        final isData = progress.status == BulkUploadStatus.sendingData;

        // Log based on status
        if (progress.status == BulkUploadStatus.sendingHeader || progress.status == BulkUploadStatus.sendingCompletion) {
           _addLog('→ ${progress.message}', _LogLevel.tx);
        } else if (isData) {
           // Service already throttles data frame events to every 25 frames, so we can safely log them
           _addLog('→ ${progress.message}', _LogLevel.tx);
        } else if (progress.status == BulkUploadStatus.waitingManualTrigger) {
           _addLog('⏳ ${progress.message}', _LogLevel.info);
        } else if (progress.boardCanId != null) {
           final isBoardSelected = _boards.any((b) => b.canId == progress.boardCanId && b.selected);
           if (!isBoardSelected) {
             _addLog('← ${progress.message} (Ignored)', _LogLevel.info);
           } else if (progress.boardSuccess == true) {
             _addLog('← ${progress.message}', _LogLevel.success);
           } else {
             _addLog('← ${progress.message}', _LogLevel.error);
           }
        } else if (progress.status == BulkUploadStatus.complete) {
           _addLog('✅ ${progress.message}', _LogLevel.success);
        } else if (progress.status == BulkUploadStatus.error) {
           _addLog('❌ ${progress.message}', _LogLevel.error);
        }

        setState(() {
          _progress = progress.percent;
          _statusMessage = progress.message;
          _waitingForManualTrigger = progress.status == BulkUploadStatus.waitingManualTrigger;

          // Update per-board progress for all selected boards during data phase
          if (progress.status == BulkUploadStatus.sendingData) {
            for (var b in _boards) {
              if (b.selected && b.status == BoardOtaStatus.uploading) {
                b.progress = progress.percent;
                b.statusMessage = 'Frame ${progress.currentFrame}/${progress.totalFrames}';
              }
            }
          }

          if (progress.status == BulkUploadStatus.complete) {
            for (var b in _boards) {
              if (b.selected && b.status == BoardOtaStatus.uploading) {
                b.status = BoardOtaStatus.success;
                b.statusMessage = 'Success';
                b.progress = 1.0;
              }
            }
          }
          
          if (progress.boardCanId != null) {
            final idx = _boards.indexWhere((b) => b.canId == progress.boardCanId);
            if (idx != -1 && _boards[idx].selected) {
              if (progress.status == BulkUploadStatus.waitingHeaderAck || progress.status == BulkUploadStatus.waitingCompletionAck) {
                if (progress.boardSuccess == true) {
                  _boards[idx].status = progress.status == BulkUploadStatus.waitingCompletionAck ? BoardOtaStatus.success : BoardOtaStatus.uploading;
                  _boards[idx].statusMessage = progress.status == BulkUploadStatus.waitingCompletionAck ? 'Success' : 'Header ACKed';
                  if (progress.status == BulkUploadStatus.waitingCompletionAck) {
                    _boards[idx].progress = 1.0;
                    if (progress.boardNewVersion != null) {
                      _boards[idx].version = progress.boardNewVersion!;
                    }
                  }
                } else if (progress.boardSuccess == false) {
                  _boards[idx].status = BoardOtaStatus.error;
                  _boards[idx].statusMessage = 'Error/NACK';
                }
              }
            }
          }
          
          if (progress.status == BulkUploadStatus.complete || 
              progress.status == BulkUploadStatus.error || 
              progress.status == BulkUploadStatus.cancelled) {
            _isUploading = false;
            _waitingForManualTrigger = false;
          }
        });
      },
      onError: (error) {
        setState(() {
          _isUploading = false;
          _waitingForManualTrigger = false;
          _statusMessage = 'Error: $error';
        });
      },
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDarkest,
      appBar: AppBar(
        backgroundColor: AppTheme.panelHeader,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Bulk CAN OTA Updater',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textBright,
          ),
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mock Mode', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(width: 4),
              Switch(
                value: _isMockMode, 
                onChanged: _isUploading || _isScanning ? null : (v) => setState(() => _isMockMode = v),
                activeColor: AppTheme.accentOrange,
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _pickFile,
                      icon: const Icon(Icons.folder),
                      label: Text(_firmwareFile != null ? _firmwareFile!.fileName : 'Select Firmware (.bin)'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.bgInput, foregroundColor: AppTheme.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isScanning || _isUploading ? null : _scanNodes,
                    icon: _isScanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search),
                    label: const Text('Scan Bus'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentCyan, foregroundColor: Colors.white),
                  )
                ],
              ),
              const SizedBox(height: 15),
  
              if (_firmwareFile != null)
                Row(
                  children: [
                    Expanded(child: _buildStatCard(Icons.sd_storage, 'File Size', '${(_firmwareFile!.fileSize / 1024).toStringAsFixed(1)} KB', const Color(0xFFF0F4FF), const Color(0xFF4A6BFF))),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatCard(Icons.view_agenda, 'Frames', '${_firmwareFile!.frameCount}', const Color(0xFFF2FAF7), const Color(0xFF22A082))),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatCard(Icons.verified, 'CRC-16', '0x${_firmwareFile!.fileCrc.toRadixString(16).padLeft(4, '0').toUpperCase()}', const Color(0xFFFFF8EE), const Color(0xFFE89A36))),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatCard(Icons.data_object, 'Chunk', '60 B', const Color(0xFFF4F5F8), const Color(0xFF758CA3))),
                  ],
                ),
              
              if (_firmwareFile != null) const SizedBox(height: 15),
  
              // Middle section (Side by side)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Nodes Grid
                    Expanded(
                      flex: 4,
                      child: Container(
                        decoration: BoxDecoration(color: AppTheme.bgDarkest, borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.all(10),
                        child: _boards.isEmpty 
                          ? Center(child: Text(_isScanning ? 'Scanning...' : 'No nodes found. Click Scan Bus.', style: GoogleFonts.inter(color: AppTheme.textMuted)))
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 250,
                                mainAxisExtent: 130,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _boards.length,
                              itemBuilder: (context, index) {
                                final b = _boards[index];
                                
                                Color statusColor = AppTheme.textSecondary;
                                IconData icon = Icons.device_hub;
                                if (b.status == BoardOtaStatus.success) {
                                  statusColor = AppTheme.successColor;
                                  icon = Icons.check_circle;
                                } else if (b.status == BoardOtaStatus.error) {
                                  statusColor = AppTheme.errorColor;
                                  icon = Icons.error;
                                } else if (b.status == BoardOtaStatus.uploading) {
                                  statusColor = AppTheme.primaryColor;
                                  icon = Icons.sync;
                                }
  
                                return Container(
                                  decoration: BoxDecoration(
                                    color: b.selected ? AppTheme.bgCard : AppTheme.bgCard.withOpacity(0.4),
                                    border: Border.all(color: b.selected ? statusColor.withOpacity(0.5) : AppTheme.borderColor.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 20, height: 20,
                                            child: Checkbox(
                                              value: b.selected,
                                              onChanged: _isUploading ? null : (val) {
                                                setState(() => b.selected = val ?? true);
                                              },
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              activeColor: AppTheme.primaryColor,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(icon, size: 14, color: statusColor),
                                          const SizedBox(width: 4),
                                          Expanded(child: Text('Node ${b.deviceIdStr}', style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textPrimary))),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(b.boardTypeName, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                                      const SizedBox(height: 2),
                                      Text('Version: ${b.version}', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                      Text('Status: ${b.statusMessage}', style: GoogleFonts.inter(fontSize: 11, color: statusColor)),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: b.progress,
                                          minHeight: 5,
                                          backgroundColor: AppTheme.bgDarkest,
                                          valueColor: AlwaysStoppedAnimation(
                                            b.status == BoardOtaStatus.success ? AppTheme.successColor :
                                            b.status == BoardOtaStatus.error ? AppTheme.errorColor :
                                            AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                    
                    const SizedBox(width: 10),
  
                    // Transfer Log Panel
                    Expanded(
                      flex: 4,
                      child: _buildLogSection(),
                    ),
                  ],
                ),
              ),
  
              const SizedBox(height: 10),
              // Progress Bar
              LinearProgressIndicator(value: _progress, backgroundColor: AppTheme.bgDark, valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text(_statusMessage, style: GoogleFonts.jetBrainsMono(color: AppTheme.textSecondary))),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Manual Mode', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
                      const SizedBox(width: 4),
                      Switch(
                        value: _isManualMode,
                        onChanged: _isUploading ? null : (v) => setState(() => _isManualMode = v),
                        activeColor: AppTheme.accentOrange,
                      ),
                    ],
                  ),
                  const SizedBox(width: 15),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      controller: _delayController,
                      decoration: const InputDecoration(
                        labelText: 'Delay ms',
                        filled: true,
                        fillColor: AppTheme.bgInput,
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_isUploading && !_isManualMode,
                      style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppTheme.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_isUploading) ...[
                    if (_waitingForManualTrigger) ...[
                      ElevatedButton.icon(
                        onPressed: _sendManualNextFrame,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Send Frame'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor, foregroundColor: Colors.white),
                      ),
                      const SizedBox(width: 10),
                    ],
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_isMockMode) {
                          _mockTimer?.cancel();
                          setState(() {
                            _isUploading = false;
                            _waitingForManualTrigger = false;
                            _statusMessage = 'Mock Upload Cancelled';
                            _addLog('Mock upload cancelled by user.', _LogLevel.warning);
                          });
                        } else {
                          _service.cancel();
                          _addLog('Cancellation requested by user.', _LogLevel.warning);
                        }
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop OTA'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
                    ),
                  ] else
                    ElevatedButton.icon(
                      onPressed: _boards.isEmpty || _firmwareFile == null ? null : _startUpload,
                      icon: const Icon(Icons.upload),
                      label: const Text('Start Bulk OTA'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(children: [
              const Icon(Icons.terminal_rounded, size: 12, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Text('Transfer Log', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
              const Spacer(),
              Text('${_log.length} entries', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: const Color(0xFF64748B))),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => setState(() => _log.clear()),
                child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
              ),
            ]),
          ),
          Expanded(
            child: Scrollbar(
              controller: _logScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                itemCount: _log.length,
                itemBuilder: (context, index) {
                  final entry = _log[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.timestamp, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF64748B))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(entry.message, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: entry.color)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildStatCard(IconData icon, String title, String value, Color bgColor, Color fgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fgColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: fgColor.withOpacity(0.8)),
              const SizedBox(width: 6),
              Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: fgColor.withOpacity(0.8))),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.bold, color: fgColor)),
        ],
      ),
    );
  }
}

enum _LogLevel { info, tx, rx, success, warning, error }

class _LogEntry {
  final String timestamp;
  final String message;
  final _LogLevel level;
  _LogEntry({required this.timestamp, required this.message, required this.level});

  Color get color {
    switch (level) {
      case _LogLevel.info: return const Color(0xFF94A3B8);
      case _LogLevel.tx: return const Color(0xFF60A5FA);
      case _LogLevel.rx: return const Color(0xFF4ADE80);
      case _LogLevel.success: return const Color(0xFF22C55E);
      case _LogLevel.warning: return const Color(0xFFFBBF24);
      case _LogLevel.error: return const Color(0xFFEF4444);
    }
  }
}
