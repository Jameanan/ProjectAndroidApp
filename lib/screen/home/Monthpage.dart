// lib/screen/home/Monthpage.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:main/database/dbusers.dart';

class MonthPage extends StatefulWidget {
  const MonthPage({super.key});

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  DateTime _monthAnchor = DateTime(DateTime.now().year, DateTime.now().month, 1);

  List<double> _calSeries   = const [];
  List<double> _sugarSeries = const [];
  List<double> _bloodSeries = const [];

  double _sumCal = 0, _sumSugar = 0, _sumProtein = 0, _sumFat = 0, _sumFiber = 0, _sumCarb = 0;
  int _mode = 0; // 0=แคล, 1=น้ำตาล, 2=น้ำตาลในเลือด
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth());
  }

  // ===== Helpers (วันที่/ไฟร์สโตร์) =====
  // d = date
  DateTime _firstDay(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _lastDay(DateTime d)  => DateTime(d.year, d.month + 1, 0);
  int _daysInMonth(DateTime d)   => _lastDay(d).day;
  String _monthLabelThai(DateTime d) => DateFormat('LLLL yyyy', 'th').format(d);

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;
  String? _uid() => FirebaseAuth.instance.currentUser?.uid;

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

  Future<void> _loadMonth() async {
    if (_loading) return;
    _loading = true;

    final days = _daysInMonth(_monthAnchor);

    // ล้าง state เพื่อกันค่าเก่าแสดงค้าง
    setState(() {
      _calSeries   = List<double>.filled(days, 0.0);
      _sugarSeries = List<double>.filled(days, 0.0);
      _bloodSeries = List<double>.filled(days, 0.0);
      _sumCal = _sumSugar = _sumProtein = _sumFat = _sumFiber = _sumCarb = 0;
    });

    final first = _firstDay(_monthAnchor);
    final loggedIn = _isLoggedIn;
    final uid = _uid();

    // โหลดแต่ละวันแบบขนาน
    final futures = List.generate(days, (i) async {
      final day = DateTime(first.year, first.month, i + 1);

      double eaten = 0, sugar = 0, protein = 0, fat = 0, fiber = 0, carb = 0;
      double blood = 0;

      if (loggedIn && uid != null) {
        // ===== Firestore (ผู้ใช้ล็อกอิน) =====
        final snap = await _dailyDoc(uid, day).get();
        final data = snap.data();
        if (data != null && data.isNotEmpty) {
          // สรุปโภชนาการ
          final sum = data['summary'] as Map<String, dynamic>?;
          if (sum != null) {
            eaten   = _toD(sum['eaten']);
            sugar   = _toD(sum['sugar']);
            protein = _toD(sum['protein']);
            fat     = _toD(sum['transFat']); // key เดิม
            fiber   = _toD(sum['fiber']);
            carb    = _toD(sum['carb']);
          } else {
            // ไม่มี summary → รวมจากเมนู
            final menus = List<Map<String, dynamic>>.from((data['menus'] ?? []) as List);
            for (final m in menus) {
              final nd = (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
              final key = (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
              final g = (nd[key] ?? {}) as Map<String, dynamic>; //g = group
              eaten   += _toD(g['Calorie']);
              sugar   += _toD(g['Sugar']);
              protein += _toD(g['Protein']);
              fat     += _toD(g['Fat']);
              fiber   += _toD(g['Fiber']);
              carb    += _toD(g['Carb']);
            }
          }

          // น้ำตาลในเลือด
          final sVal = data['currentBloodSugarMgdl'];
          if (sVal is num) blood = sVal.toDouble();
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

        final row = await DBusers.instance.getDailyBloodSugar(day: day);
        if (row != null) blood = (row['value'] as num).toDouble();
      }

      return (eaten, sugar, protein, fat, fiber, carb, blood);
    });

    final results = await Future.wait(futures);

    if (!mounted) { _loading = false; return; }

    // รวมค่ากลับเข้า state
    final cal   = List<double>.filled(days, 0.0);
    final sug   = List<double>.filled(days, 0.0);
    final blood = List<double>.filled(days, 0.0);

    double sCal = 0, sSugar = 0, sProtein = 0, sFat = 0, sFiber = 0, sCarb = 0;

    for (int i = 0; i < days; i++) {
      cal[i]   = results[i].$1;
      sug[i]   = results[i].$2;
      blood[i] = results[i].$7;

      sCal    += results[i].$1;
      sSugar  += results[i].$2;
      sProtein+= results[i].$3;
      sFat    += results[i].$4;
      sFiber  += results[i].$5;
      sCarb   += results[i].$6;
    }

    setState(() {
      _calSeries   = cal;
      _sugarSeries = sug;
      _bloodSeries = blood;

      _sumCal    = sCal;
      _sumSugar  = sSugar;
      _sumProtein= sProtein;
      _sumFat    = sFat;
      _sumFiber  = sFiber;
      _sumCarb   = sCarb;
    });

    _loading = false;
  }

  void _prevMonth() {
    setState(() => _monthAnchor = DateTime(_monthAnchor.year, _monthAnchor.month - 1, 1));
    _loadMonth();
  }

  void _nextMonth() {
    final next = DateTime(_monthAnchor.year, _monthAnchor.month + 1, 1);
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    if (!next.isAfter(currentMonth)) {
      setState(() => _monthAnchor = next);
      _loadMonth();
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _monthAnchor,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'เลือกเดือน',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
      locale: const Locale('th'),
    );
    if (picked != null) {
      setState(() => _monthAnchor = DateTime(picked.year, picked.month, 1));
      _loadMonth();
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysInMonth(_monthAnchor);
    final label = _monthLabelThai(_monthAnchor);

    List<double> series;
    Color dotColor;
    double yStep;

    switch (_mode) {
      case 1: series = _sugarSeries; dotColor = Colors.blue;  yStep = 10;   break;
      case 2: series = _bloodSeries; dotColor = Colors.red;   yStep = 50;   break;
      default:series = _calSeries;   dotColor = Colors.amber; yStep = 1000; break;
    }

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
                    IconButton(onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _pickMonth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    IconButton(onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(label: const Text('แคล'), selected: _mode == 0, onSelected: (_) => setState(() => _mode = 0)),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('น้ำตาล'), selected: _mode == 1, onSelected: (_) => setState(() => _mode = 1)),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('น้ำตาลในเลือด'), selected: _mode == 2, onSelected: (_) => setState(() => _mode = 2)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 260,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: days * 22.0 + 40,
                      child: _MonthlyDotLineChart(
                        values: series,
                        days: days,
                        yStep: yStep,
                        dotColor: dotColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ข้อมูลโภชนาการ',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _nutritionSummaryScroller(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nutritionSummaryScroller() {
    final items = [
      ('assets/icon/fire.png',       'พลังงาน', '${_sumCal.toStringAsFixed(0)} แคล', const Color(0xFFFFF3CD)),
      ('assets/icon/sugar-cube.png', 'น้ำตาล',  '${_sumSugar.toStringAsFixed(1)} ก.', const Color(0xFFFFE0EB)),
      ('assets/icon/proteins.png',   'โปรตีน',  '${_sumProtein.toStringAsFixed(1)} ก.', const Color(0xFFD4F5D5)),
      ('assets/icon/trans-fat.png',  'ไขมัน',   '${_sumFat.toStringAsFixed(1)} ก.', const Color(0xFFFFE3C5)),
      ('assets/icon/fiber.png',      'ไฟเบอร์', '${_sumFiber.toStringAsFixed(1)} ก.', const Color(0xFFE8F7E8)),
      ('assets/icon/carb.png',       'คาร์บ',   '${_sumCarb.toStringAsFixed(1)} ก.', const Color(0xFFE8E5FF)),
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
      width: 140,
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

class _MonthlyDotLineChart extends StatelessWidget {
  final List<double> values;
  final int days;
  final double yStep;
  final Color dotColor;

  const _MonthlyDotLineChart({
    required this.values,
    required this.days,
    required this.yStep,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final maxY = _ceilToStep(maxVal == 0 ? yStep : maxVal + (yStep / 5), yStep).toDouble();

    final spots = <FlSpot>[];
    for (int i = 0; i < days; i++) {
      final y = i < values.length ? values[i] : 0.0;
      if (y > 0) spots.add(FlSpot(i + 1.0, y));
    }

    return LineChart(
      LineChartData(
        minX: 1,
        maxX: days.toDouble(),
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
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yStep,
              reservedSize: 40,
              getTitlesWidget: (v, meta) =>
                  Text(v.toInt().toString(), style: const TextStyle(fontSize: 11)),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final day = v.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text((day >= 1 && day <= days) ? '$day' : '',
                      style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2,
            color: dotColor,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 3, color: dotColor, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
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
