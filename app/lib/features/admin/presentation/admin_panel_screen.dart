import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../../core/network/auth_service.dart';
import '../services/admin_service.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  final AdminService _adminService = AdminService.instance;
  late TabController _tabController;

  // Login Gate Controllers
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _masterKeyController = TextEditingController();
  bool _isAuthenticating = false;
  bool _showMasterKeyField = false;
  String? _authError;

  // Dashboard Data
  bool _isLoading = false;
  Map<String, dynamic>? _overviewMetrics;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _activityLogs = [];

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  String _userFilter = 'ALL'; // ALL, ACTIVE, SUSPENDED
  String _activityFilter = 'ALL'; // ALL, AUTH, ADMIN, REGISTRATION

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (_adminService.isAuthenticated) {
      _loadDashboardData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pinController.dispose();
    _masterKeyController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleAdminLogin() async {
    setState(() {
      _isAuthenticating = true;
      _authError = null;
    });

    final res = await _adminService.login(
      pin: _pinController.text.trim(),
      masterKey: _masterKeyController.text.trim(),
    );

    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _isAuthenticating = false;
      });
      _pinController.clear();
      _masterKeyController.clear();
      _loadDashboardData();
    } else {
      setState(() {
        _isAuthenticating = false;
        _authError = res['error'] ?? 'Authentication failed.';
      });
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final overviewRes = await _adminService.getOverview();
    final usersRes = await _adminService.getUsers();
    final activityRes = await _adminService.getActivityLogs();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (overviewRes['success'] == true) {
        _overviewMetrics = overviewRes['metrics'] as Map<String, dynamic>?;
      }
      _users = usersRes;
      _activityLogs = activityRes;
    });
  }

  Future<void> _toggleUserStatus(String username, String currentStatus) async {
    final newStatus = currentStatus == 'suspended' ? 'active' : 'suspended';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexaColors.surfaceLight,
        title: Text(
          newStatus == 'suspended' ? 'Suspend Account?' : 'Reactivate Account?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          newStatus == 'suspended'
              ? 'User @$username will be immediately disconnected and prevented from authenticating or receiving messages.'
              : 'User @$username will be restored to active status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'suspended'
                  ? NexaColors.error
                  : NexaColors.emeraldSecure,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newStatus == 'suspended' ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _adminService.updateUserStatus(username, newStatus);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('@$username is now $newStatus.'),
          backgroundColor: newStatus == 'suspended'
              ? NexaColors.error
              : NexaColors.emeraldSecure,
        ),
      );
      _loadDashboardData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update user status.'),
          backgroundColor: NexaColors.error,
        ),
      );
    }
  }

  Future<void> _resetUserPinDialog(String username) async {
    final pinController = TextEditingController(text: '123456');
    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexaColors.surfaceLight,
        title: Text('Reset PIN for @$username'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a new 6-digit login PIN for this user:',
              style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'New 6-Digit PIN',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, pinController.text.trim()),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );

    if (newPin == null || newPin.length < 4) return;

    final success = await _adminService.resetUserPin(username, newPin);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PIN for @$username has been reset to $newPin.'),
          backgroundColor: NexaColors.emeraldSecure,
        ),
      );
      _loadDashboardData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reset user PIN.'),
          backgroundColor: NexaColors.error,
        ),
      );
    }
  }

  Future<void> _deleteUserDialog(String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexaColors.surfaceLight,
        title: Text('Delete @$username?'),
        content: Text(
          'Are you sure you want to permanently delete user @$username and all associated device records from the online database? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: NexaColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _adminService.deleteUser(username);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User @$username deleted permanently.'),
          backgroundColor: NexaColors.error,
        ),
      );
      _loadDashboardData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete user.'),
          backgroundColor: NexaColors.error,
        ),
      );
    }
  }

  Future<void> _purgeExpiredQueue() async {
    final count = await _adminService.purgeQueue();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Purged $count expired/delivered envelopes.'),
        backgroundColor: NexaColors.emeraldSecure,
      ),
    );
    _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminService.isAuthenticated) {
      return _buildAuthGate();
    }

    return Scaffold(
      backgroundColor: NexaColors.backgroundLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Server Control Center',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: NexaColors.emeraldSecure,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'MASTER CONTROLLER LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: NexaColors.emeraldSecure,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Telemetry',
            onPressed: _isLoading ? null : _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock Admin Gateway',
            onPressed: () {
              _adminService.logout();
              setState(() {});
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: NexaColors.primary,
          unselectedLabelColor: NexaColors.textMuted,
          indicatorColor: NexaColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Users DB'),
            Tab(icon: Icon(Icons.security), text: 'Security Logs'),
            Tab(icon: Icon(Icons.dns_outlined), text: 'System'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildSecurityLogsTab(),
                _buildSystemTab(),
              ],
            ),
    );
  }

  // -------------------------------------------------------------
  // AUTHENTICATION GATE VIEW
  // -------------------------------------------------------------
  Widget _buildAuthGate() {
    return Scaffold(
      backgroundColor: NexaColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Admin Security Gateway'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: NexaColors.borderLight),
              ),
              color: NexaColors.surfaceLight,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [NexaColors.primary, NexaColors.emeraldSecure],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NexaColors.primary.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'System Administration',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: NexaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Access the online user database, inspect security logs, and control server operations.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: NexaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_authError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NexaColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: NexaColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: NexaColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _authError!,
                                style: const TextStyle(
                                  color: NexaColors.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // PIN Input
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: 'Admin Master PIN',
                        hintText: 'Default: 123456',
                        prefixIcon: const Icon(Icons.key, color: NexaColors.primary),
                        filled: true,
                        fillColor: NexaColors.elevatedLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Toggle Master Key input
                    TextButton.icon(
                      onPressed: () => setState(() => _showMasterKeyField = !_showMasterKeyField),
                      icon: Icon(
                        _showMasterKeyField ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: NexaColors.textMuted,
                      ),
                      label: Text(
                        _showMasterKeyField ? 'Hide Master Key' : 'Use Master Key instead',
                        style: const TextStyle(fontSize: 12, color: NexaColors.textMuted),
                      ),
                    ),

                    if (_showMasterKeyField) ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: _masterKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'ADMIN_MASTER_KEY',
                          hintText: 'Cryptographic master token',
                          prefixIcon: const Icon(Icons.vpn_key, color: NexaColors.amberWarning),
                          filled: true,
                          fillColor: NexaColors.elevatedLight,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isAuthenticating ? null : _handleAdminLogin,
                        icon: _isAuthenticating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_open, size: 20),
                        label: Text(
                          _isAuthenticating ? 'Verifying Gateway...' : 'Unlock Control Center',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NexaColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: USERS DATABASE VIEW
  // -------------------------------------------------------------
  Widget _buildUsersTab() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _users.where((u) {
      final username = (u['username'] as String? ?? '').toLowerCase();
      final fullName = (u['fullName'] as String? ?? '').toLowerCase();
      final phone = (u['phone'] as String? ?? '').toLowerCase();
      final status = (u['status'] as String? ?? 'active').toLowerCase();

      final matchesQuery = query.isEmpty ||
          username.contains(query) ||
          fullName.contains(query) ||
          phone.contains(query);

      final matchesFilter = _userFilter == 'ALL' ||
          (_userFilter == 'ACTIVE' && status == 'active') ||
          (_userFilter == 'SUSPENDED' && status == 'suspended');

      return matchesQuery && matchesFilter;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPI Metric Banner
          if (_overviewMetrics != null) _buildKpiRow(),
          const SizedBox(height: 16),

          // Search and Filters
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search username, full name, or phone...',
              prefixIcon: const Icon(Icons.search, color: NexaColors.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: NexaColors.surfaceLight,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: NexaColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: NexaColors.borderLight),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Filter Chips
          Row(
            children: [
              _buildFilterChip('ALL', 'All Users (${_users.length})'),
              const SizedBox(width: 8),
              _buildFilterChip(
                'ACTIVE',
                'Active (${_users.where((u) => u['status'] != 'suspended').length})',
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                'SUSPENDED',
                'Suspended (${_users.where((u) => u['status'] == 'suspended').length})',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // User Cards
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.person_off_outlined, size: 48, color: NexaColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No matching users in database.',
                      style: TextStyle(color: NexaColors.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map((user) => _buildUserCard(user)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _userFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : NexaColors.textSecondary,
        ),
      ),
      selected: isSelected,
      selectedColor: NexaColors.primary,
      backgroundColor: NexaColors.surfaceLight,
      onSelected: (_) => setState(() => _userFilter = value),
    );
  }

  Widget _buildKpiRow() {
    final metrics = _overviewMetrics!;
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Total Users',
            value: '${metrics['total_users'] ?? _users.length}',
            icon: Icons.people,
            color: NexaColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: 'Active Nodes',
            value: '${metrics['registered_devices'] ?? 0}',
            icon: Icons.devices,
            color: NexaColors.emeraldSecure,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: 'Queue Buffer',
            value: '${metrics['queued_envelopes'] ?? 0}',
            icon: Icons.mark_email_unread_outlined,
            color: NexaColors.amberWarning,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexaColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: NexaColors.textPrimary,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: NexaColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final username = user['username'] as String? ?? 'user';
    final fullName = user['fullName'] as String? ?? username;
    final role = user['role'] as String? ?? 'member';
    final status = user['status'] as String? ?? 'active';
    final phone = user['phone'] as String? ?? 'Not registered';
    final devices = (user['devices'] as List?)?.length ?? user['deviceCount'] ?? 0;
    final isSuspended = status == 'suspended';
    final isAdmin = role == 'admin' || username == 'admin';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSuspended
              ? NexaColors.error.withValues(alpha: 0.5)
              : NexaColors.borderLight,
        ),
      ),
      color: NexaColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isSuspended
                      ? NexaColors.error.withValues(alpha: 0.15)
                      : (isAdmin ? Colors.purple.withValues(alpha: 0.15) : NexaColors.primary.withValues(alpha: 0.15)),
                  child: Icon(
                    isAdmin ? Icons.shield : Icons.person,
                    color: isSuspended
                        ? NexaColors.error
                        : (isAdmin ? Colors.purple : NexaColors.primary),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              fullName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: NexaColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.purple.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'ADMIN',
                                style: TextStyle(
                                  color: Colors.purple,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isSuspended) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: NexaColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'SUSPENDED',
                                style: TextStyle(
                                  color: NexaColors.error,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NexaColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: NexaColors.textMuted),
                  onSelected: (val) {
                    if (val == 'status') {
                      _toggleUserStatus(username, status);
                    } else if (val == 'pin') {
                      _resetUserPinDialog(username);
                    } else if (val == 'delete') {
                      _deleteUserDialog(username);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          Icon(
                            isSuspended ? Icons.check_circle_outline : Icons.block,
                            size: 18,
                            color: isSuspended ? NexaColors.emeraldSecure : NexaColors.error,
                          ),
                          const SizedBox(width: 8),
                          Text(isSuspended ? 'Reactivate Account' : 'Suspend Account'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(Icons.password, size: 18, color: NexaColors.amberWarning),
                          const SizedBox(width: 8),
                          const Text('Reset Login PIN'),
                        ],
                      ),
                    ),
                    if (!isAdmin)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: NexaColors.error),
                            const SizedBox(width: 8),
                            Text('Delete Permanently', style: TextStyle(color: NexaColors.error)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20, color: NexaColors.borderLight),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 14, color: NexaColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  phone,
                  style: const TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                ),
                const Spacer(),
                const Icon(Icons.devices, size: 14, color: NexaColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '$devices Linked Devices',
                  style: const TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: SECURITY & ACTIVITY LOGS VIEW
  // -------------------------------------------------------------
  Widget _buildSecurityLogsTab() {
    final filteredLogs = _activityLogs.where((l) {
      if (_activityFilter == 'ALL') return true;
      final type = (l['type'] as String? ?? '').toUpperCase();
      return type == _activityFilter;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _buildActivityFilterChip('ALL', 'All Events'),
              const SizedBox(width: 6),
              _buildActivityFilterChip('AUTH', 'Authentication'),
              const SizedBox(width: 6),
              _buildActivityFilterChip('REGISTRATION', 'Signups'),
              const SizedBox(width: 6),
              _buildActivityFilterChip('ADMIN', 'Admin'),
            ],
          ),
          const SizedBox(height: 16),

          if (filteredLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 48, color: NexaColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No security activity logged yet.',
                      style: TextStyle(color: NexaColors.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filteredLogs.map((log) => _buildActivityLogItem(log)),
        ],
      ),
    );
  }

  Widget _buildActivityFilterChip(String value, String label) {
    final isSelected = _activityFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : NexaColors.textSecondary,
        ),
      ),
      selected: isSelected,
      selectedColor: NexaColors.primary,
      backgroundColor: NexaColors.surfaceLight,
      onSelected: (_) => setState(() => _activityFilter = value),
    );
  }

  Widget _buildActivityLogItem(Map<String, dynamic> log) {
    final type = (log['type'] as String? ?? 'EVENT').toUpperCase();
    final action = log['action'] as String? ?? 'ACTION';
    final actor = log['actor'] as String? ?? 'system';
    final target = log['target'] as String? ?? '-';
    final details = log['details'] as String? ?? '';
    final ip = log['ip'] as String? ?? 'unknown';
    final timestamp = log['timestamp'] as String? ?? '';

    Color badgeColor = NexaColors.primary;
    IconData icon = Icons.info_outline;

    if (type == 'AUTH') {
      badgeColor = NexaColors.emeraldSecure;
      icon = Icons.login;
    } else if (type == 'ADMIN') {
      badgeColor = Colors.purple;
      icon = Icons.admin_panel_settings;
    } else if (type == 'REGISTRATION') {
      badgeColor = NexaColors.cyanAccent;
      icon = Icons.person_add;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexaColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: badgeColor.withValues(alpha: 0.15),
            child: Icon(icon, size: 16, color: badgeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      action.replaceAll('_', ' '),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: NexaColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timestamp.length > 19 ? timestamp.substring(11, 19) : timestamp,
                      style: const TextStyle(fontSize: 11, color: NexaColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Actor: @$actor  •  Target: @$target',
                  style: const TextStyle(fontSize: 12, color: NexaColors.primary, fontWeight: FontWeight.w500),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: const TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'IP: $ip',
                  style: const TextStyle(fontSize: 10, color: NexaColors.textMuted, fontFamily: 'Courier'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: SYSTEM HEALTH & MAINTENANCE VIEW
  // -------------------------------------------------------------
  Widget _buildSystemTab() {
    final metrics = _overviewMetrics ?? {};
    final uptimeSeconds = (metrics['uptime_seconds'] as num?)?.toInt() ?? 0;
    final hours = uptimeSeconds ~/ 3600;
    final minutes = (uptimeSeconds % 3600) ~/ 60;
    final memoryMb = metrics['memory_rss_mb'] ?? '0.0';
    final dbPath = metrics['database_path'] as String? ?? 'nexa_database.json';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Web Admin Dashboard Card
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: NexaColors.primary, width: 1.5),
          ),
          color: NexaColors.surfaceLight,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NexaColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.language, color: NexaColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Web Admin Dashboard',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Access from any browser on PC, tablet, or remote network.',
                            style: TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FutureBuilder<String>(
                  future: AuthService.instance.getBaseUrl(),
                  builder: (ctx, snap) {
                    final url = '${snap.data ?? 'http://localhost:8080'}/admin';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: NexaColors.elevatedLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              url,
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 12,
                                color: NexaColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18, color: NexaColors.textMuted),
                            tooltip: 'Copy URL',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: url));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Admin URL copied to clipboard!')),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // System Telemetry Card
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: NexaColors.borderLight),
          ),
          color: NexaColors.surfaceLight,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SERVER DIAGNOSTICS & TELEMETRY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: NexaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                _buildDiagnosticRow('Server Uptime', '${hours}h ${minutes}m'),
                const Divider(height: 18, color: NexaColors.borderLight),
                _buildDiagnosticRow('Process Memory (RSS)', '$memoryMb MB'),
                const Divider(height: 18, color: NexaColors.borderLight),
                _buildDiagnosticRow('Storage Engine', 'ACID JSON DB Engine'),
                const Divider(height: 18, color: NexaColors.borderLight),
                _buildDiagnosticRow('Database Path', dbPath),
                const Divider(height: 18, color: NexaColors.borderLight),
                _buildDiagnosticRow(
                  'Security Master Key',
                  'PROTECTED (nexa_admin_master_secret_2026)',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Database Maintenance Card
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: NexaColors.borderLight),
          ),
          color: NexaColors.surfaceLight,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MAINTENANCE CONTROLS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: NexaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cleaning_services, color: NexaColors.amberWarning),
                  title: const Text('Purge Delivered Mailbox Queue', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Cleans expired cryptographic envelopes from memory buffer.'),
                  trailing: ElevatedButton(
                    onPressed: _purgeExpiredQueue,
                    style: ElevatedButton.styleFrom(backgroundColor: NexaColors.amberWarning),
                    child: const Text('Purge'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: NexaColors.textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: NexaColors.textPrimary,
              fontFamily: 'Courier',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
