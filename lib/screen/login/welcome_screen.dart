import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ★ เพิ่ม: กัน session ค้างเวลาเคยล็อกอินไว้ก่อนหน้า
import 'package:firebase_auth/firebase_auth.dart';

import 'package:main/screen/login/signin_screen.dart';
import 'package:main/screen/home/Homepage.dart';
import 'package:main/provider/session_provider.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(text: 'WELCOME ', style: TextStyle(color: Colors.pink)),
                      TextSpan(text: 'TO ', style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(text: 'FOOD', style: TextStyle(color: Colors.orange)),
                      TextSpan(text: 'SCAN', style: TextStyle(color: Colors.green)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            const Spacer(),
            Image.asset('assets/images/logo.jpg', width: 380, height: 380),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SigninScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text(
                    'เข้าสู่ระบบ',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                // ★ (1) กัน session firebase ค้างไว้
                try { await FirebaseAuth.instance.signOut(); } catch (_) {}

                // ★ (2) เข้าโหมด guest -> ใช้ SQLite (SessionProvider จัดการโหลดวันนี้จาก SQLite ให้)
                await context.read<SessionProvider>().enterGuestMode();

                // ★ (3) ไปหน้า Home แบบล้างสแต็ก (กันกดย้อนกลับมาหน้า Welcome)
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false,
                  );
                }
              },
              child: const Text(
                'ลองใช้ทันที',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
