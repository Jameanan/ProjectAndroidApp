// lib/screen/search/custom_menu_detail.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:main/services/custom_menu_service.dart';      // guest
import 'package:main/services/custom_menus_repo.dart';        // login
import 'package:main/provider/session_provider.dart';         // uid ตอน login
import 'package:main/screen/search/AddMenuScreen.dart';       // เปิดแก้ไข

class CustomMenuDetailPage extends StatelessWidget {
  final Map<String, dynamic> item; // จาก Searchpage (ของฉัน)
  final String fallbackAsset;

  const CustomMenuDetailPage({
    super.key,
    required this.item,
    required this.fallbackAsset,
  });

  bool get _isGuestItem => item.containsKey('_guestId') || item['id'] is int;

  // ✅ รองรับหลายคีย์ (_docId, docId, _id)
  String? get _docId =>
      (item['_docId'] ?? item['docId'] ?? item['_id']) as String?;

  // ใช้คีย์เดียว imagePath (อาจเป็น URL หรือ local path)
  ImageProvider _img() {
    final path = item['imagePath'] as String?;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return NetworkImage(path);
      }
      if (path.startsWith('/') && File(path).existsSync()) {
        return FileImage(File(path));
      }
    }
    return AssetImage(fallbackAsset);
  }

  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final name = (item['menuName'] ?? '').toString();

    // อ่านจาก menuData -> nutrition_data
    final menuData = (item['menuData'] ?? const {}) as Map<String, dynamic>;
    final nd = (menuData['nutrition_data'] ?? {}) as Map<String, dynamic>;
    final group = Map<String, dynamic>.from(
      nd['nosugar_nutrition'] ?? nd['sugar_nutrition'] ?? const {},
    );
    final ingredients =
        (group['Raw_materials'] as List?)?.cast<dynamic>() ?? const [];

    final kcal    = _toD(group['Calorie'] ?? item['Calorie']);
    final sugar   = _toD(group['Sugar']   ?? item['Sugar']);
    final protein = _toD(group['Protein']);
    final fat     = _toD(group['Fat']);
    final fiber   = _toD(group['Fiber']);
    final carb    = _toD(group['Carb']);

    // ====== Actions (แก้ไข/ลบ) แยก guest vs login ======
    Future<void> _edit() async {
      final init = InitialValues(
        name: name,
        ingredients: ingredients.map((e) => e.toString()).toList(),
        calorie: kcal,
        sugar: sugar,
        protein: protein,
        fat: fat,
        fiber: fiber,
        carb: carb,
      );

      if (_isGuestItem) {
        final guestId = (item['_guestId'] ?? item['id']) as int?;
        if (guestId == null) return;
        final res = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AddMenuScreen(editingGuestRowId: guestId, initialValues: init),
          ),
        );
        if (res == true && context.mounted) Navigator.pop(context, true);
        return;
      }

      // login
      final docId = _docId;
      if (docId == null) return;
      final res = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AddMenuScreen(editingDocId: docId, initialValues: init),
        ),
      );
      if (res == true && context.mounted) Navigator.pop(context, true);
    }

    Future<void> _delete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('ลบเมนูนี้?'),
          content: Text('ต้องการลบ "$name" ออกจากรายการของคุณหรือไม่'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลบ')),
          ],
        ),
      );
      if (ok != true) return;

      if (_isGuestItem) {
        final guestId = (item['_guestId'] ?? item['id']) as int?;
        if (guestId == null) return;
        await CustomMenuService.deleteGuestMenu(id: guestId);
        if (context.mounted) Navigator.pop(context, true);
        return;
      }

      // login
      final docId = _docId;
      if (docId == null) return;
      final sp = context.read<SessionProvider>();
      if (!sp.isLoggedIn || sp.ownerUid == null) return;
      await CustomMenusRepo.instance.deleteMenu(uid: sp.ownerUid!, docId: docId);
      if (context.mounted) Navigator.pop(context, true);
    }

    Widget box(String label, String val, Color color, String icon) {
      return Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Image.asset('assets/icon/$icon', width: 28, height: 28),
            const SizedBox(height: 6),
            Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _edit),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image(image: _img(), width: double.infinity, height: 200, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text('ข้อมูลโภชนาการ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  box('พลังงาน', '${kcal.toStringAsFixed(0)} kcal', Colors.amber.shade100, 'fire.png'),
                  const SizedBox(width: 8),
                  box('น้ำตาล', '${sugar.toStringAsFixed(1)} ก.', Colors.pink.shade100, 'sugar-cube.png'),
                  const SizedBox(width: 8),
                  box('โปรตีน', '${protein.toStringAsFixed(1)} ก.', Colors.green.shade100, 'proteins.png'),
                  const SizedBox(width: 8),
                  box('ไขมัน', '${fat.toStringAsFixed(1)} ก.', Colors.orange.shade100, 'trans-fat.png'),
                  const SizedBox(width: 8),
                  box('ไฟเบอร์', '${fiber.toStringAsFixed(1)} ก.', Colors.brown.shade100, 'fiber.png'),
                  const SizedBox(width: 8),
                  box('คาร์บ', '${carb.toStringAsFixed(1)} ก.', Colors.purple.shade100, 'carb.png'),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('วัตถุดิบ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: (ingredients.isEmpty)
                  ? const Text('–')
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ingredients
                    .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $e'),
                ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('ยืนยัน'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  // คืนค่า imagePath (ถ้าเป็น URL ก็ส่ง URL; ถ้าเป็น local ก็ส่ง local)
                  final String imagePathToReturn = (item['imagePath'] as String?) ?? '';

                  Navigator.pop(context, {
                    'menuName': name,
                    'imagePath': imagePathToReturn, // ✅ ใช้คีย์เดียว
                    'menuData': {
                      'nutrition_data': {
                        'sugar_nutrition': {
                          'Calorie': kcal, 'Sugar': sugar, 'Protein': protein,
                          'Fat': fat, 'Fiber': fiber, 'Carb': carb, 'Raw_materials': ingredients,
                        },
                        'nosugar_nutrition': {
                          'Calorie': kcal, 'Sugar': sugar, 'Protein': protein,
                          'Fat': fat, 'Fiber': fiber, 'Carb': carb, 'Raw_materials': ingredients,
                        },
                      }
                    },
                    'useNoSugar': (item['useNoSugar'] == true), // คงค่าที่มากับรายการ
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
