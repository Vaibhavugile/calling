// lib/services/permissions_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  static const MethodChannel _native = MethodChannel('com.example.call_leads_app/native');

  /// Request runtime phone permissions. Returns true if granted.
  static Future<bool> requestPermissions({BuildContext? context}) async {
    final statuses = await [Permission.phone].request();
    final permanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (permanentlyDenied) {
      if (context != null) _showOpenSettingsDialog(context);
      return false;
    }
    return statuses[Permission.phone]?.isGranted ?? false;
  }

  static Future<void> requestDialerRole() async {
    if (!Platform.isAndroid) return;
    try {
      await _native.invokeMethod('requestDialerRole');
    } catch (e) {
      // ignore
    }
  }

  static Future<void> openAppSettingsScreen() async {
    await openAppSettings();
  }

  static void _showOpenSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissions required'),
        content: const Text('This app needs phone permissions. Open settings to grant them.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () { Navigator.of(ctx).pop(); openAppSettings(); }, child: const Text('Open Settings')),
        ],
      ),
    );
  }
}
