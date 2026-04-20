import 'package:flutter/material.dart';
import '../../feature/serial_port/views/serial_port_screen.dart';
import '../view/splash_screen.dart';

/// Route definitions for the application
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String home = '/home';

  static Map<String, WidgetBuilder> get routes => {
        splash: (context) => const SplashScreen(),
        home: (context) => const SerialPortScreen(),
      };
}
