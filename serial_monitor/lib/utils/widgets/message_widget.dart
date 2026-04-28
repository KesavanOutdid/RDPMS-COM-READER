import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/config/models.dart';
import '../theme/app_theme.dart';

/// Renders a single row in the CAN Data Table
class MessageWidget extends StatelessWidget {
  final SerialMessage message;
  final DisplayFormat displayFormat;
  final int index;
  final bool isEven;

  const MessageWidget({
    super.key,
    required this.message,
    required this.displayFormat,
    required this.index,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = message.direction == MessageDirection.sent;
    final rowColor = isEven ? Colors.white : const Color(0xFFF7F7F7);
    final borderColor = const Color(0xFFEEEEEE);

    final textStyle = GoogleFonts.openSans(
      fontSize: 12,
      color: AppTheme.textPrimary,
    );
    final monoStyle = GoogleFonts.robotoMono(
      fontSize: 12,
      color: AppTheme.textPrimary,
    );
    
    final selectedRowColor = isSent ? Colors.transparent : Colors.transparent;

    // Prepare data
    final idxStr = index.toString().padLeft(5, '0');
    final sysTime = message.formattedTime;
    final tStamp = message.timeStampHex ?? '-';
    final ch = message.channel != null ? 'ch${message.channel}' : '-';
    final dir = message.directionLabel;
    final fId = message.canId ?? '-';
    final type = message.type ?? '-';
    final format = message.canFormat ?? '-';
    
    final dlc = message.dlc != null ? '0x${message.dlc.toString().padLeft(2, '0')}' : '-';
    
    final dataPrefix = displayFormat == DisplayFormat.hex ? 'x| ' : '';
    final dataStr = '$dataPrefix${message.getFormatted(displayFormat)}';

    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // Icon marker
          Container(
            width: 24,
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.only(left: 4),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSent ? Colors.red : Colors.green,
              ),
            ),
          ),
          _cell(idxStr, 60, textStyle),
          _cell(sysTime, 100, textStyle),
          _cell(tStamp, 90, textStyle),
          _cell(ch, 70, textStyle),
          _cell(dir, 70, textStyle),
          _cell(fId, 80, textStyle),
          _cell(type, 70, textStyle),
          _cell(format, 80, textStyle),
          _cell(dlc, 60, monoStyle),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Text(
                dataStr,
                style: monoStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, double width, TextStyle style) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
