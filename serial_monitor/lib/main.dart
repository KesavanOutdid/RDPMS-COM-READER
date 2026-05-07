import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/controllers/port_controller.dart';
import 'core/routes/app_routes.dart';
import 'utils/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SerialMonitorApp());
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

/// Root application widget
class SerialMonitorApp extends StatelessWidget {
  const SerialMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PortController(),
      child: MaterialApp(
        title: 'RDPMS Serial Monitor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        scrollBehavior: AppScrollBehavior(),
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.routes,
      ),
    );
  }
}
