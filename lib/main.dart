import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'package:main/provider/session_provider.dart';
import 'package:main/screen/login/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('th_TH');

  runApp(
    MultiProvider(
      providers: [
        // ⬇️ สำคัญ: บูต SessionProvider ให้โหลดโหมด/ข้อมูลวันนี้ตั้งแต่เริ่ม
        ChangeNotifierProvider(create: (_) => SessionProvider()..init()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
      locale: const Locale('th', 'TH'),
      home: const WelcomeScreen(), // เปิดมาหน้า Welcome เสมอ
      debugShowCheckedModeBanner: false,
    );
  }
}
