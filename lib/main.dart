import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/dojo_theme.dart';
import 'presentation/pages/dojo_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait for consistent UX
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for Dojo Dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: DojoColors.slate,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const RolodojoApp());
}

/// The root widget of the Rolodojo application.
class RolodojoApp extends StatelessWidget {
  const RolodojoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ROLODOJO',
      debugShowCheckedModeBanner: false,
      theme: DojoTheme.dark,
      home: const DojoHomePage(),
    );
  }
}
