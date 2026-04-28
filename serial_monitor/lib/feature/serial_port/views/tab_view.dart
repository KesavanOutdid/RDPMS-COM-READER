import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
                child: _buildMessageArea(tab),
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

  Widget _buildMessageArea(SerialTab tab) {
    return Container(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minTotalWidth = 1000.0;
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
          _headerCell('System Time', 100, style),
          _headerCell('Time Stamp', 90, style),
          _headerCell('Channel', 70, style),
          _headerCell('Direction', 70, style),
          _headerCell('Frame ID', 80, style),
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

  Widget _buildDocumentationArea(SerialTab tab) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Colors.white,
      alignment: Alignment.topLeft,
      child: SelectableText(
        _documentationBody(tab),
        style: GoogleFonts.openSans(
          fontSize: 12,
          color: AppTheme.textPrimary,
          height: 1.35,
        ),
      ),
    );
  }

  String _documentationTitle(SerialTab tab) {
    if (tab.sendSequences.isEmpty) {
      return 'No send sequence selected';
    }

    final selectedIndex = tab.selectedSendSequenceIndex.clamp(
      0,
      tab.sendSequences.length - 1,
    );
    final sequence = tab.sendSequences[selectedIndex];
    return 'About Send Sequence Index $selectedIndex : ${sequence.name}';
  }

  String _documentationBody(SerialTab tab) {
    if (tab.sendSequences.isEmpty) {
      return '(Send a sequence to see documentation here)';
    }

    final selectedIndex = tab.selectedSendSequenceIndex.clamp(
      0,
      tab.sendSequences.length - 1,
    );
    final sequence = tab.sendSequences[selectedIndex];
    final docs = sequence.documentation.trim();
    final preview = sequence.sequencePreview.trim();
    final canOptions = _canOptionsSummary(sequence);

    if (docs.isNotEmpty) {
      return canOptions.isEmpty ? docs : '$canOptions\n\n$docs';
    }

    if (preview.isNotEmpty) {
      final body = 'Saved ${_displayFormatLabel(sequence.format)} sequence\n$preview';
      return canOptions.isEmpty ? body : '$canOptions\n\n$body';
    }

    return canOptions.isEmpty
        ? '(Add your documentation here)'
        : '$canOptions\n\n(Add your documentation here)';
  }

  String _canOptionsSummary(SendSequence sequence) {
    final idText = sequence.canIdHex.trim().isEmpty
        ? 'Not set'
        : sequence.canIdHex.trim();
    final frameFormat = sequence.canFrameFormat == CanFrameFormat.standard
        ? 'Standard'
        : 'Extended';
    final frameType = sequence.canFrameType == CanFrameType.data
        ? 'Data'
        : 'Remote';

    return [
      'CAN Options',
      'Format: $frameFormat',
      'Type: $frameType',
      'CAN ID: $idText',
      'Channel: ${sequence.channel}',
      'Repeat: ${sequence.repeatCount}',
      'Cycle: ${sequence.sendCycleMs} ms',
      'ID Inc.: ${sequence.idIncrementEnabled ? 'On' : 'Off'}',
      'Data Inc.: ${sequence.dataIncrementEnabled ? 'On' : 'Off'}',
    ].join('\n');
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
