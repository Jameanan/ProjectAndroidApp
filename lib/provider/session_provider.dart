// lib/provider/session_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===== FIREBASE AUTH / FIRESTORE (ออนไลน์, โหมดล็อกอิน) =====
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldPath;

// ===== DATA MODEL (ใช้ถือข้อมูลในแอพ ไม่ผูก DB โดยตรง) =====
import 'package:main/models/user.dart';

// ===== FIRESTORE REPO (ออนไลน์) =====
import 'package:main/services/daily_repo.dart';

// ===== SQLITE (ออฟไลน์, โหมด guest) =====
import 'package:main/database/dbusers.dart';

class SessionProvider extends ChangeNotifier {
  // ====== สถานะบัญชีผู้ใช้ (ล็อกอินถ้ามี) ======
  String? _ownerUid;                 // ===== FIRESTORE: uid ผู้ใช้ที่ล็อกอิน (null = guest)
  String? _currentUsername;         // ชื่อที่ใช้แสดงผล
  UserModel? _user;                 // โปรไฟล์ของผู้ใช้ (อ่านจาก Firestore เมื่อ login)

  String? get ownerUid => _ownerUid;
  String? get currentUsername => _currentUsername;
  UserModel? get user => _user;
  bool get isLoggedIn => _ownerUid != null && _ownerUid!.isNotEmpty;

  // ===== REPO ต่อ Firestore เฉพาะโหมดล็อกอิน =====
  DailyRepo? _dailyRepo;            // ===== FIRESTORE
  DailyRepo? get dailyRepo => _dailyRepo;

  // ===== โปรไฟล์ listener แบบเรียลไทม์ (เฉพาะ Firestore) =====
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub; // ===== FIRESTORE

  // ===== สถานะ “วันนี้” ที่โชว์บนหน้าหลัก =====
  final List<Map<String, dynamic>> _menus = []; // รายการเมนูวันนี้ (มาจาก Firestore หรือ SQLite)
  List<Map<String, dynamic>> get menus => List.unmodifiable(_menus);

  double _eaten = 0, _sugar = 0, _protein = 0, _transFat = 0, _fiber = 0, _carb = 0;
  double get eaten => _eaten;
  double get sugar => _sugar;
  double get protein => _protein;
  double get transFat => _transFat;
  double get fiber => _fiber;
  double get carb => _carb;

  double? _currentBloodSugarMgdl;
  double? get currentBloodSugarMgdl => _currentBloodSugarMgdl;

  double _bmr = 0;
  double _sugarLimit = 0;
  double get bmr => _bmr;
  double get sugarLimit => _sugarLimit;

  // ===== รีเซ็ตข้อมูลรายวัน (เก็บใน SharedPreferences — local) =====
  String? _lastResetKey;
  String _todayKey([DateTime? now]) {
    final t = now ?? DateTime.now();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
  String _resetPrefKeyForOwner() => 'lastReset_${_ownerUid ?? DBusers.GUEST_USERNAME}';

  // ===== util แปลงค่าเป็น double (ใช้ทั้งสองโหมด) =====
  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
  }

  // ------------------------------------------------------------------
  // Bootstrap
  // ------------------------------------------------------------------
  Future<void> init() async {
    try {
      final fbUser = FirebaseAuth.instance.currentUser; // ===== FIREBASE AUTH

      if (fbUser != null) {
        // ===== FIRESTORE: โหมดล็อกอิน =====
        _ownerUid = fbUser.uid;
        _currentUsername = (fbUser.email ?? '').split('@').first;
        _dailyRepo = DailyRepo(ownerUid: fbUser.uid); // ใช้ repo คุย Firestore

        // โหลดโปรไฟล์จาก Firestore
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(fbUser.uid)
              .get(); // ===== FIRESTORE: read
          final d = doc.data();
          _user = (d != null)
              ? UserModel(
            username: (d['username'] ?? _currentUsername ?? '') as String,
            birthdate: d['birthdate'],
            gender: (d['gender'] as num?)?.toInt() ?? 0,
            diabetes: (d['diabetes'] as num?)?.toInt() ?? 0,
            height: (d['height'] as num?)?.toInt() ?? 0,
            weight: (d['weight'] as num?)?.toInt() ?? 0,
            exerciseLevel: (d['exerciseLevel'] as num?)?.toInt() ?? 0,
          )
              : null;
        } catch (e) {
          _user = null;
          debugPrint('load profile failed: $e');
        }

        _recalcLimits();

        // โหลด “วันนี้” จาก Firestore
        try {
          await _loadTodayFromFirestore(); // ===== FIRESTORE
        } catch (e) {
          debugPrint('load today from Firestore failed: $e');
          _menus.clear();
          _eaten = _sugar = _protein = _transFat = _fiber = _carb = 0;
          _currentBloodSugarMgdl = null;
        }

        // เริ่มฟังโปรไฟล์แบบเรียลไทม์จาก Firestore
        _startProfileListener(); // ===== FIRESTORE
      } else {
        // ===== SQLITE: โหมด guest (ออฟไลน์) =====
        _ownerUid = null;
        _currentUsername = DBusers.GUEST_USERNAME;
        _dailyRepo = null;  // ไม่ใช้ Firestore
        _user = null;
        _bmr = 0;
        _sugarLimit = 0;

        // โหลด “วันนี้” จาก SQLite
        await _loadTodayFromSqlite(); // ===== SQLITE

        // ปิด listener เผื่อค้างจากตอนล็อกอิน
        _stopProfileListener(); // ===== FIRESTORE (ปิด)
      }

      // อ่านคีย์รีเซ็ตวันล่าสุดจาก local
      final prefs = await SharedPreferences.getInstance();
      _lastResetKey = prefs.getString(_resetPrefKeyForOwner());

      await checkAndResetDaily();
    } catch (e) {
      debugPrint('SessionProvider.init() fatal: $e');
    } finally {
      notifyListeners();
    }
  }

  // ให้หน้าอื่นเรียกโหลด “วันนี้” ได้ (สลับตามโหมด)
  Future<void> loadTodayFromBackend() async {
    try {
      if (isLoggedIn) {
        await _loadTodayFromFirestore(); // ===== FIRESTORE
      } else {
        await _loadTodayFromSqlite();    // ===== SQLITE
      }
    } catch (e) {
      debugPrint('loadTodayFromBackend error: $e');
    } finally {
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // Load today
  // ------------------------------------------------------------------

  // ===== FIRESTORE: โหลด “วันนี้” จาก Firestore =====
  Future<void> _loadTodayFromFirestore() async {
    if (_dailyRepo == null) return;
    final data = await _dailyRepo!.getDailyLog(day: DateTime.now()); // read doc

    final menusList = (data?['menus'] is List) ? (data?['menus'] as List) : const [];
    _menus
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(
          menusList.map((e) => Map<String, dynamic>.from(e as Map)).toList()));

    final sumMap =
    (data?['summary'] is Map) ? Map<String, dynamic>.from(data?['summary'] as Map) : const {};
    if (sumMap.isNotEmpty) {
      _eaten = _toD(sumMap['eaten']);
      _sugar = _toD(sumMap['sugar']);
      _protein = _toD(sumMap['protein']);
      _transFat = _toD(sumMap['transFat']);
      _fiber = _toD(sumMap['fiber']);
      _carb = _toD(sumMap['carb']);
    } else {
      _recalcTotals();
    }

    final sVal = data?['currentBloodSugarMgdl'];
    _currentBloodSugarMgdl = (sVal is num) ? sVal.toDouble() : null;
  }

  // ===== SQLITE: โหลด “วันนี้” จาก SQLite =====
  Future<void> _loadTodayFromSqlite() async {
    final today = DateTime.now();
    final rows = await DBusers.instance.getLogsByDate(day: today); // ===== SQLITE: query

    _menus.clear();
    _eaten = _sugar = _protein = _transFat = _fiber = _carb = 0;

    for (final row in rows) {
      final withSugar = (row['with_sugar'] == 1);
      final nutrition = {
        'Calorie': (row['calorie'] as num?)?.toDouble() ?? 0,
        'Sugar': (row['sugar'] as num?)?.toDouble() ?? 0,
        'Protein': (row['protein'] as num?)?.toDouble() ?? 0,
        'Fat': (row['fat'] as num?)?.toDouble() ?? 0,
        'Fiber': (row['fiber'] as num?)?.toDouble() ?? 0,
        'Carb': (row['carb'] as num?)?.toDouble() ?? 0,
      };
      _menus.add({
        'menuName': (row['menu_name'] ?? '') as String,
        'imagePath': row['image_path'] as String?,
        'menuData': {
          'nutrition_data': {
            'sugar_nutrition': nutrition,
            'nosugar_nutrition': nutrition,
          }
        },
        'useNoSugar': !withSugar,
      });

      _eaten += nutrition['Calorie'] as double;
      _sugar += nutrition['Sugar'] as double;
      _protein += nutrition['Protein'] as double;
      _transFat += nutrition['Fat'] as double;
      _fiber += nutrition['Fiber'] as double;
      _carb += nutrition['Carb'] as double;
    }

    final bsRow = await DBusers.instance.getDailyBloodSugar(day: today); // ===== SQLITE
    _currentBloodSugarMgdl = (bsRow != null) ? (bsRow['value'] as num).toDouble() : null;
  }

  // ------------------------------------------------------------------
  // Daily reset (only once per day)
  // ------------------------------------------------------------------
  Future<void> checkAndResetDaily() async {
    final today = _todayKey();
    if (_lastResetKey == today) return;

    _menus.clear();
    _eaten = _sugar = _protein = _transFat = _fiber = _carb = 0;
    _currentBloodSugarMgdl = null;

    _lastResetKey = today;
    final prefs = await SharedPreferences.getInstance(); // local
    await prefs.setString(_resetPrefKeyForOwner(), today);

    try {
      if (isLoggedIn) {
        await _loadTodayFromFirestore(); // ===== FIRESTORE
      } else {
        await _loadTodayFromSqlite();    // ===== SQLITE
      }
    } catch (e) {
      debugPrint('checkAndResetDaily reload error: $e');
    }

    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Actions (today)
  // ------------------------------------------------------------------
  Future<void> addMenu(
      Map<String, dynamic> menu, {
        required String nutritionKey,
        DateTime? at,
      }) async {
    final day = at ?? DateTime.now();

    // อัปเดต state ในแอพ (เหมือนกันทั้งสองโหมด)
    _menus.add(menu);
    final g = ((menu['menuData']?['nutrition_data'] ?? {}) as Map)[nutritionKey] ?? {};
    _eaten += _toD(g['Calorie']);
    _sugar += _toD(g['Sugar']);
    _protein += _toD(g['Protein']);
    _transFat += _toD(g['Fat']);
    _fiber += _toD(g['Fiber']);
    _carb += _toD(g['Carb']);
    notifyListeners();

    // ===== FIRESTORE: บันทึกเข้า dailyLogs เมื่อ login =====
    if (isLoggedIn && _dailyRepo != null) {
      try {
        await _dailyRepo!.addMenu(
          day: day,
          menu: menu,
          nutrition: {
            'Calorie': _toD(g['Calorie']),
            'Sugar': _toD(g['Sugar']),
            'Protein': _toD(g['Protein']),
            'Fat': _toD(g['Fat']),
            'Fiber': _toD(g['Fiber']),
            'Carb': _toD(g['Carb']),
          },
          calorieLimit: _bmr,
          sugarLimit: _sugarLimit,
        );
      } catch (e) {
        debugPrint('addMenu Firestore failed: $e');
      }
    }
    // หมายเหตุ: โหมด guest จะบันทึก SQLite ตอนเพิ่มผ่านหน้า/บริการ guest (ไฟล์อื่น)
  }

  // อัปเดตค่าน้ำตาล “เฉพาะใน state” (ใช้ทันที)
  Future<void> setBloodSugar({required double value, String unit = 'mg/dL'}) async {
    _currentBloodSugarMgdl = value;
    notifyListeners();
  }

  void clearBloodSugar() {
    _currentBloodSugarMgdl = null;
    notifyListeners();
  }

  // เซฟค่ารายวันลง backend ตามโหมด
  Future<void> setBloodSugarForDay({
    required DateTime day,
    required double value,
    String unit = 'mg/dL',
    String? username,
  }) async {
    final mgdl = value;

    if (isLoggedIn && _dailyRepo != null) {
      // ===== FIRESTORE =====
      try {
        await _dailyRepo!.setBloodSugarForDay(day: day, value: mgdl, unit: 'mg/dL');
      } catch (e) {
        debugPrint('setBloodSugarForDay Firestore failed: $e');
      }
    } else {
      // ===== SQLITE =====
      await DBusers.instance.upsertDailyBloodSugar(
        value: mgdl,
        unit: 'mg/dL',
        at: DateTime(day.year, day.month, day.day),
      );
    }

    // ถ้าเป็น “วันนี้” อัปเดต state ให้ UI เห็นทันที
    final now = DateTime.now();
    if (day.year == now.year && day.month == now.month && day.day == now.day) {
      _currentBloodSugarMgdl = mgdl;
      notifyListeners();
    }
  }

  /// ดึงค่าน้ำตาลของวัน [day] จาก backend แล้วอัปเดต state ถ้าเป็น "วันนี้"
  Future<double?> refreshBloodSugarForDay(DateTime day) async {
    double? found;

    if (isLoggedIn) {
      // ===== FIRESTORE: อ่านจาก dailyLogs/{YYYY-MM-DD} =====
      try {
        final id = _ymd(day);
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_ownerUid!)
            .collection('dailyLogs')
            .doc(id)
            .get();
        final data = doc.data();
        if (data != null) {
          final sVal = data['currentBloodSugarMgdl'];
          if (sVal is num) found = sVal.toDouble();
        }
      } catch (e) {
        debugPrint('refreshBloodSugarForDay Firestore failed: $e');
      }
    } else {
      // ===== SQLITE: อ่านจากตาราง daily_blood_sugar =====
      final row = await DBusers.instance.getDailyBloodSugar(day: day);
      if (row != null) {
        found = (row['value'] as num).toDouble();
      }
    }

    // ถ้าเป็น “วันนี้” อัปเดต state
    final now = DateTime.now();
    if (day.year == now.year && day.month == now.month && day.day == now.day) {
      _currentBloodSugarMgdl = found;
      notifyListeners();
    }
    return found;
  }

  // ------------------------------------------------------------------
  // Profile & limits (คำนวณในแอพ ไม่ผูก DB)
  // ------------------------------------------------------------------
  void _recalcLimits() {
    if (_user == null) {
      _bmr = 0;
      _sugarLimit = 0;
      return;
    }
    final u = _user!;
    final age = _ageFromUser(u);

    // Mifflin–St Jeor
    double base;
    if (u.gender == 0) {
      base = (u.weight * 10) + (u.height * 6.25) - (age * 5) + 5;
    } else {
      base = (u.weight * 10) + (u.height * 6.25) - (age * 5) - 161;
    }
    _bmr = base * _activityFactor(u.exerciseLevel);

    // ตั้งลิมิตน้ำตาลตามอายุ/ภาวะ
    if (u.diabetes == 1) {
      _sugarLimit = 10.0;
    } else if (age >= 6 && age <= 13) {
      _sugarLimit = 16.0;
    } else if (age >= 14 && age <= 25) {
      _sugarLimit = 24.0;
    } else if (age >= 26 && age <= 60) {
      _sugarLimit = (u.exerciseLevel >= 3) ? 32.0 : 16.0;
    } else {
      _sugarLimit = 16.0;
    }
  }

  int _ageFromUser(UserModel u) {
    final dobStr = u.birthdate;
    if (dobStr != null && dobStr.isNotEmpty) {
      final p = dobStr.split('-');
      if (p.length == 3) {
        final y = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        final d = int.tryParse(p[2]);
        if (y != null && m != null && d != null) {
          return _calcAge(DateTime(y, m, d));
        }
      }
    }
    return 25;
  }

  int _calcAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthday =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age--;
    return age < 0 ? 0 : age;
  }

  double _activityFactor(int level) {
    if (level <= 0) return 1.2;
    if (level == 1) return 1.375;
    if (level == 2) return 1.55;
    if (level == 3) return 1.725;
    if (level >= 4) return 1.9;
    return 1.2;
  }

  void _recalcTotals() {
    _eaten = 0;
    _sugar = 0;
    _protein = 0;
    _transFat = 0;
    _fiber = 0;
    _carb = 0;

    for (final m in _menus) {
      final nd = (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
      final key = (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
      final g = (nd[key] ?? {}) as Map<String, dynamic>;
      _eaten += _toD(g['Calorie']);
      _sugar += _toD(g['Sugar']);
      _protein += _toD(g['Protein']);
      _transFat += _toD(g['Fat']);
      _fiber += _toD(g['Fiber']);
      _carb += _toD(g['Carb']);
    }
  }

  // ------------------------------------------------------------------
  // สรุปช่วงวันสำหรับกราฟ
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getRangeTotals(DateTime start, DateTime end) async {
    final List<Map<String, dynamic>> out = [];
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    if (isLoggedIn) {
      // ===== FIRESTORE: ดึงช่วงวันจากคอลเลกชัน dailyLogs =====
      final uid = _ownerUid!;
      final startId = _ymd(s);
      final endId = _ymd(e);

      final qs = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyLogs')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startId)
          .where(FieldPath.documentId, isLessThanOrEqualTo: endId)
          .get();

      final byId = <String, Map<String, dynamic>>{};
      for (final doc in qs.docs) {
        final data = doc.data();
        final id = doc.id; // YYYY-MM-DD
        final sum = (data['summary'] ?? {}) as Map<String, dynamic>;
        double cal = 0, sugar = 0, protein = 0, fat = 0, fiber = 0, carb = 0;
        if (sum.isNotEmpty) {
          cal = _toD(sum['eaten']);
          sugar = _toD(sum['sugar']);
          protein = _toD(sum['protein']);
          fat = _toD(sum['transFat']);
          fiber = _toD(sum['fiber']);
          carb = _toD(sum['carb']);
        } else {
          final menus =
          List<Map<String, dynamic>>.from((data['menus'] ?? []) as List? ?? const []);
          for (final m in menus) {
            final nd = (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
            final k = (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
            final g = (nd[k] ?? {}) as Map<String, dynamic>? ?? {};
            cal += _toD(g['Calorie']);
            sugar += _toD(g['Sugar']);
            protein += _toD(g['Protein']);
            fat += _toD(g['Fat']);
            fiber += _toD(g['Fiber']);
            carb += _toD(g['Carb']);
          }
        }
        byId[id] = {
          'date': id,
          'cal': cal,
          'sugar': sugar,
          'protein': protein,
          'fat': fat,
          'fiber': fiber,
          'carb': carb,
        };
      }

      DateTime d = s;
      while (!d.isAfter(e)) {
        final id = _ymd(d);
        final row = byId[id] ??
            {
              'date': id,
              'cal': 0.0,
              'sugar': 0.0,
              'protein': 0.0,
              'fat': 0.0,
              'fiber': 0.0,
              'carb': 0.0,
            };
        out.add({
          'date': row['date'],
          'cal': (row['cal'] as num).toDouble(),
          'sugar': (row['sugar'] as num).toDouble(),
          'protein': (row['protein'] as num).toDouble(),
          'fat': (row['fat'] as num).toDouble(),
          'fiber': (row['fiber'] as num).toDouble(),
          'carb': (row['carb'] as num).toDouble(),
        });
        d = d.add(const Duration(days: 1));
      }
    } else {
      // ===== SQLITE: คิวรีจาก DB โลคอลตามวัน =====
      DateTime d = s;
      while (!d.isAfter(e)) {
        final totals = await DBusers.instance.getDailyTotals(day: d); // SQLite
        out.add({
          'date': _ymd(d),
          'cal': (totals['cal'] ?? 0.0).toDouble(),
          'sugar': (totals['sugar'] ?? 0.0).toDouble(),
          'protein': (totals['protein'] ?? 0.0).toDouble(),
          'fat': (totals['fat'] ?? 0.0).toDouble(),
          'fiber': (totals['fiber'] ?? 0.0).toDouble(),
          'carb': (totals['carb'] ?? 0.0).toDouble(),
        });
        d = d.add(const Duration(days: 1));
      }
    }
    return out;
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------------
  // Switch mode helpers
  // ------------------------------------------------------------------

  // ===== SQLITE: เข้าสู่โหมด guest (ปิด Firestore listener และโหลดข้อมูลจาก SQLite) =====
  Future<void> enterGuestMode() async {
    _stopProfileListener(); // ===== FIRESTORE: ปิด listener

    _ownerUid = null;
    _currentUsername = DBusers.GUEST_USERNAME;
    _dailyRepo = null;
    _user = null;
    _bmr = 0;
    _sugarLimit = 0;

    await _loadTodayFromSqlite(); // ===== SQLITE

    final prefs = await SharedPreferences.getInstance();
    _lastResetKey = prefs.getString(_resetPrefKeyForOwner());
    await checkAndResetDaily();
    notifyListeners();
  }

  // ===== FIRESTORE: เข้าสู่โหมดผู้ใช้ (ล็อกอิน) =====
  Future<void> enterUserMode(String uid, String username) async {
    _ownerUid = uid;
    _currentUsername = username;
    _dailyRepo = DailyRepo(ownerUid: uid); // Firestore

    // โหลดโปรไฟล์จาก Firestore
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get(); // read
      final d = doc.data();
      _user = (d != null)
          ? UserModel(
        username: (d['username'] ?? username) as String,
        birthdate: d['birthdate'],
        gender: (d['gender'] as num?)?.toInt() ?? 0,
        diabetes: (d['diabetes'] as num?)?.toInt() ?? 0,
        height: (d['height'] as num?)?.toInt() ?? 0,
        weight: (d['weight'] as num?)?.toInt() ?? 0,
        exerciseLevel: (d['exerciseLevel'] as num?)?.toInt() ?? 0,
      )
          : null;
    } catch (_) {
      _user = null;
    }
    _recalcLimits();

    // โหลด “วันนี้” จาก Firestore
    try {
      await _loadTodayFromFirestore(); // ===== FIRESTORE
    } catch (e) {
      debugPrint('enterUserMode loadToday failed: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    _lastResetKey = prefs.getString(_resetPrefKeyForOwner());
    await checkAndResetDaily();

    // เริ่มฟังโปรไฟล์เรียลไทม์จาก Firestore
    _startProfileListener(); // ===== FIRESTORE

    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut(); // ===== FIREBASE AUTH
    } catch (_) {}
    await enterGuestMode(); // สลับไปโหมด SQLITE
  }

  // ====== LISTENER helpers (Firestore only) ======
  void _startProfileListener() {
    _stopProfileListener();
    if (!isLoggedIn) return;

    final uid = _ownerUid!;
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()               // ===== FIRESTORE realtime
        .listen((snap) {
      final d = snap.data();
      if (d == null) return;

      _user = UserModel(
        username: (d['username'] ?? _currentUsername ?? '') as String,
        birthdate: d['birthdate'],
        gender: (d['gender'] as num?)?.toInt() ?? 0,
        diabetes: (d['diabetes'] as num?)?.toInt() ?? 0,
        height: (d['height'] as num?)?.toInt() ?? 0,
        weight: (d['weight'] as num?)?.toInt() ?? 0,
        exerciseLevel: (d['exerciseLevel'] as num?)?.toInt() ?? 0,
      );

      _recalcLimits();
      notifyListeners(); // อัปเดต UI ทันที
    });
  }

  void _stopProfileListener() {
    _profileSub?.cancel();
    _profileSub = null;
  }

  @override
  void dispose() {
    _stopProfileListener();
    super.dispose();
  }
}
