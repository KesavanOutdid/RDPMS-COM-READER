import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config/app_constants.dart';
import 'core/controllers/port_controller.dart';
import 'core/controllers/bulk_firmware_controller.dart';
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PortController()),
        ChangeNotifierProvider(create: (_) => BulkFirmwareController()),
      ],
      child: Consumer<PortController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: controller.windowTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            scrollBehavior: AppScrollBehavior(),
            initialRoute: AppRoutes.splash,
            routes: AppRoutes.routes,
            builder: (context, child) {
              // Update the native window title dynamically (#14)
              return Title(
                title: controller.windowTitle,
                color: AppTheme.primaryColor,
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}

