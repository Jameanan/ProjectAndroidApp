// lib/services/custom_menus_repo.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:main/databaseSearch.dart';
import 'package:main/services/api_service.dart';

class CustomMenusRepo {
  CustomMenusRepo._();
  static final instance = CustomMenusRepo._();

  final _fs = FirebaseFirestore.instance;

  // ===== Load =====
  Future<List<Map<String, dynamic>>> getRecentCustomMenus({
    required String? uid,
    int limit = 20,
  }) async {
    if (uid == null) return [];
    final qs = await _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return qs.docs.map((d) => {...d.data(), '_id': d.id}).toList();
  }

  Future<List<Map<String, dynamic>>> getAllCustomMenus({required String? uid}) async {
    if (uid == null) return [];
    final qs = await _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .orderBy('menuName')
        .get();
    return qs.docs.map((d) => {...d.data(), '_id': d.id}).toList();
  }

  // ===== Create =====
  Future<void> addRecentCustomMenu({
    required String? uid,
    required Map<String, dynamic> data,
  }) async {
    if (uid == null) throw Exception('ต้องเข้าสู่ระบบก่อนเพิ่มเมนู');

    final menuName = (data['menuName'] ?? '').toString().trim();
    if (menuName.isEmpty) throw Exception('กรุณาระบุชื่อเมนู');
    final norm = _norm(menuName);

    final dupDb = await _existsInMainDatabase(menuName);
    if (dupDb) throw Exception('มีเมนูนี้อยู่แล้วในฐานข้อมูลหลัก');

    final dupMine = await existsByName(uid: uid, name: menuName);
    if (dupMine) throw Exception('คุณเคยเพิ่มเมนูนี้แล้ว');

    final md = data['menuData'];
    num? kcal;
    num? sugar;
    if (md is Map) {
      final nd = md['nutrition_data'];
      if (nd is Map) {
        final s = nd['sugar_nutrition'];
        final n = nd['nosugar_nutrition'];
        kcal  = _num(s is Map ? s['Calorie'] : null) ?? _num(n is Map ? n['Calorie'] : null);
        sugar = _num(s is Map ? s['Sugar']   : null) ?? _num(n is Map ? n['Sugar']   : null);
      }
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .doc(norm) // ใช้ name_norm เป็น docId
        .set({
      ...data,
      'menuName': menuName,
      'name_norm': norm,
      if (kcal != null) 'Calorie': kcal,
      if (sugar != null) 'Sugar': sugar,
      'createdAt': now,
    });
  }

  Future<void> addMenuIfNotExists({
    required String uid,
    required String menuName,
    required Map<String, dynamic> menuData,
    String? imagePath, // ✅ ใช้คีย์เดียว เก็บได้ทั้ง URL หรือ local path
  }) async {
    final dupDb = await _existsInMainDatabase(menuName);
    if (dupDb) throw Exception('มีเมนูนี้อยู่แล้วในฐานข้อมูลหลัก');

    final dupMine = await existsByName(uid: uid, name: menuName);
    if (dupMine) throw Exception('คุณเคยเพิ่มเมนูนี้แล้ว');

    Map? nd;
    Map? s;
    Map? n;
    if (menuData['nutrition_data'] is Map) {
      nd = menuData['nutrition_data'] as Map;
      s = nd['sugar_nutrition'] as Map?;
      n = nd['nosugar_nutrition'] as Map?;
    }
    final kcal  = _num(s?['Calorie']) ?? _num(n?['Calorie']) ?? _num(menuData['Calorie']) ?? 0;
    final sugar = _num(s?['Sugar'])   ?? _num(n?['Sugar'])   ?? _num(menuData['Sugar'])   ?? 0;

    final rawMaterials =
        (s?['Raw_materials'] as List?) ??
            (n?['Raw_materials'] as List?) ??
            (menuData['Raw_materials'] as List?) ??
            const [];

    final norm = _norm(menuName);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .doc(norm) // ใช้ name_norm เป็น docId
        .set({
      'menuName': menuName,
      'name_norm': norm,
      'menuData': menuData,
      'Calorie': kcal,
      'Sugar': sugar,
      'useNoSugar': false,
      'Raw_materials': rawMaterials,
      if (imagePath != null) 'imagePath': imagePath, // ✅ เขียนลง imagePath
      'createdAt': now,
    });
  }

  // ===== Update (แก้ไข – ไม่แตะรูป) =====
  Future<void> updateMenu({
    required String uid,
    required String docId,
    required String newName,
    required Map<String, dynamic> menuData,
    bool checkDuplicate = true,
  }) async {
    final ref = _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .doc(docId);

    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('ไม่พบเมนูที่จะแก้ไข');
    }
    final dataOld = snap.data() ?? {};
    final oldName = (dataOld['menuName'] ?? '').toString();
    final oldNorm = (dataOld['name_norm'] ?? _norm(oldName)).toString();

    final newNorm = _norm(newName);

    if (oldNorm != newNorm) {
      final dupDb = await _existsInMainDatabase(newName);
      if (dupDb) throw Exception('มีเมนูนี้อยู่แล้วในฐานข้อมูลหลัก');

      final dupMine = await existsByName(
        uid: uid,
        name: newName,
        exceptDocId: docId,
      );
      if (dupMine) throw Exception('คุณเคยเพิ่มเมนูนี้แล้ว');
    }

    Map? nd;
    Map? s;
    Map? n;
    if (menuData['nutrition_data'] is Map) {
      nd = menuData['nutrition_data'] as Map;
      s = nd['sugar_nutrition'] as Map?;
      n = nd['nosugar_nutrition'] as Map?;
    }
    final kcal  = _num(s?['Calorie']) ?? _num(n?['Calorie']) ?? _num(menuData['Calorie']) ?? 0;
    final sugar = _num(s?['Sugar'])   ?? _num(n?['Sugar'])   ?? _num(menuData['Sugar'])   ?? 0;

    final rawMaterials =
        (s?['Raw_materials'] as List?) ??
            (n?['Raw_materials'] as List?) ??
            (menuData['Raw_materials'] as List?) ??
            const [];

    await ref.update({
      'menuName': newName,
      'name_norm': newNorm,
      'menuData': menuData,
      'Calorie': kcal,
      'Sugar': sugar,
      'Raw_materials': rawMaterials,
      // ไม่แตะ createdAt / imagePath
    });
  }

  // ===== Delete =====
  Future<void> deleteMenu({required String uid, required String docId}) async {
    await _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .doc(docId)
        .delete();
  }

  // ===== Duplicates =====
  Future<bool> existsByName({
    required String uid,
    required String name,
    String? exceptDocId,
  }) async {
    final n = _norm(name);
    final qs = await _fs
        .collection('users')
        .doc(uid)
        .collection('recent_custom')
        .where('name_norm', isEqualTo: n)
        .limit(5)
        .get();

    return qs.docs.any((d) => d.id != exceptDocId);
  }

  Future<bool> _existsInMainDatabase(String name) async {
    final firstPage = await DatabaseSearch.searchMenus('');
    final n = _norm(name);
    return firstPage.any((row) {
      final nm = (row['Thai_Name'] ?? row['Foodname'] ?? row['menu_name'] ?? '').toString();
      return _norm(nm) == n;
    });
  }

  // ===== Upload helper (คืน URL เพื่อไปเก็บใน imagePath) =====
  Future<String> uploadMenuImage({
    required String uid,
    required File file,
    required String targetId, // ไว้คุมชื่อไฟล์ฝั่งคุณได้ ถ้าจำเป็น
  }) async {
    final url = await ApiService.uploadImageAndGetUrl(
      imageFile: file,
      uid: uid,
      bucket: 'custom',
    );
    if (url == null || url.isEmpty) {
      throw Exception('อัปโหลดรูปไม่สำเร็จ');
    }
    return url; // ผู้เรียกควร set ลงฟิลด์ imagePath
  }

  // ===== utils =====
  String _norm(String raw) {
    var s = raw.trim().toLowerCase();
    final thaiMarks = RegExp(r'[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]');
    s = s.replaceAll(thaiMarks, '');
    final symbols = RegExp("[\\s\\.\\-_/(){}\\[\\],;:!@#%^&*+=|\"'`~]");
    s = s.replaceAll(symbols, '');
    return s;
  }

  static num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }
}
