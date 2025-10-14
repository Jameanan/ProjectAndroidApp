// lib/screen/home/Weekpage.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:main/database/dbusers.dart';

class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  static const int _days = 7;

  DateTime _weekAnchor = DateTime.now();

  // 7 วัน (จ.–อา)
  List<double> _calories = List.filled(_days, 0.0);
  List<double> _sugars   = List.filled(_days, 0.0);
  List<double> _proteins = List.filled(_days, 0.0);
  List<double> _fats     = List.filled(_days, 0.0);
  List<double> _fibers   = List.filled(_days, 0.0);
  List<double> _carbs    = List.filled(_days, 0.0);

  bool _showCalories = true;
  bool _loading = false;

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;
  String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWeek());
  }

  DateTime _startOfWeek(DateTime d) {
    // Monday as start of week
    final diff = (d.weekday + 6) % 7;
    final base = DateTime(d.year, d.month, d.day);
    return base.subtract(Duration(days: diff));
  }

  DateTime _endOfWeek(DateTime d) => _startOfWeek(d).add(const Duration(days: 6));

  String _formatWeekRangeThai(DateTime anyDay) {
    final s = _startOfWeek(anyDay);
    final e = _endOfWeek(anyDay);
    final f = DateFormat('d MMM yyyy', 'th');
    return '${f.format(s)} - ${f.format(e)}';
  }

  String _dateId(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DocumentReference<Map<String, dynamic>> _dailyDoc(String uid, DateTime day) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyLogs')
        .doc(_dateId(day));
  }

  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString();
    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
  }

  Future<void> _loadWeek() async {
    if (_loading) return;
    _loading = true;

    // ล้างสเตตเพื่อไม่ให้เห็นค่าค้างระหว่างโหลด
    setState(() {
      _calories = List.filled(_days, 0.0);
      _sugars   = List.filled(_days, 0.0);
      _proteins = List.filled(_days, 0.0);
      _fats     = List.filled(_days, 0.0);
      _fibers   = List.filled(_days, 0.0);
      _carbs    = List.filled(_days, 0.0);
    });

    final uid = _uid();
    final loggedIn = _isLoggedIn && uid != null;

    final s = _startOfWeek(_weekAnchor);

    // โหลดแบบขนาน 7 วัน
    final futures = List.generate(_days, (i) async {
      final day = s.add(Duration(days: i));

      double eaten = 0, sugar = 0, protein = 0, fat = 0, fiber = 0, carb = 0;

      if (loggedIn) {
        // ===== Firestore (ผู้ใช้ล็อกอิน) =====
        final snap = await _dailyDoc(uid!, day).get();
        final data = snap.data();

        if (data != null && data.isNotEmpty) {
          final sum = data['summary'] as Map<String, dynamic>?;
          if (sum != null) {
            eaten   = _toD(sum['eaten']);
            sugar   = _toD(sum['sugar']);
            protein = _toD(sum['protein']);
            // ใน Firestore ของโปรเจกต์นี้ใช้ชื่อ transFat
            fat     = _toD(sum['transFat']);
            fiber   = _toD(sum['fiber']);
            carb    = _toD(sum['carb']);
          } else {
            final menus = List<Map<String, dynamic>>.from((data['menus'] ?? []) as List);
            for (final m in menus) {
              final nd = (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
              final key = (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
              final g = (nd[key] ?? {}) as Map<String, dynamic>;
              eaten   += _toD(g['Calorie']);
              sugar   += _toD(g['Sugar']);
              protein += _toD(g['Protein']);
              fat     += _toD(g['Fat']);
              fiber   += _toD(g['Fiber']);
              carb    += _toD(g['Carb']);
            }
          }
        }
      } else {
        // ===== Guest (SQLite) =====
        final totals = await DBusers.instance.getDailyTotals(day: day);
        eaten   = (totals['cal']     ?? 0).toDouble();
        sugar   = (totals['sugar']   ?? 0).toDouble();
        protein = (totals['protein'] ?? 0).toDouble();
        fat     = (totals['fat']     ?? 0).toDouble();
        fiber   = (totals['fiber']   ?? 0).toDouble();
        carb    = (totals['carb']    ?? 0).toDouble();
      }

      return (eaten, sugar, protein, fat, fiber, carb);
    });

    final results = await Future.wait(futures);

    if (!mounted) { _loading = false; return; }

    setState(() {
      _calories = results.map((e) => e.$1).toList();
      _sugars   = results.map((e) => e.$2).toList();
      _proteins = results.map((e) => e.$3).toList();
      _fats     = results.map((e) => e.$4).toList();
      _fibers   = results.map((e) => e.$5).toList();
      _carbs    = results.map((e) => e.$6).toList();
    });

    _loading = false;
  }

  void _prevWeek() {
    setState(() => _weekAnchor = _startOfWeek(_weekAnchor).subtract(const Duration(days: 7)));
    _loadWeek();
  }

  void _nextWeek() {
    final next = _startOfWeek(_weekAnchor).add(const Duration(days: 7));
    final thisWeekStart = _startOfWeek(DateTime.now());
    if (next.isAfter(thisWeekStart)) return;
    setState(() => _weekAnchor = next);
    _loadWeek();
  }

  @override
  Widget build(BuildContext context) {
    final weekLabel = _formatWeekRangeThai(_weekAnchor);
    final data = _showCalories ? _calories : _sugars;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(onPressed: _prevWeek, icon: const Icon(Icons.chevron_left)),
                    const SizedBox(width: 8),
                    Text(weekLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    IconButton(onPressed: _nextWeek, icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('แคล'),
                      selected: _showCalories,
                      onSelected: (_) => setState(() => _showCalories = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('น้ำตาล'),
                      selected: !_showCalories,
                      onSelected: (_) => setState(() => _showCalories = false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 260,
                  child: _WeeklyBarChart(
                    values: data,
                    yStep: _showCalories ? 1000 : 10,
                    barColor: _showCalories ? Colors.amber : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ค่าโภชนาการ',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              _nutritionSummaryScroller(context),
            ],
          ),
        ),
      ),
    );
  }

  double _sum(List<double> xs) => xs.fold(0.0, (a, b) => a + b);

  Widget _nutritionSummaryScroller(BuildContext context) {
    final totalCal   = _sum(_calories);
    final totalSugar = _sum(_sugars);
    final totalProt  = _sum(_proteins);
    final totalFat   = _sum(_fats);
    final totalFiber = _sum(_fibers);
    final totalCarb  = _sum(_carbs);

    final items = [
      ('assets/icon/fire.png',      'พลังงาน', '${totalCal.toStringAsFixed(0)} แคล', const Color(0xFFFFF3CD)),
      ('assets/icon/sugar-cube.png','น้ำตาล',  '${totalSugar.toStringAsFixed(1)} ก.',  const Color(0xFFFFE0EB)),
      ('assets/icon/proteins.png',  'โปรตีน',  '${totalProt.toStringAsFixed(1)} ก.',   const Color(0xFFD4F5D5)),
      ('assets/icon/trans-fat.png', 'ไขมัน',   '${totalFat.toStringAsFixed(1)} ก.',    const Color(0xFFFFE3C5)),
      ('assets/icon/fiber.png',     'ไฟเบอร์', '${totalFiber.toStringAsFixed(1)} ก.',  const Color(0xFFE8F7E8)),
      ('assets/icon/carb.png',      'คาร์บ',   '${totalCarb.toStringAsFixed(1)} ก.',   const Color(0xFFE8E5FF)),
    ];

    return SizedBox(
      height: 110,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final e in items)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _summaryChip(e.$1, e.$2, e.$3, e.$4),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(String iconPath, String label, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(iconPath, width: 22, height: 22),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  final List<double> values;
  final double yStep;
  final Color barColor;

  const _WeeklyBarChart({
    required this.values,
    this.yStep = 1000,
    this.barColor = Colors.amber,
  });

  static const _dayLabels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

  @override
  Widget build(BuildContext context) {
    final max = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final maxY = _ceilToStep(max == 0 ? yStep : max + (yStep / 5), yStep).toDouble();

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yStep,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey.shade300, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yStep,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => Text(v.toInt().toString()),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(i >= 0 && i < _dayLabels.length ? _dayLabels[i] : ''),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(_dayLabels.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: i < values.length ? values[i] : 0.0,
                width: 18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                color: barColor,
              ),
            ],
          );
        }),
      ),
    );
  }

  static int _ceilToStep(num value, double step) {
    final s = step.toInt();
    final v = value.ceil();
    if (v % s == 0) return v;
    return v + (s - (v % s));
  }
}
