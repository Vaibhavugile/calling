// lib/services/permissions_service.dart
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Request all needed permissions for:
  /// - incoming/outgoing call detection
  /// - reading caller number
  /// - notifications (Android 13+)
  Future<bool> requestPhonePermissions() async {
    print("🔐 [PERM] Requesting phone permissions...");

    // List of permissions to request
    final List<Permission> perms = [
      Permission.phone,
      // 🔥 REMOVED: Permission.microphone is not required for basic call detection.
    ];

    // Android 13+ notification runtime permission
    if (Platform.isAndroid && (await Permission.notification.isDenied)) {
      perms.add(Permission.notification);
    }

    // Request all permissions at once
    final statuses = await perms.request();

    // Debug output
    statuses.forEach((p, status) {
      print("🔐 [PERM] ${p.toString().split('.').last} → $status");
    });

    // 🔥 REQUIRED PERMISSIONS: Only PHONE
    final required = [Permission.phone];
    // Check if all required permissions (phone) are granted
    final allGranted = required.every((p) => statuses[p]?.isGranted ?? false);

    if (!allGranted) {
      print("❌ [PERM] Required permissions NOT granted.");
      return false;
    }

    print("✅ [PERM] All required permissions granted.");
    return true;
  }

  /// Open application settings where user can manually enable permissions
  Future<void> openSettings() => openAppSettings();
}