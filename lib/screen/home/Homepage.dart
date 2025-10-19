// lib/screen/home/Homepage.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:main/provider/session_provider.dart';
import 'package:main/database/dbusers.dart';

import 'package:main/services/api_service.dart';
import 'package:main/screen/food_result.dart';
import 'package:main/screen/search/Searchpage.dart';
import 'package:main/screen/Option/Setting_page.dart';
import 'package:main/screen/health/bloodsugar.dart';
import 'package:main/screen/home/Weekpage.dart';
import 'package:main/screen/home/Monthpage.dart';

// ใช้ตัวช่วยตรวจเกินค่า + หน้าแสดงสาเหตุ
import 'package:main/shared/overlimit_kind.dart';
import 'package:main/screen/overlimit_cause_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String currentTab = 'วัน';
  int bottomNavIndex = 0;

  // ====== วันที่ที่เลือก (โหมดรายวัน) ======
  DateTime _selectedDate = _dateOnly(DateTime.now());
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _thaiDate(DateTime d) => DateFormat('d MMM yyyy', 'th').format(d);

  // ====== ค่าน้ำตาลในเลือด (วันละ 1 ค่า) ======
  bool _hasDailyBlood = false;
  double? _dailyBloodValue;

  // ====== snapshot สำหรับ "วันย้อนหลัง" ======
  List<Map<String, dynamic>> _viewMenus = [];
  double _viewEaten = 0;
  double _viewSugar = 0;
  double _viewProtein = 0;
  double _viewTransFat = 0;
  double _viewFiber = 0;
  double _viewCarb = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<SessionProvider>();
      await session.checkAndResetDaily();      // รีเซ็ตเฉพาะเมื่อเปลี่ยนวัน
      await session.loadTodayFromBackend();    // ดึง “วันนี้” กลับเข้ามา

      await _loadDataFor(_selectedDate);       // สำหรับดูย้อนหลัง
      await _loadDailyBlood();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = context.read<SessionProvider>();
      session.checkAndResetDaily().then((_) async {
        await _loadDataFor(_selectedDate);
        await _loadDailyBlood();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------- เปลี่ยนวัน ----------
  void _goPrevDay() async {
    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
    await _loadDataFor(_selectedDate);
    await _loadDailyBlood();
  }

  void _goNextDay() async {
    final today = _dateOnly(DateTime.now());
    if (_selectedDate.isBefore(today)) {
      setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
      await _loadDataFor(_selectedDate);
      await _loadDailyBlood();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(1900, 1, 1),
      lastDate: _dateOnly(now),
      helpText: 'เลือกวัน',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
    );
    if (picked != null) {
      setState(() => _selectedDate = _dateOnly(picked));
      await _loadDataFor(_selectedDate);
      await _loadDailyBlood();
    }
  }

  // ---------- Firebase helpers ----------
  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;
  String? _activeUid() => FirebaseAuth.instance.currentUser?.uid;

  String _dateId(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DocumentReference<Map<String, dynamic>> _dailyDoc(String uid, DateTime day) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyLogs')
        .doc(_dateId(day));
  }

  // ---------- โหลดอาหารของ "วันที่เลือก" ----------
  Future<void> _loadDataFor(DateTime day) async {
    // เคลียร์ snapshot ก่อน
    _viewMenus = [];
    _viewEaten = _viewSugar = _viewProtein = _viewTransFat = _viewFiber = _viewCarb = 0;

    if (_isToday(day)) {
      // วันนี้: ใช้ state จาก SessionProvider โดยตรง
      if (mounted) setState(() {});
      return;
    }

    if (_isLoggedIn) {
      // ล็อกอิน → อ่านจาก Firestore
      final uid = _activeUid()!;
      final doc = await _dailyDoc(uid, day).get();
      final data = doc.data();

      if (data != null && data.isNotEmpty) {
        _viewMenus = List<Map<String, dynamic>>.from((data['menus'] ?? []) as List);

        final sum = (data['summary'] ?? {}) as Map<String, dynamic>;
        double _d(v) {
          if (v == null) return 0.0;
          if (v is num) return v.toDouble();
          final s = v.toString();
          final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
          return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
        }

        if (sum.isNotEmpty) {
          _viewEaten    = _d(sum['eaten']);
          _viewSugar    = _d(sum['sugar']);
          _viewProtein  = _d(sum['protein']);
          _viewTransFat = _d(sum['transFat']);
          _viewFiber    = _d(sum['fiber']);
          _viewCarb     = _d(sum['carb']);
        } else {
          // ไม่มี summary → สรุปจากเมนู
          for (final m in _viewMenus) {
            final nd = (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
            final k  = (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
            final g  = (nd[k] ?? {}) as Map<String, dynamic>;
            _viewEaten    += _toD(g['Calorie']);
            _viewSugar    += _toD(g['Sugar']);
            _viewProtein  += _toD(g['Protein']);
            _viewTransFat += _toD(g['Fat']);
            _viewFiber    += _toD(g['Fiber']);
            _viewCarb     += _toD(g['Carb']);
          }
        }
      }
    } else {
      // Guest → SQLite
      final rows = await DBusers.instance.getLogsByDate(day: day);
      if (rows.isNotEmpty) {
        for (final row in rows) {
          final withSugar = (row['with_sugar'] == 1);
          final nutrition = {
            'Calorie': (row['calorie'] as num?)?.toDouble() ?? 0,
            'Sugar':   (row['sugar']   as num?)?.toDouble() ?? 0,
            'Protein': (row['protein'] as num?)?.toDouble() ?? 0,
            'Fat':     (row['fat']     as num?)?.toDouble() ?? 0,
            'Fiber':   (row['fiber']   as num?)?.toDouble() ?? 0,
            'Carb':    (row['carb']    as num?)?.toDouble() ?? 0,
          };
          _viewMenus.add({
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

          _viewEaten    += nutrition['Calorie'] as double;
          _viewSugar    += nutrition['Sugar']   as double;
          _viewProtein  += nutrition['Protein'] as double;
          _viewTransFat += nutrition['Fat']     as double;
          _viewFiber    += nutrition['Fiber']   as double;
          _viewCarb     += nutrition['Carb']    as double;
        }
      }
    }

    if (mounted) setState(() {});
  }

  // ---------- โหลดค่าน้ำตาลในเลือดของวัน ----------
  Future<void> _loadDailyBlood() async {
    double? found;

    if (_isLoggedIn) {
      final uid = _activeUid()!;
      final doc = await _dailyDoc(uid, _selectedDate).get();
      final data = doc.data();
      if (data != null) {
        final sVal = data['currentBloodSugarMgdl'];
        if (sVal is num) found = sVal.toDouble();
      }
    } else {
      final row = await DBusers.instance.getDailyBloodSugar(day: _selectedDate);
      if (row != null) {
        found = (row['value'] as num).toDouble();
      }
    }

    setState(() {
      _hasDailyBlood = found != null;
      _dailyBloodValue = found;
    });

    // อัปเดตเข้า SessionProvider เมื่อเป็น "วันนี้"
    if (_isToday(_selectedDate)) {
      final session = context.read<SessionProvider>();
      if (found != null) {
        await session.setBloodSugar(value: found, unit: 'mg/dL');
      } else {
        session.clearBloodSugar();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTodaySelected = _isToday(_selectedDate);

    // เลือกคอนเทนต์ตามแท็บ
    Widget tabContent;
    if (currentTab == 'สัปดาห์') {
      tabContent = const WeekPage();
    } else if (currentTab == 'เดือน') {
      tabContent = const MonthPage();
    } else {
      tabContent = isTodaySelected
          ? _buildTodayContent(context)
          : _buildOtherDayContent(context);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('หน้าหลัก'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: _bottomNav(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topTabs(context, currentTab),
            Expanded(child: tabContent),
          ],
        ),
      ),
    );
  }

  // ====== เนื้อหา "วันนี้" (ดึงจาก SessionProvider ตรง ๆ) ======
  Widget _buildTodayContent(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        final addedMenus = session.menus;

        return _dayScaffold(
          menus: addedMenus,
          kcal: session.eaten,
          sugar: session.sugar,
          protein: session.protein,
          fat: session.transFat,
          fiber: session.fiber,
          carb: session.carb,
          isLoggedIn: _isLoggedIn,
          bmr: session.bmr,
          sugarLimit: session.sugarLimit,
        );
      },
    );
  }

  // ====== เนื้อหา "วันย้อนหลัง" (ใช้ snapshot) ======
  Widget _buildOtherDayContent(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return _dayScaffold(
      menus: _viewMenus,
      kcal: _viewEaten,
      sugar: _viewSugar,
      protein: _viewProtein,
      fat: _viewTransFat,
      fiber: _viewFiber,
      carb: _viewCarb,
      isLoggedIn: _isLoggedIn,
      bmr: session.bmr,
      sugarLimit: session.sugarLimit,
    );
  }

  // ====== โครง UI ร่วม ======
  Widget _dayScaffold({
    required List<Map<String, dynamic>> menus,
    required double kcal,
    required double sugar,
    required double protein,
    required double fat,
    required double fiber,
    required double carb,
    required bool isLoggedIn,
    required double bmr,
    required double sugarLimit,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // แถบเลือกวัน
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'ย้อนหลังหนึ่งวัน',
                  onPressed: _goPrevDay,
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _pickDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _thaiDate(_selectedDate),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _isToday(_selectedDate) ? 'เป็นวันปัจจุบันแล้ว' : 'ถัดไปหนึ่งวัน',
                  onPressed: _isToday(_selectedDate) ? null : _goNextDay,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),

          _infoBox(
            isLoggedIn: isLoggedIn,
            bmr: bmr,
            eaten: kcal,
            sugar: sugar,
            sugarLimit: sugarLimit,
          ),
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.only(left: 20, top: 10),
            child: Text(
              'รายการอาหารของคุณ ${_isToday(_selectedDate) ? "วันนี้" : _thaiDate(_selectedDate)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 190,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: menus.isEmpty
                  ? _noFoodBox(context)
                  : ListView.builder(
                itemCount: menus.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final menu = menus[index];
                  final useNoSugar = menu['useNoSugar'] == true;
                  final nutritionData =
                  (menu['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
                  final nutritionGroup =
                      (useNoSugar
                          ? nutritionData['nosugar_nutrition']
                          : nutritionData['sugar_nutrition'])
                      as Map<String, dynamic>? ??
                          {};

                  final calorieText = _fmtCalorie(nutritionGroup['Calorie']);
                  final sugarText = _fmtSugar(nutritionGroup['Sugar']);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildMenuImage(menu['imagePath']),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  menu['menuName'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      // Calorie pill
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[100],
                                          borderRadius: BorderRadius.circular(30),
                                        ),
                                        child: Row(
                                          children: [
                                            Image.asset(
                                              'assets/icon/fire.png',
                                              width: 15,
                                              height: 15,
                                              fit: BoxFit.contain,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              calorieText,
                                              style: TextStyle(
                                                color: Colors.orange[800],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Sugar pill
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[100],
                                          borderRadius: BorderRadius.circular(30),
                                        ),
                                        child: Row(
                                          children: [
                                            Image.asset(
                                              'assets/icon/sugar-cube.png',
                                              width: 15,
                                              height: 15,
                                              fit: BoxFit.contain,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              sugarText,
                                              style: TextStyle(
                                                color: Colors.blue[800],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          _addButton(context),
        ],
      ),
    );
  }

  // ====== UI helpers ======
  Widget _buildMenuImage(String? imagePath) {
    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.startsWith('http')) {
        // ถ้าเป็น URL (เช่นจาก FastAPI/Cloud)
        return Image.network(
          imagePath,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Image.asset(
              'assets/icon/spoon.jpg',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            );
          },
        );
      } else if (imagePath.startsWith('/')) {
        // ถ้าเป็น local path
        final file = File(imagePath);
        return Image.file(
          file,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Image.asset(
              'assets/icon/spoon.jpg',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            );
          },
        );
      }
    }
    return Image.asset(
      'assets/icon/spoon.jpg',
      width: 60,
      height: 60,
      fit: BoxFit.cover,
    );
  }

  // ====== กล่องข้อมูล (ซ่อน /0 และ /0.0 เมื่อไม่มี limit) ======
  Widget _infoBox({
    required bool isLoggedIn,
    required double bmr,
    required double eaten,
    required double sugar,
    required double sugarLimit,
  }) {
    final session = context.watch<SessionProvider>();

    // วันนี้อ่านจาก Provider; ย้อนหลังใช้ snapshot
    final blood = _isToday(_selectedDate)
        ? session.currentBloodSugarMgdl
        : _dailyBloodValue;

    // แสดง /limit เฉพาะเมื่อ "ล็อกอิน" และ "limit > 0"
    final showCalLimit   = isLoggedIn && bmr > 0;
    final showSugarLimit = isLoggedIn && sugarLimit > 0;

    // ไม่คำนวณ over-limit เมื่อไม่มี limit
    final over = (isLoggedIn)
        ? OverlimitResult.evaluate(
      calories: eaten,
      caloriesLimit: showCalLimit ? bmr : double.infinity,
      sugar: sugar,
      sugarLimit: showSugarLimit ? sugarLimit : double.infinity,
    )
        : const OverlimitResult(
        kind: OverlimitKinds.none, overCalories: 0, overSugar: 0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // กล่องใหญ่ซ้าย
            Expanded(
              flex: 11,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9FAFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text('ข้อมูล',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    ),
                    const SizedBox(height: 10),

                    // พลังงาน
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image.asset('assets/icon/fire.png', width: 24, height: 24),
                            const SizedBox(height: 4),
                            const Text('พลังงาน',
                                style: TextStyle(fontSize: 12, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _metricValueText(
                            value: eaten,
                            limit: bmr,
                            unitShort: 'แคล.',
                            showLimit: showCalLimit,
                            align: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // น้ำตาล
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image.asset('assets/icon/sugar-cube.png', width: 24, height: 24),
                            const SizedBox(height: 4),
                            const Text('น้ำตาล',
                                style: TextStyle(fontSize: 12, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _metricValueText(
                            value: sugar,
                            limit: sugarLimit,
                            unitShort: 'ก.',
                            showLimit: showSugarLimit,
                            align: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // น้ำตาลในเลือด
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image.asset('assets/icon/sugar-blood-level.png', width: 24, height: 24),
                            const SizedBox(height: 4),
                            const Text(
                              'น้ำตาล\nในเลือด',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.black),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            blood == null ? '0 มก/ดล.' : '${blood.toStringAsFixed(1)} มก/ดล.',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ปุ่ม
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoggedIn && over.hasAny) ...[
                          _pillButton(
                            label: 'ดูสาเหตุ',
                            color: Colors.red,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OverlimitCausePage(day: _selectedDate),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                        ],
                        _pillButtonWithAssetIcon(
                          label: _hasDailyBlood ? 'แก้ไข' : 'เพิ่ม',
                          color: const Color(0xFF6EA8FE),
                          assetPath: 'assets/icon/sugar-blood-level.png',
                          onPressed: _isToday(_selectedDate)
                              ? () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BloodSugarPage(
                                  initialValue: _dailyBloodValue,
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (!mounted) return;

                            if (result == true) {
                              final sp = context.read<SessionProvider>();
                              if (_isLoggedIn) {
                                // login → รีเฟรชจาก Firestore
                                await sp.refreshBloodSugarForDay(_selectedDate);
                              }
                              // ทั้ง guest/login → โหลดค่าของวันที่เลือกใหม่ เพื่ออัปเดต UI
                              await _loadDailyBlood();
                            }
                          }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // คอลัมน์สรุปด้านขวา (โปรตีน/ไขมัน/ไฟเบอร์/คาร์บ)
            Expanded(
              flex: 6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sideInfoTile('assets/icon/proteins.png',
                      '${_isToday(_selectedDate) ? context.watch<SessionProvider>().protein.toStringAsFixed(1) : _viewProtein.toStringAsFixed(1)} ก.',
                      'โปรตีน', const Color(0xFFFFE9D8)),
                  _sideInfoTile('assets/icon/trans-fat.png',
                      '${_isToday(_selectedDate) ? context.watch<SessionProvider>().transFat.toStringAsFixed(1) : _viewTransFat.toStringAsFixed(1)} ก.',
                      'ไขมัน', const Color(0xFFFFE1DD)),
                  _sideInfoTile('assets/icon/fiber.png',
                      '${_isToday(_selectedDate) ? context.watch<SessionProvider>().fiber.toStringAsFixed(1) : _viewFiber.toStringAsFixed(1)} ก.',
                      'ไฟเบอร์', const Color(0xFFE3F9E5)),
                  _sideInfoTile('assets/icon/carb.png',
                      '${_isToday(_selectedDate) ? context.watch<SessionProvider>().carb.toStringAsFixed(1) : _viewCarb.toStringAsFixed(1)} ก.',
                      'คาร์บ', const Color(0xFFECE7FF)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// คืนข้อความค่าพร้อมสีของ “ตัวตั้ง” ตามเกณฑ์:
  /// ปกติ=ดำ, >=80% ของลิมิต=เหลือง, เกินลิมิต=แดง
  Widget _metricValueText({
    required double value,
    required double limit,
    required String unitShort,      // 'แคล.' หรือ 'ก.'
    required bool showLimit,        // มีลิมิตให้เทียบไหม
    TextAlign align = TextAlign.right,
  }) {
    if (!showLimit) {
      // ไม่มีลิมิต → แสดงค่าปกติ (สีดำ)
      return Text(
        '${value.toStringAsFixed(value >= 100 ? 0 : 1)} $unitShort',
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      );
    }

    final Color numColor = _levelColor(value, limit);
    final String left = value.toStringAsFixed(value >= 100 ? 0 : 1);
    final String right = ' / ${limit.toInt()} $unitShort';

    return RichText(
      textAlign: align,
      maxLines: 1,
      text: TextSpan(
        children: [
          TextSpan(
            text: left,
            style: TextStyle(
              color: numColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: right,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(double value, double limit) {
    if (limit <= 0) return Colors.black;
    if (value > limit) return Colors.red;
    final ratio = value / limit;
    if (ratio >= 0.80) return Colors.amber[800]!;
    return Colors.black;
    // ถ้าอยากปรับ threshold เป็น 75% ก็เปลี่ยน 0.80 -> 0.75 ได้เลย
  }

  Widget _sideInfoTile(String imagePath, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(imagePath, width: 24, height: 24),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noFoodBox(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: screenWidth,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant, size: 40, color: Colors.grey),
              SizedBox(height: 10),
              Text('ยังไม่ได้บันทึกรายการอาหาร'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final isTodaySelected = _isToday(_selectedDate);
    final canUse = sp.isLoggedIn && isTodaySelected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!sp.isLoggedIn) ...[
            const Text(
              'จำเป็นต้องเข้าสู่ระบบก่อน',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canUse ? _showPickOptionsDialog : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('เพิ่มเมนู', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ----- แท็บบนสุด (วัน / สัปดาห์ / เดือน) -----
  Widget _topTabs(BuildContext context, String currentTab) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () {
              if (currentTab != 'วัน') setState(() => this.currentTab = 'วัน');
            },
            child: _toggleTab('วัน', currentTab == 'วัน'),
          ),
          GestureDetector(
            onTap: () {
              if (currentTab != 'สัปดาห์') setState(() => this.currentTab = 'สัปดาห์');
            },
            child: _toggleTab('สัปดาห์', currentTab == 'สัปดาห์'),
          ),
          GestureDetector(
            onTap: () {
              if (currentTab != 'เดือน') setState(() => this.currentTab = 'เดือน');
            },
            child: _toggleTab('เดือน', currentTab == 'เดือน'),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab(String label, bool selected) {
    const double fixedWidth = 100;
    return Container(
      width: fixedWidth,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.grey[300] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey),
      ),
      alignment: Alignment.center,
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  // ----- เลือกภาพ & เพิ่มเมนู -----
  void _showPickOptionsDialog() {

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('ถ่ายภาพด้วยกล้อง'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('เลือกจากคลังรูปภาพ'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    if (image == null) return;

    final result = await ApiService.uploadImage(File(image.path));
    if (result == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถทำนายเมนูได้')),
      );
      return;
    }

    if (!mounted) return;

    final selectedData = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FoodResultPage(
          menuName: result['menu_name'],
          imagePath: image.path,
          menuData: result,
        ),
      ),
    );

    if (selectedData == null) return;

    await _addMenuFromSelection(selectedData);
  }

  // เพิ่มเมนูจากผลลัพธ์หน้า Search (หรือที่อื่นที่ส่งรูปแบบเดียวกัน)
  Future<void> _addMenuFromSelection(Map<String, dynamic> selectedData) async {
    final useNoSugar = selectedData['useNoSugar'] == true;
    final session = context.read<SessionProvider>();

    final Map<String, dynamic> nutritionData =
    (selectedData['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
    final groupKey = useNoSugar ? 'nosugar_nutrition' : 'sugar_nutrition';
    final g = (nutritionData[groupKey] ?? {}) as Map<String, dynamic>;

    double _toD(v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final s = v.toString();
      final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
      return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
    }

    // ✅ เลือก image สำหรับเก็บใน dailyLogs: ใช้ URL ก่อน (ถ้ามี)
    final url  = (selectedData['imageUrl'] as String?)?.trim() ?? '';
    final path = (selectedData['imagePath'] as String?)?.trim() ?? '';
    final imagePathValue = _isLoggedIn ? (url.isNotEmpty ? url : path) : path;

    // 1) UI + persistence (login ผ่าน DailyRepo ภายใน SessionProvider)
    await session.addMenu(
      {
        'menuName': selectedData['menuName'],
        'imagePath': imagePathValue,       // ← เก็บ URL ถ้ามี
        'imageUrl': url.isNotEmpty ? url : null, // แนบไว้ด้วย (ไม่บังคับใช้)
        'menuData': selectedData['menuData'],
        'useNoSugar': useNoSugar,
      },
      nutritionKey: groupKey,
    );

    // 2) Guest → เก็บซ้ำลง SQLite (คงเดิม ใช้ path ของเครื่อง)
    if (!_isLoggedIn) {
      await DBusers.instance.insertFoodLog(
        day: _selectedDate,
        menuName: selectedData['menuName'] ?? '',
        imagePath: path,
        with_sugar: !useNoSugar,
        calorie: _toD(g['Calorie']),
        sugar: _toD(g['Sugar']),
        protein: _toD(g['Protein']),
        fat: _toD(g['Fat']),
        fiber: _toD(g['Fiber']),
        carb: _toD(g['Carb']),
      );
    }

    // ถ้าเปิดดูวันย้อนหลังอยู่ → reload snapshot
    if (!_isToday(_selectedDate)) {
      await _loadDataFor(_selectedDate);
      await _loadDailyBlood();
    }
  }

  // ----- Formats / Utils -----
  String _fmtCalorie(dynamic v) {
    if (v == null) return '- Kcal';
    final numVal = _extractNumber(v);
    return '${numVal.toInt()} Kcal';
  }

  String _fmtSugar(dynamic v) {
    if (v == null) return '- g';
    final numVal = _extractNumber(v);
    return '${numVal.toStringAsFixed(1)} g';
  }

  double _extractNumber(dynamic v) {
    if (v is num) return v.toDouble();
    final s = v.toString();
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    if (match != null) {
      final n = double.tryParse(match.group(0)!);
      if (n != null) return n;
    }
    return 0.0;
  }

  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
  }

  // ----- Bottom nav -----
  Widget _bottomNav(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFFEFFFFF),
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.grey,
      currentIndex: bottomNavIndex,
      onTap: (index) async {
        setState(() => bottomNavIndex = index);
        if (index == 1) {
          final selected = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchPage()),
          );
          if (selected != null) {
            await _addMenuFromSelection(selected);
          }
        } else if (index == 2) {
          // ignore: use_build_context_synchronously
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'หน้าหลัก'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'ค้นหา'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
      ],
    );
  }

  // ====== ปุ่มแคปซูลช่วยใช้ซ้ำ ======
  Widget _pillButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _pillButtonWithAssetIcon({
    required String label,
    required Color color,
    required String assetPath,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(assetPath, width: 20, height: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
