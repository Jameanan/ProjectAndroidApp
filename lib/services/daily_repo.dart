// lib/services/daily_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DailyRepo {
  final String ownerUid;
  DailyRepo({required this.ownerUid});

  final _db = FirebaseFirestore.instance;

  String _dateId(DateTime d) =>
      DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));

  DocumentReference<Map<String, dynamic>> _dailyDoc(DateTime day) {
    return _db
        .collection('users')
        .doc(ownerUid)
        .collection('dailyLogs')
        .doc(_dateId(day));
  }

  Future<Map<String, dynamic>?> getDailyLog({required DateTime day}) async {
    final snap = await _dailyDoc(day).get();
    return snap.data();
  }

  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
  }

  Map<String, double> _nutritionToDoubleMap(Map<String, dynamic> src) {
    return {
      'Calorie': _toD(src['Calorie']),
      'Sugar':   _toD(src['Sugar']),
      'Protein': _toD(src['Protein']),
      'Fat':     _toD(src['Fat']),
      'Fiber':   _toD(src['Fiber']),
      'Carb':    _toD(src['Carb']),
    };
  }

  /// เพิ่มเมนู + อัปเดตรวม
  /// และบันทึก "สาเหตุ" ทุกครั้งที่ค่าหลังเพิ่ม (after) > limit
  Future<void> addMenu({
    required DateTime day,
    required Map<String, dynamic> menu,
    required Map<String, dynamic> nutrition, // Calorie, Sugar, Protein, Fat, Fiber, Carb
    double? calorieLimit,
    double? sugarLimit,
  }) async {
    final n = _nutritionToDoubleMap(nutrition);

    final addCal = n['Calorie']!;
    final addSug = n['Sugar']!;
    final addPro = n['Protein']!;
    final addFat = n['Fat']!;
    final addFib = n['Fiber']!;
    final addCar = n['Carb']!;

    // ✅ FIX รูป: ใช้ URL ก่อน ถ้าไม่มีค่อยใช้ path
    final rawPath = (menu['imagePath'] as String?)?.trim() ?? '';
    final rawUrl  = (menu['imageUrl']  as String?)?.trim() ?? '';
    final storedImage = rawUrl.isNotEmpty ? rawUrl : rawPath;

    final fixedMenu = Map<String, dynamic>.from(menu)
      ..['imagePath'] = storedImage
      ..['imageUrl']  = rawUrl.isNotEmpty ? rawUrl : null;

    final ref = _dailyDoc(day);
    final nowIso = DateTime.now().toIso8601String();

    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);

      // เอกสารยังไม่เคยมีในวันนี้
      if (!snap.exists) {
        final afterEaten = addCal;
        final afterSugar = addSug;

        final List<Map<String, dynamic>> overCalList = [];
        final List<Map<String, dynamic>> overSugList = [];

        Map<String, dynamic>? lastOverCal;
        Map<String, dynamic>? lastOverSug;

        // ✅ บันทึกถ้า "หลังเพิ่ม" เกินลิมิต
        if (calorieLimit != null && afterEaten > calorieLimit) {
          lastOverCal = {
            'at': nowIso,
            'menuName': (fixedMenu['menuName'] ?? '').toString(),
            'calorie': addCal,
            'sugar': addSug,
          };
          overCalList.add(lastOverCal);
        }
        if (sugarLimit != null && afterSugar > sugarLimit) {
          lastOverSug = {
            'at': nowIso,
            'menuName': (fixedMenu['menuName'] ?? '').toString(),
            'calorie': addCal,
            'sugar': addSug,
          };
          overSugList.add(lastOverSug);
        }

        txn.set(ref, {
          'menus': [fixedMenu],
          'summary': {
            'eaten': afterEaten,
            'sugar': afterSugar,
            'protein': addPro,
            'transFat': addFat,
            'fiber': addFib,
            'carb': addCar,
          },
          if (overCalList.isNotEmpty) 'overlimit_calorie': overCalList,
          if (overSugList.isNotEmpty) 'overlimit_sugar': overSugList,
          if (lastOverCal != null) 'last_over_calorie': lastOverCal,
          if (lastOverSug != null) 'last_over_sugar': lastOverSug,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        return;
      }

      // เอกสารมีอยู่แล้ว
      final data = snap.data() ?? {};
      final oldMenus = List<Map<String, dynamic>>.from(
        (data['menus'] ?? const []) as List,
      )..add(fixedMenu);

      final sum = (data['summary'] ?? {}) as Map<String, dynamic>;
      double cur(v) => (v is num) ? v.toDouble() : 0.0;

      final prevEaten = cur(sum['eaten']);
      final prevSugar = cur(sum['sugar']);
      final afterEaten = prevEaten + addCal;
      final afterSugar = prevSugar + addSug;

      final overCalList = List<Map<String, dynamic>>.from(
        ((data['overlimit_calorie'] ?? const []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final overSugList = List<Map<String, dynamic>>.from(
        ((data['overlimit_sugar'] ?? const []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      Map<String, dynamic>? newOverCal;
      Map<String, dynamic>? newOverSug;

      // ✅ บันทึกทุกครั้งที่ "หลังเพิ่ม" เกินลิมิต
      if (calorieLimit != null && afterEaten > calorieLimit) {
        newOverCal = {
          'at': nowIso,
          'menuName': (fixedMenu['menuName'] ?? '').toString(),
          'calorie': addCal,
          'sugar': addSug,
        };
        overCalList.add(newOverCal);
      }
      if (sugarLimit != null && afterSugar > sugarLimit) {
        newOverSug = {
          'at': nowIso,
          'menuName': (fixedMenu['menuName'] ?? '').toString(),
          'calorie': addCal,
          'sugar': addSug,
        };
        overSugList.add(newOverSug);
      }

      final update = <String, dynamic>{
        'menus': oldMenus,
        'summary': {
          'eaten': afterEaten,
          'sugar': afterSugar,
          'protein': cur(sum['protein']) + addPro,
          'transFat': cur(sum['transFat']) + addFat,
          'fiber': cur(sum['fiber']) + addFib,
          'carb': cur(sum['carb']) + addCar,
        },
        'updated_at': nowIso,
      };

      // เก็บลิสต์สะสม และอัปเดต last_* เป็นตัวล่าสุดถ้ามี
      if (newOverCal != null || data['overlimit_calorie'] != null) {
        update['overlimit_calorie'] = overCalList;
      }
      if (newOverSug != null || data['overlimit_sugar'] != null) {
        update['overlimit_sugar'] = overSugList;
      }
      if (newOverCal != null) update['last_over_calorie'] = newOverCal;
      if (newOverSug != null) update['last_over_sugar'] = newOverSug;

      txn.update(ref, update);
    });
  }

  Future<void> setBloodSugarForDay({
    required DateTime day,
    required double value,
    String unit = 'mg/dL',
  }) async {
    final ref = _dailyDoc(day);
    final now = DateTime.now().toIso8601String();

    await ref.set({
      'currentBloodSugarMgdl': value,
      'bloodSugarUnit': unit,
      'updated_at': now,
      'menus': FieldValue.arrayUnion(const []),
      'summary': {
        'eaten': FieldValue.increment(0.0),
        'sugar': FieldValue.increment(0.0),
        'protein': FieldValue.increment(0.0),
        'transFat': FieldValue.increment(0.0),
        'fiber': FieldValue.increment(0.0),
        'carb': FieldValue.increment(0.0),
      },
      'created_at': now,
    }, SetOptions(merge: true));
  }
}
