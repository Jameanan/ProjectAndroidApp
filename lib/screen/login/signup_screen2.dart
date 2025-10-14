import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:main/screen/login/signin_screen.dart';

class SignupScreen2 extends StatefulWidget {
  final String username;
  final String password;

  const SignupScreen2({
    super.key,
    required this.username,
    required this.password,
  });

  @override
  State<SignupScreen2> createState() => _SignupScreen2State();
}

class _SignupScreen2State extends State<SignupScreen2> {
  static const String _aliasDomain = 'myapp.local';

  String? selectedGender;
  String? sugarCondition; // ต้องการ/ไม่ต้องการ
  String? exerciseLevel;
  bool showDropdown = false;
  String? sugarType;

  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController birthDateController = TextEditingController();

  DateTime? selectedDate;
  bool isFormFilled = false;
  bool _loading = false;

  void checkFormFilled() {
    setState(() {
      isFormFilled =
          birthDateController.text.isNotEmpty &&
              heightController.text.isNotEmpty &&
              weightController.text.isNotEmpty &&
              selectedGender != null &&
              sugarCondition != null &&
              exerciseLevel != null;
    });
  }

  InputDecoration _decoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: Colors.grey[300],
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      labelStyle: const TextStyle(fontSize: 14),
      suffixStyle: const TextStyle(fontSize: 14),
    );
  }

  Widget _radio(String label, String? groupValue, ValueChanged<String?> onChanged) {
    return Row(
      children: [
        Radio<String>(
          value: label,
          groupValue: groupValue,
          onChanged: (val) {
            onChanged(val);
            checkFormFilled();
          },
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  String _toYyyyMmDd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'เลือกวันเกิด',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
    );
    if (picked != null) {
      selectedDate = picked;
      birthDateController.text = _toYyyyMmDd(picked);
      checkFormFilled();
    }
  }

  int _calcAge(DateTime dob) {
    final today = DateTime.now();
    int age = today.year - dob.year;
    final hadBirthday = (today.month > dob.month) ||
        (today.month == dob.month && today.day >= dob.day);
    if (!hadBirthday) age--;
    return age;
  }

  @override
  void dispose() {
    heightController.dispose();
    weightController.dispose();
    birthDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!isFormFilled || _loading) return;

    // กันอายุต่ำกว่า 13 ปี (ถ้าต้องการ)
    if (selectedDate != null && _calcAge(selectedDate!) < 13) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ต้องมีอายุตั้งแต่ 13 ปีขึ้นไป')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final email = '${widget.username}@$_aliasDomain'.replaceAll(' ', '');
      final pass = widget.password;

      // ✅ เช็ค username ซ้ำใน Firestore ก่อน (usernames/{username})
      final usernameRef =
      FirebaseFirestore.instance.doc('usernames/${widget.username}');
      final existSnap = await usernameRef.get();
      if (existSnap.exists) {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'username already taken',
        );
      }

      // 1) สมัคร Auth
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;

      // 2) บันทึกโปรไฟล์ลง users/{uid}
      final genderInt = (selectedGender == 'ชาย') ? 0 : 1;
      final diabetesInt = (sugarCondition == 'ต้องการ') ? 1 : 0;
      final exerciseMap = {'0': 0, '1-3': 1, '4-5': 2, '6-7': 3};
      final exerciseInt = exerciseMap[exerciseLevel] ?? 0;

      final height = int.tryParse(heightController.text) ?? 0;
      final weight = int.tryParse(weightController.text) ?? 0;

      final userDoc =
      FirebaseFirestore.instance.collection('users').doc(uid);
      final usernameDoc =
      FirebaseFirestore.instance.doc('usernames/${widget.username}');

      // 3) เขียนพร้อมกันแบบ batch เพื่อความถูกต้อง (จอง username)
      final batch = FirebaseFirestore.instance.batch();

      batch.set(userDoc, {
        'uid': uid,
        'username': widget.username,
        'email': email,
        'birthdate': birthDateController.text, // 'YYYY-MM-DD'
        'gender': genderInt,
        'diabetes': diabetesInt,
        'height': height,
        'weight': weight,
        'exerciseLevel': exerciseInt,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // map username -> uid เพื่อกันชนกัน/เช็คซ้ำ
      batch.set(usernameDoc, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลงทะเบียนสำเร็จ')),
      );

      // กลับไปหน้า Sign In
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SigninScreen()),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'สมัครไม่สำเร็จ';
      if (e.code == 'email-already-in-use') {
        msg = 'ชื่อผู้ใช้นี้ถูกใช้แล้ว';
      } else if (e.code == 'weak-password') {
        msg = 'รหัสผ่านอ่อนเกินไป';
      } else if (e.code == 'invalid-email') {
        msg = 'ชื่อผู้ใช้ไม่ถูกต้อง';
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, toolbarHeight: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Image.asset('assets/images/arrow.png', width: 28, height: 28),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('ลงทะเบียน',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 32),

              TextField(
                controller: birthDateController,
                readOnly: true,
                style: const TextStyle(fontSize: 14),
                decoration: _decoration('วันเกิด (YYYY-MM-DD)'),
                onTap: _pickBirthDate,
              ),
              const SizedBox(height: 12),

              const Text('เพศ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _radio('ชาย', selectedGender, (v) => setState(() => selectedGender = v))),
                  Expanded(child: _radio('หญิง', selectedGender, (v) => setState(() => selectedGender = v))),
                ],
              ),
              const SizedBox(height: 12),

              // ===== กำหนดค่าน้ำตาล (ให้ UI เหมือน signup2) =====
              const Text(
                'คุณอยากให้ระบบกำหนดค่าน้ำตาลแบบไหน?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
              ),
              const SizedBox(height: 8),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // '0' = กำหนด 10 กรัม (สำหรับคนเคร่งเรื่องน้ำตาล)
                  InkWell(
                    onTap: () {
                      setState(() {
                        sugarCondition = '0';   // คง mapping เดิม แต่เป็นสตริง
                        showDropdown = true;
                      });
                      checkFormFilled();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Radio<String>(
                          value: '0',
                          groupValue: sugarCondition,
                          onChanged: (v) {
                            setState(() {
                              sugarCondition = v ?? '0';
                              showDropdown = true;
                            });
                            checkFormFilled();
                          },
                        ),
                        const Flexible(
                          child: Text('กำหนด 10 กรัม(สำหรับคนเคร่งเรื่องน้ำตาล)'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // '1' = คำนวณตามอายุของฉัน
                  InkWell(
                    onTap: () {
                      setState(() {
                        sugarCondition = '1';
                        showDropdown = false;
                        sugarType = null;
                      });
                      checkFormFilled();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Radio<String>(
                          value: '1',
                          groupValue: sugarCondition,
                          onChanged: (v) {
                            setState(() {
                              sugarCondition = v ?? '1';
                              showDropdown = false;
                              sugarType = null;
                            });
                            checkFormFilled();
                          },
                        ),
                        const Flexible(child: Text('คำนวณตามอายุของฉัน')),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: _decoration('ส่วนสูง', suffix: 'ซม.'),
                onChanged: (_) => checkFormFilled(),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: _decoration('น้ำหนัก', suffix: 'กก.'),
                onChanged: (_) => checkFormFilled(),
              ),
              const SizedBox(height: 12),

              const Text('ระดับการออกกำลังกาย',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[300],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Image.asset('assets/images/down-arrow.png', width: 20, height: 20),
                  ),
                ),
                icon: const SizedBox.shrink(),
                value: exerciseLevel,
                items: const [
                  DropdownMenuItem(value: '0', child: Text('ไม่ค่อยออกกำลังกาย', style: TextStyle(fontSize: 14))),
                  DropdownMenuItem(value: '1-3', child: Text('ออกกำลังกาย 1-3 ครั้ง/สัปดาห์', style: TextStyle(fontSize: 14))),
                  DropdownMenuItem(value: '4-5', child: Text('ออกกำลังกาย 4-5 ครั้ง/สัปดาห์', style: TextStyle(fontSize: 14))),
                  DropdownMenuItem(value: '6-7', child: Text('ออกกำลังกาย 6-7 ครั้ง/สัปดาห์', style: TextStyle(fontSize: 14))),
                ],
                onChanged: (v) {
                  setState(() => exerciseLevel = v);
                  checkFormFilled();
                },
              ),
              const SizedBox(height: 32),

              Center(
                child: ElevatedButton(
                  onPressed: isFormFilled && !_loading ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isFormFilled && !_loading) ? Colors.blue : Colors.grey,
                    minimumSize: const Size.fromHeight(56),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 14),
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
                      : const Text('ลงทะเบียน', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
