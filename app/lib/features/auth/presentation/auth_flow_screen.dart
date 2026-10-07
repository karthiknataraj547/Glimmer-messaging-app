import 'package:flutter/material.dart';
import '../../../core/session/user_session.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../focus_orbit/presentation/focus_orbit_screen.dart';

class AuthFlowScreen extends StatefulWidget {
  final bool isLoginInitial;
  const AuthFlowScreen({super.key, this.isLoginInitial = false});

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  late bool _isLoginMode;
  int _createStep = 0; // 0 = Handle/Identity, 1 = Recovery Seed, 2 = Profile Avatar

  // Create Account Form State
  final TextEditingController _handleController = TextEditingController(text: 'karthik_n');
  final TextEditingController _displayNameController = TextEditingController(text: 'Karthik');
  final TextEditingController _statusController = TextEditingController(text: 'Encrypted & Focused');
  int _selectedAvatar = 0;
  bool _seedBackedUp = false;
  final String _generatedNexaId = 'NX-77A1-49PQ';

  // Login Form State
  int _loginMethod = 0; // 0 = 24 Words, 1 = PIN, 2 = QR
  final TextEditingController _seedImportController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  final List<String> _dummyMnemonic = [
    'orbit', 'quantum', 'cipher', 'vault', 'secure', 'privacy',
    'zero', 'knowledge', 'whisper', 'enigma', 'signal', 'matrix',
    'sovereign', 'shield', 'key', 'relay', 'crypto', 'mesh',
    'silent', 'telemetry', 'daemon', 'ratchet', 'packet', 'beacon'
  ];

  @override
  void initState() {
    super.initState();
    _isLoginMode = widget.isLoginInitial;
  }

  @override
  void dispose() {
    _handleController.dispose();
    _displayNameController.dispose();
    _statusController.dispose();
    _seedImportController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _finishAuthentication() {
    UserSession.instance.login(
      name: _displayNameController.text.trim().isEmpty ? 'Karthik' : _displayNameController.text.trim(),
      handle: '@${_handleController.text.trim()}',
      avatarIndex: _selectedAvatar,
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FocusOrbitScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvasLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top NEXA Branding & Mode Switcher
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: NexaColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield, color: NexaColors.primary, size: 22),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'NEXA',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: NexaColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: NexaColors.elevatedLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: NexaColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        _buildModeTab('Register', !_isLoginMode, () {
                          setState(() {
                            _isLoginMode = false;
                            _createStep = 0;
                          });
                        }),
                        _buildModeTab('Login', _isLoginMode, () {
                          setState(() => _isLoginMode = true);
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Main Body: Either Create Account Stepper or Login
              if (!_isLoginMode) ...[
                _buildCreateAccountStepper(),
              ] else ...[
                _buildLoginCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? NexaColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : NexaColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // STEP-BY-STEP CREATE ACCOUNT
  // ==========================================
  Widget _buildCreateAccountStepper() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stepper Progress Header
        Row(
          children: [
            _buildStepIndicator(0, 'Handle'),
            _buildStepDivider(0),
            _buildStepIndicator(1, 'Key Vault'),
            _buildStepDivider(1),
            _buildStepIndicator(2, 'Profile'),
          ],
        ),
        const SizedBox(height: 28),

        // Step 0: Handle & Decentralized Identity
        if (_createStep == 0) ...[
          const Text(
            'Create Self-Sovereign Identity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NexaColors.textPrimary, letterSpacing: -0.4),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your identity is backed by asymmetric Ed25519 cryptography. No phone number or email is ever needed.',
            style: TextStyle(fontSize: 14, color: NexaColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),

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
                const Text('Choose Your Handle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _handleController,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NexaColors.textPrimary),
                  decoration: InputDecoration(
                    prefixText: '@ ',
                    prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: NexaColors.primary, fontSize: 16),
                    filled: true,
                    fillColor: NexaColors.elevatedLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Generated Zero-Knowledge NEXA ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _generatedNexaId,
                        style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.w700, color: NexaColors.emeraldSecure, fontSize: 15),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 14),
                          SizedBox(width: 4),
                          Text('Ed25519 PubKey', style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _createStep = 1),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next: Generate Cryptographic Keys'),
            ),
          ),
        ],

        // Step 1: 24-Word Recovery Seed
        if (_createStep == 1) ...[
          const Text(
            'Your 24-Word Recovery Vault',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NexaColors.textPrimary, letterSpacing: -0.4),
          ),
          const SizedBox(height: 6),
          const Text(
            'Write down these 24 words in order. This seed phrase is the ONLY way to restore your chats if you switch devices.',
            style: TextStyle(fontSize: 14, color: NexaColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NexaColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NexaColors.borderLight),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_dummyMnemonic.length, (idx) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: NexaColors.elevatedLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NexaColors.borderLight),
                  ),
                  child: Text(
                    '${idx + 1}. ${_dummyMnemonic[idx]}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NexaColors.textPrimary),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _seedBackedUp,
            onChanged: (val) => setState(() => _seedBackedUp = val ?? false),
            title: const Text('I have written down and securely stored my 24 recovery words.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _createStep = 0),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _seedBackedUp ? () => setState(() => _createStep = 2) : null,
                  child: const Text('Next: Set Profile & Avatar'),
                ),
              ),
            ],
          ),
        ],

        // Step 2: Personal Profile & Avatar
        if (_createStep == 2) ...[
          const Text(
            'Set Up Your Profile',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NexaColors.textPrimary, letterSpacing: -0.4),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose your avatar and display name. All metadata is stored encrypted locally.',
            style: TextStyle(fontSize: 14, color: NexaColors.textSecondary),
          ),
          const SizedBox(height: 20),

          // Avatar Picker Grid
          const Text('CHOOSE AVATAR BADGE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(UserSession.avatarPresets.length, (i) {
              final preset = UserSession.avatarPresets[i];
              final isSel = _selectedAvatar == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedAvatar = i),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isSel ? NexaColors.primary : Colors.transparent, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: preset['color'] as Color,
                    child: Icon(preset['icon'] as IconData, color: Colors.white, size: 18),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NexaColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NexaColors.borderLight),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _displayNameController,
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'e.g. Karthik',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: NexaColors.elevatedLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _statusController,
                  decoration: InputDecoration(
                    labelText: 'Status Message',
                    hintText: 'e.g. Encrypted & Focused',
                    prefixIcon: const Icon(Icons.chat_bubble_outline),
                    filled: true,
                    fillColor: NexaColors.elevatedLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _createStep = 1),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _finishAuthentication,
                  icon: const Icon(Icons.rocket_launch, size: 18),
                  label: const Text('Launch NEXA Orbit'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title) {
    final isActive = _createStep == stepIndex;
    final isDone = _createStep > stepIndex;
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isDone
                ? NexaColors.emeraldSecure
                : (isActive ? NexaColors.primary : NexaColors.elevatedLight),
            child: isDone
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : NexaColors.textMuted,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? NexaColors.primary : NexaColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(int stepIndex) {
    final isDone = _createStep > stepIndex;
    return Container(
      width: 24,
      height: 2,
      color: isDone ? NexaColors.emeraldSecure : NexaColors.borderLight,
      margin: const EdgeInsets.only(bottom: 16),
    );
  }

  // ==========================================
  // LOGIN SCREEN
  // ==========================================
  Widget _buildLoginCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Unlock Your Cryptographic Vault',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NexaColors.textPrimary, letterSpacing: -0.4),
        ),
        const SizedBox(height: 6),
        const Text(
          'Restore your self-sovereign account using your 24 recovery words or hardware linked device.',
          style: TextStyle(fontSize: 14, color: NexaColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Login Method Selector
        Row(
          children: [
            _buildLoginMethodPill('24 Words', 0, Icons.vpn_key_outlined),
            const SizedBox(width: 8),
            _buildLoginMethodPill('Master PIN', 1, Icons.pin_outlined),
            const SizedBox(width: 8),
            _buildLoginMethodPill('Device QR', 2, Icons.qr_code_scanner),
          ],
        ),
        const SizedBox(height: 20),

        if (_loginMethod == 0) ...[
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
                const Text('Enter 24 Recovery Words', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _seedImportController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13, fontFamily: 'Courier'),
                  decoration: InputDecoration(
                    hintText: 'orbit quantum cipher vault secure privacy zero knowledge...',
                    filled: true,
                    fillColor: NexaColors.elevatedLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _seedImportController.text = _dummyMnemonic.join(' ');
                    });
                  },
                  icon: const Icon(Icons.paste, size: 16),
                  label: const Text('Paste demo recovery words'),
                ),
              ],
            ),
          ),
        ] else if (_loginMethod == 1) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NexaColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NexaColors.borderLight),
            ),
            child: Column(
              children: [
                const Text('Enter 6-Digit Master Hardware PIN', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: NexaColors.elevatedLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NexaColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NexaColors.borderLight),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.qr_code_scanner, size: 64, color: NexaColors.primary),
                  const SizedBox(height: 12),
                  const Text('Scan Primary Device QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text('On your authorized phone, go to Menu > Linked Devices > Show Link QR.', textAlign: TextAlign.center, style: TextStyle(color: NexaColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _finishAuthentication,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('Simulate QR Handshake'),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _finishAuthentication,
            icon: const Icon(Icons.lock_open, size: 18),
            label: const Text('Unlock Vault & Enter NEXA'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginMethodPill(String label, int index, IconData icon) {
    final isSel = _loginMethod == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _loginMethod = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? NexaColors.primary.withValues(alpha: 0.12) : NexaColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSel ? NexaColors.primary : NexaColors.borderLight),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSel ? NexaColors.primary : NexaColors.textMuted, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? NexaColors.primary : NexaColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
