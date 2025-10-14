import 'package:flutter/material.dart';

class OverlimitKinds {
  static const String none = 'none';
  static const String calories = 'calories';
  static const String sugar = 'sugar';
  static const String both = 'both';
}

/// ใช้บอกว่าอยากให้สรุป “ฝั่งไหน”
class OverlimitMetric {
  static const String calorie = 'calorie';
  static const String sugar = 'sugar';
}

class OverlimitResult {
  final String kind;
  final double overCalories; // จำนวน kcal ที่เกินแล้ว (ถ้าไม่เกิน = 0)
  final double overSugar;    // จำนวน g น้ำตาลที่เกินแล้ว (ถ้าไม่เกิน = 0)

  const OverlimitResult({
    required this.kind,
    required this.overCalories,
    required this.overSugar,
  });

  bool get hasAny => kind != OverlimitKinds.none;

  static OverlimitResult evaluate({
    required double calories,
    required double caloriesLimit,
    required double sugar,
    required double sugarLimit,
  }) {
    final overCal = (calories - caloriesLimit).clamp(0.0, double.infinity).toDouble();
    final overSug = (sugar - sugarLimit).clamp(0.0, double.infinity).toDouble();

    String k = OverlimitKinds.none;
    if (overCal > 0 && overSug > 0) {
      k = OverlimitKinds.both;
    } else if (overCal > 0) {
      k = OverlimitKinds.calories;
    } else if (overSug > 0) {
      k = OverlimitKinds.sugar;
    }
    return OverlimitResult(
      kind: k,
      overCalories: overCal,
      overSugar: overSug,
    );
  }

  Color color() {
    if (kind == OverlimitKinds.calories) return const Color(0xFFFFA726);
    if (kind == OverlimitKinds.sugar) return const Color(0xFF42A5F5);
    if (kind == OverlimitKinds.both) return const Color(0xFFE53935);
    return const Color(0xFF26A69A);
  }

  /// รายละเอียด “ตามฝั่งที่เลือกดู” (ไม่ปะปนอีกฝั่ง)
  List<String> detailLinesThForMetric(
      String metric, {
        double? totalCalories,
        double? caloriesLimit,
        double? totalSugar,
        double? sugarLimit,
      }) {
    if (metric == OverlimitMetric.calorie) {
      if (totalCalories == null || caloriesLimit == null) return const [];
      final diff = (totalCalories - caloriesLimit).clamp(0, double.infinity);
      return [
        'วันนี้คุณได้รับแคลอรีรวมแล้ว ${_fmtKcal(totalCalories)}',
        if (diff > 0) 'เกินจากค่าแนะนำถึง ${_fmtKcal(diff)}',
      ];
    } else {
      if (totalSugar == null || sugarLimit == null) return const [];
      final diff = (totalSugar - sugarLimit).clamp(0, double.infinity);
      return [
        'วันนี้คุณได้รับน้ำตาลรวมแล้ว ${_fmtGram(totalSugar)}',
        if (diff > 0) 'เกินจากค่าแนะนำถึง ${_fmtGram(diff)}',
      ];
    }
  }

  /// ข้อแนะนำ “เฉพาะฝั่งที่เลือกดู” (ทั่วไป ไม่ใช่ออกกำลังกาย)
  List<String> adviceThForMetric(String metric, {int maxItems = 3}) {
    final pool = (metric == OverlimitMetric.calorie) ? _calTips : _sugarTips;
    return pool.length > maxItems ? pool.take(maxItems).toList() : pool;
  }

  // --------- แหล่งคำแนะนำภายใน (ทั่วไป) ---------
  static const List<String> _calTips = [
    'แบ่งครึ่งส่วน หรือเก็บไว้กินมื้อถัดไป'
  ];

  static const List<String> _sugarTips = [
    'หลีกเลี่ยงอาหารคาว/ของหวานที่มีน้ำตาลมาก'
  ];
}

/// ---- คำแนะนำ “ออกกำลังกาย” ----

/// แนะนำการออกกำลังเมื่อน้ำตาลเกิน (รับค่า “เกินจริง” เป็นกรัม)
String exerciseAdviceForSugar(double overSugarGram) {
  if (overSugarGram <= 0) {
    return 'ยังไม่เกินตามที่กำหนด — เดินยืดเส้น 5–10 นาทีพอครับ';
  } else if (overSugarGram <= 10) {
    return 'น้ำตาลเกินเล็กน้อย: เดินสบาย ๆ 10–15 นาทีหลังมื้อถัดไป';
  } else if (overSugarGram <= 20) {
    return 'น้ำตาลเกินปานกลาง: เดินเร็ว/ปั่นจักรยาน 20–30 นาที เพื่อช่วยใช้น้ำตาล';
  } else {
    return 'น้ำตาลเกินเยอะ: จ๊อกกิ้ง 30–45 นาที หรือ HIIT 10–15 นาที (ถ้าสุขภาพพร้อม)';
  }
}

/// แนะนำการออกกำลังเมื่อแคลอรีเกิน (รับค่า “เกินจริง” เป็นกิโลแคลอรี)
String exerciseAdviceForCalories(double overKcal) {
  if (overKcal <= 0) {
    return 'ยังไม่เกินแคลอรี — ขยับตัวเบา ๆ ระหว่างวันต่อเนื่องถือว่าดีครับ';
  } else if (overKcal <= 250) {
    return 'พลังงานเกินเล็กน้อย: เดินเร็ว 20–30 นาที หรือทำงานบ้านเพิ่ม';
  } else if (overKcal <= 600) {
    return 'พลังงานเกินปานกลาง: เดินเร็ว/ปั่นจักรยาน 40–60 นาที หรือเวทเทรนนิ่งเบา ๆ';
  } else {
    return 'พลังงานเกินมาก: คาร์ดิโอระดับกลาง 60 นาที หรือเวทเทรนนิ่งเต็มรูปแบบ (ถ้าร่างกายพร้อม)';
  }
}

// ---------- Utilities ----------
String _fmtKcal(num v) => '${v.round()} kcal';
String _fmtGram(num v) => '${v.toStringAsFixed(1)} กรัม';

class OverlimitUI {
  final String title;
  final Color color;
  final IconData icon;
  const OverlimitUI(this.title, this.color, this.icon);
}
