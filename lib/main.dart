import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workmanager/workmanager.dart';

import 'auth.dart';
import 'db.dart';
import 'notifications.dart';
import 'smooth.dart';
import 'splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Workmanager().initialize(callbackDispatcher);
  } catch (_) {}
  try {
    await loadAppSettings();
  } catch (_) {}
  runApp(const RealEstateApp());
}

class RealEstateApp extends StatelessWidget {
  const RealEstateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E85));
    return MaterialApp(
      title: 'RentPal',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const SmoothScrollBehavior(),
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: SmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
        }),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF4F7FA),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withAlpha(30)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withAlpha(30)),
          ),
        ),
      ),
      home: const SplashGate(),
    );
  }
}
