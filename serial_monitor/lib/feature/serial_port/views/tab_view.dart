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
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _searchController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Consumer<PortController>(
      builder: (context, controller, _) {
        if (widget.tabIndex >= controller.tabs.length) {
          return const SizedBox.shrink();
        }

        final tab = controller.tabs[widget.tabIndex];

        if (tab.autoScroll && tab.messages.isNotEmpty && !_showSearch) {
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
                    // Search bar
                    if (_showSearch)
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: const BoxDecoration(
                          color: AppTheme.panelHeader,
                          border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textPrimary),
                                decoration: InputDecoration(
                                  hintText: 'Filter by CAN ID, direction, data...',
                                  hintStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  controller.setFilterQuery(widget.tabIndex, value);
                                },
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  _searchController.clear();
                                  controller.setFilterQuery(widget.tabIndex, '');
                                },
                                child: const Icon(Icons.close, size: 14, color: AppTheme.textMuted),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              '${tab.filteredMessages.length} / ${tab.messages.length}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: _buildMessageArea(tab, controller.canConfig.canType == CanType.canFd),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

  Widget _buildMessageArea(SerialTab tab, bool isFd) {
    final displayMessages = tab.filteredMessages;

    return Container(
      color: AppTheme.consoleBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double minTotalWidth = isFd ? 2200.0 : 1000.0;
          final double tableWidth = constraints.maxWidth > minTotalWidth
              ? constraints.maxWidth
              : minTotalWidth;

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
                    _buildTableHeader(),
                    Expanded(
                      child: displayMessages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tab.filterQuery.isNotEmpty
                                        ? Icons.filter_list_off
                                        : Icons.monitor_outlined,
                                    size: 32,
                                    color: AppTheme.textMuted.withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    tab.filterQuery.isNotEmpty
                                        ? 'No matching messages'
                                        : 'No communication data yet',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
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

          if (displayMessages.isEmpty) {
            return content;
          }

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

  Widget _buildTableHeader() {
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
          _headerCell('Time Stamp', 110, style),
          _headerCell('Channel', 70, style),
          _headerCell('Direction', 80, style),
          _headerCell('Frame ID', 90, style),
          _headerCell('Type', 70, style),
          _headerCell('Format', 80, style),
          _headerCell('DLC', 60, style),
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
}


/// Message row with right-click context menu (#10)
class _MessageRowWithContextMenu extends StatelessWidget {
  final SerialMessage message;
  final DisplayFormat displayFormat;
  final int index;
  final bool isEven;

  const _MessageRowWithContextMenu({
    required this.message,
    required this.displayFormat,
    required this.index,
    required this.isEven,
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
            controller.setFilterQuery(
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
