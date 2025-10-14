import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart'; // เผื่อบางโปรเจกต์ต้องใช้
import 'package:main/screen/login/signup_screen2.dart';
import 'package:main/screen/login/signin_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _loading = false;

  bool get isFormFilled =>
      usernameController.text.isNotEmpty &&
          passwordController.text.isNotEmpty &&
          confirmPasswordController.text.isNotEmpty;

  // กำหนดรูปแบบ username (ปรับได้)
  final _usernameRegex = RegExp(r'^[a-z0-9_]{3,20}$');

  // ✅ ตรวจรหัสผ่าน: ยาว 6–15 ตัว และต้องมีตัวพิมพ์ใหญ่ >= 1
  bool _isValidPassword(String pass) {
    if (pass.length < 6 || pass.length > 15) return false;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(pass);
    return hasUpper;
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint, String iconPath) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[200],
      prefixIcon: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Image.asset(iconPath, width: 24, height: 24),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Future<void> _next() async {
    if (!isFormFilled || _loading) return;

    final rawUsername = usernameController.text.trim();
    final username = rawUsername.toLowerCase(); // บังคับ lower case
    final pass = passwordController.text;
    final confirm = confirmPasswordController.text;

    if (!_usernameRegex.hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ชื่อผู้ใช้ต้องเป็น a-z, 0-9 หรือ _ ความยาว 3–20 ตัว'),
        ),
      );
      return;
    }

    // ✅ เช็กตามกติกาใหม่
    if (!_isValidPassword(pass)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('รหัสผ่านต้องยาว 6–15 ตัว และมีตัวพิมพ์ใหญ่อย่างน้อย 1 ตัว'),
        ),
      );
      return;
    }

    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รหัสผ่านไม่ตรงกัน')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // ✅ เช็กซ้ำ: ต้องอ่านได้แม้ยังไม่ล็อกอิน (rules ด้านบนเปิด read)
      final snap = await FirebaseFirestore.instance.doc('usernames/$username').get();

      if (snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ชื่อผู้ใช้นี้ถูกใช้แล้ว')),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SignupScreen2(
            username: username,
            password: pass,
          ),
        ),
      );
    } on FirebaseException catch (e) {
      String msg = 'เกิดข้อผิดพลาด กรุณาลองใหม่';
      if (e.code == 'permission-denied') {
        msg = 'ไม่มีสิทธิ์เข้าถึงฐานข้อมูล (permission-denied) — ตรวจสอบ Firestore Rules';
      } else if (e.code == 'unavailable') {
        msg = 'บริการชั่วคราวไม่พร้อมใช้งาน ลองใหม่อีกครั้ง';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = isFormFilled && !_loading; // ปุ่มจะ disable ขณะโหลด เพื่อกันกดซ้ำ

    return Scaffold(
      backgroundColor: Colors.lightBlue.shade50,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: 380,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundImage: AssetImage('assets/images/add-user.png'),
                    ),
                    const SizedBox(height: 32),

                    TextField(
                      controller: usernameController,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('ชื่อผู้ใช้', 'assets/images/email.png'),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('รหัสผ่าน', 'assets/images/lock.png'),
                    ),
                    const SizedBox(height: 5),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('** รหัสผ่าน (6–15 ตัว)', style: TextStyle(fontSize: 12)),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('** A-Z อย่างน้อย 1 ตัวอักษร', style: TextStyle(fontSize: 12)),
                    ),


                    const SizedBox(height: 12),

                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('พิมพ์รหัสผ่านอีกครั้ง', 'assets/images/lock.png'),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: canSubmit ? _next : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSubmit ? const Color(0xFFFEC100) : Colors.grey,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _loading
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                            : const Text(
                          'ถัดไป',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("มีบัญชีอยู่แล้วใช่ไหม? "),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SigninScreen()),
                    ),
                    child: const Text(
                      "เข้าสู่ระบบ",
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
