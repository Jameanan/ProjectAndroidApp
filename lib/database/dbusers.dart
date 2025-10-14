import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBusers {
  // ---------- singleton ----------
  static final DBusers instance = DBusers._init();
  static Database? _database;
  DBusers._init();

  // ---------- constants ----------
  static const String GUEST_USERNAME = '__guest__'; // ใช้ค่าตายตัวเสมอ

  final String foodLogsTable    = 'food_logs';
  final String dailyBloodTable  = 'daily_blood_sugar';
  final String customMenusTable = 'custom_menus';

  // ---------- bootstrap ----------
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('user.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    // LOGS
    await db.execute('''
      CREATE TABLE $foodLogsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username   TEXT NOT NULL,
        log_date   TEXT NOT NULL,
        menu_code_no TEXT,
        menu_name  TEXT,
        image_path TEXT,
        with_sugar INTEGER NOT NULL,
        qty        REAL NOT NULL DEFAULT 1.0,
        calorie    REAL NOT NULL,
        sugar      REAL NOT NULL,
        protein    REAL NOT NULL,
        fat        REAL NOT NULL,
        fiber      REAL NOT NULL,
        carb       REAL NOT NULL,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_food_logs_user_date ON $foodLogsTable(username, log_date)',
    );

    // BLOOD SUGAR
    await db.execute('''
      CREATE TABLE $dailyBloodTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username   TEXT NOT NULL,
        log_date   TEXT NOT NULL,
        value      REAL NOT NULL,
        unit       TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(username, log_date)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_blood_user_date ON $dailyBloodTable(username, log_date)',
    );

    // CUSTOM MENUS
    await db.execute('''
      CREATE TABLE $customMenusTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username    TEXT NOT NULL,
        name        TEXT NOT NULL,
        image_path  TEXT,
        ingredients TEXT,
        calorie     REAL NOT NULL,
        sugar       REAL NOT NULL,
        protein     REAL NOT NULL,
        fat         REAL NOT NULL,
        fiber       REAL NOT NULL,
        carb        REAL NOT NULL,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_custom_menus_user_name ON $customMenusTable(username, name)',
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // คง logic upgrade เดิมไว้ เพื่อให้ผู้ใช้เก่าอัปเกรด schema ได้
    if (oldVersion < 3) {
      try {
        await db.execute('''
          CREATE TABLE $foodLogsTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username   TEXT NOT NULL,
            log_date   TEXT NOT NULL,
            menu_code_no TEXT,
            menu_name  TEXT,
            image_path TEXT,
            with_sugar INTEGER NOT NULL,
            qty        REAL NOT NULL DEFAULT 1.0,
            calorie    REAL NOT NULL,
            sugar      REAL NOT NULL,
            protein    REAL NOT NULL,
            fat        REAL NOT NULL,
            fiber      REAL NOT NULL,
            carb       REAL NOT NULL,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_food_logs_user_date ON $foodLogsTable(username, log_date)',
        );
      } catch (_) {}
    }

    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE $dailyBloodTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username   TEXT NOT NULL,
            log_date   TEXT NOT NULL,
            value      REAL NOT NULL,
            unit       TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(username, log_date)
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_daily_blood_user_date ON $dailyBloodTable(username, log_date)',
        );
      } catch (_) {}
    }

    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE $customMenusTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username    TEXT NOT NULL,
            name        TEXT NOT NULL,
            image_path  TEXT,
            ingredients TEXT,
            calorie     REAL NOT NULL,
            sugar       REAL NOT NULL,
            protein     REAL NOT NULL,
            fat         REAL NOT NULL,
            fiber       REAL NOT NULL,
            carb        REAL NOT NULL,
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_custom_menus_user_name ON $customMenusTable(username, name)',
        );
      } catch (_) {}
    }
  }

  // ---------- utils ----------
  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // =================================================================
  // FOOD LOGS (Guest only)
  // =================================================================
  Future<int> insertFoodLog({
    required DateTime day,
    required String menuName,
    String? menuCodeNo,
    String? imagePath,
    required bool with_sugar,
    double qty = 1.0,
    required double calorie,
    required double sugar,
    required double protein,
    required double fat,
    required double fiber,
    required double carb,
  }) async {
    final db = await database;
    final dateOnly = DateTime(day.year, day.month, day.day);
    return db.insert(foodLogsTable, {
      'username': GUEST_USERNAME, // ตายตัว
      'log_date': _ymd(dateOnly),
      'menu_code_no': menuCodeNo,
      'menu_name': menuName,
      'image_path': imagePath,
      'with_sugar': with_sugar ? 1 : 0,
      'qty': qty,
      'calorie': calorie * qty,
      'sugar': sugar * qty,
      'protein': protein * qty,
      'fat': fat * qty,
      'fiber': fiber * qty,
      'carb': carb * qty,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getLogsByDate({
    required DateTime day,
  }) async {
    final db = await database;
    final s = _ymd(DateTime(day.year, day.month, day.day));
    return db.query(
      foodLogsTable,
      where: 'username = ? AND log_date = ?',
      whereArgs: [GUEST_USERNAME, s],
      orderBy: 'id DESC',
    );
  }

  Future<Map<String, double>> getDailyTotals({
    required DateTime day,
  }) async {
    final db = await database;
    final s = _ymd(DateTime(day.year, day.month, day.day));
    final res = await db.rawQuery('''
      SELECT 
        IFNULL(SUM(calorie),0) AS cal,
        IFNULL(SUM(sugar),0)   AS sugar,
        IFNULL(SUM(protein),0) AS protein,
        IFNULL(SUM(fat),0)     AS fat,
        IFNULL(SUM(fiber),0)   AS fiber,
        IFNULL(SUM(carb),0)    AS carb
      FROM $foodLogsTable
      WHERE username = ? AND log_date = ?
    ''', [GUEST_USERNAME, s]);

    final row = res.first;
    double _toD(Object? v) => (v is num) ? v.toDouble() : 0.0;

    return {
      'cal': _toD(row['cal']),
      'sugar': _toD(row['sugar']),
      'protein': _toD(row['protein']),
      'fat': _toD(row['fat']),
      'fiber': _toD(row['fiber']),
      'carb': _toD(row['carb']),
    };
  }

  Future<int> deleteFoodLog(int id) async {
    final db = await database;
    return db.delete(foodLogsTable, where: 'id = ?', whereArgs: [id]);
  }

  // =================================================================
  // DAILY BLOOD SUGAR (Guest only)
  // =================================================================
  Future<Map<String, dynamic>?> getDailyBloodSugar({
    required DateTime day,
  }) async {
    final db = await database;
    final s = _ymd(DateTime(day.year, day.month, day.day));
    final res = await db.query(
      dailyBloodTable,
      where: 'username = ? AND log_date = ?',
      whereArgs: [GUEST_USERNAME, s],
      limit: 1,
    );
    return res.isEmpty ? null : res.first;
  }

  Future<void> upsertDailyBloodSugar({
    required double value,
    String unit = "mg/dL",
    DateTime? at,
  }) async {
    final db = await database;
    final ts = (at ?? DateTime.now());
    final dateOnly = DateTime(ts.year, ts.month, ts.day);
    final ymd = _ymd(dateOnly);
    final tsIso = ts.toIso8601String();

    final updated = await db.update(
      dailyBloodTable,
      {
        'value': value,
        'unit': unit,
        'created_at': tsIso,
      },
      where: 'username = ? AND log_date = ?',
      whereArgs: [GUEST_USERNAME, ymd],
    );

    if (updated == 0) {
      await db.insert(dailyBloodTable, {
        'username': GUEST_USERNAME,
        'log_date': ymd,
        'value': value,
        'unit': unit,
        'created_at': tsIso,
      });
    }
  }

  Future<void> setDailyBloodSugar({
    required DateTime day,
    required double value,
    String unit = "mg/dL",
  }) async {
    await upsertDailyBloodSugar(value: value, unit: unit, at: day);
  }

  Future<List<Map<String, dynamic>>> getDailyBloodSugarRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await database;
    final s = _ymd(DateTime(start.year, start.month, start.day));
    final e = _ymd(DateTime(end.year, end.month, end.day));
    return db.query(
      dailyBloodTable,
      where: 'username = ? AND log_date BETWEEN ? AND ?',
      whereArgs: [GUEST_USERNAME, s, e],
      orderBy: 'log_date DESC',
    );
  }

  // =================================================================
  // CUSTOM MENUS (Guest only)
  // =================================================================
  Future<int> insertCustomMenu({
    required String name,
    String? imagePath,
    String? ingredients,
    required double calorie,
    required double sugar,
    required double protein,
    required double fat,
    required double fiber,
    required double carb,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert(customMenusTable, {
      'username': GUEST_USERNAME,
      'name': name,
      'image_path': imagePath,
      'ingredients': ingredients,
      'calorie': calorie,
      'sugar': sugar,
      'protein': protein,
      'fat': fat,
      'fiber': fiber,
      'carb': carb,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> updateCustomMenu({
    required int id,
    String? name,
    String? imagePath,
    String? ingredients,
    double? calorie,
    double? sugar,
    double? protein,
    double? fat,
    double? fiber,
    double? carb,
  }) async {
    final db = await database;
    final data = <String, Object?>{
      if (name != null) 'name': name,
      if (imagePath != null) 'image_path': imagePath,
      if (ingredients != null) 'ingredients': ingredients,
      if (calorie != null) 'calorie': calorie,
      if (sugar != null) 'sugar': sugar,
      if (protein != null) 'protein': protein,
      if (fat != null) 'fat': fat,
      if (fiber != null) 'fiber': fiber,
      if (carb != null) 'carb': carb,
      'updated_at': DateTime.now().toIso8601String(),
    };
    return db.update(customMenusTable, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomMenu({required int id}) async {
    final db = await database;
    return db.delete(customMenusTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getCustomMenus({
    String? keyword,
  }) async {
    final db = await database;
    if (keyword == null || keyword.trim().isEmpty) {
      return db.query(
        customMenusTable,
        where: 'username = ?',
        whereArgs: [GUEST_USERNAME],
        orderBy: 'id DESC',
      );
    }
    final k = '%${keyword.trim()}%';
    return db.query(
      customMenusTable,
      where: 'username = ? AND name LIKE ?',
      whereArgs: [GUEST_USERNAME, k],
      orderBy: 'id DESC',
    );
  }

  /// กันชื่อซ้ำ (Guest)
  Future<bool> existsCustomMenuName({
    required String name,
    int? exceptId,
  }) async {
    final db = await database;
    final rows = await db.query(
      customMenusTable,
      columns: ['id'],
      where: (exceptId == null)
          ? 'username = ? AND name = ?'
          : 'username = ? AND name = ? AND id != ?',
      whereArgs: (exceptId == null)
          ? [GUEST_USERNAME, name]
          : [GUEST_USERNAME, name, exceptId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ล้างข้อมูล Guest ทั้งหมด
  Future<void> deleteAllGuestData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(foodLogsTable,    where: 'username = ?', whereArgs: [GUEST_USERNAME]);
      await txn.delete(dailyBloodTable,  where: 'username = ?', whereArgs: [GUEST_USERNAME]);
      await txn.delete(customMenusTable, where: 'username = ?', whereArgs: [GUEST_USERNAME]);
    });
  }
}
