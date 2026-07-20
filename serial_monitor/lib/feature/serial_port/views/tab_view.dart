import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/config/can_config.dart';
import '../../../core/config/models.dart';
import '../../../core/controllers/port_controller.dart';
import '../../../utils/theme/app_theme.dart';
import '../../../utils/widgets/message_widget.dart';

/// Right-hand communication console and documentation area.
class TabViewWidget extends StatefulWidget {
  final int tabIndex;

  const TabViewWidget({super.key, required this.tabIndex});

  @override
  State<TabViewWidget> createState() => _TabViewWidgetState();
}

class _TabViewWidgetState extends State<TabViewWidget> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final TextEditingController _frameIdController = TextEditingController();
  final TextEditingController _sendInputController = TextEditingController();

  String _localFrameId = '';
  String _localDirection = 'All';
  String _localChannel = 'All';
  bool _initialized = false;

  int? _lastTabIndex;
  String? _lastAppliedFrameId;
  String? _lastAppliedDirection;
  String? _lastAppliedChannel;

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _frameIdController.dispose();
    _sendInputController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        final position = _scrollController.position;
        position.jumpTo(position.maxScrollExtent);
      });
    }
  }

  String _displayFormatLabel(DisplayFormat format) {
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

  void _applyFilters(PortController controller) {
    debugPrint('TAB_VIEW: _applyFilters clicked. localFrameId: "$_localFrameId", localDirection: "$_localDirection", localChannel: "$_localChannel"');
    _lastAppliedFrameId = _localFrameId;
    _lastAppliedDirection = _localDirection;
    _lastAppliedChannel = _localChannel;
    controller.setFilterFrameId(widget.tabIndex, _localFrameId);
    controller.setFilterDirection(widget.tabIndex, _localDirection);
    controller.setFilterChannel(widget.tabIndex, _localChannel);
  }

  void _clearFilters(PortController controller) {
    debugPrint('TAB_VIEW: _clearFilters clicked.');
    setState(() {
      _localFrameId = '';
      _localDirection = 'All';
      _localChannel = 'All';
      _frameIdController.clear();
      _lastAppliedFrameId = '';
      _lastAppliedDirection = 'All';
      _lastAppliedChannel = 'All';
    });
    controller.clearAllFilters(widget.tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PortController>(
      builder: (context, controller, _) {
        if (widget.tabIndex >= controller.tabs.length) {
          return const SizedBox.shrink();
        }

        final tab = controller.tabs[widget.tabIndex];

        // Sync local UI state with tab state if they don't match (e.g. from tab switch or context menu)
        final bool tabChanged = _lastTabIndex != widget.tabIndex;
        final bool modelChangedFromOutside = _lastAppliedFrameId != tab.filterFrameId ||
            _lastAppliedDirection != tab.filterDirection ||
            _lastAppliedChannel != tab.filterChannel;

        debugPrint('TAB_VIEW build: tabIndex: ${widget.tabIndex}, tabChanged: $tabChanged, modelChangedFromOutside: $modelChangedFromOutside, tab.filterFrameId: "${tab.filterFrameId}", tab.filterDirection: "${tab.filterDirection}", tab.filterChannel: "${tab.filterChannel}"');

        if (!_initialized || tabChanged || modelChangedFromOutside) {
          debugPrint('TAB_VIEW syncing local state with tab model. Previous localFrameId: "$_localFrameId", New: "${tab.filterFrameId}"');
          _localFrameId = tab.filterFrameId;
          _localDirection = tab.filterDirection;
          _localChannel = tab.filterChannel;
          _frameIdController.text = _localFrameId;

          _lastTabIndex = widget.tabIndex;
          _lastAppliedFrameId = tab.filterFrameId;
          _lastAppliedDirection = tab.filterDirection;
          _lastAppliedChannel = tab.filterChannel;
          _initialized = true;
        }

        if (tab.autoScroll && tab.messages.isNotEmpty) {
          _scrollToBottom();
        }

        return Column(
          children: [
            Expanded(
              child: _GroupPanel(
                title: 'Communication',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionButton(
                      icon: Icons.delete_outline,
                      label: 'Clear',
                      onPressed: () => controller.clearMessages(widget.tabIndex),
                    ),
                    const SizedBox(width: 10),
                    _buildModeTabs(
                      currentFormat: tab.displayFormat,
                      onChanged: (format) {
                        controller.setDisplayFormat(widget.tabIndex, format);
                      },
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildFilterBar(controller, tab),
                    Expanded(
                      child: _buildMessageArea(tab, controller.canConfig.canType == CanType.canFd, controller.isCanMode),
                    ),
                    if (!controller.isCanMode)
                      _buildSendInputBar(controller, tab),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(PortController controller, SerialTab tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final isVeryNarrow = constraints.maxWidth < 350;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            color: AppTheme.panelHeader,
            border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
          ),
          child: Row(
            children: [
              // Frame ID Filter
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _frameIdController,
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: isVeryNarrow ? 'Filter...' : isNarrow ? 'ID Filter' : 'Filter Frame ID (e.g. 0x002)',
                      hintStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search, size: 14, color: AppTheme.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.only(top: 0, bottom: 0, right: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                      fillColor: AppTheme.bgInput,
                      filled: true,
                    ),
                    onChanged: (val) {
                      _localFrameId = val;
                    },
                    onSubmitted: (_) => _applyFilters(controller),
                  ),
                ),
              ),
              if (!isVeryNarrow) ...[
                const SizedBox(width: 10),
                // Direction Filter Dropdown
                SizedBox(
                  height: 28,
                  width: isNarrow ? 90 : 140,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('dir_$_localDirection'),
                    initialValue: _localDirection,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary),
                    dropdownColor: AppTheme.bgElevated,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                      fillColor: AppTheme.bgInput,
                      filled: true,
                    ),
                    items: isNarrow
                        ? const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(value: 'TX', child: Text('TX')),
                            DropdownMenuItem(value: 'RX', child: Text('RX')),
                          ]
                        : const [
                            DropdownMenuItem(value: 'All', child: Text('All Directions')),
                            DropdownMenuItem(value: 'TX', child: Text('TX Only')),
                            DropdownMenuItem(value: 'RX', child: Text('RX Only')),
                          ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _localDirection = val;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Channel Filter Dropdown
                SizedBox(
                  height: 28,
                  width: isNarrow ? 90 : 140,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('chan_$_localChannel'),
                    initialValue: _localChannel,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary),
                    dropdownColor: AppTheme.bgElevated,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                      fillColor: AppTheme.bgInput,
                      filled: true,
                    ),
                    items: isNarrow
                        ? const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(value: 'Channel 1', child: Text('CH 1')),
                            DropdownMenuItem(value: 'Channel 2', child: Text('CH 2')),
                          ]
                        : const [
                            DropdownMenuItem(value: 'All', child: Text('All Channels')),
                            DropdownMenuItem(value: 'Channel 1', child: Text('Channel 1')),
                            DropdownMenuItem(value: 'Channel 2', child: Text('Channel 2')),
                          ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _localChannel = val;
                        });
                      }
                    },
                  ),
                ),
              ],
              const SizedBox(width: 10),
              // Apply Button
              SizedBox(
                height: 28,
                child: Tooltip(
                  message: 'Apply Filters',
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _applyFilters(controller),
                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Clear Button
              SizedBox(
                height: 28,
                child: Builder(
                  builder: (context) {
                    final bool isAnyFilterApplied = tab.filterFrameId.isNotEmpty || tab.filterDirection != 'All' || tab.filterChannel != 'All';
                    return Tooltip(
                      message: 'Clear Filters',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(28, 28),
                          foregroundColor: isAnyFilterApplied ? AppTheme.textSecondary : AppTheme.textMuted.withValues(alpha: 0.5),
                          side: BorderSide(color: isAnyFilterApplied ? AppTheme.borderColor : AppTheme.borderColor.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onPressed: isAnyFilterApplied ? () => _clearFilters(controller) : null,
                        child: Icon(Icons.filter_alt_off, size: 14, color: isAnyFilterApplied ? AppTheme.textSecondary : AppTheme.textMuted.withValues(alpha: 0.5)),
                      ),
                    );
                  }
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isActive ? AppTheme.primaryColor.withValues(alpha: 0.3) : AppTheme.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: isActive ? AppTheme.primaryColor : AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isActive ? AppTheme.primaryColor : AppTheme.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeTabs({
    required DisplayFormat currentFormat,
    required ValueChanged<DisplayFormat> onChanged,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: DisplayFormat.values.map((format) {
          final selected = currentFormat == format;
          return InkWell(
            onTap: () => onChanged(format),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryColor.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _displayFormatLabel(format),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppTheme.primaryColor : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessageArea(SerialTab tab, bool isFd, bool isCanMode) {
    final displayMessages = tab.filteredMessages;

    return Container(
      color: AppTheme.consoleBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!isCanMode) {
            final hasActiveFilter = tab.filterDirection != 'All' || tab.filterChannel != 'All';
            if (displayMessages.isEmpty) {
              return Center(
                child: Text(
                  hasActiveFilter ? 'No matching messages' : 'No communication data yet',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                ),
              );
            }
            return Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              child: NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification notification) {
                  if (notification is ScrollUpdateNotification) {
                    final metrics = notification.metrics;
                    if (metrics.axis == Axis.vertical) {
                      tab.autoScroll = metrics.pixels >= metrics.maxScrollExtent - 20;
                    }
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: displayMessages.length,
                  itemBuilder: (context, index) {
                    return _ConsoleRowWithContextMenu(
                      message: displayMessages[index],
                      displayFormat: tab.displayFormat,
                      index: index + 1,
                    );
                  },
                ),
              ),
            );
          }

          final double minTotalWidth = isCanMode ? (isFd ? 2200.0 : 1000.0) : 500.0;
          final double tableWidth = constraints.maxWidth > minTotalWidth
              ? constraints.maxWidth
              : minTotalWidth;

          final hasActiveFilter = tab.filterFrameId.isNotEmpty || tab.filterDirection != 'All' || tab.filterChannel != 'All';
          if (displayMessages.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTableHeader(isCanMode),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasActiveFilter
                              ? Icons.filter_list_off
                              : Icons.monitor_outlined,
                          size: 32,
                          color: AppTheme.textMuted.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasActiveFilter
                              ? 'No matching messages'
                              : 'No communication data yet',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final content = Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            interactive: true,
            notificationPredicate: (ScrollNotification notification) {
              return notification.metrics.axis == Axis.horizontal;
            },
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTableHeader(isCanMode),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification notification) {
                          if (notification is ScrollUpdateNotification) {
                            final metrics = notification.metrics;
                            if (metrics.axis == Axis.vertical) {
                              tab.autoScroll = metrics.pixels >= metrics.maxScrollExtent - 20;
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          itemCount: displayMessages.length,
                          itemBuilder: (context, index) {
                            return _MessageRowWithContextMenu(
                              message: displayMessages[index],
                              displayFormat: tab.displayFormat,
                              index: index + 1,
                              isEven: index % 2 == 0,
                              isCanMode: isCanMode,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            interactive: true,
            notificationPredicate: (ScrollNotification notification) {
              return notification.metrics.axis == Axis.vertical;
            },
            child: content,
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(bool isCanMode) {
    final style = GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: AppTheme.textSecondary,
      letterSpacing: 0.3,
    );
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.panelHeader,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          _headerCell('Index', 60, style),
          _headerCell('System Time', 110, style),
          if (isCanMode) ...[
            _headerCell('Time Stamp', 110, style),
            _headerCell('Channel', 70, style),
          ],
          _headerCell('Direction', 80, style),
          if (isCanMode) ...[
            _headerCell('Frame ID', 90, style),
            _headerCell('Type', 70, style),
            _headerCell('Format', 80, style),
            _headerCell('DLC', 60, style),
          ],
          Expanded(
            child: _headerCell('Data', double.infinity, style),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, double width, TextStyle style) {
    return Container(
      width: width == double.infinity ? null : width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppTheme.borderColor)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: style,
        maxLines: 1,
      ),
    );
  }
  Widget _buildSendInputBar(PortController controller, SerialTab tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 300;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: AppTheme.panelHeader,
            border: Border(top: BorderSide(color: AppTheme.borderColor)),
          ),
          child: Row(
            children: [
              _buildSendFormatSelector(controller, tab),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _sendInputController,
                    style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppTheme.textPrimary),
                    inputFormatters: [
                      if (tab.sendFormat == DisplayFormat.binary)
                        FilteringTextInputFormatter.allow(RegExp(r'[01\s]'))
                      else if (tab.sendFormat == DisplayFormat.hex)
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F\s]'))
                      else if (tab.sendFormat == DisplayFormat.decimal)
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9\s]')),
                    ],
                    decoration: InputDecoration(
                      hintText: isNarrow
                          ? 'Message...'
                          : tab.sendFormat == DisplayFormat.ascii
                              ? 'Type ASCII message here...'
                              : tab.sendFormat == DisplayFormat.hex
                                  ? 'Type HEX message here (e.g. 53 41 49)...'
                                  : tab.sendFormat == DisplayFormat.decimal
                                      ? 'Type decimal message here (e.g. 83 65 73)...'
                                      : 'Type binary message here (e.g. 0101 0000)...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: AppTheme.bgInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {});
                    },
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        _sendInputMessage(controller);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: isNarrow
                    ? Tooltip(
                        message: 'Send',
                        child: ElevatedButton(
                          onPressed: controller.isConnected && _sendInputController.text.isNotEmpty
                              ? () => _sendInputMessage(controller)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(36, 32),
                          ),
                          child: const Icon(Icons.send_rounded, size: 14),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: controller.isConnected && _sendInputController.text.isNotEmpty
                            ? () => _sendInputMessage(controller)
                            : null,
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: Text('Send', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSendFormatSelector(PortController controller, SerialTab tab) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DisplayFormat>(
          value: tab.sendFormat,
          isDense: true,
          dropdownColor: AppTheme.bgElevated,
          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          items: DisplayFormat.values.map((f) {
            return DropdownMenuItem<DisplayFormat>(
              value: f,
              child: Text(_displayFormatLabel(f)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              controller.setSendFormat(widget.tabIndex, value);
            }
          },
        ),
      ),
    );
  }

  void _sendInputMessage(PortController controller) {
    final text = _sendInputController.text;
    if (text.isEmpty) return;
    
    final success = controller.sendData(text);
    if (success) {
      _sendInputController.clear();
      _scrollToBottom();
      setState(() {});
    }
  }
}

/// Message row with right-click context menu (#10)
class _MessageRowWithContextMenu extends StatelessWidget {
  final SerialMessage message;
  final DisplayFormat displayFormat;
  final int index;
  final bool isEven;
  final bool isCanMode;

  const _MessageRowWithContextMenu({
    required this.message,
    required this.displayFormat,
    required this.index,
    required this.isEven,
    required this.isCanMode,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: MessageWidget(
        message: message,
        displayFormat: displayFormat,
        index: index,
        isEven: isEven,
        isCanMode: isCanMode,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: AppTheme.bgCard,
      items: [
        PopupMenuItem(
          value: 'copy_row',
          height: 32,
          child: _menuItem(Icons.copy, 'Copy Row'),
        ),
        PopupMenuItem(
          value: 'copy_data',
          height: 32,
          child: _menuItem(Icons.content_copy, 'Copy Data'),
        ),
        if (isCanMode) ...[
          PopupMenuItem(
            value: 'copy_id',
            height: 32,
            child: _menuItem(Icons.tag, 'Copy CAN ID'),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'filter_id',
            height: 32,
            child: _menuItem(Icons.filter_alt, 'Filter by this ID'),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy_row':
          final row = '${message.formattedTime}  ${message.directionLabel}  '
              '${message.canId ?? "-"}  ${message.getFormatted(displayFormat)}';
          Clipboard.setData(ClipboardData(text: row));
          break;
        case 'copy_data':
          Clipboard.setData(ClipboardData(text: message.getFormatted(displayFormat)));
          break;
        case 'copy_id':
          Clipboard.setData(ClipboardData(text: message.canId ?? ''));
          break;
        case 'filter_id':
          if (message.canId != null) {
            final controller = Provider.of<PortController>(context, listen: false);
            controller.setFilterFrameId(
              controller.activeTabIndex,
              message.canId!.replaceAll('0x', ''),
            );
          }
          break;
      }
    });
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary)),
      ],
    );
  }
}


class _GroupPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _GroupPanel({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppTheme.panelDecorationFlat,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: AppTheme.headerDecoration,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (trailing != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: trailing!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(0), child: child),
          ),
        ],
      ),
    );
  }
}

class ConsoleMessageRow extends StatelessWidget {
  final SerialMessage message;
  final DisplayFormat displayFormat;
  final int index;

  const ConsoleMessageRow({
    super.key,
    required this.message,
    required this.displayFormat,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = message.direction == MessageDirection.sent;
    final sysTime = message.formattedTime;
    final dir = isSent ? 'TX' : 'RX';
    final dataStr = message.getFormatted(displayFormat);

    final timeStyle = GoogleFonts.jetBrainsMono(
      fontSize: 12,
      color: AppTheme.textMuted,
    );
    final dirStyle = GoogleFonts.jetBrainsMono(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: isSent ? AppTheme.sentColor : AppTheme.receivedColor,
    );
    final dataStyle = GoogleFonts.jetBrainsMono(
      fontSize: 12,
      color: isSent ? AppTheme.textPrimary : AppTheme.accentCyan,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '[$sysTime] ', style: timeStyle),
            TextSpan(text: '[$dir] ', style: dirStyle),
            TextSpan(text: dataStr, style: dataStyle),
          ],
        ),
      ),
    );
  }
}

class _ConsoleRowWithContextMenu extends StatelessWidget {
  final SerialMessage message;
  final DisplayFormat displayFormat;
  final int index;

  const _ConsoleRowWithContextMenu({
    required this.message,
    required this.displayFormat,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: ConsoleMessageRow(
        message: message,
        displayFormat: displayFormat,
        index: index,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'copy_row',
          height: 32,
          child: _menuItem(Icons.copy, 'Copy Line'),
        ),
        PopupMenuItem(
          value: 'copy_data',
          height: 32,
          child: _menuItem(Icons.content_copy, 'Copy Data'),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      final dataStr = message.getFormatted(displayFormat);
      if (value == 'copy_row') {
        Clipboard.setData(ClipboardData(text: '[${message.formattedTime}] [${message.directionLabel}] $dataStr'));
      } else if (value == 'copy_data') {
        Clipboard.setData(ClipboardData(text: dataStr));
      }
    });
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary),
        ),
      ],
    );
  }
}
