import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/supabase_service.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF091911),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const IronBloodApp());
}

class IronBloodApp extends StatelessWidget {
  const IronBloodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IRONBLOOD Gym & Fitness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF091911),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC9A227),
          primary: const Color(0xFFC9A227),
          secondary: const Color(0xFF123222),
          surface: const Color(0xFF0F261B),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
