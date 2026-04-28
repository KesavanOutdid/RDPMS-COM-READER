import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_constants.dart';
import '../../core/controllers/port_controller.dart';
import '../theme/app_theme.dart';

/// Custom tab bar with renameable tabs, add/remove functionality
class TabBarWidget extends StatefulWidget {
  const TabBarWidget({super.key});

  @override
  State<TabBarWidget> createState() => _TabBarWidgetState();
}

class _TabBarWidgetState extends State<TabBarWidget> {
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

  void _finishEditing(PortController controller, int index) {
    if (_editController.text.trim().isNotEmpty) {
      controller.renameTab(index, _editController.text.trim());
    }
    setState(() {
      _editingIndex = null;
    });
  }

  Future<String?> _showCanIdDialog(BuildContext context) async {
    String canId = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text('New Tab CAN ID', style: GoogleFonts.rajdhani(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: TextField(
            style: GoogleFonts.sourceCodePro(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. 0x123 (Leave empty for all messages)',
              hintStyle: GoogleFonts.sourceCodePro(color: AppTheme.textMuted),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.borderColor)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
            ),
            onChanged: (value) => canId = value.trim(),
            onSubmitted: (_) => Navigator.of(context).pop(canId),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(canId),
              child: const Text('OK', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PortController>(
      builder: (context, controller, _) {
        return Container(
          height: AppConstants.tabHeight + 8,
          decoration: BoxDecoration(
            color: AppTheme.bgDark,
            border: Border(
              bottom: BorderSide(
                color: AppTheme.borderColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Tabs list
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  itemCount: controller.tabs.length,
                  itemBuilder: (context, index) {
                    return _buildTab(controller, index);
                  },
                ),
              ),

              // Add tab button
              if (controller.tabs.length < AppConstants.maxTabs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () async {
                      final canId = await _showCanIdDialog(context);
                      if (canId != null) {
                        controller.addTab(canId: canId);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: AppConstants.tabHeight,
        constraints: const BoxConstraints(minWidth: AppConstants.minTabWidth),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.bgCard
              : AppTheme.bgDark,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          border: Border(
            top: BorderSide(
              color: isActive ? AppTheme.primaryColor : Colors.transparent,
              width: 2,
            ),
            left: BorderSide(
              color: isActive ? AppTheme.borderColor : Colors.transparent,
            ),
            right: BorderSide(
              color: isActive ? AppTheme.borderColor : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tab name or editor
            if (isEditing)
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _editController,
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _finishEditing(controller, index),
                  onTapOutside: (_) => _finishEditing(controller, index),
                ),
              )
            else
              Text(
                tab.name,
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),

            // Message count badge
            if (tab.messages.isNotEmpty && !isEditing) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${tab.messages.length}',
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 9,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            // Close button
            if (controller.tabs.length > 1 && !isEditing) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => controller.removeTab(index),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
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
}
