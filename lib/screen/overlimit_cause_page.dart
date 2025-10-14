import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:main/provider/session_provider.dart';
import 'package:main/shared/overlimit_kind.dart';

/// แท็บ
class _CauseTab {
  static const String sugar = 'sugar';     // ซ้าย
  static const String calorie = 'calorie'; // ขวา
}

/// metric ภายในหน้านี้
class _Metric {
  static const String sugar = 'sugar';
  static const String calorie = 'calorie';
}

class OverlimitCausePage extends StatefulWidget {
  /// วันที่ที่ต้องการดูสาเหตุ (ถ้าไม่ส่งมา จะใช้วันนี้)
  final DateTime? day;

  const OverlimitCausePage({super.key, this.day});

  @override
  State<OverlimitCausePage> createState() => _OverlimitCausePageState();
}

class _OverlimitCausePageState extends State<OverlimitCausePage> {
  String _tab = _CauseTab.sugar; // เริ่มที่ “น้ำตาล”
  late final DateTime _targetDay;

  // ข้อมูลของวันนั้น (สำหรับผู้ใช้ที่ล็อกอินเท่านั้น)
  List<Map<String, dynamic>> _menus = [];
  double _totalCal = 0, _totalSugar = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _targetDay = DateTime(
      (widget.day ?? DateTime.now()).year,
      (widget.day ?? DateTime.now()).month,
      (widget.day ?? DateTime.now()).day,
    );
    _loadForDay();
  }

  Future<void> _loadForDay() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _menus = [];
        _totalCal = 0;
        _totalSugar = 0;
        return;
      }

      final id = _ymd(_targetDay);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyLogs')
          .doc(id)
          .get();

      final data = snap.data();
      final menus = List<Map<String, dynamic>>.from(
        (data?['menus'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
            const [],
      );

      _menus = _orderChronological(menus);

      final sum = (data?['summary'] as Map?) ?? {};
      if (sum.isNotEmpty) {
        _totalCal = _toD(sum['eaten']);
        _totalSugar = _toD(sum['sugar']);
      } else {
        // คำนวณจากเมนู
        double c = 0, s = 0;
        for (final m in _menus) {
          final key = (m['useNoSugar'] == true)
              ? 'nosugar_nutrition'
              : 'sugar_nutrition';
          final nd =
          (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
          final g = (nd[key] ?? {}) as Map<String, dynamic>;
          c += _toD(g['Calorie']);
          s += _toD(g['Sugar']);
        }
        _totalCal = c;
        _totalSugar = s;
      }
    } catch (_) {
      _menus = [];
      _totalCal = 0;
      _totalSugar = 0;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();

    final over = OverlimitResult.evaluate(
      calories: _totalCal,
      caloriesLimit: sp.bmr,
      sugar: _totalSugar,
      sugarLimit: sp.sugarLimit,
    );

    // เลือก metric ตามแท็บ
    final String metric =
    (_tab == _CauseTab.sugar) ? OverlimitMetric.sugar : OverlimitMetric.calorie;

    // ยังไม่เกิน? → แสดงข้อความชมเชย 1 บรรทัด และไม่แสดง tips
    final bool isOver = (metric == OverlimitMetric.calorie)
        ? (_totalCal > sp.bmr)
        : (_totalSugar > sp.sugarLimit);

    final lines = isOver
        ? over.detailLinesThForMetric(
      metric,
      totalCalories: _totalCal,
      caloriesLimit: sp.bmr,
      totalSugar: _totalSugar,
      sugarLimit: sp.sugarLimit,
    )
        : const ['ยังไม่เกินตามที่กำหนด ถือว่าดีมากครับ'];

    final tips =
    isOver ? over.adviceThForMetric(metric, maxItems: 5) : const <String>[];

    // ✅ เพิ่ม “คำแนะนำออกกำลังกาย” โดยใช้ค่าที่เกินจริงจาก over.*
    final List<String> exercise = [];
    if (isOver && metric == OverlimitMetric.sugar) {
      exercise.add(exerciseAdviceForSugar(over.overSugar));
    }
    if (isOver && metric == OverlimitMetric.calorie) {
      exercise.add(exerciseAdviceForCalories(over.overCalories));
    }

    final split = _computeSplit(
      menus: _menus,
      calLimit: sp.bmr,
      sugarLimit: sp.sugarLimit,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('สาเหตุ'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('รายการอาหาร',
                style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),

            // แท็บ: น้ำตาล / แคลอรี
            _segmentedTabs(),

            const SizedBox(height: 12),

            // กล่องรายการ
            LayoutBuilder(
              builder: (context, _) {
                final screenH = MediaQuery.of(context).size.height;
                final minH = 160.0;
                final maxH = (screenH * 0.48).clamp(260.0, 330.0);
                return ConstrainedBox(
                  constraints:
                  BoxConstraints(minHeight: minH, maxHeight: maxH),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F6F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _buildListForCurrentTab(split),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            const Text('คำแนะนำ',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54)),
            const SizedBox(height: 8),

            if (lines.isEmpty && tips.isEmpty && exercise.isEmpty)
              _bullet('เยี่ยมมาก! รักษาพฤติกรรมที่ดีต่อไปนะ')
            else ...[
              ...lines.map(_bullet),
              ...tips.map(_bullet),
              ...exercise.map(_bullet),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- UI helpers ----------------

  Widget _segmentedTabs() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _segBtn(
            label: 'น้ำตาล',
            selected: _tab == _CauseTab.sugar,
            onTap: () => setState(() => _tab = _CauseTab.sugar),
          ),
          _segBtn(
            label: 'แคลอรี',
            selected: _tab == _CauseTab.calorie,
            onTap: () => setState(() => _tab = _CauseTab.calorie),
          ),
        ],
      ),
    );
  }

  Widget _segBtn({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFD7EEFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black87 : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  // รายการในแท็บปัจจุบัน (ทำให้เลื่อนได้เองหาก child เกิน)
  Widget _buildListForCurrentTab(_Split s) {
    final bool isSugarTab = _tab == _CauseTab.sugar;
    final int? causeIdx = isSugarTab ? s.idxSugar : s.idxCal;
    final int? otherIdx = isSugarTab ? s.idxCal : s.idxSugar;

    if (causeIdx == null) {
      return Center(
        child: Text(
          isSugarTab ? 'ยังไม่มีเมนูที่ทำให้น้ำตาลเกิน'
              : 'ยังไม่มีเมนูที่ทำให้พลังงานเกิน',
        ),
      );
    }

    final tiles = <Widget>[];

    // รายการที่ทำให้ “เกิน” ของแท็บนี้
    tiles.add(_menuTile(
      s.menus[causeIdx],
      mainMetric: isSugarTab ? _Metric.sugar : _Metric.calorie,
      secondaryMetric: (otherIdx != null && causeIdx >= otherIdx)
          ? (isSugarTab ? _Metric.calorie : _Metric.sugar)
          : null,
      causeBadge: true,
    ));
    tiles.add(const SizedBox(height: 8));

    // ต่อด้วยรายการหลังจากนั้นทั้งหมด
    for (int i = causeIdx + 1; i < s.menus.length; i++) {
      final afterOther = (otherIdx != null && i >= otherIdx);
      tiles.add(_menuTile(
        s.menus[i],
        mainMetric: isSugarTab ? _Metric.sugar : _Metric.calorie,
        secondaryMetric:
        afterOther ? (isSugarTab ? _Metric.calorie : _Metric.sugar) : null,
      ));
      tiles.add(const SizedBox(height: 8));
    }

    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(overscroll: false),
      child: ListView(children: tiles),
    );
  }

  /// บรรทัดคำแนะนำมีจุดนำหน้า •
  Widget _bullet(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _menuTile(
      Map<String, dynamic> m, {
        required String mainMetric,
        String? secondaryMetric,
        bool causeBadge = false,
      }) {
    final name = (m['menuName'] ?? '').toString();
    final key =
    (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
    final nd = (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
    final g = (nd[key] ?? {}) as Map<String, dynamic>;

    final cal = _toD(g['Calorie']); // kcal
    final sug = _toD(g['Sugar']);   // g

    String mainValue() => (mainMetric == _Metric.sugar)
        ? '${sug.toStringAsFixed(1)} กรัม'
        : '${cal.round()} kcal';

    String? secondaryValue() {
      if (secondaryMetric == null) return null;
      return (secondaryMetric == _Metric.sugar)
          ? '${sug.toStringAsFixed(1)} กรัม'
          : '${cal.round()} kcal';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _thumb(m['imagePath']),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (causeBadge)
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE3E3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('ทำให้เกิน',
                      style:
                      TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              Text(mainValue(), style: const TextStyle(fontWeight: FontWeight.bold)),
              if (secondaryValue() != null)
                Text(secondaryValue()!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }

  // รูป (รองรับทั้ง path และ URL)
  Widget _thumb(dynamic imagePath) {
    const w = 54.0, h = 54.0;
    if (imagePath is String && imagePath.isNotEmpty) {
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            imagePath,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/icon/spoon.jpg',
              width: w,
              height: h,
              fit: BoxFit.cover,
            ),
          ),
        );
      }
      if (imagePath.startsWith('/')) {
        final f = File(imagePath);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            f,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/icon/spoon.jpg',
              width: w,
              height: h,
              fit: BoxFit.cover,
            ),
          ),
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset('assets/icon/spoon.jpg',
          width: w, height: h, fit: BoxFit.cover),
    );
  }

  // ---------------- Logic helpers ----------------

  List<Map<String, dynamic>> _orderChronological(List<Map<String, dynamic>> menus) {
    if (menus.length <= 1) return menus;

    const timeKeys = ['created_at', 'createdAt', 'timestamp', 'ts'];
    final hasTime = menus.any((m) => timeKeys.any((k) => m[k] != null));
    if (hasTime) {
      final copy = List<Map<String, dynamic>>.from(menus);
      copy.sort((a, b) {
        DateTime? ta = _parseTime(
            a[timeKeys.firstWhere((k) => a[k] != null, orElse: () => '')]);
        DateTime? tb = _parseTime(
            b[timeKeys.firstWhere((k) => b[k] != null, orElse: () => '')]);
        if (ta == null && tb == null) return 0;
        if (ta == null) return -1;
        if (tb == null) return 1;
        return ta.compareTo(tb); // เก่าสุด -> ใหม่สุด
      });
      return copy;
    }

    // ไม่มีเวลา → ใช้ลำดับเดิม
    return List<Map<String, dynamic>>.from(menus);
  }

  DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is int) {
      return v > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(v)
          : DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    if (v is double) return _parseTime(v.toInt());
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  _Split _computeSplit({
    required List<Map<String, dynamic>> menus,
    required double calLimit,
    required double sugarLimit,
  }) {
    double cumCal = 0, cumSugar = 0;
    int? idxSugar;
    int? idxCal;

    for (int i = 0; i < menus.length; i++) {
      final m = menus[i];
      final key =
      (m['useNoSugar'] == true) ? 'nosugar_nutrition' : 'sugar_nutrition';
      final nd =
      (m['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
      final g = (nd[key] ?? {}) as Map<String, dynamic>;

      cumCal += _toD(g['Calorie']);
      cumSugar += _toD(g['Sugar']);

      if (idxSugar == null && cumSugar > sugarLimit) idxSugar = i;
      if (idxCal == null && cumCal > calLimit) idxCal = i;
      if (idxSugar != null && idxCal != null) break;
    }

    return _Split(menus: menus, idxSugar: idxSugar, idxCal: idxCal);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(v);
      if (m != null) return double.tryParse(m.group(0)!) ?? 0.0;
    }
    return 0.0;
  }
}

class _Split {
  final List<Map<String, dynamic>> menus; // เรียง “เก่า -> ใหม่”
  final int? idxSugar; // index ที่น้ำตาลเกินครั้งแรก
  final int? idxCal;   // index ที่แคลอรีเกินครั้งแรก
  const _Split({required this.menus, required this.idxSugar, required this.idxCal});
}
