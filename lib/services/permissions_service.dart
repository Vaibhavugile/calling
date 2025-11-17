// lib/services/permissions_service.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  // Must match the MethodChannel name in MainActivity.kt
  static const MethodChannel _native =
      MethodChannel('com.example.call_leads_app/native');

  /// Request runtime permissions needed for call detection.
  /// Requests READ_PHONE_STATE/CALL_PHONE via Permission.phone (umbrella).
  /// Note: READ_CALL_LOG may not be exposed directly by permission_handler on
  /// all versions — you may need a native request for READ_CALL_LOG if needed.
  /// Returns true if all required permissions are granted.
  static Future<bool> requestPermissions({BuildContext? context}) async {
    // Use Permission.phone as the umbrella for phone related permissions.
    final Map<Permission, PermissionStatus> statuses =
        await [Permission.phone, Permission.contacts].request();

    // If any critical permission is permanently denied, prompt to open settings.
    bool permanentlyDenied =
        statuses.values.any((s) => s.isPermanentlyDenied || s.isDenied && !s.isRestricted);

    if (permanentlyDenied) {
      if (context != null) {
        _showOpenSettingsDialog(context);
      }
      return false;
    }

    // Consider success when Permission.phone is granted.
    final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;
    return phoneGranted;
  }

  /// Helper that requests permissions and then requests dialer role.
  /// Use from initState — passing context is optional.
  static Future<void> ensurePermissionsAndRole({BuildContext? context}) async {
    final granted = await requestPermissions(context: context);
    if (!granted) {
      debugPrint('[PermissionsService] Not all permissions granted');
    } else {
      debugPrint('[PermissionsService] Runtime permissions granted');
    }

    // Attempt to show the dialer role dialog (Android Q+). This is a no-op on older Android.
    try {
      await requestDialerRole();
      debugPrint(
          '[PermissionsService] Requested dialer role (native prompt should appear on Android Q+)');
    } on PlatformException catch (e) {
      debugPrint(
          '[PermissionsService] PlatformException while requesting role: ${e.message}');
    } catch (e) {
      debugPrint('[PermissionsService] Error while requesting role: $e');
    }
  }

  /// Calls the MethodChannel to ask the native Android side to request the
  /// ROLE_DIALER / default phone app.
  static Future<void> requestDialerRole() async {
    if (!Platform.isAndroid) return;
    await _native.invokeMethod('requestDialerRole');
  }

  /// Open app settings to allow the user to grant permissions manually.
  static Future<void> openAppSettingsScreen() async {
    await openAppSettings();
  }

  static void _showOpenSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Permissions required'),
        content: Text(
            'This app needs permission to read phone state (and call logs) so it can detect calls. '
            'Please open app settings and enable the permissions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
