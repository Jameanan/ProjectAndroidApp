import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'signup_screen.dart';
import 'package:main/screen/home/Homepage.dart';
import 'package:main/provider/session_provider.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  static const String _aliasDomain = 'myapp.local';

  bool get _isFormFilled =>
      _idController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
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

  String _normalizeToEmail(String input) {
    final v = input.trim();
    if (v.contains('@')) return v;
    return '$v@$_aliasDomain';
  }

  Future<void> _signIn() async {
    if (!_isFormFilled) return;
    setState(() => _loading = true);

    try {
      final email = _normalizeToEmail(_idController.text);
      final pass = _passwordController.text;

      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);

      // โหลด session ให้ครบก่อนเข้า Home
      await context.read<SessionProvider>().init();

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } on FirebaseAuthException catch (e) {
      String message = 'เข้าสู่ระบบไม่สำเร็จ';
      if (e.code == 'invalid-email') {
        message = 'อีเมล/ชื่อผู้ใช้ไม่ถูกต้อง';
      } else if (e.code == 'user-disabled') {
        message = 'บัญชีนี้ถูกปิดใช้งาน';
      } else if (e.code == 'user-not-found') {
        message = 'ไม่พบบัญชีผู้ใช้';
      } else if (e.code == 'wrong-password') {
        message = 'รหัสผ่านไม่ถูกต้อง';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      backgroundImage: AssetImage('assets/images/account.jpg'),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _idController,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('อีเมลหรือชื่อผู้ใช้', 'assets/images/email.png'),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('รหัสผ่าน', 'assets/images/lock.png'),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (!_isFormFilled || _loading) ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          (!_isFormFilled || _loading) ? Colors.grey : Colors.teal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Text(
                          'เข้าสู่ระบบ',
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
                  const Text("ยังไม่ได้ลงทะเบียน? "),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      );
                    },
                    child: const Text(
                      "ลงทะเบียน",
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
