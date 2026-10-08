import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../network/auth_service.dart';

/// Real Device Contacts & NEXA Peer Directory Synchronization Service
class ContactsService {
  static final ContactsService instance = ContactsService._internal();
  ContactsService._internal();

  static const MethodChannel _nativeChannel = MethodChannel('com.nexa.media_picker');

  /// Fetches real contacts from the user's mobile device and correlates with online NEXA accounts
  Future<List<Map<String, dynamic>>> fetchDeviceContacts() async {
    if (kIsWeb) {
      // In web browser environment, return empty list (web clients use NEXA ID / Directory search)
      return [];
    }

    try {
      // 1. Check or request contacts permission natively on Android
      final bool hasPermission = await requestContactsPermission();
      if (!hasPermission) {
        debugPrint('[ContactsService] Device contacts permission denied or not granted.');
        return [];
      }

      // 2. Fetch native contacts via Android content resolver
      final dynamic raw = await _nativeChannel.invokeMethod('getNativeContacts');
      if (raw is List) {
        final List<Map<String, dynamic>> deviceList = raw.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final rawPhone = (map['phone'] as String?) ?? '';
          final cleanPhone = rawPhone.replaceAll(RegExp(r'[\s\-()]'), '').trim();
          return {
            'name': (map['name'] as String?) ?? 'Contact',
            'phone': cleanPhone,
            'isOnNexa': false,
            'nexaUser': null,
          };
        }).where((c) => (c['name'] as String).isNotEmpty || (c['phone'] as String).isNotEmpty).toList();

        // 3. Correlate with registered NEXA users via server-side sync API
        return await syncDeviceContactsWithServer(deviceList);
      }
    } catch (e) {
      debugPrint('[ContactsService] Native fetch error: $e');
    }
    return [];
  }

  /// Request runtime contacts permission on device
  Future<bool> requestContactsPermission() async {
    try {
      final dynamic isGranted = await _nativeChannel.invokeMethod('checkNativePermission', {
        'permission': 'contacts',
      });
      if (isGranted == true) return true;

      final dynamic requested = await _nativeChannel.invokeMethod('requestNativePermission', {
        'permission': 'contacts',
      });
      return requested == true;
    } catch (e) {
      debugPrint('[ContactsService] Permission request error: $e');
      return false;
    }
  }

  /// Synchronizes device contact phone numbers with the NEXA directory
  Future<List<Map<String, dynamic>>> syncDeviceContactsWithServer(
    List<Map<String, dynamic>> contacts,
  ) async {
    if (contacts.isEmpty) return contacts;

    try {
      final phones = contacts
          .map((c) => (c['phone'] as String?) ?? '')
          .where((p) => p.length >= 7)
          .toList();

      if (phones.isEmpty) return contacts;

      final response = await AuthService.instance.postJson('/v1/auth/contacts/sync', {
        'phones': phones,
      });

      if (response != null && response['contacts'] is List) {
        final matchedList = List<Map<String, dynamic>>.from(response['contacts'] as List);
        final phoneToUserMap = <String, Map<String, dynamic>>{};

        for (final user in matchedList) {
          final rawPhone = (user['phone'] ?? '').toString();
          final clean = rawPhone.replaceAll(RegExp(r'[\s\-()]'), '');
          if (clean.isNotEmpty) {
            phoneToUserMap[clean] = user;
            // Also store suffix (e.g. last 10 digits) for national format matching
            if (clean.length > 10) {
              phoneToUserMap[clean.substring(clean.length - 10)] = user;
            }
          }
        }

        return contacts.map((c) {
          final cPhone = (c['phone'] as String? ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
          Map<String, dynamic>? match = phoneToUserMap[cPhone];
          if (match == null && cPhone.length > 10) {
            match = phoneToUserMap[cPhone.substring(cPhone.length - 10)];
          }

          if (match != null) {
            return {
              ...c,
              'isOnNexa': true,
              'nexaUser': match,
              'nexaId': match['nexaId'] ?? match['nexa_id'],
              'handle': match['handle'] ?? '@${match['username']}',
            };
          }
          return c;
        }).toList();
      }
    } catch (e) {
      debugPrint('[ContactsService] Server sync error: $e');
    }
    return contacts;
  }

  /// Searches the online NEXA user directory by NEXA ID, @username, or phone
  Future<List<Map<String, dynamic>>> searchNexaDirectory(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      
      // 1. Try unified lookup endpoint
      final lookupUri = Uri.parse('$baseUrl/v1/users/lookup?q=${Uri.encodeComponent(clean)}');
      final lookupRes = await AuthService.instance.getJson(lookupUri);
      if (lookupRes != null && lookupRes['users'] is List) {
        final list = List<Map<String, dynamic>>.from(lookupRes['users'] as List);
        if (list.isNotEmpty) return list;
      }

      // 2. Fallback to direct identifier resolution (@username or NX-ID)
      final resolveUri = Uri.parse('$baseUrl/v1/directory/resolve/${Uri.encodeComponent(clean)}');
      final resolveRes = await AuthService.instance.getJson(resolveUri);
      if (resolveRes != null && resolveRes['user_id'] != null) {
        return [
          {
            'username': resolveRes['username'] ?? clean,
            'handle': resolveRes['handle'] ?? '@$clean',
            'fullName': resolveRes['full_name'] ?? clean,
            'nexaId': resolveRes['user_id'],
            'phone': resolveRes['phone'] ?? '',
            'about': 'Verified NEXA Peer',
          }
        ];
      }

      // 3. Fallback to directory users list filtered client-side
      final dirUri = Uri.parse('$baseUrl/v1/directory/users');
      final dirRes = await AuthService.instance.getJson(dirUri);
      if (dirRes != null && dirRes['users'] is List) {
        final qLower = clean.toLowerCase();
        final allUsers = List<Map<String, dynamic>>.from(dirRes['users'] as List);
        return allUsers.where((u) {
          final un = (u['username'] ?? '').toString().toLowerCase();
          final fn = (u['full_name'] ?? u['fullName'] ?? '').toString().toLowerCase();
          final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toLowerCase();
          return un.contains(qLower) || fn.contains(qLower) || nid.contains(qLower);
        }).toList();
      }
    } catch (e) {
      debugPrint('[ContactsService] Directory search error: $e');
    }
    return [];
  }

  /// Correlates device contacts against registered NEXA accounts in-memory
  List<Map<String, dynamic>> correlateContactsWithRegistered(
    List<Map<String, dynamic>> deviceContacts,
    List<Map<String, dynamic>> registeredUsers,
  ) {
    final phoneMap = <String, Map<String, dynamic>>{};
    for (final u in registeredUsers) {
      final rawPhone = (u['phone'] as String?) ?? '';
      final clean = rawPhone.replaceAll(RegExp(r'[\s\-()]'), '').trim();
      if (clean.isNotEmpty) {
        phoneMap[clean] = u;
        if (clean.length > 10) {
          phoneMap[clean.substring(clean.length - 10)] = u;
        }
      }
    }

    return deviceContacts.map((c) {
      final contactPhone = ((c['phone'] as String?) ?? '').replaceAll(RegExp(r'[\s\-()]'), '').trim();
      Map<String, dynamic>? matched = phoneMap[contactPhone];
      if (matched == null && contactPhone.length > 10) {
        matched = phoneMap[contactPhone.substring(contactPhone.length - 10)];
      }

      return {
        ...c,
        'isOnNexa': matched != null,
        'nexaUser': matched,
        'nexaId': matched != null ? (matched['nexaId'] ?? matched['nexa_id']) : null,
        'handle': matched != null ? (matched['handle'] ?? '@${matched['username']}') : null,
      };
    }).toList();
  }
}
