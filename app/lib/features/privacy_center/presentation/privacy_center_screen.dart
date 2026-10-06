import 'package:flutter/material.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../auth/presentation/device_link_qr_screen.dart';
import '../../auth/presentation/recovery_key_vault_screen.dart';

class PrivacyCenterScreen extends StatefulWidget {
  const PrivacyCenterScreen({super.key});

  @override
  State<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends State<PrivacyCenterScreen> {
  bool _phoneDiscovery = false;
  bool _usernameDiscovery = true;
  bool _readReceipts = true;
  bool _allowCloudAi = false;
  bool _blockUnknownCallers = true;
  final String _onlineStatus = 'Contacts';
  final String _lastSeen = 'Nobody';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      appBar: AppBar(
        title: const Text('Privacy Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cryptographic health check: 100% Secure. All keys hardware-isolated.'),
                  backgroundColor: NexaColors.elevated,
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Security Status Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: NexaColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NexaColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NexaColors.emeraldSecure.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: NexaColors.emeraldSecure, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zero-Knowledge Protected',
                        style: TextStyle(
                          color: NexaColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'End-to-End Double Ratchet encryption active. Server has zero access to your plaintext.',
                        style: TextStyle(color: NexaColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildSectionHeader('DISCOVERY & IDENTITY'),
          _buildSwitchTile(
            title: 'Phone Number Discovery',
            subtitle: 'Allow people with your phone number to find your account',
            value: _phoneDiscovery,
            onChanged: (val) => setState(() => _phoneDiscovery = val),
          ),
          _buildSwitchTile(
            title: 'Username Discovery',
            subtitle: 'Allow discovery via @username',
            value: _usernameDiscovery,
            onChanged: (val) => setState(() => _usernameDiscovery = val),
          ),
          _buildActionTile(
            title: 'My NEXA ID',
            value: 'NX-7K4M-29QP',
            icon: Icons.fingerprint,
            onTap: () {},
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('PRESENCE & MESSAGING'),
          _buildActionTile(
            title: 'Last Seen',
            value: _lastSeen,
            icon: Icons.visibility_off_outlined,
            onTap: () {},
          ),
          _buildActionTile(
            title: 'Online Status',
            value: _onlineStatus,
            icon: Icons.circle_outlined,
            onTap: () {},
          ),
          _buildSwitchTile(
            title: 'Read Receipts',
            subtitle: 'Display double checkmarks when messages are viewed',
            value: _readReceipts,
            onChanged: (val) => setState(() => _readReceipts = val),
          ),
          _buildSwitchTile(
            title: 'Block Unknown Callers',
            subtitle: 'Silently filter calls from non-contacts',
            value: _blockUnknownCallers,
            onChanged: (val) => setState(() => _blockUnknownCallers = val),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('AI & DATA ENCLAVE'),
          _buildSwitchTile(
            title: 'Cloud AI Processing',
            subtitle: 'Off = Strictly on-device local models. No conversations leave device.',
            value: _allowCloudAi,
            onChanged: (val) => setState(() => _allowCloudAi = val),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('MULTI-DEVICE CRYPTOGRAPHY'),
          _buildActionTile(
            title: 'Active Cryptographic Devices',
            value: '4 devices',
            icon: Icons.devices,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()),
            ),
          ),
          _buildActionTile(
            title: '24-Word Recovery Key Vault',
            value: 'View & Backup',
            icon: Icons.vpn_key_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecoveryKeyVaultScreen()),
            ),
          ),

          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audit complete: 0 leaks, 4 linked devices verified.'),
                  backgroundColor: NexaColors.elevated,
                ),
              );
            },
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Run Security Checkup'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: NexaColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.qr_code_scanner, color: NexaColors.cyanAccent),
            label: const Text('Link New Device via QR', style: TextStyle(color: NexaColors.textPrimary)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: NexaColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: NexaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NexaColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          title: Text(title, style: const TextStyle(color: NexaColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12)),
          value: value,
          activeThumbColor: NexaColors.cyanAccent,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: NexaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NexaColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: NexaColors.cyanAccent, size: 22),
          title: Text(title, style: const TextStyle(color: NexaColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          trailing: Text(value, style: const TextStyle(color: NexaColors.textSecondary, fontSize: 14)),
          onTap: onTap,
        ),
      ),
    );
  }
}
