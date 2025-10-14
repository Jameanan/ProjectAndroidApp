import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:main/screen/home/Homepage.dart';
import 'package:main/screen/search/Searchpage.dart';
import 'package:main/screen/login/signin_screen.dart';
import 'package:main/screen/Option/EditProfile.dart';
import 'package:main/provider/session_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: bottomNav(context),
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('ค้นหา'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false, // ✅ ชื่อที่ถูกต้อง
      ),
      body: SafeArea(
        child: Consumer<SessionProvider>(
          builder: (context, session, child) {
            final isLoggedIn = session.user != null;
            final username = session.user?.username ?? '';

            if (!isLoggedIn) {
              // กรณียังไม่ได้เข้าสู่ระบบ: แสดงแค่ปุ่มเข้าสู่ระบบตรงกลาง
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SigninScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              );
            }

            // หากเข้าสู่ระบบแล้ว:
            return Column(
              children: [
                const SizedBox(height: 20),

                // กล่องโปรไฟล์
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.image, size: 30, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const EditProfilePage()),
                                );
                              },
                              child: const Text('แก้ไขข้อมูลส่วนตัว', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ปุ่มออกจากระบบ
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: ElevatedButton(
                    onPressed: () {
                      session.logout();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text('ออกจากระบบ', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget bottomNav(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFFEFFFFF),
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.grey,
      currentIndex: 2,
      onTap: (index) {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SearchPage()),
          );
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'หน้าหลัก'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'ค้นหา'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
      ],
    );
  }
}
