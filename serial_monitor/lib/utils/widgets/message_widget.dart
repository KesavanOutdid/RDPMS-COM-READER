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
    final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);
    final borderColor = AppTheme.borderLight;

    final textStyle = GoogleFonts.inter(
      fontSize: 11,
      color: AppTheme.textPrimary,
    );
    final monoStyle = GoogleFonts.jetBrainsMono(
      fontSize: 11,
      color: AppTheme.textPrimary,
    );


    // Prepare data
    final idxStr = index.toString().padLeft(5, '0');
    final sysTime = message.formattedTime;
    final tStamp = message.timeStampHex ?? '-';
    final ch = message.channel != null ? 'ch${message.channel}' : '-';
    final dir = message.directionLabel;
    final fId = message.canId ?? '-';
    final type = message.type ?? '-';
    final format = message.canFormat ?? '-';
    
    final dlc = message.dlc != null ? '0x${message.dlc!.toRadixString(16).toUpperCase().padLeft(2, '0')}' : '-';
    
    final dataStr = message.getFormatted(displayFormat);

    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // Direction indicator
          Container(
            width: 24,
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.only(left: 4),
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: isSent
                    ? AppTheme.sentColor.withValues(alpha: 0.7)
                    : AppTheme.receivedColor.withValues(alpha: 0.7),
              ),
            ),
          ),
          _cell(idxStr, 60, textStyle.copyWith(color: AppTheme.textMuted)),
          _cell(sysTime, 110, textStyle),
          _cell(tStamp, 110, textStyle),
          _cell(ch, 70, textStyle),
          _cell(
            dir,
            80,
            textStyle.copyWith(
              color: isSent ? AppTheme.sentColor : AppTheme.receivedColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          _cell(fId, 90, monoStyle.copyWith(color: AppTheme.accentOrange)),
          _cell(type, 70, textStyle),
          _cell(format, 80, textStyle),
          _cell(dlc, 60, monoStyle),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              alignment: Alignment.centerLeft,
              child: Text(
                dataStr,
                style: monoStyle.copyWith(
                  color: isSent ? AppTheme.sentColor : AppTheme.accentCyan,
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppTheme.borderLight)),
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
