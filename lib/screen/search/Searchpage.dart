// lib/screen/search/Searchpage.dart
import 'dart:async';
import 'dart:io'; // ✅ เพิ่มสำหรับ Image.file
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:main/screen/Option/Setting_page.dart';
import 'package:main/databaseSearch.dart';

import 'package:main/screen/search/AddMenuScreen.dart';
import 'package:main/screen/search/menu_detail.dart';
import 'package:main/screen/search/custom_menu_detail.dart'; // ⬅ ใช้หน้า custom

import 'package:main/services/custom_menus_repo.dart';
import 'package:main/services/custom_menu_service.dart';   // ⬅ ใช้ดึงเมนู guest
import 'package:main/provider/session_provider.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  // แหล่งข้อมูล
  List<Map<String, dynamic>> _dbAll = [];      // ทั้งหมดจาก Database
  List<Map<String, dynamic>> _userAll = [];    // ทั้งหมดจากผู้ใช้ (login/guest)
  List<Map<String, dynamic>> _filtered = [];   // หลังฟิลเตอร์

  bool _loading = true;

  // แท็บปัจจุบัน: 'db' | 'mine'
  String _tab = 'db';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);

    // 1) ฐานข้อมูลหลัก
    final dbAll = await _getAllFromDatabase();

    // 2) ของฉัน (แยก login / guest)
    final sp = context.read<SessionProvider>();
    final uid = sp.isLoggedIn ? sp.ownerUid : null;

    List<Map<String, dynamic>> mine;
    if (sp.isLoggedIn && uid != null) {
      // login: Firestore
      mine = await CustomMenusRepo.instance.getRecentCustomMenus(uid: uid, limit: 1000);
    } else {
      // guest: SQLite -> normalize ให้มี Calorie/Sugar + menuData
      final rows = await CustomMenuService.getGuestMenus();
      mine = rows.map((r) {
        final sel = CustomMenuService.toHomeSelection(r);
        final nd = (sel['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
        final g  = (nd['sugar_nutrition'] ?? nd['nosugar_nutrition'] ?? {}) as Map<String, dynamic>;
        return {
          'menuName': sel['menuName'] ?? '',
          'Calorie' : _asNum(g['Calorie']),
          'Sugar'   : _asNum(g['Sugar']),
          'menuData': sel['menuData'] ?? const {},
          '_guestId': r['id'], // เผื่อไปแก้ไข/ลบต่อ
          // เผื่อมีรูป local จาก guest
          'imagePath': sel['imagePath'],
          'imageUrl' : sel['imageUrl'],
        };
      }).toList();
    }

    setState(() {
      _dbAll = _sortByName(dbAll);
      _userAll = _sortByName(mine);
      _applyFilter(_searchCtrl.text.trim());
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _getAllFromDatabase() async {
    // ใช้ searchMenus('') เพื่อดึงก้อนแรกทั้งหมด
    final all = await DatabaseSearch.searchMenus('');
    return all;
  }

  List<Map<String, dynamic>> _sortByName(List<Map<String, dynamic>> rows) {
    final copy = List<Map<String, dynamic>>.from(rows);
    copy.sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
    return copy;
  }

  String _nameOf(Map<String, dynamic> row) {
    return (row['Thai_Name'] ??
        row['Foodname'] ??
        row['menu_name'] ??
        row['menuName'] ??
        '')
        .toString();
  }

  void _applyFilter(String keyword) {
    final q = _norm(keyword);
    final source = (_tab == 'db') ? _dbAll : _userAll;

    if (q.isEmpty) {
      _filtered = source;
    } else {
      _filtered = source.where((row) {
        final name = _norm(_nameOf(row));
        return name.contains(q);
      }).toList();
    }
  }

  void _onSearchChanged(String keyword) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _applyFilter(keyword));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- เพิ่มเมนูใหม่ ----------
  Future<void> _openAddMenu() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddMenuScreen(), // สร้างใหม่เท่านั้น
      ),
    );

    if (!mounted) return;

    // ถ้าหน้า Add ส่ง true กลับมา → รีโหลด “ของฉัน”
    if (result == true) {
      await _reloadMine();
      setState(() => _applyFilter(_searchCtrl.text.trim()));
    }
  }

  Future<void> _reloadMine() async {
    final sp = context.read<SessionProvider>();
    final uid = sp.isLoggedIn ? sp.ownerUid : null;

    if (sp.isLoggedIn && uid != null) {
      final mine = await CustomMenusRepo.instance.getRecentCustomMenus(uid: uid, limit: 1000);
      _userAll = _sortByName(mine);
    } else {
      final rows = await CustomMenuService.getGuestMenus();
      final mine = rows.map((r) {
        final sel = CustomMenuService.toHomeSelection(r);
        final nd = (sel['menuData']?['nutrition_data'] ?? {}) as Map<String, dynamic>;
        final g  = (nd['sugar_nutrition'] ?? nd['nosugar_nutrition'] ?? {}) as Map<String, dynamic>;
        return {
          'menuName': sel['menuName'] ?? '',
          'Calorie' : _asNum(g['Calorie']),
          'Sugar'   : _asNum(g['Sugar']),
          'menuData': sel['menuData'] ?? const {},
          '_guestId': r['id'],
          'imagePath': sel['imagePath'],
          'imageUrl' : sel['imageUrl'],
        };
      }).toList();
      _userAll = _sortByName(mine);
    }
  }

  // ---------- Normalize ----------
  String _norm(String raw) {
    var s = raw.trim().toLowerCase();

    // ตัดวรรณยุกต์ไทย
    final thaiMarks = RegExp(r'[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]');
    s = s.replaceAll(thaiMarks, '');

    // ตัดช่องว่างและสัญลักษณ์ทั่วไป (ใช้สตริงปกติ + escape ให้ถูกต้อง)
    final symbols = RegExp("[\\s\\.\\-_/(){}\\[\\],;:!@#%^&*+=|\"'`~]");
    s = s.replaceAll(symbols, '');

    return s;
  }

  // ---------- เปิดรายละเอียด ----------
  Future<void> _openDetail(Map<String, dynamic> row) async {
    final String menuName = _nameOf(row).isEmpty ? 'ไม่มีชื่อเมนู' : _nameOf(row);
    final String menuCodeNo =
    (row['Menu_Code_No'] ?? row['Code_No'] ?? row['code_no'] ?? '').toString();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuDetailPage(
          menuName: menuName,
          menuCodeNo: menuCodeNo,
          initialRow: row,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) Navigator.pop(context, result);
  }

  Future<void> _openMyMenu(Map<String, dynamic> e) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomMenuDetailPage(
          item: e,
          fallbackAsset: 'assets/icon/spoon.jpg',
        ),
      ),
    );

    if (!mounted) return;

    // แก้ไข/ลบ -> true => รีโหลด "ของฉัน"
    if (result == true) {
      await _reloadMine();
      setState(() => _applyFilter(_searchCtrl.text.trim()));
      return;
    }

    // ✅ ยืนยันเลือกเมนู -> ส่ง payload กลับไปหน้าเดิม (เช่น Home)
    if (result is Map) {
      Navigator.pop(context, result);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: bottomNav(context),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openAddMenu,
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มเมนูใหม่'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),

      appBar: AppBar(
        title: const Text('ค้นหา'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            // ค้นหา
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'พิมพ์คำค้นหา',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 10),

            // แถบสลับ
            _segmentedTabs(),
            const SizedBox(height: 8),

            // รายการ
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                child: Text(
                  _tab == 'mine'
                      ? 'ยังไม่มีเมนูที่เพิ่มเอง'
                      : 'ไม่มีรายการ',
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = _filtered[index];
                  final name = _nameOf(row);

                  // อ่านค่า Calorie/Sugar แบบยืดหยุ่น (มีได้ทั้งบนสุดหรือใน menuData)
                  final cal  = _readCalorie(row);
                  final sug  = _readSugar(row);

                  final onTap = () {
                    if (_tab == 'mine') {
                      _openMyMenu(row);
                    } else {
                      _openDetail(row);
                    }
                  };

                  return InkWell(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ รูป thumbnail ตามแท็บ
                          _thumbForRow(row),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 22,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics:
                                    const BouncingScrollPhysics(),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'แคลอรี่: ${cal.toInt()} kcal',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'น้ำตาล: ${sug.toStringAsFixed(1)} g',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right,
                              size: 18, color: Colors.black45),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Tabs UI ----------
  Widget _segmentedTabs() {
    final pill = (String text, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (selected) return;
            setState(() {
              _tab = (text == 'เมนู') ? 'db' : 'mine';
              _applyFilter(_searchCtrl.text.trim());
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFD7EEFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black87 : Colors.black54,
              ),
            ),
          ),
        ),
      );
    };

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          pill('เมนู', _tab == 'db', () {}),
          pill('เมนูของฉัน', _tab == 'mine', () {}),
        ],
      ),
    );
  }

  // ---------- Utils ----------
  static double _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  double _readCalorie(Map<String, dynamic> row) {
    if (row['Calorie'] != null) return _asNum(row['Calorie']);
    final md = row['menuData'] as Map<String, dynamic>?;
    final nd = md?['nutrition_data'] as Map<String, dynamic>?;
    final g  = (nd?['sugar_nutrition'] ?? nd?['nosugar_nutrition']) as Map<String, dynamic>?;
    return _asNum(g?['Calorie']);
  }

  double _readSugar(Map<String, dynamic> row) {
    if (row['Sugar'] != null) return _asNum(row['Sugar']);
    final md = row['menuData'] as Map<String, dynamic>?;
    final nd = md?['nutrition_data'] as Map<String, dynamic>?;
    final g  = (nd?['sugar_nutrition'] ?? nd?['nosugar_nutrition']) as Map<String, dynamic>?;
    return _asNum(g?['Sugar']);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ รูป thumbnail: เมนู = spoon.jpg, เมนูของฉัน = รูปผู้ใช้ (หรือ spoon.jpg ถ้าไม่มี)
  Widget _thumbForRow(Map<String, dynamic> row) {
    const double size = 40;
    Widget fallback() => Image.asset(
      'assets/icon/spoon.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );

    // แท็บ “เมนู” → ใช้ช้อนตายตัว
    if (_tab == 'db') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: fallback(),
      );
    }

    // แท็บ “เมนูของฉัน”
    final dynamic raw =
        row['imageUrl'] ?? row['image_path'] ?? row['imagePath']; // รองรับหลาย key
    final String v = (raw ?? '').toString();

    Widget child;
    if (v.isEmpty) {
      child = fallback();
    } else if (v.startsWith('http://') || v.startsWith('https://')) {
      child = Image.network(
        v,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else if (v.startsWith('/')) {
      child = Image.file(
        File(v),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else {
      child = fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: child,
    );
  }

  // ---------- Bottom nav ----------
  Widget bottomNav(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFFEFFFFF),
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.grey,
      currentIndex: 1,
      onTap: (index) async {
        if (index == 0) {
          Navigator.pop(context);
        } else if (index == 2) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'หน้าหลัก'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'ค้นหา'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
      ],
    );
  }
}
