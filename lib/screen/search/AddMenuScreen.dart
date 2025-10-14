// lib/screen/search/AddMenuScreen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:provider/provider.dart';
import 'package:main/services/custom_menu_service.dart';
import 'package:main/services/custom_menus_repo.dart';
import 'package:main/provider/session_provider.dart';

class AddMenuScreen extends StatefulWidget {
  final Set<String>? reservedNames;
  final String? forceUid;

  // ====== โหมดแก้ไข ======
  final String? editingDocId;         // login (Firestore)
  final int? editingGuestRowId;       // guest (SQLite)
  final InitialValues? initialValues;

  const AddMenuScreen({
    super.key,
    this.reservedNames,
    this.forceUid,
    this.editingDocId,
    this.editingGuestRowId,
    this.initialValues,
  });

  bool get isEditing => editingDocId != null || editingGuestRowId != null;

  @override
  State<AddMenuScreen> createState() => _AddMenuScreenState();
}

class _AddMenuScreenState extends State<AddMenuScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final ingredientsCtrl = TextEditingController();
  final calorieCtrl = TextEditingController();
  final sugarCtrl = TextEditingController();
  final proteinCtrl = TextEditingController();
  final fatCtrl = TextEditingController();
  final fiberCtrl = TextEditingController();
  final carbCtrl = TextEditingController();

  final _numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  // ===== รูป (เฉพาะตอนเพิ่มของ login) =====
  XFile? _picked;                // รูปที่ผู้ใช้เลือก
  bool _uploading = false;       // สถานะอัปโหลด

  @override
  void initState() {
    super.initState();
    _prefillIfEditing();
  }

  void _prefillIfEditing() {
    final v = widget.initialValues;
    if (!widget.isEditing || v == null) return;
    nameCtrl.text = v.name;
    ingredientsCtrl.text = v.ingredients.join('\n');
    calorieCtrl.text = _fmt(v.calorie);
    sugarCtrl.text = _fmt(v.sugar);
    proteinCtrl.text = _fmt(v.protein);
    fatCtrl.text = _fmt(v.fat);
    fiberCtrl.text = _fmt(v.fiber);
    carbCtrl.text = _fmt(v.carb);
  }

  String _fmt(num n) => (n == n.roundToDouble()) ? n.toInt().toString() : n.toString();

  @override
  void dispose() {
    nameCtrl.dispose();
    ingredientsCtrl.dispose();
    calorieCtrl.dispose();
    sugarCtrl.dispose();
    proteinCtrl.dispose();
    fatCtrl.dispose();
    fiberCtrl.dispose();
    carbCtrl.dispose();
    super.dispose();
  }

  InputDecoration _box({String? suffix}) => InputDecoration(
    filled: true,
    fillColor: Colors.grey[200],
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    suffixText: suffix,
    suffixStyle: const TextStyle(fontSize: 15, color: Colors.black87),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
  );

  Widget _numField(TextEditingController c, {required String unit}) => TextFormField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: _numFmt,
    decoration: _box(suffix: unit),
    validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาใส่ข้อมูลด้วย' : null,
  );

  double _toD(String s) => double.tryParse(s.trim()) ?? 0.0;

  String _norm(String raw) {
    var s = raw.trim().toLowerCase();
    final thaiMarks = RegExp(r'[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]');
    s = s.replaceAll(thaiMarks, '');
    final symbols = RegExp("[\\s\\.\\-_/(){}\\[\\],;:!@#%^&*+=|\"'`~]");
    s = s.replaceAll(symbols, '');
    return s;
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _picked = x);
  }

  Future<void> _onSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final kcal = _toD(calorieCtrl.text);
    final sugar = _toD(sugarCtrl.text);
    final protein = _toD(proteinCtrl.text);
    final fat = _toD(fatCtrl.text);
    final fiber = _toD(fiberCtrl.text);
    final carb = _toD(carbCtrl.text);

    final ingredientsList = ingredientsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final nutrition = {
      'Calorie': kcal,
      'Sugar': sugar,
      'Protein': protein,
      'Fat': fat,
      'Fiber': fiber,
      'Carb': carb,
      'Raw_materials': ingredientsList,
    };
    final menuData = {
      'nutrition_data': {
        'sugar_nutrition': nutrition,
        'nosugar_nutrition': nutrition,
      },
      'Raw_materials': ingredientsList,
    };

    final sp = context.read<SessionProvider>();
    final uid = widget.forceUid ?? (sp.isLoggedIn ? sp.ownerUid : null);

    // ===== โหมดแก้ไข =====
    if (widget.isEditing) {
      if (uid != null && widget.editingDocId != null) {
        try {
          final newName = nameCtrl.text.trim();
          final oldName = widget.initialValues?.name ?? '';
          final changed = _norm(newName) != _norm(oldName);

          await CustomMenusRepo.instance.updateMenu(
            uid: uid,
            docId: widget.editingDocId!,
            newName: newName,
            menuData: menuData,
            checkDuplicate: changed,
          );
          _toast('บันทึกการแก้ไขแล้ว');
          if (!mounted) return;
          Navigator.pop(context, true);
        } catch (e) {
          _toast(e.toString().replaceFirst('Exception: ', ''));
        }
        return;
      }

      if (widget.editingGuestRowId != null) {
        await CustomMenuService.updateGuestMenu(
          id: widget.editingGuestRowId!,
          name: nameCtrl.text.trim(),
          imagePath: null,
          ingredients: ingredientsCtrl.text.trim(),
          calorie: kcal,
          sugar: sugar,
          protein: protein,
          fat: fat,
          fiber: fiber,
          carb: carb,
        );
        _toast('บันทึกการแก้ไขแล้ว');
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
    }

    // ===== เพิ่มใหม่ =====
    final n = _norm(nameCtrl.text);
    if (widget.reservedNames?.contains(n) == true) {
      _toast('มีเมนูนี้อยู่แล้ว');
      return;
    }

    // Guest → SQLite (ไม่มีรูปอัปโหลด)
    if (!sp.isLoggedIn) {
      await CustomMenuService.addGuestMenu(
        name: nameCtrl.text.trim(),
        imagePath: null,
        ingredients: ingredientsCtrl.text.trim(),
        calorie: kcal,
        sugar: sugar,
        protein: protein,
        fat: fat,
        fiber: fiber,
        carb: carb,
      );
      _toast('บันทึกในโหมดทดลองแล้ว');
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }

    // Login → อัปโหลดรูป (ถ้ามี) แล้วเก็บ "imagePath" เป็น URL ที่ได้
    String? imagePath; // <- ใช้คีย์เดียวทั่วระบบ
    try {
      if (_picked != null) {
        setState(() => _uploading = true);
        imagePath = await CustomMenusRepo.instance.uploadMenuImage(
          uid: uid!,
          file: File(_picked!.path),
          // ใช้ docId เป็นชื่อ normalize เพื่อให้ไฟล์สอดคล้องกับเอกสาร
          targetId: _norm(nameCtrl.text.trim()),
        );
      }

      await CustomMenusRepo.instance.addMenuIfNotExists(
        uid: uid!,
        menuName: nameCtrl.text.trim(),
        menuData: menuData,
        // ✅ เก็บเป็น imagePath (URL) เพียงคีย์เดียว
        imagePath: imagePath,
      );
      _toast('เพิ่มเมนูสำเร็จ');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEditing;
    final sp = context.watch<SessionProvider>();
    final isLogin = sp.isLoggedIn;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'แก้ไขเมนู' : 'เพิ่มเมนูใหม่')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== รูปเมนู (เฉพาะ "เพิ่มใหม่" + login) =====
                    if (!isEdit && isLogin) ...[
                      _label('รูปเมนู (ไม่บังคับ)'),
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: _picked == null
                              ? const Text('แตะเพื่อเลือกรูป')
                              : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_picked!.path),
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _label('ชื่อเมนู'),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: _box(),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'ต้องมีชื่อเมนู' : null,
                    ),
                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F7FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E7FF)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ตัวอย่างการใส่วัตถุดิบ',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'ข้าวสวย 1 ถ้วย\nอกไก่ย่าง 100 กรัม\nพริก 3 เม็ด\nกระเทียม 2 กลีบ\nน้ำมันพืช 1 ช้อนชา',
                            style: TextStyle(fontSize: 13, color: Colors.black54),
                          ),
                          // (ตัดปุ่ม "เติมตัวอย่าง" ออก)
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _label('รายการวัตถุดิบ'),
                    SizedBox(
                      height: 150,
                      child: TextFormField(
                        controller: ingredientsCtrl,
                        maxLines: null,
                        expands: true,
                        keyboardType: TextInputType.multiline,
                        decoration: _box(),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'ต้องมีรายการวัตถุดิบ' : null,
                      ),
                    ),

                    const SizedBox(height: 10),
                    // ===== คอมเมนต์สีแดงตามที่ขอ =====
                    const Text(
                      'ข้อมูลด้านล่างหากช่องไหนไม่ต้องการใส่ข้อมูลให้ใส่ 0',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 14),

                    _label('พลังงาน'),
                    _numField(calorieCtrl, unit: 'kcal'),
                    const SizedBox(height: 16),

                    _label('น้ำตาลในอาหาร'),
                    _numField(sugarCtrl, unit: 'กรัม'),
                    const SizedBox(height: 16),

                    _label('โปรตีน'),
                    _numField(proteinCtrl, unit: 'กรัม'),
                    const SizedBox(height: 16),

                    _label('ไขมัน'),
                    _numField(fatCtrl, unit: 'กรัม'),
                    const SizedBox(height: 16),

                    _label('ไฟเบอร์'),
                    _numField(fiberCtrl, unit: 'กรัม'),
                    const SizedBox(height: 16),

                    _label('คาร์บ'),
                    _numField(carbCtrl, unit: 'กรัม'),
                    const SizedBox(height: 22),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _uploading
                            ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                            : Icon(isEdit ? Icons.save : Icons.add, size: 22),
                        label: Text(
                          isEdit ? 'บันทึก' : 'เพิ่มเมนูใหม่',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC52E),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        onPressed: _uploading ? null : _onSubmit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// โครงสร้างค่าตั้งต้นเวลาแก้ไข (public)
class InitialValues {
  final String name;
  final List<String> ingredients;
  final double calorie, sugar, protein, fat, fiber, carb;

  InitialValues({
    required this.name,
    required this.ingredients,
    required this.calorie,
    required this.sugar,
    required this.protein,
    required this.fat,
    required this.fiber,
    required this.carb,
  });
}
