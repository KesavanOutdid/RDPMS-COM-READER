import 'package:flutter/material.dart';
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

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom(PortController controller, int tabIndex, SerialTab tab) {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        
        final position = _scrollController.position;
        
        // If the user has manually scrolled up more than 50 pixels from the bottom
        if (position.pixels < position.maxScrollExtent - 50) {
          // Automatically turn off auto-scroll so they can read in peace
          if (tab.autoScroll) {
            controller.toggleAutoScroll(tabIndex);
          }
        } else {
          // Otherwise, stick to the bottom
          position.jumpTo(position.maxScrollExtent);
        }
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

        if (tab.autoScroll && tab.messages.isNotEmpty) {
          _scrollToBottom(controller, widget.tabIndex, tab);
        }

        return Column(
          children: [
            Expanded(
              child: _GroupPanel(
                title: 'Communication',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: tab.autoScroll,
                            onChanged: (val) {
                              controller.toggleAutoScroll(widget.tabIndex);
                            },
                            activeColor: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Auto-Scroll',
                          style: GoogleFonts.openSans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => controller.clearMessages(widget.tabIndex),
                      icon: const Icon(Icons.delete_outline, size: 14, color: AppTheme.textSecondary),
                      label: Text('Clear', style: GoogleFonts.openSans(fontSize: 12, color: AppTheme.textSecondary)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildModeTabs(
                      currentFormat: tab.displayFormat,
                      onChanged: (format) {
                        controller.setDisplayFormat(widget.tabIndex, format);
                      },
                    ),
                  ],
                ),
                child: _buildMessageArea(tab, controller.canConfig.canType == CanType.canFd),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModeTabs({
    required DisplayFormat currentFormat,
    required ValueChanged<DisplayFormat> onChanged,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: DisplayFormat.values.map((format) {
          final selected = currentFormat == format;
          return InkWell(
            onTap: () => onChanged(format),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.selectionBlueSoft
                    : Colors.transparent,
                border: format == DisplayFormat.values.last
                    ? null
                    : const Border(
                        right: BorderSide(color: AppTheme.borderLight),
                      ),
              ),
              child: Text(
                _displayFormatLabel(format),
                style: GoogleFonts.openSans(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessageArea(SerialTab tab, bool isFd) {
    return Container(
      color: Colors.white,
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
                      child: tab.messages.isEmpty
                          ? Center(
                              child: Text(
                                'No communication data yet',
                                style: GoogleFonts.openSans(
                                  fontSize: 13,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.zero,
                              itemCount: tab.messages.length,
                              itemBuilder: (context, index) {
                                return MessageWidget(
                                  message: tab.messages[index],
                                  displayFormat: tab.displayFormat,
                                  index: index + 1,
                                  isEven: index % 2 == 0,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );

          if (tab.messages.isEmpty) {
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
    final style = GoogleFonts.openSans(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppTheme.textPrimary,
    );
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE5E5E5),
        border: Border(bottom: BorderSide(color: Color(0xFFCCCCCC))),
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
        border: Border(right: BorderSide(color: Color(0xFFCCCCCC))),
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


class _GroupPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _GroupPanel({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppTheme.panelDecoration,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppTheme.panelHeader,
              border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      title,
                      style: GoogleFonts.openSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
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
            child: Padding(padding: const EdgeInsets.all(10), child: child),
          ),
        ],
      ),
    );
  }
}
