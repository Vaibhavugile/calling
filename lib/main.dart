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
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  Future<void> _initializeApp() async {
    try {
      await PermissionsService.requestPermissions(context: navigatorKey.currentContext);
      _callEventHandler = CallEventHandler(navigatorKey: navigatorKey);
      await PermissionsService.requestDialerRole();
      _callEventHandler.startListening();
    } catch (e) {
      print("Init error: $e");
    } finally {
      setState(() => _initDone = true);
    }
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
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Call Leads',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: _initDone ? const LeadListScreen() : const Scaffold(body: Center(child: CircularProgressIndicator())),
      debugShowCheckedModeBanner: false,
    );
  }
}
