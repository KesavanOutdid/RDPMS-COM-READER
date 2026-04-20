import 'package:flutter/material.dart';
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
class SerialPortScreen extends StatelessWidget {
  const SerialPortScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<PortController>(
          builder: (context, controller, _) {
            return Column(
              children: [
                _buildStatusStrip(controller),
                _buildControlStrip(controller),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Left: Send Sequences ──
                        SizedBox(
                          width: 280,
                          child: _buildSendSequencesPanel(controller),
                        ),
                        const SizedBox(width: 12),
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
            );
          },
        ),
      ),
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
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F4F7),
        border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(
              controller.isConnected ? Icons.usb : Icons.usb_off,
              size: 18,
              color: controller.isConnected
                  ? AppTheme.receivedColor
                  : AppTheme.errorColor,
            ),
            const SizedBox(width: 8),
            Text(
              connectionText,
              style: GoogleFonts.openSans(
                fontSize: 12,
                color: AppTheme.textPrimary,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bgDark,
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
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: OutlinedButton.icon(
              onPressed: controller.isConnected
                  ? null
                  : controller.refreshPorts,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: Builder(
              builder: (context) => OutlinedButton.icon(
                onPressed: controller.isConnected
                    ? null
                    : () => _showCanConfigDialog(context, controller),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: controller.isConnecting
                  ? null
                  : controller.toggleConnection,
              icon: Icon(
                controller.isConnected ? Icons.link_off : Icons.link,
                size: 16,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: controller.isConnected
                    ? AppTheme.errorColor
                    : AppTheme.primaryColor,
              ),
              label: Text(
                controller.isConnecting
                    ? 'Connecting...'
                    : controller.isConnected
                        ? 'Disconnect'
                        : 'Connect',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              controller.statusMessage,
              style: GoogleFonts.openSans(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 12),
          _metricChip('TX', controller.totalBytesSent, AppTheme.sentColor),
          const SizedBox(width: 6),
          _metricChip(
            'RX',
            controller.totalBytesReceived,
            AppTheme.receivedColor,
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
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final isSelected = index == selectedIndex;
                return Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.selectionBlueSoft
                        : index.isEven
                        ? Colors.white
                        : AppTheme.panelFill,
                    border: Border(
                      bottom: const BorderSide(color: AppTheme.borderLight),
                      left: isSelected
                          ? const BorderSide(
                              color: AppTheme.selectionBlue,
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
                                    style: GoogleFonts.openSans(
                                      fontSize: 12,
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
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
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
      height: 34,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        icon: const Icon(Icons.keyboard_arrow_down, size: 16),
        style: GoogleFonts.openSans(fontSize: 12, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          filled: true,
          fillColor: Colors.white,
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
      height: 40,
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
                style: GoogleFonts.openSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Text(
        '$label ${_formatMetric(value)}',
        style: GoogleFonts.robotoMono(fontSize: 11, color: color),
      ),
    );
  }

  Widget _statusCell(String text) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Text(
        text,
        style: GoogleFonts.openSans(fontSize: 11, color: AppTheme.textPrimary),
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: AppTheme.bgDark,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        children: [
          // ── Scrollable tab list ──
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 6, top: 4),
              itemCount: controller.tabs.length,
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
                      ? controller.addTab
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

    return GestureDetector(
      onTap: () => controller.setActiveTab(index),
      onDoubleTap: () => _startEditing(index, tab.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: 34,
        constraints: const BoxConstraints(minWidth: 90),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.bgCard : Colors.transparent,
          border: isActive ? Border.all(color: AppTheme.borderColor) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active indicator dot
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
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
                  autofocus: true,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
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
                style: GoogleFonts.openSans(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
                ),
              ),

            // Message count badge
            if (tab.messages.isNotEmpty && !isEditing) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${tab.messages.length}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 9,
                    color: AppTheme.primaryColor,
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
                    size: 13,
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
      decoration: AppTheme.panelDecoration,
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppTheme.panelHeader,
              border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: GoogleFonts.openSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: AppTheme.bgCard,
              padding: const EdgeInsets.all(10),
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
    final borderColor = enabled ? AppTheme.textSecondary : AppTheme.borderColor;
    final textColor = enabled ? Colors.black : AppTheme.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 42,
          height: 24,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : AppTheme.panelFill,
            border: Border.all(color: borderColor),
          ),
          alignment: Alignment.center,
          child: Text(
            '---->',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  CAN Configuration Edit Dialog
// ═══════════════════════════════════════════════════════════════

Future<void> _showCanConfigDialog(
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

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          // Build the live connect frame preview
          int flagsByte = 0;
          if (canType == CanType.canFd) flagsByte |= 0x01;
          if (brsEnabled) flagsByte |= 0x02;
          if (nonIso) flagsByte |= 0x04;

          final modeByte = canType == CanType.classicCan
              ? classicMode.value
              : fdDataBaud.value;

          final frame = [
            0xA0, 0x01, channel.value,
            nominalBaudRate.value, modeByte, flagsByte, 0x00,
          ];
          final hexFrame = frame
              .map((b) => '0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
              .join('  ');

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
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Connection',
                              style: GoogleFonts.openSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'CAN Bus Configuration',
                              style: GoogleFonts.openSans(
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
                                              : Colors.white,
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
                                              style: GoogleFonts.openSans(
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
                                              style: GoogleFonts.openSans(
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
                                color: Colors.white,
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

                            // ── Connect Frame Preview ──
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FB),
                                border: Border.all(color: AppTheme.borderLight),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CONNECT FRAME PREVIEW',
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textMuted,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      hexFrame,
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryColor,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'CMD   IF   CH   BAUD  MODE  FLAGS  RSV',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 9,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                            onPressed: () => Navigator.of(context).pop(),
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
          style: GoogleFonts.robotoMono(
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppTheme.borderColor),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        style: GoogleFonts.openSans(
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
              style: GoogleFonts.openSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.openSans(
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
    final normalized = _normalizeSequenceEditorInput(value, format);
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
                          style: GoogleFonts.openSans(
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
                                  style: GoogleFonts.openSans(
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
                                    color: Colors.white,
                                    border: Border.all(
                                      color: AppTheme.borderColor,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$sequenceIndex',
                                    style: GoogleFonts.robotoMono(
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
                              style: GoogleFonts.openSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '1 - Name',
                              style: GoogleFonts.openSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: nameController,
                              style: GoogleFonts.openSans(fontSize: 13),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Text(
                                  '2 - Sequence',
                                  style: GoogleFonts.openSans(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 22),
                                Text(
                                  'Edit Mode',
                                  style: GoogleFonts.openSans(
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
                                              : Colors.white,
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
                                          style: GoogleFonts.openSans(
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
                                Text(
                                  'Pos. ${sequenceController.text.length} / ${sequenceController.text.isEmpty ? 0 : sequenceController.text.length - 1}',
                                  style: GoogleFonts.openSans(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
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
                                style: GoogleFonts.robotoMono(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  alignLabelWithHint: true,
                                ),
                                onChanged: (value) =>
                                    normalizeEditorInput(setState, value),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '3 - CAN Message Options',
                              style: GoogleFonts.openSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
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
                                              style: GoogleFonts.openSans(
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
                                                  setState(
                                                    () => canFrameFormat = value,
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
                                              'Type',
                                              style: GoogleFonts.openSans(
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
                                              style: GoogleFonts.openSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            TextField(
                                              controller: canIdController,
                                              style: GoogleFonts.robotoMono(
                                                fontSize: 13,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '00 00 00 01',
                                                filled: true,
                                                fillColor: Colors.white,
                                              ),
                                              onChanged: (value) {
                                                final normalized = _groupInput(
                                                  value
                                                      .replaceAll(
                                                        RegExp(
                                                          r'[^0-9A-Fa-f]',
                                                        ),
                                                        '',
                                                      )
                                                      .toUpperCase(),
                                                  2,
                                                );
                                                if (normalized != value) {
                                                  canIdController.value =
                                                      TextEditingValue(
                                                        text: normalized,
                                                        selection:
                                                            TextSelection.collapsed(
                                                          offset:
                                                              normalized.length,
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
                                              style: GoogleFonts.openSans(
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
                                              style: GoogleFonts.openSans(
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
                                              style: GoogleFonts.robotoMono(
                                                fontSize: 13,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '1',
                                                filled: true,
                                                fillColor: Colors.white,
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
                                              style: GoogleFonts.openSans(
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
                                              style: GoogleFonts.robotoMono(
                                                fontSize: 13,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '0',
                                                filled: true,
                                                fillColor: Colors.white,
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
                                            style: GoogleFonts.openSans(
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
                                            style: GoogleFonts.openSans(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'These fields are saved in the frontend now and can be wired to backend send behavior later.',
                                      style: GoogleFonts.openSans(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '4 - Sequence Documentation',
                              style: GoogleFonts.openSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 120,
                              child: TextField(
                                controller: documentationController,
                                maxLines: null,
                                expands: true,
                                style: GoogleFonts.openSans(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Add your documentation here',
                                  filled: true,
                                  fillColor: Colors.white,
                                  alignLabelWithHint: true,
                                ),
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

  nameController.dispose();
  sequenceController.dispose();
  documentationController.dispose();
  canIdController.dispose();
  repeatCountController.dispose();
  sendCycleController.dispose();
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
