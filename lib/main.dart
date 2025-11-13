// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'call_event_handler.dart';
import 'screens/lead_list_screen.dart';
import 'firebase_options.dart';
import 'services/permissions_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late CallEventHandler _callEventHandler;
  final PermissionsService _permissions = PermissionsService();

  bool _initDone = false;

  @override
  void initState() {
    super.initState();

    // 🔥 Correct way: run initialization AFTER MaterialApp builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.microtask(() => _initializeApp());
    });
  }

  Future<void> _initializeApp() async {
    print("🔧 [MAIN] Starting initialization...");

    try {
      // ---------------------------
      // 1. PERMISSIONS
      // ---------------------------
      final granted = await _permissions.requestPhonePermissions();

      // ---------------------------
      // 2. CALL HANDLER
      // ---------------------------
      _callEventHandler = CallEventHandler(navigatorKey: navigatorKey);

      if (!granted) {
        // 🔥 FIX: Delay the showDialog call to ensure MaterialLocalizations is available
        if (mounted) {
          await Future.delayed(Duration.zero);
          if (navigatorKey.currentContext != null) {
            _showPermissionDeniedDialog(navigatorKey.currentContext!);
          } else {
            print("❌ [MAIN] Cannot show permission dialog: Navigator Context null.");
          }
        }
      }

      // ---------------------------
      // 3. LISTEN FOR CALLS
      // ---------------------------
      _callEventHandler.startListening();

      setState(() => _initDone = true);
      print("✅ [MAIN] Initialization complete.");
    } catch (e) {
      print("❌ [MAIN] init error: $e");
      // Still set initDone to true to show the main screen
      setState(() => _initDone = true);
    }
  }

  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text(
            'Call and Phone State permissions are required for call tracking. Please enable them in App Settings for full functionality.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _permissions.openSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    try {
      _callEventHandler.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initDone) {
      return MaterialApp(
        title: 'Call Leads',
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Initializing...'),
              ],
            ),
          ),
        ),
        debugShowCheckedModeBanner: false,
      );
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Call Leads',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const LeadListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}