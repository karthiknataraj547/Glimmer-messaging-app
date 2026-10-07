import 'package:flutter/material.dart';
import 'core/session/user_session.dart';
import 'core/theme/nexa_theme.dart';
import 'features/auth/presentation/auth_flow_screen.dart';
import 'features/focus_orbit/presentation/focus_orbit_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexaApp());
}

class NexaApp extends StatelessWidget {
  final bool? startOnAuth;
  const NexaApp({super.key, this.startOnAuth});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UserSession.instance,
      builder: (context, _) {
        final bool showHome = (startOnAuth == true) ? false : UserSession.instance.isLoggedIn;
        return MaterialApp(
          title: 'NEXA',
          debugShowCheckedModeBanner: false,
          theme: NexaTheme.lightTheme,
          darkTheme: NexaTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: showHome ? const FocusOrbitScreen() : const AuthFlowScreen(),
        );
      },
    );
  }
}
