import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/crypto/key_manager.dart';
import '../../../core/theme/nexa_theme.dart';

class RecoveryKeyVaultScreen extends StatefulWidget {
  const RecoveryKeyVaultScreen({super.key});

  @override
  State<RecoveryKeyVaultScreen> createState() => _RecoveryKeyVaultScreenState();
}

class _RecoveryKeyVaultScreenState extends State<RecoveryKeyVaultScreen> {
  late final List<String> _mnemonicWords;
  bool _isRevealed = false;
  bool _hasBackedUp = false;

  @override
  void initState() {
    super.initState();
    final keyManager = NexaKeyManager(
      nexaId: 'NX-7K4M-29QP',
      deviceId: 'dev-primary-phone',
    );
    _mnemonicWords = keyManager.generateRecoveryMnemonic();
    keyManager.dispose();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _mnemonicWords.join(' ')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery seed copied to clipboard. Clear clipboard after saving!'),
        backgroundColor: NexaColors.elevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      appBar: AppBar(
        title: const Text('Recovery Key Vault'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // Warning Alert Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexaColors.amberAttention.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NexaColors.amberAttention.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: NexaColors.amberAttention, size: 28),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zero-Knowledge Recovery',
                          style: TextStyle(
                            color: NexaColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'NEXA holds zero copies of your master keys. If you lose this 24-word phrase, your encrypted messages cannot be recovered.',
                          style: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 24-Word Grid or Obscured View
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NexaColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: NexaColors.border),
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _mnemonicWords.length,
                    itemBuilder: (context, index) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: NexaColors.elevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: NexaColors.border),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Text(
                              '${index + 1}. ',
                              style: const TextStyle(color: NexaColors.textMuted, fontSize: 11),
                            ),
                            Expanded(
                              child: Text(
                                _isRevealed ? _mnemonicWords[index] : '••••••',
                                style: const TextStyle(
                                  color: NexaColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Reveal Overlay button
                if (!_isRevealed)
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _isRevealed = true),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Tap to Reveal Recovery Words'),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // Actions
            if (_isRevealed) ...[
              OutlinedButton.icon(
                onPressed: _copyToClipboard,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: NexaColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.copy, color: NexaColors.cyanAccent, size: 18),
                label: const Text('Copy 24 Words', style: TextStyle(color: NexaColors.textPrimary)),
              ),
              const SizedBox(height: 16),
            ],

            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: NexaColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: NexaColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  title: const Text(
                    'I have stored these 24 words in a secure offline location.',
                    style: TextStyle(color: NexaColors.textPrimary, fontSize: 13),
                  ),
                  value: _hasBackedUp,
                  activeColor: NexaColors.cyanAccent,
                  checkColor: Colors.black,
                  onChanged: (val) => setState(() => _hasBackedUp = val ?? false),
                ),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _hasBackedUp
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Recovery vault verified and secured!'),
                          backgroundColor: NexaColors.elevated,
                        ),
                      );
                      Navigator.pop(context);
                    }
                  : null,
              child: const Text('Confirm Backup Complete'),
            ),
          ],
        ),
      ),
    );
  }
}
