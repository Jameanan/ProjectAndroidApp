import 'package:flutter/material.dart';
import 'package:main/databaseSearch.dart';

class MenuDetailPage extends StatefulWidget {
  final String menuName;
  final String menuCodeNo;
  final Map<String, dynamic>? initialRow;

  // รองรับส่งโภชนาการตรง ๆ (เช่น recent/custom)
  final Map<String, dynamic>? withSugarOverride;
  final Map<String, dynamic>? noSugarOverride;

  const MenuDetailPage({
    Key? key,
    required this.menuName,
    required this.menuCodeNo,
    this.initialRow,
    this.withSugarOverride,
    this.noSugarOverride,
  }) : super(key: key);

  @override
  State<MenuDetailPage> createState() => _MenuDetailPageState();
}

class _MenuDetailPageState extends State<MenuDetailPage> {
  bool useNoSugar = false;

  Map<String, dynamic>? withSugarData;
  Map<String, dynamic>? noSugarData;
  bool isLoading = true;
  String? errorMsg;

  bool get _hasOverride =>
      widget.withSugarOverride != null || widget.noSugarOverride != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_hasOverride) {
      setState(() {
        withSugarData = widget.withSugarOverride;
        noSugarData = widget.noSugarOverride;
        isLoading = false;
      });
      return;
    }
    await _loadMenuData();
  }

  Future<void> _loadMenuData() async {
    try {
      final data = await DatabaseSearch.getMenuDetails(widget.menuCodeNo);
      if (!mounted) return;
      setState(() {
        withSugarData = data?['withSugar'] as Map<String, dynamic>?;
        noSugarData = data?['noSugar'] as Map<String, dynamic>?;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMsg = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentData = useNoSugar ? noSugarData : withSugarData;
    final initialCalorie = (widget.initialRow?['Calorie'] ?? '-').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.menuName),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: isLoading
          ? _buildLoading(initialCalorie)
          : (errorMsg != null
          ? _buildError(errorMsg!)
          : _buildContent(currentData)),
    );
  }

  // -------- UI blocks --------

  Widget _buildLoading(String initialCalorie) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _fixedHeroImage(),
          const SizedBox(height: 16),
          Text('กำลังโหลดรายละเอียดเมนู…',
              style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('พลังงาน (เบื้องต้น): ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text('$initialCalorie kcal'),
            ],
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล\n$msg',
            textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic>? currentData) {
    final rawString = useNoSugar
        ? (noSugarData?['Raw_material_Nosugar'] ?? '')
        : (withSugarData?['Raw_material'] ?? '');

    final ingredientsList = rawString
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String getCalorie(Map<String, dynamic>? d) =>
        useNoSugar
            ? (d?['Calorie_Nosugar'] ?? '-').toString()
            : (d?['Calorie'] ?? '-').toString();
    String getSugar(Map<String, dynamic>? d) =>
        useNoSugar ? (d?['No_sugar'] ?? '-').toString() : (d?['Sugar'] ?? '-').toString();
    String getCarb(Map<String, dynamic>? d) =>
        useNoSugar ? (d?['Carb_Nosugar'] ?? '-').toString() : (d?['Carb'] ?? '-').toString();
    String getProtein(Map<String, dynamic>? d) => (d?['Protein'] ?? '-').toString();
    String getFat(Map<String, dynamic>? d) => (d?['Fat'] ?? '-').toString();
    String getFiber(Map<String, dynamic>? d) => (d?['Fiber'] ?? '-').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _fixedHeroImage(),
          const SizedBox(height: 16),

          // ✅ ปุ่มเลือกสูตร — เปิดได้เสมอทั้งสองปุ่ม
          _SugarChoiceRow(
            useNoSugar: useNoSugar,
            onChanged: (v) => setState(() => useNoSugar = v),
          ),

          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ข้อมูลโภชนาการ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _nutritionBox('fire.png',       getCalorie(currentData), 'พลังงาน', Colors.lightBlue.shade100),
                _nutritionBox('sugar-cube.png', getSugar(currentData),   'น้ำตาล',  Colors.pink.shade100),
                _nutritionBox('proteins.png',   getProtein(currentData), 'โปรตีน',  Colors.green.shade100),
                _nutritionBox('trans-fat.png',  getFat(currentData),     'ไขมัน',   Colors.orange.shade100),
                _nutritionBox('fiber.png',      getFiber(currentData),   'ไฟเบอร์', Colors.brown.shade100),
                _nutritionBox('carb.png',       getCarb(currentData),    'คาร์บ',   Colors.purple.shade100),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'วัตถุดิบ',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: ingredientsList.isEmpty
                ? const Text('—')
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ingredientsList
                  .map((item) => Text('• $item',
                  style: const TextStyle(height: 1.4)))
                  .toList(),
            ),
          ),

          const SizedBox(height: 32),

          // === ปุ่มยืนยันแบบกว้างเต็มขอบ ===
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmAndPop,
              icon: const Icon(Icons.check),
              label: const Text('ยืนยัน'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14, // สูงขึ้นเล็กน้อย
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // รูปช้อนส้อมด้านบน (คงเดิม)
  Widget _fixedHeroImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/icon/spoon.jpg',
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _nutritionBox(String iconName, String valueText, String label, Color bgColor) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/icon/$iconName', width: 36, height: 36),
          const SizedBox(height: 8),
          Text(valueText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.black87)),
        ],
      ),
    );
  }

  // -------- Actions --------

  Future<void> _confirmAndPop() async {
    if (withSugarData == null && noSugarData == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีข้อมูลเมนู กรุณารอสักครู่')),
      );
      return;
    }

    final normalizedMenuData = _buildNormalizedMenuData(
      withSugar: withSugarData,
      noSugar: noSugarData,
    );

    Navigator.pop(context, {
      'menuName': widget.menuName,
      'imagePath': 'assets/icon/spoon.jpg',
      'menuData': normalizedMenuData,
      'useNoSugar': useNoSugar,
    });
  }

  /// รวมโภชนาการให้อยู่รูปแบบเดียวกับที่หน้าอื่นใช้
  Map<String, dynamic> _buildNormalizedMenuData({
    Map<String, dynamic>? withSugar,
    Map<String, dynamic>? noSugar,
  }) {
    double _toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final s = v.toString();
      final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
      return m == null ? 0.0 : (double.tryParse(m.group(0)!) ?? 0.0);
    }

    List<String> _splitRaw(dynamic v) {
      final s = (v ?? '').toString();
      if (s.isEmpty) return const [];
      return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    final sugar = {
      'Calorie': _toD(withSugar?['Calorie']),
      'Sugar': _toD(withSugar?['Sugar']),
      'Protein': _toD(withSugar?['Protein']),
      'Fat': _toD(withSugar?['Fat']),
      'Fiber': _toD(withSugar?['Fiber']),
      'Carb': _toD(withSugar?['Carb']),
      'Raw_materials': _splitRaw(withSugar?['Raw_material']),
    };

    final nosugar = {
      'Calorie': _toD(noSugar?['Calorie_Nosugar'] ?? withSugar?['Calorie']),
      'Sugar': _toD(noSugar?['No_sugar'] ?? withSugar?['Sugar']),
      'Protein': _toD(noSugar?['Protein'] ?? withSugar?['Protein']),
      'Fat': _toD(noSugar?['Fat'] ?? withSugar?['Fat']),
      'Fiber': _toD(noSugar?['Fiber'] ?? withSugar?['Fiber']),
      'Carb': _toD(noSugar?['Carb_Nosugar'] ?? withSugar?['Carb']),
      'Raw_materials': _splitRaw(noSugar?['Raw_material_Nosugar'] ?? withSugar?['Raw_material']),
    };

    return {
      'nutrition_data': {
        'sugar_nutrition': sugar,
        'nosugar_nutrition': nosugar,
      }
    };
  }
}

/// แถวปุ่มเลือกสูตร — เปิดได้เสมอทั้งสองด้าน
class _SugarChoiceRow extends StatelessWidget {
  final bool useNoSugar;
  final ValueChanged<bool> onChanged;

  const _SugarChoiceRow({
    required this.useNoSugar,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('คุณต้องการสูตรอาหารแบบไหน',
            style: TextStyle(fontSize: 16, color: Colors.grey[700])),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('ปรุงโดยมีน้ำตาล'),
              selected: !useNoSugar,
              onSelected: (_) => onChanged(false),
              selectedColor: const Color(0xFFEFF6FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            ChoiceChip(
              label: const Text('ปรุงโดยไม่มีน้ำตาล'),
              selected: useNoSugar,
              onSelected: (_) => onChanged(true),
              selectedColor: const Color(0xFFEFF6FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}
