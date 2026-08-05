import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/config/can_config.dart';
import '../../../core/services/serial_port_service.dart';
import '../../../utils/theme/app_theme.dart';

enum ChangeSnStep {
  idle,
  step1Scan100k,
  step2SnDetected,
  step3Bootloader100k,
  step4Switch250k,
  step5SendSn250k,
  step6BackToApp250k,
  step7Switch100k,
  complete,
}

typedef ChangeSerialNoDialog = ChangeSerialNoScreen;

class ChangeSerialNoScreen extends StatefulWidget {
  final SerialPortService serialService;
  final int channel;
  final bool isFD;

  const ChangeSerialNoScreen({
    super.key,
    required this.serialService,
    required this.channel,
    required this.isFD,
  });

  @override
  State<ChangeSerialNoScreen> createState() => _ChangeSerialNoScreenState();
}

class _ChangeSerialNoScreenState extends State<ChangeSerialNoScreen> {
  final TextEditingController _snController = TextEditingController();
  final TextEditingController _canId100kController = TextEditingController(text: '000000FF');
  final TextEditingController _canId250kController = TextEditingController(text: '00000001');
  final ScrollController _logScrollController = ScrollController();

  ChangeSnStep _currentStep = ChangeSnStep.idle;
  bool _isAutoScanning = false;
  bool _isProceeding = false;
  String _lastDetectedSn = '';
  final List<String> _logs = [];

  Function(Map<String, dynamic>)? _oldCanFrameRx;
  Function(Uint8List)? _oldDataReceived;

  @override
  void initState() {
    super.initState();
    _setupRxInterceptors();
    _addLog('System initialized. Click "Start Scan (100 kbps)" to begin.', Colors.cyan);
  }

  void _setupRxInterceptors() {
    _oldCanFrameRx = widget.serialService.onCanFrameRx;
    _oldDataReceived = widget.serialService.onDataReceived;

    if (!widget.serialService.isCanMode) {
      widget.serialService.onDataReceived = (data) {
        if (_oldDataReceived != null) _oldDataReceived!(data);
        _handleIncomingRawSerial(data);
      };
    } else {
      widget.serialService.onCanFrameRx = (frame) {
        if (_oldCanFrameRx != null) _oldCanFrameRx!(frame);
        _handleIncomingCanFrame(frame);
      };
    }
  }

  @override
  void dispose() {
    widget.serialService.onCanFrameRx = _oldCanFrameRx;
    widget.serialService.onDataReceived = _oldDataReceived;
    _snController.dispose();
    _canId100kController.dispose();
    _canId250kController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String msg, [Color? color]) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    if (!mounted) return;
    setState(() {
      _logs.add('[$ts] $msg');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<int> _parseDataHex(String? dataHex) {
    if (dataHex == null || dataHex.isEmpty) return [];
    try {
      return dataHex
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((p) => int.parse(p, radix: 16))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _handleIncomingRawSerial(Uint8List data) {
    if (data.isEmpty) return;
    final printable = data.where((b) => b >= 32 && b <= 126).toList();
    if (printable.isNotEmpty) {
      final sn = String.fromCharCodes(printable).trim();
      if (sn.length >= 2) {
        _onSerialNumberDetected(sn);
      }
    }
  }

  Completer<bool>? _okCompleter;

  Future<bool> _waitForOkResponse({Duration timeout = const Duration(seconds: 3)}) async {
    _okCompleter = Completer<bool>();
    try {
      return await _okCompleter!.future.timeout(timeout);
    } catch (_) {
      return false;
    } finally {
      _okCompleter = null;
    }
  }

  void _handleIncomingCanFrame(Map<String, dynamic> frame) {
    final canId = frame['canId']?.toString() ?? '';
    final dataHex = frame['dataHex']?.toString() ?? '';
    final rawBytes = _parseDataHex(dataHex);

    if (rawBytes.isEmpty) return;

    // Check for OK response (4F 4B)
    final asciiStr = String.fromCharCodes(rawBytes).trim().toUpperCase();
    final isOk = (rawBytes.length >= 2 && rawBytes[0] == 0x4F && rawBytes[1] == 0x4B) ||
        asciiStr == 'OK' ||
        asciiStr.startsWith('OK');

    if (isOk) {
      _addLog('← RX CAN [$canId]: 4F 4B (OK)', AppTheme.successColor);
      if (_okCompleter != null && !_okCompleter!.isCompleted) {
        _okCompleter!.complete(true);
      }
    } else {
      _addLog('← RX CAN [$canId]: $dataHex', AppTheme.textSecondary);
    }

    // Check for Serial Number response
    bool isSerialResponse = false;
    List<int> asciiBytes = [];

    if (rawBytes.length >= 2 && rawBytes[0] == 0x01 && rawBytes[1] == 0x02) {
      isSerialResponse = true;
      asciiBytes = rawBytes.sublist(2).where((b) => b >= 32 && b <= 126).toList();
    } else {
      final printable = rawBytes.where((b) => b >= 32 && b <= 126).toList();
      if (printable.length >= 3 && printable.length >= rawBytes.length - 1) {
        isSerialResponse = true;
        asciiBytes = printable;
      }
    }

    if (isSerialResponse) {
      String sn = String.fromCharCodes(asciiBytes).trim();
      if (sn.isNotEmpty && sn.length >= 2) {
        _onSerialNumberDetected(sn);
      }
    }
  }

  void _onSerialNumberDetected(String sn) {
    if (_lastDetectedSn != sn) {
      _lastDetectedSn = sn;
      _addLog('✓ RX Serial Number from Device: "$sn"', AppTheme.successColor);
    }
    if (mounted && _snController.text != sn && !_isProceeding) {
      setState(() {
        _snController.text = sn;
        _currentStep = ChangeSnStep.step2SnDetected;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEQUENCE CONTROLLER
  // ═══════════════════════════════════════════════════════════════

  Future<void> _startScanSequence() async {
    if (!widget.serialService.isConnected) {
      _addLog('❌ Cannot start sequence: USB port not connected.', AppTheme.errorColor);
      return;
    }

    setState(() {
      _isAutoScanning = true;
      _currentStep = ChangeSnStep.step1Scan100k;
    });

    _addLog('--- STEP 1: Setting CAN Baud Rate to 100 kbps ---', AppTheme.primaryColor);
    final baud100kOk = await widget.serialService.setCanBaudRate(CanNominalBaudRate.kbps100);
    if (!baud100kOk) {
      _addLog('❌ STEP 1 ERROR: CAN controller rejected 100 kbps baud rate switch (No 0xA1 ACK).', AppTheme.errorColor);
      setState(() => _isAutoScanning = false);
      return;
    }
    _addLog('✓ Received 0xA1 ACK: CAN Baud Rate set to 100 kbps. Waiting 500ms...', AppTheme.successColor);
    await Future.delayed(const Duration(milliseconds: 500));

    final canId100k = _canId100kController.text.trim();
    final canIdStr = '0x$canId100k';
    _addLog('→ STEP 1: Transmitting Scan Serial Number command (01 02) to $canIdStr at 100 kbps (Expected: ASCII Serial Number)...', AppTheme.accentCyan);

    final frameData = [0x01, 0x02, 0, 0, 0, 0, 0, 0];

    widget.serialService.sendCanFrame(
      canId: canIdStr,
      data: frameData,
      channel: widget.channel,
      isExtended: canIdStr.length > 5,
      isFD: widget.isFD,
    );
  }

  Future<void> _executeProceedSequence() async {
    final rawSn = _snController.text.trim();
    if (rawSn.isEmpty) {
      _addLog('❌ Validation error: Serial Number cannot be empty.', AppTheme.errorColor);
      return;
    }

    if (!widget.serialService.isConnected) {
      _addLog('❌ USB port disconnected.', AppTheme.errorColor);
      return;
    }

    final finalSn = rawSn.toUpperCase().startsWith('SN') ? rawSn : 'SN$rawSn';

    setState(() {
      _isProceeding = true;
      _currentStep = ChangeSnStep.step3Bootloader100k;
    });

    try {
      // ── STEP 2: Send Back to Bootloader 65 72 65 at 100 kbps (Expected: 4F 4B) ──
      final canId100kStr = '0x${_canId100kController.text.trim()}';
      _addLog('--- STEP 2: Sending Back to Bootloader command (65 72 65) to $canId100kStr at 100 kbps (Expected Response: 4F 4B / OK) ---', AppTheme.primaryColor);

      final bootloaderData = [0x65, 0x72, 0x65, 0, 0, 0, 0, 0];
      
      _okCompleter = Completer<bool>();
      widget.serialService.sendCanFrame(
        canId: canId100kStr,
        data: bootloaderData,
        channel: widget.channel,
        isExtended: canId100kStr.length > 5,
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response from $canId100kStr...', AppTheme.accentOrange);
      final ok1 = await _waitForOkResponse(timeout: const Duration(seconds: 3));

      if (!ok1) {
        _addLog('❌ STEP 2 TIMEOUT: No 4F 4B (OK) response received from $canId100kStr for Bootloader command. SEQUENCE ABORTED.', AppTheme.errorColor);
        setState(() {
          _isProceeding = false;
          _currentStep = ChangeSnStep.idle;
        });
        return;
      }

      _addLog('✓ STEP 2 SUCCESS: Received 4F 4B (OK) from $canId100kStr. Waiting 500ms...', AppTheme.successColor);
      await Future.delayed(const Duration(milliseconds: 500));

      // ── STEP 3: Switch CAN Baud Rate to 250 kbps (Expected: 0xA1 ACK) ──
      setState(() => _currentStep = ChangeSnStep.step4Switch250k);
      _addLog('--- STEP 3: Switching CAN Baud Rate to 250 kbps (Expected Response: 0xA1 ACK) ---', AppTheme.accentOrange);

      final switch250kOk = await widget.serialService.setCanBaudRate(CanNominalBaudRate.kbps250);
      if (!switch250kOk) {
        _addLog('❌ STEP 3 ERROR: No 0xA1 ACK received when switching baud rate to 250 kbps. SEQUENCE ABORTED.', AppTheme.errorColor);
        setState(() {
          _isProceeding = false;
          _currentStep = ChangeSnStep.idle;
        });
        return;
      }
      _addLog('✓ STEP 3 SUCCESS: Received 0xA1 ACK. CAN Baud Rate set to 250 kbps. Waiting 500ms...', AppTheme.successColor);
      await Future.delayed(const Duration(milliseconds: 500));

      // ── STEP 4: Send SN Command at 250 kbps to 0x00000001 (Expected: 4F 4B) ──
      setState(() => _currentStep = ChangeSnStep.step5SendSn250k);
      final canId250kStr = '0x${_canId250kController.text.trim()}';
      _addLog('--- STEP 4: Transmitting Serial Number "$finalSn" to $canId250kStr at 250 kbps (Expected Response: 4F 4B / OK) ---', AppTheme.primaryColor);

      List<int> snPayload = finalSn.codeUnits;

      _okCompleter = Completer<bool>();
      widget.serialService.sendCanFrame(
        canId: canId250kStr,
        data: snPayload,
        channel: widget.channel,
        isExtended: canId250kStr.length > 5,
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response for Serial Number write from $canId250kStr...', AppTheme.accentOrange);
      final ok2 = await _waitForOkResponse(timeout: const Duration(seconds: 3));

      if (!ok2) {
        _addLog('❌ STEP 4 TIMEOUT: No 4F 4B (OK) response received from $canId250kStr for Serial Number write. SEQUENCE ABORTED.', AppTheme.errorColor);
        setState(() {
          _isProceeding = false;
          _currentStep = ChangeSnStep.idle;
        });
        return;
      }

      _addLog('✓ STEP 4 SUCCESS: Received 4F 4B (OK) for Serial Number write from $canId250kStr. Waiting 500ms...', AppTheme.successColor);
      await Future.delayed(const Duration(milliseconds: 500));

      // ── STEP 5: Send Back to App (46 4A 41) at 250 kbps (Expected: 4F 4B) ──
      setState(() => _currentStep = ChangeSnStep.step6BackToApp250k);
      _addLog('--- STEP 5: Sending Back to App command (46 4A 41 / FJA) to $canId250kStr at 250 kbps (Expected Response: 4F 4B / OK) ---', AppTheme.accentCyan);

      final backToAppData = [0x46, 0x4A, 0x41, 0, 0, 0, 0, 0];
      
      _okCompleter = Completer<bool>();
      widget.serialService.sendCanFrame(
        canId: canId250kStr,
        data: backToAppData,
        channel: widget.channel,
        isExtended: canId250kStr.length > 5,
        isFD: widget.isFD,
      );

      _addLog('Waiting for 4F 4B (OK) response for Back to App command from $canId250kStr...', AppTheme.accentOrange);
      final ok3 = await _waitForOkResponse(timeout: const Duration(seconds: 3));

      if (!ok3) {
        _addLog('❌ STEP 5 TIMEOUT: No 4F 4B (OK) response received from $canId250kStr for Back to App command. SEQUENCE ABORTED.', AppTheme.errorColor);
        setState(() {
          _isProceeding = false;
          _currentStep = ChangeSnStep.idle;
        });
        return;
      }

      _addLog('✓ STEP 5 SUCCESS: Received 4F 4B (OK) for Back to App command from $canId250kStr. Waiting 500ms...', AppTheme.successColor);
      await Future.delayed(const Duration(milliseconds: 500));

      // ── STEP 6: Switch back to 100 kbps & Resume Scan Loop (Expected: 0xA1 ACK) ──
      setState(() => _currentStep = ChangeSnStep.step7Switch100k);
      _addLog('--- STEP 6: Re-configuring CAN Baud Rate back to 100 kbps (Expected Response: 0xA1 ACK) ---', AppTheme.accentOrange);

      final switch100kOk = await widget.serialService.setCanBaudRate(CanNominalBaudRate.kbps100);
      if (!switch100kOk) {
        _addLog('❌ STEP 6 ERROR: No 0xA1 ACK received when switching baud rate back to 100 kbps. SEQUENCE ABORTED.', AppTheme.errorColor);
        setState(() {
          _isProceeding = false;
          _currentStep = ChangeSnStep.idle;
        });
        return;
      }

      _addLog('✓ STEP 6 SUCCESS: Received 0xA1 ACK. Switched back to 100 kbps. Resuming scan loop...', AppTheme.successColor);
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _currentStep = ChangeSnStep.complete;
        _isProceeding = false;
      });

      _addLog('🎉 SUCCESS: All 6 steps completed cleanly with verified responses!', AppTheme.successColor);
    } catch (e) {
      _addLog('❌ Error in sequence: $e', AppTheme.errorColor);
      setState(() {
        _isProceeding = false;
      });
    }
  }



  // ═══════════════════════════════════════════════════════════════
  //  BUILD UI
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final canProceed = _snController.text.trim().isNotEmpty && !_isProceeding;

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
          'Change Serial No Routine',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textBright,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step Progress Bar
              _buildStepProgressBar(),
              const SizedBox(height: 16),

              // Main Input Panel & Log Row
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Pane: Controls & Inputs
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.bgMedium,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 100k & 250k CAN ID configuration
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('100k CAN ID', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          height: 34,
                                          child: TextField(
                                            controller: _canId100kController,
                                            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.textPrimary),
                                            decoration: const InputDecoration(
                                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('250k CAN ID', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          height: 34,
                                          child: TextField(
                                            controller: _canId250kController,
                                            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.textPrimary),
                                            decoration: const InputDecoration(
                                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Step 1 Trigger Button
                              SizedBox(
                                height: 38,
                                child: ElevatedButton.icon(
                                  onPressed: _isProceeding ? null : _startScanSequence,
                                  icon: const Icon(Icons.search_rounded, size: 16),
                                  label: Text(
                                    _isAutoScanning ? 'Rescan 100k Serial' : '1. Start Scan (100 kbps)',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              const Divider(color: AppTheme.borderColor),
                              const SizedBox(height: 12),

                              // Serial Number Input
                              Text(
                                'Target Device Serial Number',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _snController,
                                  onChanged: (val) => setState(() {}),
                                  style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textBright),
                                  decoration: InputDecoration(
                                    hintText: 'Enter or Scan Serial Number',
                                    hintStyle: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                                    prefixIcon: const Icon(Icons.fingerprint, size: 18, color: AppTheme.accentOrange),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // PROCEED BUTTON
                              SizedBox(
                                height: 42,
                                child: ElevatedButton.icon(
                                  onPressed: canProceed ? _executeProceedSequence : null,
                                  icon: _isProceeding
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.play_arrow_rounded, size: 20),
                                  label: Text(
                                    _isProceeding ? 'Proceeding Routine...' : 'Proceed (Write SN & Switch 250k)',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.successColor,
                                    disabledBackgroundColor: AppTheme.bgDarkest,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Right Pane: Activity Trace Log
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgDarkest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Sequence Trace Log',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppTheme.textMuted),
                                  tooltip: 'Clear Trace Log',
                                  onPressed: () => setState(() => _logs.clear()),
                                ),
                              ],
                            ),
                            const Divider(height: 1, color: AppTheme.borderColor),
                            const SizedBox(height: 6),
                            Expanded(
                              child: ListView.builder(
                                controller: _logScrollController,
                                itemCount: _logs.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      _logs[index],
                                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textPrimary),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepProgressBar() {
    final stepIndex = _currentStep.index;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgMedium,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stepBadge(1, '100k Scan', stepIndex >= 1),
          _stepDivider(),
          _stepBadge(2, 'Bootloader (65 72 65)', stepIndex >= 3),
          _stepDivider(),
          _stepBadge(3, '250k Switch', stepIndex >= 4),
          _stepDivider(),
          _stepBadge(4, 'Write SN', stepIndex >= 5),
          _stepDivider(),
          _stepBadge(5, 'App (46 4A 41)', stepIndex >= 6),
          _stepDivider(),
          _stepBadge(6, '100k Loop', stepIndex >= 7),
        ],
      ),
    );
  }

  Widget _stepBadge(int num, String label, bool active) {
    final color = active ? AppTheme.successColor : AppTheme.textMuted;
    return Row(
      children: [
        CircleAvatar(
          radius: 9,
          backgroundColor: active ? AppTheme.successColor : AppTheme.bgDarkest,
          child: Text(
            '$num',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active ? Colors.black : AppTheme.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _stepDivider() {
    return Container(width: 12, height: 1, color: AppTheme.borderColor);
  }
}
