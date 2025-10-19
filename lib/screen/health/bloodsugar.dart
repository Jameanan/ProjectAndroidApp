import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:main/provider/session_provider.dart';
import 'package:main/database/dbusers.dart';

class BloodSugarPage extends StatefulWidget {
  final double? initialValue;
  final DateTime? selectedDate;

  const BloodSugarPage({super.key, this.initialValue, this.selectedDate});

  @override
  State<BloodSugarPage> createState() => _BloodSugarPageState();
}

class _BloodSugarPageState extends State<BloodSugarPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _valCtrl;

  @override
  void initState() {
    super.initState();
    _valCtrl = TextEditingController(
      text: widget.initialValue != null ? widget.initialValue!.toStringAsFixed(1) : '',
    );
  }

  @override
  void dispose() {
    _valCtrl.dispose();
    super.dispose();
  }

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final raw = _valCtrl.text.trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกค่าน้ำตาลเป็นตัวเลขที่มากกว่า 0')),
      );
      return;
    }

    final now = DateTime.now();
    final at = (widget.selectedDate ?? now);
    final dayOnly = DateTime(at.year, at.month, at.day);
    final todayOnly = DateTime(now.year, now.month, now.day);

    if (_isLoggedIn) {
      // Login → ผ่าน SessionProvider (ไป Firestore)
      await context.read<SessionProvider>().setBloodSugarForDay(
        day: dayOnly,
        value: parsed,
        unit: 'mg/dL',
      );
    } else {
      // Guest → SQLite (username เฉพาะ guest)
      await DBusers.instance.upsertDailyBloodSugar(
        value: parsed,
        unit: 'mg/dL',
        at: dayOnly,
      );

      // ถ้าเป็น “วันนี้” อัปเดต state ของ Provider เพื่อให้หน้า Home รีเฟรชทันที
      if (DateUtils.isSameDay(dayOnly, todayOnly)) {
        await context.read<SessionProvider>().setBloodSugar(value: parsed, unit: 'mg/dL');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกค่าน้ำตาลในเลือดเรียบร้อย')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialValue != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'แก้ไขค่าน้ำตาลในเลือด' : 'เพิ่มค่าน้ำตาลในเลือด')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _valCtrl,
                decoration: const InputDecoration(
                  labelText: 'ค่าน้ำตาลในเลือด (mg/dL)',
                  hintText: 'เช่น 95.0',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'กรุณากรอกค่าน้ำตาลในเลือด';
                  final n = double.tryParse(v.trim());
                  if (n == null) return 'รูปแบบไม่ถูกต้อง';
                  if (n <= 0) return 'ค่าต้องมากกว่า 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(isEdit ? 'บันทึกการแก้ไข' : 'บันทึก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
