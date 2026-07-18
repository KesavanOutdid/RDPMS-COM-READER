import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/controllers/bulk_firmware_controller.dart';
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

/// Minimal StatefulWidget — only owns ScrollController & TextEditingController
/// which require dispose(). All business state lives in BulkFirmwareController.
class _BulkFirmwareDialogState extends State<BulkFirmwareDialog> {
  final ScrollController _logScrollController = ScrollController();
  late TextEditingController _delayController;

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<BulkFirmwareController>();
    ctrl.updateConnection(
      serialService: widget.serialService,
      channel: widget.channel,
      isExtended: widget.isExtended,
    );
    _delayController = TextEditingController(text: ctrl.delayMs);
    _delayController.addListener(() {
      ctrl.setDelayMs(_delayController.text.trim());
    });
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BulkFirmwareController>(
      builder: (context, ctrl, _) {
        // Auto-scroll log when entries change
        _scrollLogToBottom();

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
                          onPressed: ctrl.isUploading ? null : ctrl.pickFile,
                          icon: const Icon(Icons.folder),
                          label: Text(ctrl.firmwareFile != null
                              ? ctrl.firmwareFile!.fileName
                              : 'Select Firmware (.bin)'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.bgInput,
                              foregroundColor: AppTheme.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed:
                            ctrl.isScanning || ctrl.isUploading ? null : ctrl.scanNodes,
                        icon: ctrl.isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.search),
                        label: const Text('Scan Bus'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentCyan,
                            foregroundColor: Colors.white),
                      )
                    ],
                  ),
                  const SizedBox(height: 15),

                  if (ctrl.firmwareFile != null)
                    Row(
                      children: [
                        Expanded(
                            child: _buildStatCard(
                                Icons.sd_storage,
                                'File Size',
                                '${(ctrl.firmwareFile!.fileSize / 1024).toStringAsFixed(1)} KB',
                                const Color(0xFFF0F4FF),
                                const Color(0xFF4A6BFF))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildStatCard(
                                Icons.view_agenda,
                                'Frames',
                                '${ctrl.firmwareFile!.frameCount}',
                                const Color(0xFFF2FAF7),
                                const Color(0xFF22A082))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildStatCard(
                                Icons.verified,
                                'CRC-16',
                                '0x${ctrl.firmwareFile!.fileCrc.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                                const Color(0xFFFFF8EE),
                                const Color(0xFFE89A36))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildStatCard(
                                Icons.data_object,
                                'Chunk',
                                '60 B',
                                const Color(0xFFF4F5F8),
                                const Color(0xFF758CA3))),
                      ],
                    ),

                  if (ctrl.firmwareFile != null) const SizedBox(height: 15),

                  // Middle section (Side by side)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Nodes Grid
                        Expanded(
                          flex: 4,
                          child: Container(
                            decoration: BoxDecoration(
                                color: AppTheme.bgDarkest,
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.all(10),
                            child: ctrl.boards.isEmpty
                                ? Center(
                                    child: Text(
                                        ctrl.isScanning
                                            ? 'Scanning...'
                                            : 'No nodes found. Click Scan Bus.',
                                        style: GoogleFonts.inter(
                                            color: AppTheme.textMuted)))
                                : GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 250,
                                      mainAxisExtent: 130,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: ctrl.boards.length,
                                    itemBuilder: (context, index) {
                                      final b = ctrl.boards[index];

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
                                          color: b.selected
                                              ? AppTheme.bgCard
                                              : AppTheme.bgCard.withOpacity(0.4),
                                          border: Border.all(
                                              color: b.selected
                                                  ? statusColor.withOpacity(0.5)
                                                  : AppTheme.borderColor
                                                      .withOpacity(0.3)),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              children: [
                                                SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: Checkbox(
                                                    value: b.selected,
                                                    onChanged: ctrl.isUploading
                                                        ? null
                                                        : (val) {
                                                            ctrl
                                                                .toggleBoardSelection(
                                                                    index,
                                                                    val ?? true);
                                                          },
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    activeColor:
                                                        AppTheme.primaryColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(icon,
                                                    size: 14,
                                                    color: statusColor),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                    child: Text(
                                                        'Node ${b.deviceIdStr} (${b.canIdHex})',
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 12,
                                                                color: AppTheme
                                                                    .textPrimary))),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(b.boardTypeName,
                                                style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        AppTheme.primaryColor)),
                                            const SizedBox(height: 2),
                                            Text('Version: ${b.version}',
                                                style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: AppTheme
                                                        .textSecondary)),
                                            Text('Status: ${b.statusMessage}',
                                                style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: statusColor)),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: b.progress,
                                                minHeight: 5,
                                                backgroundColor:
                                                    AppTheme.bgDarkest,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                  b.status ==
                                                          BoardOtaStatus.success
                                                      ? AppTheme.successColor
                                                      : b.status ==
                                                              BoardOtaStatus
                                                                  .error
                                                          ? AppTheme.errorColor
                                                          : AppTheme
                                                              .primaryColor,
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
                          child: _buildLogSection(ctrl),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  // Progress Bar
                  LinearProgressIndicator(
                      value: ctrl.progress,
                      backgroundColor: AppTheme.bgDark,
                      valueColor:
                          AlwaysStoppedAnimation(AppTheme.primaryColor)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: Text(ctrl.statusMessage,
                              style: GoogleFonts.jetBrainsMono(
                                  color: AppTheme.textSecondary))),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Manual Mode',
                              style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                          const SizedBox(width: 4),
                          Switch(
                            value: ctrl.isManualMode,
                            onChanged: ctrl.isUploading
                                ? null
                                : (v) => ctrl.setManualMode(v),
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
                          enabled: !ctrl.isUploading && !ctrl.isManualMode,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 13, color: AppTheme.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (ctrl.isUploading) ...[
                        if (ctrl.waitingForManualTrigger) ...[
                          ElevatedButton.icon(
                            onPressed: ctrl.sendManualNextFrame,
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Send Frame'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.successColor,
                                foregroundColor: Colors.white),
                          ),
                          const SizedBox(width: 10),
                        ],
                        ElevatedButton.icon(
                          onPressed: ctrl.cancelUpload,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop OTA'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.errorColor,
                              foregroundColor: Colors.white),
                        ),
                      ] else
                        ElevatedButton.icon(
                          onPressed: ctrl.boards.isEmpty || ctrl.firmwareFile == null
                              ? null
                              : ctrl.startUpload,
                          icon: const Icon(Icons.upload),
                          label: const Text('Start Bulk OTA'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white),
                        )
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogSection(BulkFirmwareController ctrl) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
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
              const Icon(Icons.terminal_rounded,
                  size: 12, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Text('Transfer Log',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.5)),
              const Spacer(),
              Text('${ctrl.log.length} entries',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, color: const Color(0xFF64748B))),
              const SizedBox(width: 10),
              InkWell(
                onTap: ctrl.clearLog,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delete_outline,
                        size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 4),
                    Text(
                      'Clear',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          Expanded(
            child: Scrollbar(
              controller: _logScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _logScrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                itemCount: ctrl.log.length,
                itemBuilder: (context, index) {
                  final entry = ctrl.log[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.timestamp,
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: const Color(0xFF64748B))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(entry.message,
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11, color: _logColor(entry.level))),
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

  Color _logColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return const Color(0xFF94A3B8);
      case LogLevel.tx:
        return const Color(0xFF60A5FA);
      case LogLevel.rx:
        return const Color(0xFF4ADE80);
      case LogLevel.success:
        return const Color(0xFF22C55E);
      case LogLevel.warning:
        return const Color(0xFFFBBF24);
      case LogLevel.error:
        return const Color(0xFFEF4444);
    }
  }

  Widget _buildStatCard(
      IconData icon, String title, String value, Color bgColor, Color fgColor) {
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
              Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fgColor.withOpacity(0.8))),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 15, fontWeight: FontWeight.bold, color: fgColor)),
        ],
      ),
    );
  }
}
