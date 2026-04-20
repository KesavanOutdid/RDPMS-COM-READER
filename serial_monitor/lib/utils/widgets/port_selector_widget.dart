import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_constants.dart';
import '../../core/controllers/port_controller.dart';
import '../../core/services/serial_port_service.dart';
import '../theme/app_theme.dart';

/// Sidebar widget for port configuration and connection
class PortSelectorWidget extends StatelessWidget {
  const PortSelectorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PortController>(
      builder: (context, controller, _) {
        return Container(
          width: AppConstants.sidebarWidth,
          decoration: BoxDecoration(
            color: AppTheme.bgDark,
            border: Border(
              right: BorderSide(
                color: AppTheme.borderColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(controller),
              const Divider(height: 1),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Connection status indicator
                      _buildStatusIndicator(controller),
                      const SizedBox(height: 20),

                      // Port selection
                      _buildSectionTitle('PORT'),
                      const SizedBox(height: 8),
                      _buildPortDropdown(controller),
                      const SizedBox(height: 6),
                      _buildRefreshButton(controller),
                      const SizedBox(height: 20),

                      // Baud rate
                      _buildSectionTitle('BAUD RATE'),
                      const SizedBox(height: 8),
                      _buildBaudRateDropdown(controller),
                      const SizedBox(height: 20),

                      // Data bits
                      _buildSectionTitle('DATA BITS'),
                      const SizedBox(height: 8),
                      _buildDataBitsDropdown(controller),
                      const SizedBox(height: 20),

                      // Stop bits
                      _buildSectionTitle('STOP BITS'),
                      const SizedBox(height: 8),
                      _buildStopBitsDropdown(controller),
                      const SizedBox(height: 20),

                      // Parity
                      _buildSectionTitle('PARITY'),
                      const SizedBox(height: 8),
                      _buildParityDropdown(controller),
                      const SizedBox(height: 24),

                      // Connect/Disconnect button
                      _buildConnectButton(controller),
                      const SizedBox(height: 20),

                      // Statistics
                      if (controller.isConnected) ...[
                        const Divider(),
                        const SizedBox(height: 12),
                        _buildSectionTitle('STATISTICS'),
                        const SizedBox(height: 8),
                        _buildStatistics(controller),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.bgDark,
            AppTheme.bgMedium.withValues(alpha: 0.5),
          ],
        ),
      ),
      child: Row(
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
              Icons.settings_input_hdmi_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONNECTION',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'Serial Port Configuration',
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(PortController controller) {
    final isConnected = controller.isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (isConnected ? AppTheme.receivedColor : AppTheme.errorColor)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isConnected ? AppTheme.receivedColor : AppTheme.errorColor)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? AppTheme.receivedColor
                  : AppTheme.errorColor,
              boxShadow: [
                BoxShadow(
                  color: (isConnected
                          ? AppTheme.receivedColor
                          : AppTheme.errorColor)
                      .withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              controller.statusMessage,
              style: GoogleFonts.sourceCodePro(
                fontSize: 11,
                color: isConnected
                    ? AppTheme.receivedColor
                    : AppTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.rajdhani(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.primaryColor,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildPortDropdown(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: controller.availablePorts.contains(controller.config.portName)
              ? controller.config.portName
              : null,
          hint: Text(
            'Select Port',
            style: GoogleFonts.sourceCodePro(
              fontSize: 13,
              color: AppTheme.textMuted,
            ),
          ),
          isExpanded: true,
          dropdownColor: AppTheme.bgSurface,
          style: GoogleFonts.sourceCodePro(
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          items: controller.availablePorts.map((port) {
            final desc = SerialPortService.getPortDescription(port);
            return DropdownMenuItem(
              value: port,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(port, style: const TextStyle(fontSize: 13)),
                  if (desc != port)
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: controller.isConnected
              ? null
              : (value) {
                  if (value != null) {
                    controller.updateConfig(portName: value);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildRefreshButton(PortController controller) {
    return TextButton.icon(
      onPressed: controller.isConnected ? null : controller.refreshPorts,
      icon: Icon(
        Icons.refresh_rounded,
        size: 16,
        color: controller.isConnected
            ? AppTheme.textMuted
            : AppTheme.primaryColor,
      ),
      label: Text(
        'Refresh Ports',
        style: GoogleFonts.rajdhani(
          fontSize: 12,
          color: controller.isConnected
              ? AppTheme.textMuted
              : AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildBaudRateDropdown(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: controller.config.baudRate,
          isExpanded: true,
          dropdownColor: AppTheme.bgSurface,
          style: GoogleFonts.sourceCodePro(
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          items: AppConstants.commonBaudRates.map((rate) {
            return DropdownMenuItem(
              value: rate,
              child: Text(rate.toString()),
            );
          }).toList(),
          onChanged: controller.isConnected
              ? null
              : (value) {
                  if (value != null) {
                    controller.updateConfig(baudRate: value);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildDataBitsDropdown(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: controller.config.dataBits,
          isExpanded: true,
          dropdownColor: AppTheme.bgSurface,
          style: GoogleFonts.sourceCodePro(
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          items: AppConstants.dataBitsOptions.map((d) {
            final val = int.parse(d);
            return DropdownMenuItem(value: val, child: Text(d));
          }).toList(),
          onChanged: controller.isConnected
              ? null
              : (value) {
                  if (value != null) {
                    controller.updateConfig(dataBits: value);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildStopBitsDropdown(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: controller.config.stopBits,
          isExpanded: true,
          dropdownColor: AppTheme.bgSurface,
          style: GoogleFonts.sourceCodePro(
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1')),
            DropdownMenuItem(value: 2, child: Text('2')),
          ],
          onChanged: controller.isConnected
              ? null
              : (value) {
                  if (value != null) {
                    controller.updateConfig(stopBits: value);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildParityDropdown(PortController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: controller.config.parity,
          isExpanded: true,
          dropdownColor: AppTheme.bgSurface,
          style: GoogleFonts.sourceCodePro(
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('None')),
            DropdownMenuItem(value: 1, child: Text('Odd')),
            DropdownMenuItem(value: 2, child: Text('Even')),
            DropdownMenuItem(value: 3, child: Text('Mark')),
            DropdownMenuItem(value: 4, child: Text('Space')),
          ],
          onChanged: controller.isConnected
              ? null
              : (value) {
                  if (value != null) {
                    controller.updateConfig(parity: value);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildConnectButton(PortController controller) {
    final isConnected = controller.isConnected;
    final isConnecting = controller.isConnecting;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: ElevatedButton.icon(
        onPressed: isConnecting ? null : controller.toggleConnection,
        icon: isConnecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                isConnected ? Icons.link_off_rounded : Icons.link_rounded,
                size: 20,
              ),
        label: Text(
          isConnecting
              ? 'CONNECTING...'
              : isConnected
                  ? 'DISCONNECT'
                  : 'CONNECT',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isConnected ? AppTheme.errorColor : AppTheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildStatistics(PortController controller) {
    return Column(
      children: [
        _buildStatRow(
          'TX Bytes',
          controller.totalBytesSent.toString(),
          AppTheme.sentColor,
        ),
        const SizedBox(height: 6),
        _buildStatRow(
          'RX Bytes',
          controller.totalBytesReceived.toString(),
          AppTheme.receivedColor,
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: controller.resetCounters,
          icon: const Icon(Icons.restart_alt_rounded, size: 14),
          label: Text(
            'Reset Counters',
            style: GoogleFonts.rajdhani(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            value,
            style: GoogleFonts.sourceCodePro(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
