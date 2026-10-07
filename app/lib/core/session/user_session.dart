import 'package:flutter/material.dart';

/// Central singleton holding the local user profile, avatar, and authentication state.
class UserSession extends ChangeNotifier {
  static final UserSession instance = UserSession._internal();

  UserSession._internal();

  // User Profile Data
  String _name = 'Karthik';
  String _handle = '@karthik';
  final String _nexaId = 'NX-77A1-49PQ';
  String _status = 'Encrypted & Focused';
  String _bio = 'Building decentralized AI systems. Hardware & local models.';
  int _avatarIndex = 0; // 0 to 5 preset avatars
  String? _customAvatarPath;
  bool _isLoggedIn = true;

  // Preset avatar definitions
  static const List<Map<String, dynamic>> avatarPresets = [
    {'name': 'Cyan Orbit', 'color': Color(0xFF0284C7), 'icon': Icons.public},
    {'name': 'Emerald Shield', 'color': Color(0xFF059669), 'icon': Icons.shield},
    {'name': 'Amber Pulse', 'color': Color(0xFFD97706), 'icon': Icons.bolt},
    {'name': 'Violet Node', 'color': Color(0xFF7C3AED), 'icon': Icons.hub},
    {'name': 'Rose Spark', 'color': Color(0xFFE11D48), 'icon': Icons.auto_awesome},
    {'name': 'Teal Wave', 'color': Color(0xFF0D9488), 'icon': Icons.waves},
  ];

  // Getters
  String get name => _name;
  String get handle => _handle;
  String get nexaId => _nexaId;
  String get status => _status;
  String get bio => _bio;
  int get avatarIndex => _avatarIndex;
  String? get customAvatarPath => _customAvatarPath;
  bool get isLoggedIn => _isLoggedIn;

  Map<String, dynamic> get currentAvatarPreset => avatarPresets[_avatarIndex % avatarPresets.length];

  // Update profile
  void updateProfile({
    String? name,
    String? handle,
    String? status,
    String? bio,
    int? avatarIndex,
    String? customAvatarPath,
  }) {
    if (name != null) _name = name;
    if (handle != null) _handle = handle;
    if (status != null) _status = status;
    if (bio != null) _bio = bio;
    if (avatarIndex != null) {
      _avatarIndex = avatarIndex;
      _customAvatarPath = null;
    }
    if (customAvatarPath != null) _customAvatarPath = customAvatarPath;
    notifyListeners();
  }

  // Authentication toggles
  void login({String? name, String? handle, int? avatarIndex}) {
    if (name != null) _name = name;
    if (handle != null) _handle = handle;
    if (avatarIndex != null) _avatarIndex = avatarIndex;
    _isLoggedIn = true;
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    notifyListeners();
  }
}
