import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/firmware_upload_service.dart';
import '../../../core/services/serial_port_service.dart';
import '../../../utils/theme/app_theme.dart';

/// Professional firmware upload dialog with file picker, CAN ID, progress, and log.
class FirmwareUploadDialog extends StatefulWidget {
  final SerialPortService serialService;
  final bool isFD;
  final int channel;

  const FirmwareUploadDialog({
    super.key,
    required this.serialService,
    required this.isFD,
    required this.channel,
  });

  @override
  State<FirmwareUploadDialog> createState() => _FirmwareUploadDialogState();
}

class _FirmwareUploadDialogState extends State<FirmwareUploadDialog>
    with SingleTickerProviderStateMixin {
  late final FirmwareUploadService _uploadService;
  late final AnimationController _pulseController;
  final TextEditingController _canIdController = TextEditingController(text: '00 00 00 01');
  final TextEditingController _delayController = TextEditingController(text: '0');

  FirmwareFile? _firmwareFile;
  String? _selectedFilePath;
  bool _isUploading = false;
  bool _isComplete = false;
  double _progress = 0;
  int _currentFrame = 0;
  int _totalFrames = 0;
  UploadStatus _status = UploadStatus.idle;
  
  bool _sendCrcInHeader = true;
  bool _sendCrcInData = true;
  final List<_LogEntry> _log = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _uploadService = FirmwareUploadService(widget.serialService);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _logScrollController.dispose();
    _canIdController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  // ── File Selection ──

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
      if (!await file.exists()) {
        _addLog('File not found: $path', _LogLevel.error);
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _addLog('File is empty.', _LogLevel.error);
        return;
      }

      final fileName = path.split(RegExp(r'[/\\]')).last;
      final firmware = _uploadService.prepareFile(fileName, bytes);

      setState(() {
        _selectedFilePath = path;
        _firmwareFile = firmware;
        _isComplete = false;
        _progress = 0;
        _currentFrame = 0;
        _totalFrames = firmware.frameCount;
        _status = UploadStatus.idle;
      });

      _addLog(
        'File loaded: $fileName (${firmware.fileSize} bytes, '
        '${firmware.frameCount} frames, CRC: 0x${firmware.fileCrc.toRadixString(16).toUpperCase().padLeft(4, '0')})',
        _LogLevel.info,
      );
    } catch (e) {
      _addLog('Error picking file: $e', _LogLevel.error);
    }
  }

  // ── Upload ──

  String _getCanIdHex() {
    final raw = _canIdController.text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (raw.isEmpty) return '0x1';
    return '0x$raw';
  }

  Future<void> _startUpload() async {
    if (_firmwareFile == null || _isUploading) return;

    final canIdHex = _getCanIdHex();

    setState(() {
      _isUploading = true;
      _isComplete = false;
      _progress = 0;
      _log.clear();
    });
    _pulseController.repeat(reverse: true);

    _addLog('Starting firmware upload (CAN ID: $canIdHex, ${widget.isFD ? "CAN FD" : "Classic CAN"})...', _LogLevel.info);

    final delayMs = int.tryParse(_delayController.text) ?? 0;

    await for (final event in _uploadService.startUpload(
      _firmwareFile!,
      canId: canIdHex,
      channel: widget.channel,
      isExtended: canIdHex.replaceAll('0x', '').length > 3,
      isFD: widget.isFD,
      sendCrcInHeader: _sendCrcInHeader,
      sendCrcInData: _sendCrcInData,
      interFrameDelayMs: delayMs,
    )) {
      if (!mounted) return;

      setState(() {
        _status = event.status;
        _currentFrame = event.currentFrame;
        _totalFrames = event.totalFrames;
        _progress = event.percent;
      });

      switch (event.status) {
        case UploadStatus.sendingHeader:
          _addLog('→ ${event.message}', _LogLevel.tx);
          break;
        case UploadStatus.waitingHeaderAck:
          _addLog('→ ${event.message}', _LogLevel.tx);
          break;
        case UploadStatus.sendingFrame:
          if (event.message.contains('acknowledged')) {
            _addLog('← OK received ✓', _LogLevel.rx);
          } else {
            _addLog('→ ${event.message}', _LogLevel.tx);
          }
          break;
        case UploadStatus.waitingFrameAck:
          _addLog('⏳ ${event.message}', _LogLevel.info);
          break;
        case UploadStatus.complete:
          _addLog('✅ ${event.message}', _LogLevel.success);
          setState(() { _isComplete = true; _isUploading = false; _progress = 1.0; });
          _pulseController.stop();
          break;
        case UploadStatus.error:
          _addLog('❌ ${event.message}', _LogLevel.error);
          setState(() { _isUploading = false; });
          _pulseController.stop();
          break;
        case UploadStatus.cancelled:
          _addLog('⚠ ${event.message}', _LogLevel.warning);
          setState(() { _isUploading = false; });
          _pulseController.stop();
          break;
        case UploadStatus.idle:
          break;
      }
    }
  }

  void _cancelUpload() {
    _uploadService.cancel();
    _addLog('Cancel requested by user...', _LogLevel.warning);
  }

  void _addLog(String message, _LogLevel level) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    setState(() {
      _log.add(_LogEntry(timestamp: ts, message: message, level: level));
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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 850),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor),
          boxShadow: const [
            BoxShadow(color: Color(0x30000000), blurRadius: 40, offset: Offset(0, 16)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: AppTheme.borderColor),
              _buildFileSection(),
              _buildConfigurationPanel(),
              if (_firmwareFile != null) ...[
                const Divider(height: 1, color: AppTheme.borderLight),
                _buildInfoCards(),
              ],
              if (_isUploading || _isComplete || _log.isNotEmpty) ...[
                const Divider(height: 1, color: AppTheme.borderLight),
                _buildProgressSection(),
              ],
              if (_log.isNotEmpty) ...[
                const Divider(height: 1, color: AppTheme.borderLight),
                _buildLogSection(),
              ],
              const Divider(height: 1, color: AppTheme.borderColor),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.panelHeader,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppTheme.primaryColor, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.memory_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Firmware Upload', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textBright, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text(
                  'Upload binary firmware via ${widget.isFD ? "CAN FD" : "Classic CAN"}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_isUploading)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.warningColor.withValues(alpha: 0.5 + _pulseController.value * 0.5),
                  boxShadow: [BoxShadow(color: AppTheme.warningColor.withValues(alpha: 0.3 + _pulseController.value * 0.3), blurRadius: 8)],
                ),
              ),
            )
          else if (_isComplete)
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppTheme.successColor,
                boxShadow: [BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.5), blurRadius: 8)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Material(
        color: AppTheme.bgInput.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _isUploading ? null : _pickFile,
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppTheme.primaryColor.withValues(alpha: 0.05),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.borderColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Icon(
                  _firmwareFile != null ? Icons.check_circle_outline_rounded : Icons.cloud_upload_outlined,
                  size: 36,
                  color: _firmwareFile != null ? AppTheme.successColor : AppTheme.primaryColor.withValues(alpha: 0.8),
                ),
                const SizedBox(height: 12),
                Text(
                  _selectedFilePath != null ? _selectedFilePath!.split(RegExp(r'[/\\]')).last : 'Click to browse firmware binary',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _selectedFilePath != null ? AppTheme.textPrimary : AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                if (_selectedFilePath == null) ...[
                  const SizedBox(height: 6),
                  Text('Supports .bin files for CAN protocol upload', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Configuration Panel ──

  Widget _buildConfigurationPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target CAN ID', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _canIdController,
                    enabled: !_isUploading,
                    style: GoogleFonts.jetBrainsMono(fontSize: 15, letterSpacing: 1.0, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '00 00 00 01',
                      hintStyle: GoogleFonts.jetBrainsMono(fontSize: 15, letterSpacing: 1.0, color: AppTheme.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                    onChanged: (value) {
                      final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
                      final buffer = StringBuffer();
                      for (var i = 0; i < compact.length; i++) {
                        if (i > 0 && i % 2 == 0) buffer.write(' ');
                        buffer.write(compact[i]);
                      }
                      final normalized = buffer.toString();
                      if (normalized != value) {
                        _canIdController.value = TextEditingValue(
                          text: normalized,
                          selection: TextSelection.collapsed(offset: normalized.length),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 50, color: AppTheme.borderColor),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Inter-frame Delay', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _delayController,
                    enabled: !_isUploading,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: 'ms',
                      suffixStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 50, color: AppTheme.borderColor),
          const SizedBox(width: 16),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protocol Options', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        _buildCheckbox('Header CRC', _sendCrcInHeader, (val) => setState(() => _sendCrcInHeader = val ?? true)),
                        const SizedBox(width: 12),
                        _buildCheckbox('Data CRC', _sendCrcInData, (val) => setState(() => _sendCrcInData = val ?? true)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.75,
          child: Switch(
            value: value,
            onChanged: _isUploading ? null : (val) => onChanged(val),
            activeColor: AppTheme.primaryColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCards() {
    final fw = _firmwareFile!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          _infoCard(icon: Icons.straighten_rounded, label: 'File Size', value: _formatBytes(fw.fileSize), color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          _infoCard(icon: Icons.view_agenda_rounded, label: 'Frames', value: '${fw.frameCount}', color: AppTheme.accentCyan),
          const SizedBox(width: 10),
          _infoCard(icon: Icons.verified_rounded, label: 'CRC-16', value: '0x${fw.fileCrc.toRadixString(16).toUpperCase().padLeft(4, '0')}', color: AppTheme.accentOrange),
          const SizedBox(width: 10),
          _infoCard(icon: Icons.data_array_rounded, label: 'Chunk', value: '60 B', color: AppTheme.textSecondary),
        ],
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 13, color: color), const SizedBox(width: 5),
              Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.textMuted, letterSpacing: 0.3)),
            ]),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    final String statusLabel;
    final Color statusColor;
    switch (_status) {
      case UploadStatus.sendingHeader:
      case UploadStatus.waitingHeaderAck:
        statusLabel = 'Sending header...'; statusColor = AppTheme.warningColor; break;
      case UploadStatus.sendingFrame:
      case UploadStatus.waitingFrameAck:
        statusLabel = 'Frame $_currentFrame / $_totalFrames'; statusColor = AppTheme.primaryColor; break;
      case UploadStatus.complete:
        statusLabel = 'Upload complete!'; statusColor = AppTheme.successColor; break;
      case UploadStatus.error:
        statusLabel = 'Upload failed'; statusColor = AppTheme.errorColor; break;
      case UploadStatus.cancelled:
        statusLabel = 'Upload cancelled'; statusColor = AppTheme.warningColor; break;
      case UploadStatus.idle:
        statusLabel = 'Ready'; statusColor = AppTheme.textMuted; break;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(statusLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
            const Spacer(),
            Text('${(_progress * 100).toStringAsFixed(0)}%', style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _progress, minHeight: 6, backgroundColor: AppTheme.bgDark, valueColor: AlwaysStoppedAnimation<Color>(statusColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogSection() {
    return Container(
      height: 320,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
            ]),
          ),
          Expanded(
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
                      Text(entry.timestamp, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF64748B))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.message, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: entry.color))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.panelHeader,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          if (_firmwareFile != null && !_isUploading && !_isComplete)
            Text('Ready to upload ${_firmwareFile!.frameCount} frames', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
          if (_isUploading)
            Text('Do not disconnect during upload', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.warningColor, fontWeight: FontWeight.w500)),
          const Spacer(),
          if (_isUploading)
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: _cancelUpload,
                icon: const Icon(Icons.stop_circle_outlined, size: 14),
                label: Text('Cancel', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 34,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: Text('Close', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 34,
              child: ElevatedButton.icon(
                onPressed: _firmwareFile != null && !_isUploading ? _startUpload : null,
                icon: const Icon(Icons.upload_rounded, size: 16),
                label: Text('Upload', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.white54, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
