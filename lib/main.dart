import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/dojo_theme.dart';
import 'core/dojo_provider.dart';
import 'presentation/pages/biometric_gate_page.dart';
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
class RolodojoApp extends StatefulWidget {
  const RolodojoApp({super.key});

  @override
  State<RolodojoApp> createState() => _RolodojoAppState();
}

class _RolodojoAppState extends State<RolodojoApp> {
  bool _isAuthenticated = false;

  // Set to true to skip biometric gate during development
  static const bool _devMode = true;

  late final Future<DojoProvider> _providerFuture;

  @override
  void initState() {
    super.initState();
    _providerFuture = DojoProvider.initialize(
      child: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DojoProvider>(
      future: _providerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DojoTheme.dark,
            home: const _LoadingScreen(),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DojoTheme.dark,
            home: _ErrorScreen(error: snapshot.error.toString()),
          );
        }

        final provider = snapshot.data!;

        final home = _isAuthenticated || _devMode
            ? const DojoHomePage()
            : BiometricGatePage(
                onAuthenticated: () {
                  setState(() {
                    _isAuthenticated = true;
                  });
                },
                allowSkip: _devMode,
                onSkip: _devMode
                    ? () {
                        setState(() {
                          _isAuthenticated = true;
                        });
                      }
                    : null,
              );

        return DojoProvider(
          dojoService: provider.dojoService,
          librarianService: provider.librarianService,
          backupService: provider.backupService,
          senseiLlm: provider.senseiLlm,
          synthesisService: provider.synthesisService,
          roloRepository: provider.roloRepository,
          recordRepository: provider.recordRepository,
          attributeRepository: provider.attributeRepository,
          journalRepository: provider.journalRepository,
          userRepository: provider.userRepository,
          senseiRepository: provider.senseiRepository,
          child: MaterialApp(
            title: 'ROLODOJO',
            debugShowCheckedModeBanner: false,
            theme: DojoTheme.dark,
            home: home,
          ),
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: DojoColors.slate,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🥋', style: TextStyle(fontSize: 48)),
            SizedBox(height: 24),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DojoColors.senseiGold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Opening the Dojo...',
              style: TextStyle(color: DojoColors.textHint, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  const _ErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DojoColors.slate,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: DojoColors.alert, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Failed to open the Dojo',
                style: TextStyle(
                  color: DojoColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
