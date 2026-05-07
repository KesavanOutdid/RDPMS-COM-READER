import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/config/can_config.dart';
import '../../../core/config/models.dart';
import '../../../core/controllers/port_controller.dart';
import '../../../utils/theme/app_theme.dart';
import 'tab_view.dart';

/// Docklight-style serial monitor screen.
/// Left pane: Send Sequences (full height)
/// Right pane: Horizontal tab bar + Terminal/Communication view
class SerialPortScreen extends StatefulWidget {
  const SerialPortScreen({super.key});

  @override
  State<SerialPortScreen> createState() => _SerialPortScreenState();
}

class _SerialPortScreenState extends State<SerialPortScreen> {
  double _sidebarWidth = 280;
  static const double _minSidebarWidth = 180;
  static const double _maxSidebarWidth = 500;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<PortController>(
      builder: (context, controller, _) {
        // Show error snackbar when new error occurs (#13)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (controller.lastError != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  controller.lastError!,
                  style: GoogleFonts.inter(fontSize: 12),
                ),
                backgroundColor: AppTheme.errorColor,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'DISMISS',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
            controller.clearLastError();
          }
        });

        // Keyboard shortcuts (#9)
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
              controller.addTab();
            },
            const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
              controller.clearMessages(controller.activeTabIndex);
            },
            const SingleActivator(LogicalKeyboardKey.keyE, control: true): () async {
              final result = await controller.exportMessages(controller.activeTabIndex);
              if (result != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result, style: GoogleFonts.inter(fontSize: 12)),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: AppTheme.bgDarkest,
              body: SafeArea(
                child: Column(
                  children: [
                    _buildStatusStrip(controller),
                    _buildControlStrip(controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Left: Send Sequences ──
                            SizedBox(
                              width: _sidebarWidth,
                              child: _buildSendSequencesPanel(controller),
                            ),
                            // ── Draggable Divider ──
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                onHorizontalDragStart: (_) {
                                  setState(() => _isDragging = true);
                                },
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    _sidebarWidth = (_sidebarWidth + details.delta.dx)
                                        .clamp(_minSidebarWidth, _maxSidebarWidth);
                                  });
                                },
                                onHorizontalDragEnd: (_) {
                                  setState(() => _isDragging = false);
                                },
                                child: Container(
                                  width: 6,
                                  color: Colors.transparent,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      width: _isDragging ? 3 : 1,
                                      height: double.infinity,
                                      color: _isDragging
                                          ? AppTheme.primaryColor
                                          : AppTheme.borderColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // ── Right: Tabs + Terminal ──
                            Expanded(
                              child: Column(
                                children: [
                                  _HorizontalTabBar(controller: controller),
                                  Expanded(
                                    child: KeyedSubtree(
                                      key: ValueKey(controller.activeTabIndex),
                                      child: TabViewWidget(
                                        tabIndex: controller.activeTabIndex,
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusStrip(PortController controller) {
    final canConfig = controller.canConfig;
    final connectionText = controller.isConnected
        ? 'Communication port open'
        : 'Communication port closed';
    final canTypeLabel = canConfig.canType == CanType.classicCan
        ? 'Classic CAN'
        : 'CAN FD';

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: AppTheme.bgDark,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: controller.isConnected
                    ? AppTheme.successColor
                    : AppTheme.errorColor,
                boxShadow: [
                  BoxShadow(
                    color: (controller.isConnected
                            ? AppTheme.successColor
                            : AppTheme.errorColor)
                        .withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              connectionText,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: controller.isConnected
                    ? AppTheme.successColor
                    : AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 16),
            _statusCell('$canTypeLabel Mode'),
            _statusCell(
              controller.config.portName.isEmpty
                  ? 'No Port'
                  : controller.config.portName,
            ),
            _statusCell(canConfig.channel.label),
            _statusCell(canConfig.nominalBaudRate.label),
            _statusCell(
              canConfig.canType == CanType.classicCan
                  ? canConfig.classicMode.label
                  : canConfig.fdDataBaud.label,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlStrip(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.bgMedium,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildDropdown<String>(
            width: 110,
            value: controller.availablePorts.contains(
              controller.config.portName,
            )
                ? controller.config.portName
                : null,
            hint: 'Port',
            items: controller.availablePorts,
            onChanged: controller.isConnected
                ? null
                : (value) {
                    if (value != null) {
                      controller.updateConfig(portName: value);
                    }
                  },
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 30,
            child: OutlinedButton.icon(
              onPressed: controller.isConnected
                  ? null
                  : controller.refreshPorts,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text('Refresh', style: GoogleFonts.inter(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.borderColor),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 30,
            child: Builder(
              builder: (context) => ElevatedButton.icon(
                onPressed: controller.isConnecting
                    ? null
                    : () async {
                        if (!controller.isConnected) {
                          final shouldConnect = await _showCanConfigDialog(context, controller);
                          if (shouldConnect == true) {
                            await controller.connect();
                            if (context.mounted) {
                              _showConnectionPopup(context, controller.isConnected, controller.statusMessage);
                            }
                          }
                        } else {
                          await controller.disconnect();
                        }
                      },
                icon: Icon(
                  controller.isConnected ? Icons.link_off : Icons.link,
                  size: 14,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.isConnected
                      ? AppTheme.errorColor
                      : AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                label: Text(
                  controller.isConnecting
                      ? 'Connecting...'
                      : controller.isConnected
                          ? 'Disconnect'
                          : 'Connect',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.statusMessage,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 10),
          _metricChip('TX', controller.totalBytesSent, AppTheme.sentColor),
          const SizedBox(width: 4),
          _metricChip(
            'RX',
            controller.totalBytesReceived,
            AppTheme.receivedColor,
          ),
          const SizedBox(width: 8),
          // About button (#19)
          SizedBox(
            height: 24,
            width: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              tooltip: 'About',
              icon: const Icon(Icons.info_outline, color: AppTheme.textMuted),
              onPressed: () => _showAboutDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppTheme.borderColor),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cable_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textBright,
                  ),
                ),
                Text(
                  'Version ${AppConstants.appVersion}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: AppTheme.borderLight),
            const SizedBox(height: 8),
            Text(
              'CAN Bus Analyzer & Serial Monitor',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'A professional-grade CAN bus communication tool for real-time monitoring, '
              'frame analysis, and data logging.',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 16),
            _aboutRow('Protocol', 'CAN 2.0 / CAN FD'),
            _aboutRow('Keyboard', 'Ctrl+N New Tab • Ctrl+L Clear • Ctrl+E Export'),
            const SizedBox(height: 8),
            const Divider(color: AppTheme.borderLight),
            const SizedBox(height: 4),
            Text(
              '© 2026 RDPMS',
              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.inter(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendSequencesPanel(PortController controller) {
    final activeTab = controller.activeTab;
    final rows = activeTab?.sendSequences ?? const <SendSequence>[];
    final selectedIndex = activeTab?.selectedSendSequenceIndex ?? -1;

    return _PanelFrame(
      title: 'Send Sequences',
      child: Column(
        children: [
          _tableHeader(
            columns: const [
              _TableColumn(label: 'Send', width: 60),
              _TableColumn(label: 'Name', width: 100),
              _TableColumn(label: 'Sequence'),
            ],
          ),
          Expanded(
            child: ListView.builder(
              key: PageStorageKey('send_seq_${controller.activeTabIndex}'),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final isSelected = index == selectedIndex;
                return Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.selectionBlue
                        : index.isEven
                        ? Colors.white
                        : AppTheme.panelFill,
                    border: Border(
                      bottom: const BorderSide(color: AppTheme.borderLight),
                      left: isSelected
                          ? const BorderSide(
                              color: AppTheme.primaryColor,
                              width: 2,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Center(
                          child: _DocklightSendButton(
                            enabled:
                                controller.isConnected &&
                                row.sequence.trim().isNotEmpty,
                            onPressed: activeTab == null
                                ? null
                                : () {
                                    controller.selectSendSequence(
                                      controller.activeTabIndex,
                                      index,
                                    );
                                    controller.sendSavedSequence(
                                      controller.activeTabIndex,
                                      index,
                                    );
                                  },
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: activeTab == null
                              ? null
                              : () async {
                                  controller.selectSendSequence(
                                    controller.activeTabIndex,
                                    index,
                                  );
                                  await _showEditSendSequenceDialog(
                                    context,
                                    controller,
                                    controller.activeTabIndex,
                                    index,
                                  );
                                },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    row.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      row.sequencePreview,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: AppTheme.primaryColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildDropdown<T>({
    required double width,
    required T? value,
    required String hint,
    required List<T> items,
    required ValueChanged<T?>? onChanged,
    String Function(T value)? labelBuilder,
  }) {
    return SizedBox(
      width: width,
      height: 30,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        icon: const Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.textMuted),
        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary),
        dropdownColor: AppTheme.bgElevated,
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          filled: true,
          fillColor: AppTheme.bgInput,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder?.call(item) ?? item.toString()),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _tableHeader({required List<_TableColumn> columns}) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: AppTheme.panelHeader,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        children: columns.map((column) {
          final label = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                column.label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );

          if (column.width == null) {
            return Expanded(child: label);
          }

          return SizedBox(width: column.width!, child: label);
        }).toList(),
      ),
    );
  }

  Widget _metricChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label ${_formatMetric(value)}',
        style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _statusCell(String text) {
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgMedium,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
      ),
    );
  }

  String _formatMetric(int value) {
    if (value < 1000) {
      return value.toString();
    }
    if (value < 1000000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return '${(value / 1000000).toStringAsFixed(1)}m';
  }

  void _showConnectionPopup(BuildContext context, bool isSuccess, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: isSuccess ? AppTheme.successColor : AppTheme.errorColor,
              ),
              const SizedBox(width: 10),
              Text(
                isSuccess ? 'Connection Successful' : 'Connection Failed',
                style: GoogleFonts.inter(
                  color: AppTheme.textBright,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: GoogleFonts.inter(color: AppTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Horizontal Tab Bar (Docklight-style)
// ═══════════════════════════════════════════════════════════════

class _HorizontalTabBar extends StatefulWidget {
  final PortController controller;

  const _HorizontalTabBar({required this.controller});

  @override
  State<_HorizontalTabBar> createState() => _HorizontalTabBarState();
}

class _HorizontalTabBarState extends State<_HorizontalTabBar> {
  int? _editingIndex;
  final TextEditingController _editController = TextEditingController();

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing(int index, String currentName) {
    setState(() {
      _editingIndex = index;
      _editController.text = currentName;
    });
  }

  void _finishEditing(int index) {
    if (_editController.text.trim().isNotEmpty) {
      widget.controller.renameTab(index, _editController.text.trim());
    }
    setState(() {
      _editingIndex = null;
    });
  }

  Future<String?> _showCanIdDialog(BuildContext context) async {
    final TextEditingController canIdController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text('New Tab CAN ID', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: canIdController,
            style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '00 00 00 01 (Leave empty for all messages)',
              hintStyle: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted),
              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.borderColor)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
            ),
            onChanged: (value) {
              final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
              final buffer = StringBuffer();
              for (var index = 0; index < compact.length; index++) {
                if (index > 0 && index % 2 == 0) buffer.write(' ');
                buffer.write(compact[index]);
              }
              final normalized = buffer.toString();
              if (normalized != value) {
                canIdController.value = TextEditingValue(
                  text: normalized,
                  selection: TextSelection.collapsed(offset: normalized.length),
                );
              }
            },
            onSubmitted: (_) => Navigator.of(context).pop(canIdController.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(canIdController.text),
              child: const Text('OK', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: AppTheme.bgDark,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        children: [
          // ── Scrollable tab list ──
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 4, top: 2),
              itemCount: controller.tabs.length,
              onReorder: (oldIndex, newIndex) {
                controller.reorderTabs(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                return _buildTab(controller, index);
              },
            ),
          ),

          // ── Add / Remove buttons ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _miniButton(
                  icon: Icons.add,
                  tooltip: 'Add tab',
                  onPressed: controller.tabs.length < AppConstants.maxTabs
                      ? () async {
                          final canId = await _showCanIdDialog(context);
                          if (canId != null) {
                            controller.addTab(canId: canId);
                          }
                        }
                      : null,
                ),
                const SizedBox(width: 2),
                _miniButton(
                  icon: Icons.close,
                  tooltip: 'Remove current tab',
                  onPressed: controller.tabs.length > 1
                      ? () => controller.removeTab(controller.activeTabIndex)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(PortController controller, int index) {
    final tab = controller.tabs[index];
    final isActive = index == controller.activeTabIndex;
    final isEditing = _editingIndex == index;

    return ReorderableDragStartListener(
      key: ValueKey(tab.id),
      index: index,
      child: GestureDetector(
        onTap: () => controller.setActiveTab(index),
        onDoubleTap: () => _startEditing(index, tab.name),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 32,
        constraints: const BoxConstraints(minWidth: 80),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.bgCard : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppTheme.primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active indicator dot
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? AppTheme.primaryColor
                    : AppTheme.textMuted.withValues(alpha: 0.4),
              ),
            ),
            // Tab name or inline editor
            if (isEditing)
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _editController,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onSubmitted: (_) => _finishEditing(index),
                  onTapOutside: (_) => _finishEditing(index),
                ),
              )
            else
              Text(
                tab.name,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? AppTheme.textBright
                      : AppTheme.textSecondary,
                ),
              ),

            // Message count badge
            if (tab.messages.isNotEmpty && !isEditing) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${tab.messages.length}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            // Per-tab close button
            if (controller.tabs.length > 1 && !isEditing) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => controller.removeTab(index),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: isActive
                        ? AppTheme.textSecondary
                        : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _miniButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 14,
        color: onPressed != null
            ? AppTheme.textSecondary
            : AppTheme.textMuted.withValues(alpha: 0.4),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Shared helper widgets
// ═══════════════════════════════════════════════════════════════

class _PanelFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _PanelFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppTheme.panelDecorationFlat,
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: AppTheme.headerDecoration,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: AppTheme.bgCard,
              padding: const EdgeInsets.all(0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableColumn {
  final String label;
  final double? width;

  const _TableColumn({required this.label, this.width});
}

class _DocklightSendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onPressed;

  const _DocklightSendButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 40,
          height: 22,
          decoration: BoxDecoration(
            color: enabled ? AppTheme.primaryColor.withValues(alpha: 0.08) : AppTheme.panelFill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: enabled ? AppTheme.primaryColor.withValues(alpha: 0.4) : AppTheme.borderColor,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.send,
            size: 12,
            color: enabled ? AppTheme.primaryColor : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  CAN Configuration Edit Dialog
// ═══════════════════════════════════════════════════════════════

Future<bool?> _showCanConfigDialog(
  BuildContext context,
  PortController controller,
) async {
  // Make local copies for editing
  var channel = controller.canConfig.channel;
  var nominalBaudRate = controller.canConfig.nominalBaudRate;
  var canType = controller.canConfig.canType;
  var classicMode = controller.canConfig.classicMode;
  var fdDataBaud = controller.canConfig.fdDataBaud;
  var brsEnabled = controller.canConfig.brsEnabled;
  var nonIso = controller.canConfig.nonIso;

  return await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 60,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header (fixed) ──
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.settings_ethernet,
                            color: AppTheme.textBright,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Connection',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'CAN Bus Configuration',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),

                    // ── Scrollable body ──
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Channel ──
                            _configSectionTitle('CHANNEL', 'Byte 2'),
                            const SizedBox(height: 8),
                            _configDropdown<CanChannel>(
                              value: channel,
                              items: CanChannel.values,
                              labelBuilder: (v) => v.label,
                              onChanged: (v) {
                                if (v != null) setState(() => channel = v);
                              },
                            ),
                            const SizedBox(height: 16),

                            // ── Nominal Baud Rate ──
                            _configSectionTitle('NOMINAL BAUD RATE', 'Byte 3'),
                            const SizedBox(height: 8),
                            _configDropdown<CanNominalBaudRate>(
                              value: nominalBaudRate,
                              items: CanNominalBaudRate.values,
                              labelBuilder: (v) => v.label,
                              onChanged: (v) {
                                if (v != null) setState(() => nominalBaudRate = v);
                              },
                            ),
                            const SizedBox(height: 16),

                            // ── CAN Type ──
                            _configSectionTitle('CAN TYPE', 'Byte 5 – Bit 0'),
                            const SizedBox(height: 8),
                            Row(
                              children: CanType.values.map((type) {
                                final isSelected = canType == type;
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: type != CanType.values.last ? 8 : 0,
                                    ),
                                    child: InkWell(
                                      onTap: () => setState(() {
                                        canType = type;
                                      }),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                            ? AppTheme.selectionBlueSoft
                                            : AppTheme.bgInput,
                                          border: Border.all(
                                            color: isSelected
                                                ? AppTheme.selectionBlue
                                                : AppTheme.borderColor,
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              type == CanType.classicCan
                                                  ? Icons.cable
                                                  : Icons.speed,
                                              color: isSelected
                                                  ? AppTheme.primaryColor
                                                  : AppTheme.textMuted,
                                              size: 22,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              type.label,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: isSelected
                                                    ? AppTheme.primaryColor
                                                    : AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              type == CanType.classicCan
                                                  ? 'Standard CAN 2.0A/2.0B'
                                                  : 'Flexible Data Rate',
                                              style: GoogleFonts.inter(
                                                fontSize: 9,
                                                color: AppTheme.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),

                            // ── Mode / Data Baud (dynamic) ──
                            _configSectionTitle(
                              canType == CanType.classicCan ? 'MODE' : 'DATA BAUD RATE',
                              'Byte 4',
                            ),
                            const SizedBox(height: 8),
                            if (canType == CanType.classicCan)
                              _configDropdown<ClassicCanMode>(
                                value: classicMode,
                                items: ClassicCanMode.values,
                                labelBuilder: (v) => v.label,
                                onChanged: (v) {
                                  if (v != null) setState(() => classicMode = v);
                                },
                              )
                            else
                              _configDropdown<CanFdDataBaud>(
                                value: fdDataBaud,
                                items: CanFdDataBaud.values,
                                labelBuilder: (v) => v.label,
                                onChanged: (v) {
                                  if (v != null) setState(() => fdDataBaud = v);
                                },
                              ),
                            const SizedBox(height: 16),

                            // ── Flags ──
                            _configSectionTitle('FLAGS', 'Byte 5 – Bits 1..2'),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.bgInput,
                                border: Border.all(color: AppTheme.borderColor),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                children: [
                                  _configCheckbox(
                                    label: 'BRS (Bit Rate Switching)',
                                    subtitle: canType == CanType.canFd
                                        ? 'Switch to higher data rate for payload'
                                        : 'Only applicable in CAN FD mode',
                                    value: brsEnabled,
                                    enabled: canType == CanType.canFd,
                                    onChanged: (v) {
                                      setState(() => brsEnabled = v ?? false);
                                    },
                                  ),
                                  const Divider(height: 16),
                                  _configCheckbox(
                                    label: 'Non-ISO FD Format',
                                    subtitle: canType == CanType.canFd
                                        ? 'Use Non-ISO CAN FD (Bosch original spec)'
                                        : 'Only applicable in CAN FD mode',
                                    value: nonIso,
                                    enabled: canType == CanType.canFd,
                                    onChanged: (v) {
                                      setState(() => nonIso = v ?? false);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Connect Frame Preview (Removed) ──
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Action Buttons (fixed at bottom) ──
                    Row(
                      children: [
                        const Spacer(),
                        SizedBox(
                          width: 120,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: ElevatedButton(
                            onPressed: () {
                              controller.updateCanConfig(
                                channel: channel,
                                nominalBaudRate: nominalBaudRate,
                                canType: canType,
                                classicMode: classicMode,
                                fdDataBaud: fdDataBaud,
                                brsEnabled: brsEnabled,
                                nonIso: nonIso,
                              );
                              Navigator.of(context).pop(true);
                            },
                            child: const Text('Connect'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _configSectionTitle(String title, String byteLabel) {
  return Row(
    children: [
      Text(
        title,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryColor,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          byteLabel,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

Widget _configDropdown<T>({
  required T value,
  required List<T> items,
  required String Function(T) labelBuilder,
  required ValueChanged<T?> onChanged,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppTheme.bgInput,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppTheme.borderColor),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        dropdownColor: AppTheme.bgElevated,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: AppTheme.textPrimary,
        ),
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(labelBuilder(item)),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

Widget _configCheckbox({
  required String label,
  required String subtitle,
  required bool value,
  required bool enabled,
  required ValueChanged<bool?> onChanged,
}) {
  return Row(
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: AppTheme.primaryColor,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Future<void> _showEditSendSequenceDialog(
  BuildContext context,
  PortController controller,
  int tabIndex,
  int sequenceIndex,
) async {
  final tab = controller.tabs[tabIndex];
  final sequence = tab.sendSequences[sequenceIndex];
  final nameController = TextEditingController(text: sequence.name);
  final sequenceController = TextEditingController(text: sequence.sequence);
  final documentationController = TextEditingController(
    text: sequence.documentation,
  );
  final canIdController = TextEditingController(text: sequence.canIdHex);
  final repeatCountController = TextEditingController(
    text: sequence.repeatCount.toString(),
  );
  final sendCycleController = TextEditingController(
    text: sequence.sendCycleMs.toString(),
  );
  var format = sequence.format;
  var canFrameFormat = sequence.canFrameFormat;
  var canFrameType = sequence.canFrameType;
  var channel = sequence.channel.clamp(1, 2);
  var idIncrementEnabled = sequence.idIncrementEnabled;
  var dataIncrementEnabled = sequence.dataIncrementEnabled;

  void switchFormat(StateSetter setState, DisplayFormat nextFormat) {
    if (format == nextFormat) {
      return;
    }

    try {
      sequenceController.text = convertSequenceInput(
        sequenceController.text,
        format,
        nextFormat,
      );
      sequenceController.selection = TextSelection.collapsed(
        offset: sequenceController.text.length,
      );
      setState(() {
        format = nextFormat;
      });
    } catch (_) {
      setState(() {
        format = nextFormat;
      });
    }
  }

  void normalizeEditorInput(StateSetter setState, String value) {
    String normalized = _normalizeSequenceEditorInput(value, format);

    final int maxBytes = controller.canConfig.canType == CanType.classicCan ? 8 : 64;
    try {
      final bytes = parseSequenceInput(normalized, format);
      if (bytes.length > maxBytes) {
        final truncatedBytes = Uint8List.fromList(bytes.sublist(0, maxBytes));
        normalized = formatSequenceBytes(truncatedBytes, format);
      }
    } catch (_) {
      if (format == DisplayFormat.ascii && normalized.length > maxBytes) {
        normalized = normalized.substring(0, maxBytes);
      } else if (format == DisplayFormat.hex) {
        final clean = normalized.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
        if (clean.length > maxBytes * 2) {
          normalized = _normalizeSequenceEditorInput(clean.substring(0, maxBytes * 2), format);
        }
      } else if (format == DisplayFormat.binary) {
        final clean = normalized.replaceAll(RegExp(r'[^01]'), '');
        if (clean.length > maxBytes * 8) {
          normalized = _normalizeSequenceEditorInput(clean.substring(0, maxBytes * 8), format);
        }
      }
    }

    if (normalized != value) {
      sequenceController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    setState(() {});
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 80,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Edit Send Sequence',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Index',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Container(
                                  width: 72,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgInput,
                                    border: Border.all(
                                      color: AppTheme.borderColor,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$sequenceIndex',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Sequence Definition',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '1 - Name',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: nameController,
                              style: GoogleFonts.inter(fontSize: 13),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: AppTheme.bgInput,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Text(
                                  '2 - Sequence',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 22),
                                Text(
                                  'Edit Mode',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ...DisplayFormat.values.map(
                                  (displayFormat) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: InkWell(
                                      onTap: () => switchFormat(
                                        setState,
                                        displayFormat,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: format == displayFormat
                                              ? AppTheme.selectionBlueSoft
                                              : AppTheme.bgInput,
                                          border: Border.all(
                                            color: format == displayFormat
                                                ? AppTheme.selectionBlue
                                                : AppTheme.borderColor,
                                          ),
                                        ),
                                        child: Text(
                                          _displayFormatDialogLabel(
                                            displayFormat,
                                          ),
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: format == displayFormat
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Builder(
                                  builder: (context) {
                                    final int maxBytes = controller.canConfig.canType == CanType.classicCan ? 8 : 64;
                                    int currentBytes = 0;
                                    try {
                                      currentBytes = parseSequenceInput(sequenceController.text, format).length;
                                    } catch (_) {
                                      final clean = sequenceController.text.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
                                      if (format == DisplayFormat.hex) {
                                        currentBytes = clean.length ~/ 2;
                                      } else if (format == DisplayFormat.binary) {
                                        currentBytes = clean.length ~/ 8;
                                      } else {
                                        currentBytes = clean.length;
                                      }
                                    }
                                    return Text(
                                      'Bytes: $currentBytes / $maxBytes',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: currentBytes > maxBytes ? AppTheme.errorColor : AppTheme.textSecondary,
                                      ),
                                    );
                                  }
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 140,
                              child: TextField(
                                controller: sequenceController,
                                maxLines: null,
                                expands: true,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: AppTheme.bgInput,
                                  alignLabelWithHint: true,
                                ),
                                onChanged: (value) =>
                                    normalizeEditorInput(setState, value),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '3 - CAN Message Options',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.bgInput,
                                border: Border.all(color: AppTheme.borderColor),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Format',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _configDropdown<CanFrameFormat>(
                                              value: canFrameFormat,
                                              items: CanFrameFormat.values,
                                              labelBuilder:
                                                  _canFrameFormatLabel,
                                              onChanged: (value) {
                                                if (value != null) {
                                                  setState(() {
                                                    canFrameFormat = value;
                                                    String clean = canIdController.text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
                                                    if (clean.isNotEmpty) {
                                                      int? intValue = int.tryParse(clean, radix: 16);
                                                      if (intValue != null) {
                                                        if (canFrameFormat == CanFrameFormat.standard && intValue > 0x7FF) {
                                                          clean = '7FF';
                                                        } else if (canFrameFormat == CanFrameFormat.extended && intValue > 0x1FFFFFFF) {
                                                          clean = '1FFFFFFF';
                                                        }
                                                      }
                                                    }
                                                    canIdController.text = _groupInput(clean, 2);
                                                  });
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Type',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _configDropdown<CanFrameType>(
                                              value: canFrameType,
                                              items: CanFrameType.values,
                                              labelBuilder: _canFrameTypeLabel,
                                              onChanged: (value) {
                                                if (value != null) {
                                                  setState(
                                                    () => canFrameType = value,
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'CAN ID (HEX)',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            TextField(
                                              controller: canIdController,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 13,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '00 00 00 01',
                                                filled: true,
                                                fillColor: AppTheme.bgInput,
                                              ),
                                              onChanged: (value) {
                                                String clean = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
                                                if (clean.isNotEmpty) {
                                                  int? intValue = int.tryParse(clean, radix: 16);
                                                  if (intValue != null) {
                                                    if (canFrameFormat == CanFrameFormat.standard && intValue > 0x7FF) {
                                                      clean = '7FF';
                                                    } else if (canFrameFormat == CanFrameFormat.extended && intValue > 0x1FFFFFFF) {
                                                      clean = '1FFFFFFF';
                                                    }
                                                  }
                                                }
                                                final normalized = _groupInput(clean, 2);
                                                if (normalized != value) {
                                                  canIdController.value =
                                                      TextEditingValue(
                                                        text: normalized,
                                                        selection: TextSelection.collapsed(
                                                          offset: normalized.length,
                                                        ),
                                                      );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Channel',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _configDropdown<int>(
                                              value: channel,
                                              items: const [1, 2],
                                              labelBuilder: (value) => '$value',
                                              onChanged: (value) {
                                                if (value != null) {
                                                  setState(
                                                    () => channel = value,
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Number to send',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            TextField(
                                              controller: repeatCountController,
                                              keyboardType:
                                                  TextInputType.number,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 13,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '1',
                                                filled: true,
                                                fillColor: AppTheme.bgInput,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Send cycle (ms)',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            TextField(
                                              controller: sendCycleController,
                                              keyboardType:
                                                  TextInputType.number,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 13,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '0',
                                                filled: true,
                                                fillColor: AppTheme.bgInput,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: CheckboxListTile(
                                          value: idIncrementEnabled,
                                          onChanged: (value) {
                                            setState(
                                              () =>
                                                  idIncrementEnabled =
                                                      value ?? false,
                                            );
                                          },
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          title: Text(
                                            'ID Increment',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: CheckboxListTile(
                                          value: dataIncrementEnabled,
                                          onChanged: (value) {
                                            setState(
                                              () =>
                                                  dataIncrementEnabled =
                                                      value ?? false,
                                            );
                                          },
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          title: Text(
                                            'Data Increment',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                ],
                              ),
                            ),

                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: OutlinedButton(
                            onPressed: () {
                              controller.deleteSendSequence(
                                tabIndex,
                                sequenceIndex,
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Delete Sequence'),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 120,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: ElevatedButton(
                            onPressed: () {
                              controller.updateSendSequence(
                                tabIndex,
                                sequenceIndex,
                                name: nameController.text.trim().isEmpty
                                    ? 'message ${sequenceIndex + 1}'
                                    : nameController.text.trim(),
                                sequence: sequenceController.text,
                                format: format,
                                documentation: documentationController.text,
                                canFrameFormat: canFrameFormat,
                                canFrameType: canFrameType,
                                canIdHex: canIdController.text.trim(),
                                channel: channel,
                                repeatCount:
                                    int.tryParse(repeatCountController.text) ??
                                    1,
                                sendCycleMs:
                                    int.tryParse(sendCycleController.text) ?? 0,
                                idIncrementEnabled: idIncrementEnabled,
                                dataIncrementEnabled: dataIncrementEnabled,
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('OK'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

String _displayFormatDialogLabel(DisplayFormat format) {
  switch (format) {
    case DisplayFormat.ascii:
      return 'ASCII';
    case DisplayFormat.hex:
      return 'HEX';
    case DisplayFormat.decimal:
      return 'Decimal';
    case DisplayFormat.binary:
      return 'Binary';
  }
}

String _canFrameFormatLabel(CanFrameFormat format) {
  switch (format) {
    case CanFrameFormat.standard:
      return 'Standard';
    case CanFrameFormat.extended:
      return 'Extended';
  }
}

String _canFrameTypeLabel(CanFrameType type) {
  switch (type) {
    case CanFrameType.data:
      return 'Data';
    case CanFrameType.remote:
      return 'Remote';
  }
}

String _normalizeSequenceEditorInput(String input, DisplayFormat format) {
  switch (format) {
    case DisplayFormat.ascii:
      return input;
    case DisplayFormat.hex:
      return _groupInput(
        input.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase(),
        2,
      );
    case DisplayFormat.decimal:
      return input.replaceAll(RegExp(r'[,\s]+'), ' ').trimLeft();
    case DisplayFormat.binary:
      return _groupInput(input.replaceAll(RegExp(r'[^01]'), ''), 8);
  }
}

String _groupInput(String compact, int groupSize) {
  if (compact.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  for (var index = 0; index < compact.length; index++) {
    if (index > 0 && index % groupSize == 0) {
      buffer.write(' ');
    }
    buffer.write(compact[index]);
  }
  return buffer.toString();
}
