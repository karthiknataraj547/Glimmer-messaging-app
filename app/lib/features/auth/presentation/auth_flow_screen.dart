import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/auth_service.dart';
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
  // Mode: Login (true) or Register (false)
  late bool _isLoginMode;

  // Registration step: 1 = Username Check (Online DB), 2 = Password, Name, About, Phone
  int _registerStep = 1;

  // Loading & Error States
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Controllers
  final TextEditingController _loginHandleController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();

  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regFullNameController = TextEditingController();
  final TextEditingController _regAboutController = TextEditingController(text: 'Encrypted & Focused');
  final TextEditingController _regPhoneController = TextEditingController();

  // Username validation state
  bool _isCheckingUsername = false;
  String? _validatedUsername;
  String? _usernameCheckError;
  bool _isUsernameAvailable = false;
  Timer? _debounceTimer;

  bool _obscureLoginPin = true;
  bool _obscureRegPin = true;

  @override
  void initState() {
    super.initState();
    _isLoginMode = widget.isLoginInitial;
    _loginHandleController.text = '';
    _loginPasswordController.text = '';
    AuthService.instance.checkHealthAsync();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _loginHandleController.dispose();
    _loginPasswordController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regFullNameController.dispose();
    _regAboutController.dispose();
    _regPhoneController.dispose();
    super.dispose();
  }

  // =====================================================================
  // ONLINE DATABASE USERNAME UNIQUENESS CHECK
  // =====================================================================
  Future<void> _checkUsernameOnline({bool autoAdvance = false}) async {
    final raw = _regUsernameController.text.trim();
    final clean = raw.replaceFirst(RegExp(r'^@+'), '').toLowerCase();

    if (clean.length < 3) {
      setState(() {
        _usernameCheckError = 'Username must be at least 3 characters.';
        _isUsernameAvailable = false;
        _validatedUsername = null;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameCheckError = null;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.instance.checkUsernameOnline(clean);

      if (!mounted) return;

      if (result['available'] == true) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = true;
          _usernameCheckError = null;
          _validatedUsername = clean;
        });

        if (autoAdvance) {
          HapticFeedback.mediumImpact();
          setState(() {
            _registerStep = 2;
          });
        }
      } else {
        // REJECT USERNAME - Already taken
        HapticFeedback.heavyImpact();
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = false;
          _validatedUsername = null;
          _usernameCheckError = result['message'] ??
              result['error'] ??
              "Username '@$clean' is already taken. Please choose another username.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _usernameCheckError = 'Unable to check username availability. Please try again.';
      });
    }
  }

  // =====================================================================
  // COMPLETE REGISTRATION (STEP 2 SUBMISSION)
  // =====================================================================
  Future<void> _submitRegistration() async {
    final username = _validatedUsername;
    if (username == null || username.isEmpty) {
      setState(() {
        _registerStep = 1;
        _errorMessage = 'Please verify your username first.';
      });
      return;
    }

    final password = _regPasswordController.text.trim();
    if (password.length < 4) {
      setState(() {
        _errorMessage = 'Password / Master PIN must be at least 4 digits.';
      });
      return;
    }

    final fullName = _regFullNameController.text.trim().isEmpty ? username : _regFullNameController.text.trim();
    final about = _regAboutController.text.trim();
    final phone = _regPhoneController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final res = await AuthService.instance.registerUserOnline(
        username: username,
        password: password,
        fullName: fullName,
        about: about,
        phone: phone,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final userData = res['user'] as Map<String, dynamic>? ?? {};
        final nexaId = (userData['nexaId'] as String?) ?? 'NX-77A1-49PQ';

        UserSession.instance.login(
          name: fullName,
          handle: '@$username',
          bio: about,
          phone: phone,
          nexaId: nexaId,
          avatarIndex: 0,
        );

        HapticFeedback.mediumImpact();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const FocusOrbitScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res['error'] ?? 'Registration could not be completed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connection failure. Please check your network and try again.';
      });
    }
  }

  // =====================================================================
  // SIMPLE LOGIN SUBMISSION
  // =====================================================================
  Future<void> _submitLogin() async {
    final rawHandle = _loginHandleController.text.trim();
    final cleanHandle = rawHandle.replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    final password = _loginPasswordController.text.trim();

    if (cleanHandle.isEmpty) {
      setState(() => _errorMessage = 'Please enter your username.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password / Master PIN.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await AuthService.instance.loginUserOnline(
        username: cleanHandle,
        password: password,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final userData = res['user'] as Map<String, dynamic>? ?? {};
        final name = (userData['fullName'] as String?) ?? cleanHandle;
        final about = (userData['about'] as String?) ?? 'Encrypted & Focused';
        final phone = (userData['phone'] as String?) ?? '';
        final nexaId = (userData['nexaId'] as String?) ?? 'NX-77A1-49PQ';

        UserSession.instance.login(
          name: name,
          handle: '@$cleanHandle',
          bio: about,
          phone: phone,
          nexaId: nexaId,
          avatarIndex: 0,
        );

        HapticFeedback.mediumImpact();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const FocusOrbitScreen()),
          (route) => false,
        );
      } else {
        // If login failed, show clear message
        setState(() {
          _isLoading = false;
          _errorMessage = res['error'] ?? 'Invalid username or password.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to sign in. Please check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvasLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Brand Shield & Name
                _buildHeader(),
                const SizedBox(height: 24),

                // Main Auth Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: NexaColors.surfaceLight,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: NexaColors.borderLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mode Selector (Log In vs Register)
                      _buildModeSwitchTabs(),
                      const SizedBox(height: 22),

                      // Error / Success Banners
                      if (_errorMessage != null) ...[
                        _buildAlertBanner(
                          text: _errorMessage!,
                          isError: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_successMessage != null) ...[
                        _buildAlertBanner(
                          text: _successMessage!,
                          isError: false,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Body: Either Simple Login OR Unique Multi-Step Register
                      if (_isLoginMode) ...[
                        _buildSimpleLoginForm(),
                      ] else ...[
                        _buildUniqueRegisterForm(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Bottom Switcher
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _isLoginMode = !_isLoginMode;
                        _registerStep = 1;
                        _errorMessage = null;
                        _usernameCheckError = null;
                      });
                    },
                    child: Text(
                      _isLoginMode
                          ? "New to NEXA? Create an Account"
                          : "Already registered? Log In",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: NexaColors.cyanAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // HEADER
  // =====================================================================
  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NexaColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, color: NexaColors.primary, size: 30),
            ),
            const SizedBox(width: 12),
            const Text(
              'NEXA',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: NexaColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Zero-Knowledge Secure Messaging',
          style: TextStyle(
            fontSize: 13,
            color: NexaColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // MODE TABS (LOG IN VS REGISTER)
  // =====================================================================
  Widget _buildModeSwitchTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NexaColors.elevatedLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexaColors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              'Log In',
              _isLoginMode,
              () => setState(() {
                _isLoginMode = true;
                _errorMessage = null;
              }),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              'Register',
              !_isLoginMode,
              () => setState(() {
                _isLoginMode = false;
                _registerStep = 1;
                _errorMessage = null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? NexaColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : NexaColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // 1. SIMPLE LOGIN FORM
  // =====================================================================
  Widget _buildSimpleLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Log In to NEXA',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NexaColors.textPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter your handle and Master PIN to access your vault.',
          style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Username / Handle
        const Text(
          'Username / Handle',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _loginHandleController,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. karthik_n',
            prefixIcon: const Icon(Icons.alternate_email, color: NexaColors.primary, size: 20),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),

        // Password / Master PIN
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Master PIN (6 Digits)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
            ),
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Default PIN for seeded accounts is 123456')),
                );
              },
              child: const Text(
                'Help?',
                style: TextStyle(fontSize: 12, color: NexaColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _loginPasswordController,
          obscureText: _obscureLoginPin,
          keyboardType: TextInputType.text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: '••••••',
            prefixIcon: const Icon(Icons.lock_outline, color: NexaColors.textMuted, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscureLoginPin ? Icons.visibility_off : Icons.visibility, color: NexaColors.textMuted, size: 20),
              onPressed: () => setState(() => _obscureLoginPin = !_obscureLoginPin),
            ),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onSubmitted: (_) => _submitLogin(),
        ),
        const SizedBox(height: 22),

        // Log In Button
        ElevatedButton(
          onPressed: _isLoading ? null : _submitLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: NexaColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_open, size: 18),
                    SizedBox(width: 8),
                    Text('Log In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
      ],
    );
  }

  // =====================================================================
  // 2. UNIQUE STEP-BY-STEP REGISTRATION FORM
  // =====================================================================
  Widget _buildUniqueRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stepper Progress Header
        _buildStepperProgressHeader(),
        const SizedBox(height: 20),

        if (_registerStep == 1) ...[
          // STEP 1: ENTER USERNAME & CHECK ONLINE DATABASE
          _buildRegisterStep1(),
        ] else ...[
          // STEP 2: PASSWORD, FULL NAME, ABOUT, FEASIBLE PHONE NUMBER
          _buildRegisterStep2(),
        ],
      ],
    );
  }

  // =====================================================================
  // STEPPER PROGRESS HEADER
  // =====================================================================
  Widget _buildStepperProgressHeader() {
    return Row(
      children: [
        // Step 1 badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _registerStep == 1
                ? NexaColors.primary
                : NexaColors.emeraldSecure.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _registerStep > 1 ? Icons.check_circle : Icons.looks_one,
                size: 14,
                color: _registerStep == 1 ? Colors.white : NexaColors.emeraldSecure,
              ),
              const SizedBox(width: 4),
              Text(
                '1. Username',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _registerStep == 1 ? Colors.white : NexaColors.emeraldSecure,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 2,
            color: _registerStep > 1 ? NexaColors.emeraldSecure : NexaColors.borderLight,
          ),
        ),
        const SizedBox(width: 8),

        // Step 2 badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _registerStep == 2 ? NexaColors.primary : NexaColors.elevatedLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.looks_two,
                size: 14,
                color: _registerStep == 2 ? Colors.white : NexaColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                '2. Account Details',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _registerStep == 2 ? Colors.white : NexaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // STEP 1 WIDGET: CHOOSE USERNAME & ONLINE DATABASE CHECK
  // =====================================================================
  Widget _buildRegisterStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create Account',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NexaColors.textPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Step 1: Choose your unique username.',
          style: TextStyle(fontSize: 13, color: NexaColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),

        const Text(
          'Username / Handle',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regUsernameController,
          autofocus: true,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. karthik_n or sovereign_user',
            prefixIcon: const Icon(Icons.alternate_email, color: NexaColors.primary, size: 20),
            suffixIcon: _isCheckingUsername
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_isUsernameAvailable
                    ? const Icon(Icons.check_circle, color: NexaColors.emeraldSecure)
                    : null),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: _usernameCheckError != null
                  ? const BorderSide(color: NexaColors.rubyDestructive, width: 1.5)
                  : BorderSide.none,
            ),
          ),
          onChanged: (val) {
            setState(() {
              _usernameCheckError = null;
              _isUsernameAvailable = false;
              _validatedUsername = null;
            });
          },
          onSubmitted: (_) => _checkUsernameOnline(autoAdvance: true),
        ),
        const SizedBox(height: 12),

        // Live Availability Feedback
        if (_usernameCheckError != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF450A0A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF991B1B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, color: NexaColors.rubyDestructive, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _usernameCheckError!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFCA5A5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else if (_isUsernameAvailable && _validatedUsername != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF059669)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, color: NexaColors.emeraldSecure, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Username '@$_validatedUsername' is available!",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6EE7B7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 8),

        // Action Button: Verify Username & Continue
        ElevatedButton(
          onPressed: _isCheckingUsername ? null : () => _checkUsernameOnline(autoAdvance: true),
          style: ElevatedButton.styleFrom(
            backgroundColor: NexaColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isCheckingUsername
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
        ),
      ],
    );
  }

  // =====================================================================
  // STEP 2 WIDGET: PASSWORD, NAME, ABOUT, FEASIBLE PHONE NUMBER
  // =====================================================================
  Widget _buildRegisterStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Verified Username Tag with back link
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF064E3B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF059669)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: NexaColors.emeraldSecure, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verified Handle: @$_validatedUsername',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6EE7B7)),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _registerStep = 1;
                    _isUsernameAvailable = false;
                  });
                },
                child: const Text(
                  'Change',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.primary, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Account Details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: NexaColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Set your Master PIN, display name, bio, and feasible phone number.',
          style: TextStyle(fontSize: 12, color: NexaColors.textSecondary),
        ),
        const SizedBox(height: 16),

        // Master PIN / Password
        const Text(
          'Master PIN / Password (Required)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regPasswordController,
          obscureText: _obscureRegPin,
          keyboardType: TextInputType.text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Choose at least 4 digits/characters',
            prefixIcon: const Icon(Icons.lock_outline, color: NexaColors.primary, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscureRegPin ? Icons.visibility_off : Icons.visibility, color: NexaColors.textMuted, size: 20),
              onPressed: () => setState(() => _obscureRegPin = !_obscureRegPin),
            ),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),

        // Display Name / Full Name
        const Text(
          'Full Name (Required)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regFullNameController,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Karthik N',
            prefixIcon: const Icon(Icons.badge_outlined, color: NexaColors.textMuted, size: 20),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),

        // About / Status
        const Text(
          'About / Status (Required)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regAboutController,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Building decentralized systems • Available',
            prefixIcon: const Icon(Icons.info_outline, color: NexaColors.textMuted, size: 20),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),

        // Phone Number (Feasible / Optional)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'Phone Number (If Feasible)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted),
            ),
            Text(
              'Optional',
              style: TextStyle(fontSize: 11, color: NexaColors.primary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regPhoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: NexaColors.textPrimary),
          decoration: InputDecoration(
            hintText: '+91 98765 43210 (Mobile contact discovery)',
            prefixIcon: const Icon(Icons.phone_outlined, color: NexaColors.textMuted, size: 20),
            filled: true,
            fillColor: NexaColors.elevatedLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 22),

        // Complete Registration Button
        ElevatedButton(
          onPressed: _isLoading ? null : _submitRegistration,
          style: ElevatedButton.styleFrom(
            backgroundColor: NexaColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.how_to_reg, size: 18),
                    SizedBox(width: 8),
                    Text('Complete Registration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
        const SizedBox(height: 10),

        // Back to step 1 button
        TextButton.icon(
          onPressed: () => setState(() => _registerStep = 1),
          icon: const Icon(Icons.arrow_back, size: 16, color: NexaColors.textMuted),
          label: const Text('Back to Username', style: TextStyle(color: NexaColors.textMuted, fontSize: 13)),
        ),
      ],
    );
  }

  // =====================================================================
  // ALERT BANNER HELPER
  // =====================================================================
  Widget _buildAlertBanner({required String text, required bool isError}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF450A0A) : const Color(0xFF064E3B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isError ? const Color(0xFF991B1B) : const Color(0xFF059669)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isError ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
