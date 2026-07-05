// VERSÃO: v30
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/theme/unl_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/student/live/screens/live_screen.dart';
import 'features/student/screens/student_community_screen.dart';
import 'features/student/screens/student_courses_screen.dart';
import 'features/student/screens/student_gamification_screen.dart';
import 'features/student/screens/student_home_screen.dart';
import 'features/student/screens/student_trails_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF000000),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const UniversidadeLideresApp());
}

class UniversidadeLideresApp extends StatelessWidget {
  const UniversidadeLideresApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universidade de Líderes',
      debugShowCheckedModeBanner: false,
      theme: UnlTheme.dark(),
      routes: {
        StudentHomeScreen.routeName: (_) => const StudentHomeScreen(),
        StudentTrailsScreen.routeName: (_) => const StudentTrailsScreen(),
        StudentCoursesScreen.routeName: (_) => const StudentCoursesScreen(),
        LiveScreen.routeName: (_) => const LiveScreen(),
        StudentCommunityScreen.routeName: (_) => const StudentCommunityScreen(),
        StudentGamificationScreen.routeName: (_) =>
            const StudentGamificationScreen(),
      },
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        return const StudentHomeScreen();
      },
    );
  }
}
