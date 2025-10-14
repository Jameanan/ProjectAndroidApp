// lib/databaseSearch.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseSearch {
  static Database? _database;

  // ชื่อไฟล์ในเครื่อง & path ใน assets (อย่าลืมประกาศใน pubspec.yaml)
  static const _dbFileName = "menuV2.db";
  static const _assetPath  = "assets/databasemenu/menuV2.db";

  // ====== เวอร์ชันของ "ไฟล์ assets" (เปลี่ยนเลขนี้เมื่อคุณอัปเดตไฟล์ menuV2.db ใน assets) ======
  static const int _assetDbVersion = 2; // <— เพิ่มเลขทุกครั้งที่เปลี่ยนไฟล์ DB ใน assets
  static const String _verSidecarName = "menuV2.ver"; // ไฟล์ตัวบอกเวอร์ชันที่ Documents

  /// เปิด DB (ถ้าไม่มีในเครื่องจะคัดลอกจาก assets มาก่อน)
  static Future<Database> getDatabase({int schemaVersion = 1}) async {
    if (_database != null) return _database!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath  = join(dir.path, _dbFileName);
    final verPath = join(dir.path, _verSidecarName);

    // --- ตรวจเวอร์ชันไฟล์ assets ด้วย sidecar ---
    final verFile = File(verPath);
    int currentLocalAssetVer = 0;
    if (await verFile.exists()) {
      try {
        currentLocalAssetVer = int.parse(await verFile.readAsString());
      } catch (_) {
        currentLocalAssetVer = 0;
      }
    }

    // ถ้าเลขเวอร์ชัน assets เปลี่ยน -> ลบ DB เก่าเพื่อให้คัดลอกใหม่
    if (currentLocalAssetVer != _assetDbVersion && await File(dbPath).exists()) {
      try {
        await File(dbPath).delete();
      } catch (_) {}
    }

    // คัดลอก DB จาก assets ถ้ายังไม่มี
    if (!await File(dbPath).exists()) {
      final data  = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
      // อัปเดตไฟล์เวอร์ชันเคียงข้าง
      await verFile.writeAsString(_assetDbVersion.toString(), flush: true);
    }

    _database = await openDatabase(
      dbPath,
      version: schemaVersion,
      onOpen: (db) async => _ensureIndexes(db),
      onUpgrade: (db, o, n) async => _ensureIndexes(db),
    );
    return _database!;
  }

  /// ใช้เมื่ออยาก “บังคับ” ให้คัดลอกจาก assets ใหม่ (เช่น กดปุ่มล้างแคช)
  static Future<void> forceReplaceFromAssets() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath  = join(dir.path, _dbFileName);
    final verPath = join(dir.path, _verSidecarName);

    if (await File(dbPath).exists()) {
      try { await File(dbPath).delete(); } catch (_) {}
    }
    final data  = await rootBundle.load(_assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(dbPath).writeAsBytes(bytes, flush: true);

    // เขียนเลขเวอร์ชันใหม่ลงไฟล์ sidecar
    await File(verPath).writeAsString(_assetDbVersion.toString(), flush: true);

    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// สร้างดัชนีให้คิวรีเร็วขึ้น (ถ้ายังไม่มี)
  static Future<void> _ensureIndexes(Database db) async {
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_food_menu_code ON food_menu(Menu_Code_No);',
      );
    } catch (e) {
      // ignore: avoid_print
      print('[DB] create index food_menu failed: $e');
    }
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_food_menu_nosugar_code ON food_menu_nosugar(Menu_Code_No);',
      );
    } catch (e) {
      print('[DB] create index food_menu_nosugar failed: $e');
    }
  }

  /// เรียกสักครั้งตอนเริ่มแอปเพื่อเช็คตาราง/คอลัมน์ใน log
  static Future<void> diagnose() async {
    final db = await getDatabase();
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      print('[DB] tables: $tables');

      final cols1 = await db.rawQuery("PRAGMA table_info(food_menu)");
      final cols2 = await db.rawQuery("PRAGMA table_info(food_menu_nosugar)");
      print('[DB] food_menu columns: $cols1');
      print('[DB] food_menu_nosugar columns: $cols2');
    } catch (e, st) {
      print('[DB][diagnose] error: $e\n$st');
    }
  }

  // ---------------------------------------------------------------------------
  // เมธอดที่หน้า Search ใช้
  // ---------------------------------------------------------------------------

  /// ดึง “เมนูทั้งหมด” จากตารางหลัก (กำหนด limit เพื่อความเร็ว)
  static Future<List<Map<String, dynamic>>> getAllMenus({int limit = 3000}) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'food_menu',
        columns: [
          'Menu_Code_No',
          'Thai_Name',
          'Raw_material',
          'Calorie',
          'Sugar',
          'Protein',
          'Fat',
          'Fiber',
          'Carb',
        ],
        limit: limit,
      );
    } catch (e, st) {
      print('[getAllMenus] failed: $e\n$st');
      return [];
    }
  }

  /// ค้นหาเมนูจากตาราง food_menu
  /// ถ้า keyword ว่าง -> คืน “ก้อนแรกทั้งหมด” (เหมือน getAllMenus)
  static Future<List<Map<String, dynamic>>> searchMenus(
      String keyword, {
        int limit = 3000,
      }) async {
    final db = await getDatabase();
    final q = keyword.trim();

    if (q.isEmpty) {
      return getAllMenus(limit: limit);
    }

    // สร้าง pattern สำหรับ LIKE และ escape เครื่องหมายพิเศษ %, _ และ backslash
    String esc(String s) {
      // ต้อง escape backslash ก่อน
      final s1 = s.replaceAll('\\', '\\\\');
      return s1.replaceAll('%', r'\%').replaceAll('_', r'\_');
    }

    final pattern = '%${esc(q)}%';

    try {
      // ค้นหาด้วย Thai_Name (ปรับ where ให้ตรง schema ของคุณได้)
      return await db.query(
        'food_menu',
        columns: [
          'Menu_Code_No',
          'Thai_Name',
          'Raw_material',
          'Calorie',
          'Sugar',
          'Protein',
          'Fat',
          'Fiber',
          'Carb',
        ],
        where: "Thai_Name LIKE ? ESCAPE '\\' COLLATE NOCASE",
        whereArgs: [pattern],
        limit: limit,
      );
    } catch (e, st) {
      print('[searchMenus] query() failed: $e\n$st');
      // fallback rawQuery
      try {
        return await db.rawQuery(
          '''
          SELECT Menu_Code_No, Thai_Name, Raw_material, Calorie, Sugar, Protein, Fat, Fiber, Carb
          FROM food_menu
          WHERE Thai_Name LIKE ? ESCAPE '\\' COLLATE NOCASE
          LIMIT ?
          ''',
          [pattern, limit],
        );
      } catch (e2, st2) {
        print('[searchMenus] fallback rawQuery failed: $e2\n$st2');
        return [];
      }
    }
  }

  /// ดึงรายละเอียดเมนูจาก 2 ตาราง (with sugar / no sugar)
  static Future<Map<String, dynamic>?> getMenuDetails(String code) async {
    final db = await getDatabase();

    final withSugarRows = await db.query(
      'food_menu',
      columns: [
        'Menu_Code_No',
        'Thai_Name',
        'Raw_material',
        'Calorie',
        'Sugar',
        'Protein',
        'Fat',
        'Fiber',
        'Carb',
      ],
      where: 'Menu_Code_No = ?',
      whereArgs: [code],
      limit: 1,
    );

    // กันกรณีฐานข้อมูลบางเครื่องยังไม่มีตาราง nosugar
    List<Map<String, Object?>> noSugarRows = const [];
    try {
      noSugarRows = await db.query(
        'food_menu_nosugar',
        columns: [
          'Menu_Code_No',
          'Thai_Name',
          'Raw_material_Nosugar',
          'Calorie_Nosugar',
          'No_sugar',
          'Protein',
          'Fat',
          'Fiber',
          'Carb_Nosugar',
        ],
        where: 'Menu_Code_No = ?',
        whereArgs: [code],
        limit: 1,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[getMenuDetails] nosugar table not available: $e');
    }

    return {
      'withSugar': withSugarRows.isNotEmpty
          ? Map<String, dynamic>.from(withSugarRows.first)
          : null,
      'noSugar': noSugarRows.isNotEmpty
          ? Map<String, dynamic>.from(noSugarRows.first)
          : null,
    };
  }
}
