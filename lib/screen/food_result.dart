// lib/screen/food_result.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:main/provider/session_provider.dart';
import 'package:main/services/api_service.dart';

class FoodResultPage extends StatefulWidget {
  final String menuName;

  final String imagePath;

  /// payload โภชนาการจากโมเดล
  final Map<String, dynamic> menuData;

  const FoodResultPage({
    super.key,
    required this.menuName,
    required this.imagePath,
    required this.menuData,
  });

  @override
  State<FoodResultPage> createState() => _FoodResultPageState();
}

class _FoodResultPageState extends State<FoodResultPage> {
  bool useNoSugar = false;

  // ฟีดแบ็กผลลัพธ์
  bool _isSatisfied = true; // ค่าตั้งต้น: พอใจ
  final TextEditingController _note = TextEditingController();
  bool _submittingFeedback = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nutritionData = widget.menuData['nutrition_data'] as Map<String, dynamic>? ?? {};
    final selectedGroup = useNoSugar ? 'nosugar_nutrition' : 'sugar_nutrition';
    final ingredients = (nutritionData[selectedGroup]?['Raw_materials'] as List<dynamic>?) ?? const [];

    const int maxVisibleItems = 10;
    final bool needsScroll = ingredients.length > maxVisibleItems;

    String readNutrition(String key) {
      final group = nutritionData[selectedGroup];
      if (group is Map<String, dynamic>) {
        final value = group[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
      return '-';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.menuName),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // รูปตัวอย่าง (รองรับทั้ง URL และ local path; ถ้าว่างแสดง spoon.jpg)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildPreviewImage(widget.imagePath),
            ),
            const SizedBox(height: 16),

            // สลับสูตร มี/ไม่มีน้ำตาล
            Text('คุณต้องการสูตรอาหารแบบไหน', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("ปรุงโดยมีน้ำตาล"),
                  selected: !useNoSugar,
                  onSelected: (_) => setState(() => useNoSugar = false),
                  selectedColor: const Color(0xFFEFF6FF),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text("ปรุงโดยไม่มีน้ำตาล"),
                  selected: useNoSugar,
                  onSelected: (_) => setState(() => useNoSugar = true),
                  selectedColor: const Color(0xFFEFF6FF),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('ข้อมูลโภชนาการ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  nutritionBox('fire.png',       readNutrition("Calorie"), 'พลังงาน', Colors.lightBlue.shade100),
                  nutritionBox('sugar-cube.png', readNutrition("Sugar"),   'น้ำตาล',  Colors.pink.shade100),
                  nutritionBox('proteins.png',   readNutrition("Protein"), 'โปรตีน',  Colors.green.shade100),
                  nutritionBox('trans-fat.png',  readNutrition("Fat"),     'ไขมัน',   Colors.orange.shade100),
                  nutritionBox('fiber.png',      readNutrition("Fiber"),   'ไฟเบอร์', Colors.brown.shade100),
                  nutritionBox('carb.png',       readNutrition("Carb"),    'คาร์บ',   Colors.purple.shade100),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('วัตถุดิบ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              height: 250,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: needsScroll
                  ? Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: ingredients
                        .map((item) => Text('• $item', style: const TextStyle(height: 1.4)))
                        .toList(),
                  ),
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ingredients
                    .map((item) => Text('• $item', style: const TextStyle(height: 1.4)))
                    .toList(),
              ),
            ),

            const SizedBox(height: 24),
            // ===== ส่วน "หมายเหตุ/ฟีดแบ็ก" =====
            Align(
              alignment: Alignment.centerLeft,
              child: Text('ผลลัพธ์พอใจไหม?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87)),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('พอใจ'),
                  selected: _isSatisfied,
                  onSelected: (_) => setState(() => _isSatisfied = true),
                  selectedColor: const Color(0xFFE8F5E9),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('ไม่พอใจ'),
                  selected: !_isSatisfied,
                  onSelected: (_) => setState(() => _isSatisfied = false),
                  selectedColor: const Color(0xFFFFEBEE),
                ),
              ],
            ),

            const SizedBox(height: 12),
            if (!_isSatisfied) _feedbackBox(),

            const SizedBox(height: 32),

            // ปุ่มยืนยันกว้างเต็มขอบ (เพิ่มเมนูเข้าวันนี้)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onConfirm,
                icon: const Icon(Icons.check),
                label: const Text('ยืนยัน'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ===== ฟีดแบ็ก UI กล่องข้อความ + ปุ่มส่งเล็ก ๆ =====
  Widget _feedbackBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('ช่วยบอกหน่อยว่าที่ถูกควรเป็นเมนูอะไร', style: TextStyle(fontSize: 14, color: Colors.black54)),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _note,
                decoration: InputDecoration(
                  hintText: 'เช่น น้ำตกหมู (แทน ลาบหมู)',
                  filled: true,
                  fillColor: Colors.grey[200],
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _submittingFeedback ? null : _submitFeedback,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _submittingFeedback
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('ส่ง'),
            ),
          ],
        ),
      ],
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ===== ส่งฟีดแบ็กเข้า Firestore =====
  Future<void> _submitFeedback() async {
    setState(() => _submittingFeedback = true);
    try {
      final sp = context.read<SessionProvider>();
      final uid = sp.ownerUid ?? '';
      final username = sp.user?.username ?? sp.currentUsername ?? '';
      final userCorrection = _note.text.trim();

      // ใช้ imagePath ตัวเดียว (ถ้าเป็น local และล็อกอิน → อัปโหลดก่อน)
      String imagePathOut = widget.imagePath;
      final isLocalFile = imagePathOut.isNotEmpty && imagePathOut.startsWith('/');

      if (sp.isLoggedIn && isLocalFile) {
        final file = File(imagePathOut);
        if (await file.exists()) {
          final url = await ApiService.uploadImageAndGetUrl(
            imageFile: file,
            uid: uid,
            bucket: 'feedbacks',
          );
          if (url != null && url.isNotEmpty) {
            imagePathOut = url; // เก็บ URL กลับไปใน imagePath
          }
        }
      }

      final data = <String, dynamic>{
        'uid': uid,
        'username': username,
        'predictedMenu': widget.menuName,
        'userCorrection': userCorrection,
        'imagePath': imagePathOut, // <-- คีย์เดียว
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('feedback_predictions')
          .add(data);

      _toast('ส่งหมายเหตุแล้ว ขอบคุณมาก!');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('ส่งหมายเหตุไม่สำเร็จ: $e');
    } finally {
      if (mounted) {
        setState(() => _submittingFeedback = false);
      }
    }
  }

  // ===== ปุ่มยืนยัน (เพิ่มเมนูเข้าวันนี้และ pop กลับ) =====
  Future<void> _onConfirm() async {
    final sp = context.read<SessionProvider>();

    // ใช้ imagePath ตัวเดียว (ถ้าเป็น local และล็อกอิน → อัปโหลดก่อน)
    String imagePathOut = widget.imagePath;
    final isLocalFile = imagePathOut.isNotEmpty && imagePathOut.startsWith('/');

    if (sp.isLoggedIn && isLocalFile) {
      final file = File(imagePathOut);
      if (await file.exists()) {
        final uid = sp.ownerUid!;
        final url = await ApiService.uploadImageAndGetUrl(
          imageFile: file,
          uid: uid,
          bucket: 'predictions',
        );
        if (url != null && url.isNotEmpty) {
          imagePathOut = url; // เก็บ URL กลับใน imagePath
        }
      }
    }

    // การันตีให้มี nutrition_data ครบ 2 group ก่อนส่งกลับ
    Map<String, dynamic> md = Map<String, dynamic>.from(widget.menuData);
    final nd = (md['nutrition_data'] as Map<String, dynamic>?) ?? {};
    Map<String, dynamic> sugar = Map<String, dynamic>.from(nd['sugar_nutrition'] ?? {});
    Map<String, dynamic> nosugar = Map<String, dynamic>.from(nd['nosugar_nutrition'] ?? {});

    md['nutrition_data'] = {
      'sugar_nutrition': {
        'Calorie': sugar['Calorie'] ?? 0,
        'Sugar': sugar['Sugar'] ?? 0,
        'Protein': sugar['Protein'] ?? 0,
        'Fat': sugar['Fat'] ?? 0,
        'Fiber': sugar['Fiber'] ?? 0,
        'Carb': sugar['Carb'] ?? 0,
        'Raw_materials': sugar['Raw_materials'] ?? const [],
      },
      'nosugar_nutrition': {
        'Calorie': nosugar['Calorie'] ?? sugar['Calorie'] ?? 0,
        'Sugar': nosugar['Sugar'] ?? sugar['Sugar'] ?? 0,
        'Protein': nosugar['Protein'] ?? sugar['Protein'] ?? 0,
        'Fat': nosugar['Fat'] ?? sugar['Fat'] ?? 0,
        'Fiber': nosugar['Fiber'] ?? sugar['Fiber'] ?? 0,
        'Carb': nosugar['Carb'] ?? sugar['Carb'] ?? 0,
        'Raw_materials': nosugar['Raw_materials'] ?? sugar['Raw_materials'] ?? const [],
      },
    };

    final selectedGroup = useNoSugar ? 'nosugar_nutrition' : 'sugar_nutrition';
    final sel = md['nutrition_data'][selectedGroup] as Map<String, dynamic>;

    Navigator.pop(context, {
      'menuName': widget.menuName,
      'imagePath': imagePathOut, // <-- ส่งกลับคีย์เดียว (เป็น URL ถ้าอัปโหลดแล้ว)
      'menuData': md,
      'useNoSugar': useNoSugar,
      'recentForSearch': {
        'menuName': widget.menuName,
        'imagePath': imagePathOut, // <-- คีย์เดียว
        'Calorie': _numToDouble(sel['Calorie']),
        'Sugar': _numToDouble(sel['Sugar']),
        'createdAt': DateTime.now().toIso8601String(),
        'custom': false,
      },
    });
  }

  double _numToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
  }

  Widget nutritionBox(String iconName, String valueText, String label, Color bgColor) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/icon/$iconName', width: 36, height: 36),
          const SizedBox(height: 8),
          Text(valueText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.black87)),
        ],
      ),
    );
  }

  // ---------- Helper: แสดงรูปจาก path หรือ URL ----------
  Widget _buildPreviewImage(String pathOrUrl) {
    const double h = 200;

    if (pathOrUrl.isEmpty) {
      return Image.asset('assets/icon/spoon.jpg', height: h, fit: BoxFit.cover);
    }

    // ถ้าเป็น URL
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Image.network(
        pathOrUrl,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Image.asset('assets/icon/spoon.jpg', height: h, fit: BoxFit.cover),
      );
    }

    // ถ้าเป็นไฟล์ในเครื่อง
    if (pathOrUrl.startsWith('/')) {
      final f = File(pathOrUrl);
      return Image.file(
        f,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Image.asset('assets/icon/spoon.jpg', height: h, fit: BoxFit.cover),
      );
    }

    // เผื่อรูปแบบอื่น ๆ ที่ไม่เข้าเงื่อนไข
    return Image.asset('assets/icon/spoon.jpg', height: h, fit: BoxFit.cover);
  }
}
