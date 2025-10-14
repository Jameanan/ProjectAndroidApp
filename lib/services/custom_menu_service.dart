// lib/services/custom_menu_service.dart
import 'dart:io';
import 'package:main/database/dbusers.dart';
import 'package:main/databaseSearch.dart';

class CustomMenuService {
  // ===== Utils (normalize) =====
  static String _norm(String raw) {
    var s = raw.trim().toLowerCase();
    final thaiMarks = RegExp(r'[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]');
    s = s.replaceAll(thaiMarks, '');
    final symbols = RegExp("[\\s\\.\\-_/(){}\\[\\],;:!@#%^&*+=|\"'`~]");
    s = s.replaceAll(symbols, '');
    return s;
  }

  static Future<bool> _existsInMainDatabase(String name) async {
    final firstPage = await DatabaseSearch.searchMenus('');
    final n = _norm(name);
    return firstPage.any((row) {
      final nm = (row['Thai_Name'] ?? row['Foodname'] ?? row['menu_name'] ?? '').toString();
      return _norm(nm) == n;
    });
  }

  // ===== Public: ให้ AddMenuScreen ใช้เช็คซ้ำฝั่ง Guest =====
  static Future<bool> existsGuestMenu({required String name, int? exceptId}) {
    return DBusers.instance.existsCustomMenuName(name: name, exceptId: exceptId);
  }

  // ===== Create (Guest) =====
  static Future<int> addGuestMenu({
    required String name,
    String? imagePath,
    String? ingredients,
    required double calorie,
    required double sugar,
    required double protein,
    required double fat,
    required double fiber,
    required double carb,
  }) async {
    // กันชื่อซ้ำในฐานหลักด้วย
    if (await _existsInMainDatabase(name)) {
      throw Exception('มีเมนูนี้อยู่แล้วในฐานข้อมูลหลัก');
    }
    // กันชื่อซ้ำใน guest
    if (await DBusers.instance.existsCustomMenuName(name: name)) {
      throw Exception('มีเมนูนี้อยู่แล้วในโหมดทดลอง');
    }

    return DBusers.instance.insertCustomMenu(
      name: name,
      imagePath: imagePath,
      ingredients: ingredients,
      calorie: calorie,
      sugar: sugar,
      protein: protein,
      fat: fat,
      fiber: fiber,
      carb: carb,
    );
  }

  // ===== Read (Guest) =====
  static Future<List<Map<String, dynamic>>> getGuestMenus({String? keyword}) async {
    return DBusers.instance.getCustomMenus(keyword: keyword);
  }

  // แปลง row -> payload ที่ Search/Detail ใช้
  static Map<String, dynamic> toHomeSelection(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString();
    final img = row['image_path'] as String?;

    double _toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final s = v.toString();
      final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
      return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
    }

    final cal     = _toD(row['calorie']);
    final sugar   = _toD(row['sugar']);
    final protein = _toD(row['protein']);
    final fat     = _toD(row['fat']);
    final fiber   = _toD(row['fiber']);
    final carb    = _toD(row['carb']);

    // ✅ แปลง "ingredients" (TEXT) -> List<String> เพื่อโชว์วัตถุดิบ
    final ingStr = (row['ingredients'] ?? '').toString();
    final rawMaterials = ingStr
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final nutrition = {
      'Calorie': cal,
      'Sugar': sugar,
      'Protein': protein,
      'Fat': fat,
      'Fiber': fiber,
      'Carb': carb,
      'Raw_materials': rawMaterials,
    };

    return {
      'id': row['id'], // สำคัญสำหรับแก้ไข/ลบ
      'menuName': name,
      'imagePath': (img != null && img.isNotEmpty && File(img).existsSync()) ? img : null,
      'menuData': {
        'nutrition_data': {
          'sugar_nutrition': nutrition,
          'nosugar_nutrition': nutrition,
        }
      },
      'useNoSugar': false,
    };
  }

  // ===== Update (Guest) =====
  static Future<void> updateGuestMenu({
    required int id,
    required String name,
    String? imagePath,
    String? ingredients,
    required double calorie,
    required double sugar,
    required double protein,
    required double fat,
    required double fiber,
    required double carb,
  }) async {
    // กันชื่อซ้ำ (เว้น id เดิม) + กันชนฐานหลักถ้าชื่อเปลี่ยน
    final dupGuest = await DBusers.instance.existsCustomMenuName(name: name, exceptId: id);
    if (dupGuest) {
      throw Exception('มีเมนูนี้อยู่แล้วในโหมดทดลอง');
    }
    // ถ้าชื่อใหม่ชนฐานหลัก
    if (await _existsInMainDatabase(name)) {
      throw Exception('มีเมนูนี้อยู่แล้วในฐานข้อมูลหลัก');
    }

    await DBusers.instance.updateCustomMenu(
      id: id,
      name: name,
      imagePath: imagePath,
      ingredients: ingredients,
      calorie: calorie,
      sugar: sugar,
      protein: protein,
      fat: fat,
      fiber: fiber,
      carb: carb,
    );
  }

  // ===== Delete (Guest) =====
  static Future<void> deleteGuestMenu({ required int id }) async {
    await DBusers.instance.deleteCustomMenu(id: id);
  }
}
