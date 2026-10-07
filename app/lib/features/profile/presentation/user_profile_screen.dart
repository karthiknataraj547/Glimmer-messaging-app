import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/session/user_session.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../auth/presentation/device_link_qr_screen.dart';
import '../../admin/presentation/admin_panel_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final UserSession _session = UserSession.instance;
  static const MethodChannel _nativeMediaChannel = MethodChannel('com.nexa.media_picker');

  late TextEditingController _nameController;
  late TextEditingController _statusController;
  late TextEditingController _bioController;
  late int _selectedAvatarIndex;
  String? _customAvatarPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _session.name);
    _statusController = TextEditingController(text: _session.status);
    _bioController = TextEditingController(text: _session.bio);
    _selectedAvatarIndex = _session.avatarIndex;
    _customAvatarPath = _session.customAvatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    _session.updateProfile(
      name: _nameController.text.trim(),
      status: _statusController.text.trim(),
      bio: _bioController.text.trim(),
      avatarIndex: _selectedAvatarIndex,
      customAvatarPath: _customAvatarPath,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile and avatar updated successfully!'),
        backgroundColor: NexaColors.emeraldSecure,
      ),
    );

    Navigator.pop(context);
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: NexaColors.borderLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Choose Your Avatar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: NexaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select a decentralized avatar badge or upload your personal photo.',
                      style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                    ),
                    const SizedBox(height: 20),

                    // Grid of 6 Preset Avatars
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: UserSession.avatarPresets.length,
                      itemBuilder: (context, index) {
                        final preset = UserSession.avatarPresets[index];
                        final isSelected = _selectedAvatarIndex == index;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedAvatarIndex = index;
                              _customAvatarPath = null;
                            });
                            setModalState(() {});
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (preset['color'] as Color).withValues(alpha: 0.12)
                                  : NexaColors.elevatedLight,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? (preset['color'] as Color) : NexaColors.borderLight,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: preset['color'] as Color,
                                  child: Icon(preset['icon'] as IconData, color: Colors.white, size: 20),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  preset['name'] as String,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: NexaColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(ctx);
                              try {
                                final dynamic permGranted = await _nativeMediaChannel.invokeMethod('requestNativePermission', {'permission': 'camera'});
                                if (permGranted == false) {
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Camera permission is required to take a profile photo.')),
                                  );
                                  return;
                                }
                                final dynamic result = await _nativeMediaChannel.invokeMethod('openInbuiltCamera');
                                if (!mounted) return;
                                if (result != null && result is Map && result['path'] != null) {
                                  setState(() {
                                    _customAvatarPath = result['path'] as String;
                                  });
                                  setModalState(() {});
                                  navigator.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Inbuilt camera photo captured & set as profile picture!')),
                                  );
                                }
                              } catch (e) {
                                if (!mounted) return;
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Camera error: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.camera_alt_outlined, size: 16),
                            label: const Text('Take Photo'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(ctx);
                              try {
                                final dynamic permGranted = await _nativeMediaChannel.invokeMethod('requestNativePermission', {'permission': 'storage'});
                                if (permGranted == false) {
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Gallery/Photos permission is required to choose a profile photo.')),
                                  );
                                  return;
                                }
                                final dynamic result = await _nativeMediaChannel.invokeMethod('openInbuiltGallery');
                                if (!mounted) return;
                                if (result != null && result is Map && result['path'] != null) {
                                  setState(() {
                                    _customAvatarPath = result['path'] as String;
                                  });
                                  setModalState(() {});
                                  navigator.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Gallery photo selected & set as profile picture!')),
                                  );
                                }
                              } catch (e) {
                                if (!mounted) return;
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Gallery error: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.photo_outlined, size: 16),
                            label: const Text('From Gallery'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showNexaIdQrModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NexaColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner, color: NexaColors.primary, size: 30),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your Cryptographic QR',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NexaColors.textPrimary),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Peers can scan this QR to start end-to-end encrypted chats without disclosing phone numbers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NexaColors.borderLight),
                  ),
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.qr_code_2, size: 110, color: Colors.black),
                          Text(_session.nexaId, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _session.nexaId));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('NEXA ID copied to clipboard')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy NEXA ID'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPreset = UserSession.avatarPresets[_selectedAvatarIndex % UserSession.avatarPresets.length];

    return Scaffold(
      backgroundColor: NexaColors.canvasLight,
      appBar: AppBar(
        title: const Text('My Profile & Vault'),
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text('Save', style: TextStyle(color: NexaColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Avatar Center Stage with Edit Badge
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _showAvatarPicker,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: (currentPreset['color'] as Color), width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: (currentPreset['color'] as Color),
                      backgroundImage: (_customAvatarPath != null && File(_customAvatarPath!).existsSync())
                          ? FileImage(File(_customAvatarPath!))
                          : null,
                      child: (_customAvatarPath != null && File(_customAvatarPath!).existsSync())
                          ? null
                          : Icon(currentPreset['icon'] as IconData, color: Colors.white, size: 48),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: _showAvatarPicker,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NexaColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _showAvatarPicker,
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('Change Profile Picture'),
            ),
          ),
          const SizedBox(height: 20),

          // User Cryptographic Identity Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NexaColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NexaColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Self-Sovereign NEXA ID',
                          style: TextStyle(fontWeight: FontWeight.bold, color: NexaColors.textPrimary, fontSize: 13),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: NexaColors.emeraldSecure.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _session.nexaId,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: NexaColors.primary,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.qr_code, color: NexaColors.primary, size: 20),
                          tooltip: 'Show QR Code',
                          onPressed: _showNexaIdQrModal,
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: NexaColors.textSecondary, size: 18),
                          tooltip: 'Copy NEXA ID',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _session.nexaId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('NEXA ID copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text('EDITABLE DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
          const SizedBox(height: 12),

          // Display Name Field
          _buildTextField(
            label: 'Display Name',
            controller: _nameController,
            icon: Icons.person_outline,
            hint: 'Your display name',
          ),
          const SizedBox(height: 14),

          // Status Field
          _buildTextField(
            label: 'Status Message',
            controller: _statusController,
            icon: Icons.chat_bubble_outline,
            hint: 'e.g. Encrypted & Focused',
          ),
          const SizedBox(height: 14),

          // Bio Field
          _buildTextField(
            label: 'Bio / Interests',
            controller: _bioController,
            icon: Icons.info_outline,
            hint: 'Brief decentralized bio',
            maxLines: 2,
          ),

          const SizedBox(height: 24),
          const Text('SECURITY & LINKED HARDWARE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
          const SizedBox(height: 12),

          // Linked Devices Tile
          Material(
            color: NexaColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: NexaColors.borderLight),
            ),
            child: ListTile(
              leading: const Icon(Icons.devices, color: NexaColors.primary),
              title: const Text('Linked Devices', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('2 Authorized hardware sessions'),
              trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Server Admin Control Center Tile
          Material(
            color: NexaColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _session.handle.toLowerCase().contains('admin')
                    ? Colors.purple.withValues(alpha: 0.5)
                    : NexaColors.borderLight,
              ),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.admin_panel_settings, color: Colors.purple, size: 20),
              ),
              title: Row(
                children: [
                  const Text('Admin Control Center', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'CONTROLLER',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: const Text('Users database, security logs & server telemetry'),
              trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Save Changes Big Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save Profile Changes'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexaColors.borderLight),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: NexaColors.textSecondary, fontSize: 13),
          hintText: hint,
          prefixIcon: Icon(icon, color: NexaColors.textMuted, size: 20),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
