// lib/screen/Option/EditProfile.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _dobController;   // YYYY-MM-DD
  late TextEditingController _ageController;   // read-only
  late TextEditingController _heightController;
  late TextEditingController _weightController;

  int _gender = 0;        // 0 = ชาย, 1 = หญิง
  int _diabetes = 0;      // 0 = ไม่ติดตาม, 1 = ติดตาม
  int _exerciseLevel = 0; // 0..3
  DateTime? _selectedDob;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _dobController = TextEditingController();
    _ageController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();

    _loadProfileFromFirestore();
  }

  @override
  void dispose() {
    _dobController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  DateTime? _parseDob(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    final p = dob.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  String _formatYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _calcAge(DateTime dob) {
    final today = DateTime.now();
    var age = today.year - dob.year;
    final hadBirthday =
        (today.month > dob.month) || (today.month == dob.month && today.day >= dob.day);
    if (!hadBirthday) age--;
    return age < 0 ? 0 : age;
  }

  // ===== Load current profile from Firestore =====
  Future<void> _loadProfileFromFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // ไม่ได้ล็อกอิน: กรอกค่าว่าง
        _setFieldsFromMap({});
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      _setFieldsFromMap(doc.data() ?? {});
    } catch (_) {
      // ถ้ามีปัญหา ก็ปล่อยให้ฟอร์มว่างไว้
      _setFieldsFromMap({});
    }
  }

  void _setFieldsFromMap(Map<String, dynamic> d) {
    final birth = (d['birthdate'] as String?) ?? '';
    final dob = _parseDob(birth);

    _dobController.text = birth;
    _ageController.text = dob != null ? _calcAge(dob).toString() : '0';
    _selectedDob = dob;

    _heightController.text = (d['height'] is num) ? (d['height']).toString() : '0';
    _weightController.text = (d['weight'] is num) ? (d['weight']).toString() : '0';

    _gender = (d['gender'] is num) ? (d['gender'] as num).toInt() : 0;
    _diabetes = (d['diabetes'] is num) ? (d['diabetes'] as num).toInt() : 0;
    _exerciseLevel = (d['exerciseLevel'] is num) ? (d['exerciseLevel'] as num).toInt() : 0;

    setState(() => _loading = false);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _selectedDob ?? DateTime(now.year - 20, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? DateTime(now.year - 20) : initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      helpText: 'เลือกวันเกิด',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
    );
    if (picked != null) {
      _selectedDob = picked;
      _dobController.text = _formatYmd(picked);
      _ageController.text = _calcAge(picked).toString();
      setState(() {});
    }
  }

  // ===== Save to Firestore (no SessionProvider) =====
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนบันทึกข้อมูล')),
      );
      return;
    }

    final height = int.tryParse(_heightController.text) ?? 0;
    final weight = int.tryParse(_weightController.text) ?? 0;

    String? birthdate;
    if (_dobController.text.isNotEmpty) {
      final dob = _parseDob(_dobController.text);
      if (dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รูปแบบวันเกิดไม่ถูกต้อง')),
        );
        return;
      }
      birthdate = _dobController.text;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'gender': _gender,
        'diabetes': _diabetes,
        'height': height,
        'weight': weight,
        'exerciseLevel': _exerciseLevel,
        'birthdate': birthdate,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกข้อมูลเรียบร้อย')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('แก้ไขข้อมูลส่วนตัว')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('แก้ไขข้อมูลส่วนตัว')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // วันเกิด (แตะเพื่อเลือก) – ใช้คำนวณอายุ
              TextFormField(
                controller: _dobController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'วันเกิด (YYYY-MM-DD)',
                  hintText: 'แตะเพื่อเลือกวันเกิด',
                ),
                onTap: _pickDob,
              ),

              // อายุ (โชว์อัตโนมัติ, แก้ไม่ได้)
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: 'อายุ'),
                readOnly: true,
                enabled: false,
              ),

              TextFormField(
                controller: _heightController,
                decoration: const InputDecoration(labelText: 'ส่วนสูง (cm)'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                (value == null || value.isEmpty) ? 'กรุณากรอกส่วนสูง' : null,
              ),
              TextFormField(
                controller: _weightController,
                decoration: const InputDecoration(labelText: 'น้ำหนัก (kg)'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                (value == null || value.isEmpty) ? 'กรุณากรอกน้ำหนัก' : null,
              ),

              const SizedBox(height: 10),
              const Text('เพศ'),
              Row(
                children: [
                  Radio(
                    value: 0,
                    groupValue: _gender,
                    onChanged: (val) => setState(() => _gender = val ?? 0),
                  ),
                  const Text('ชาย'),
                  Radio(
                    value: 1,
                    groupValue: _gender,
                    onChanged: (val) => setState(() => _gender = val ?? 1),
                  ),
                  const Text('หญิง'),
                ],
              ),

              const Text(
                'คุณอยากให้ระบบกำหนดค่าน้ำตาลแบบไหน?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
              ),
              const SizedBox(height: 8),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<int>(
                    value: 1,
                    groupValue: _diabetes,
                    onChanged: (v) => setState(() => _diabetes = v ?? 1),
                    title: const Text('กำหนด 10 กรัม (สำหรับคนเคร่งเรื่องน้ำตาล)'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  RadioListTile<int>(
                    value: 0,
                    groupValue: _diabetes,
                    onChanged: (v) => setState(() => _diabetes = v ?? 0),
                    title: const Text('คำนวณตามอายุของฉัน'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),


              const SizedBox(width: 12),

              const Text('ระดับการออกกำลังกาย'),
              DropdownButton<int>(
                value: _exerciseLevel,
                onChanged: (val) => setState(() => _exerciseLevel = val ?? 0),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('ไม่ค่อยออกกำลังกาย')),
                  DropdownMenuItem(value: 1, child: Text('ออกกำลังกาย 1-3 ครั้ง/สัปดาห์')),
                  DropdownMenuItem(value: 2, child: Text('ออกกำลังกาย 4-5 ครั้ง/สัปดาห์')),
                  DropdownMenuItem(value: 3, child: Text('ออกกำลังกาย 6-7 ครั้ง/สัปดาห์')),
                ],
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveProfile,
                child: const Text('บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
