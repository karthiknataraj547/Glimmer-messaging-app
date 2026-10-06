import 'package:flutter/material.dart';
import 'core/theme/nexa_theme.dart';
import 'features/focus_orbit/presentation/focus_orbit_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexaApp());
}

class NexaApp extends StatelessWidget {
  const NexaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXA',
      debugShowCheckedModeBanner: false,
      theme: NexaTheme.darkTheme,
      home: const FocusOrbitScreen(),
    );
  }
}
