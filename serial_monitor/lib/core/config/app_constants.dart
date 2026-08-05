/// Application-wide constants for Serial Port Monitor
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'RDPMS Serial Monitor';
  static const String appVersion = '1.0.0';

  // Backend API Server Config (Host machine IP for local network sharing)
  static const String backendHost = '192.168.0.38';
  static const int backendPort = 3001;
  static const String apiBaseUrl = 'http://$backendHost:$backendPort/api';

  // Tab Limits
  static const int maxTabs = 20;
  static const int maxMessagesPerTab = 5000;

  // Default Port Settings
  static const int defaultBaudRate = 115200;
  static const String defaultDataBits = '8';
  static const String defaultStopBits = '1';
  static const String defaultParity = 'None';
  static const String defaultFlowControl = 'None';

  // Common Baud Rates
  static const List<int> commonBaudRates = [
    300,
    1200,
    2400,
    4800,
    9600,
    14400,
    19200,
    28800,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];

  // Data Bits Options
  static const List<String> dataBitsOptions = ['5', '6', '7', '8'];

  // Stop Bits Options
  static const List<String> stopBitsOptions = ['1', '1.5', '2'];

  // Parity Options
  static const List<String> parityOptions = ['None', 'Even', 'Odd', 'Mark', 'Space'];

  // Flow Control Options
  static const List<String> flowControlOptions = ['None', 'XON/XOFF', 'RTS/CTS', 'DSR/DTR'];

  // Display Modes
  static const List<String> displayModes = ['ASCII', 'HEX', 'DEC', 'BIN'];

  // Send Modes
  static const List<String> sendModes = ['ASCII', 'HEX', 'DEC', 'BIN'];

  // Line Ending Options
  static const Map<String, String> lineEndings = {
    'None': '',
    'CR': '\r',
    'LF': '\n',
    'CR+LF': '\r\n',
  };

  // UI Constants
  static const double sidebarWidth = 280.0;
  static const double minTabWidth = 120.0;
  static const double tabHeight = 36.0;

  // UI Feature Flags
  static const bool showOnlyTestOption = false;

  // Splash Screen Duration — fast for desktop tools
  static const Duration splashDuration = Duration(milliseconds: 800);
}
