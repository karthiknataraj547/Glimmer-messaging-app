import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../network/auth_service.dart';

/// Real Device Contacts & NEXA Peer Directory Service
class ContactsService {
  static final ContactsService instance = ContactsService._internal();
  ContactsService._internal();

  static const MethodChannel _nativeChannel = MethodChannel('com.nexa.media_picker');

  /// Fetches real contacts from the user's mobile device
  Future<List<Map<String, dynamic>>> fetchDeviceContacts() async {
    if (kIsWeb) {
      // In web browser environment, return empty list or directory contacts
      return [];
    }

    try {
      // 1. Check or request contacts permission natively
      final bool hasPermission = await _checkAndRequestPermission();
      if (!hasPermission) {
        return [];
      }

      // 2. Fetch native contacts
      final dynamic raw = await _nativeChannel.invokeMethod('getNativeContacts');
      if (raw is List) {
        return raw.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return {
            'name': (map['name'] as String?) ?? 'Contact',
            'phone': (map['phone'] as String?) ?? '',
            'isOnNexa': false,
            'nexaUser': null,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[ContactsService] Native fetch error: $e');
    }
    return [];
  }

  Future<bool> _checkAndRequestPermission() async {
    try {
      final dynamic isGranted = await _nativeChannel.invokeMethod('checkNativePermission', {
        'permission': 'contacts',
      });
      if (isGranted == true) return true;

      final dynamic requested = await _nativeChannel.invokeMethod('requestNativePermission', {
        'permission': 'contacts',
      });
      return requested == true;
    } catch (_) {
      return false;
    }
  }

  /// Searches the online NEXA user directory by NEXA ID, @username, or phone
  Future<List<Map<String, dynamic>>> searchNexaDirectory(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/users/lookup?q=${Uri.encodeComponent(query.trim())}');
      final response = await AuthService.instance.getJson(uri);
      if (response != null && response['users'] is List) {
        return List<Map<String, dynamic>>.from(response['users'] as List);
      }
    } catch (e) {
      debugPrint('[ContactsService] Directory search error: $e');
    }
    return [];
  }

  /// Correlates device contacts against registered NEXA accounts
  List<Map<String, dynamic>> correlateContactsWithRegistered(
    List<Map<String, dynamic>> deviceContacts,
    List<Map<String, dynamic>> registeredUsers,
  ) {
    final phoneMap = <String, Map<String, dynamic>>{};
    for (final u in registeredUsers) {
      final rawPhone = (u['phone'] as String?) ?? '';
      final clean = rawPhone.replaceAll(RegExp(r'\s+|-'), '').trim();
      if (clean.isNotEmpty) {
        phoneMap[clean] = u;
      }
    }

    return deviceContacts.map((c) {
      final contactPhone = ((c['phone'] as String?) ?? '').replaceAll(RegExp(r'\s+|-'), '').trim();
      final matched = phoneMap[contactPhone];
      return {
        ...c,
        'isOnNexa': matched != null,
        'nexaUser': matched,
      };
    }).toList();
  }
}
