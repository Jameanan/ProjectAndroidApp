// lib/services/api_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static String _globalBaseUrl = 'http://172.20.10.4:8000';
  static void setBaseUrl(String url) => _globalBaseUrl = url;
  static String get baseUrlGlobal => _globalBaseUrl;

  final String baseUrl;
  ApiService(this.baseUrl);


  /// POST /predict/ : อัปโหลดรูปให้โมเดลทำนาย
  Future<Map<String, dynamic>> predict({
    required String filePath,
    String? uid,
  }) async {
    final uri = Uri.parse('$baseUrl/predict/');
    final req = http.MultipartRequest('POST', uri)
      ..fields['save_image']  = 'true'
      ..fields['uid']         = uid ?? 'public'
      ..files.add(await http.MultipartFile.fromPath(
        'file', filePath, contentType: MediaType('image','jpeg'),
      ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception('predict failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// GET /nutrition/<menuName> : (instance) — เปลี่ยนชื่อเพื่อไม่ชนกับ static
  Future<Map<String, dynamic>> fetchNutritionByMenuName(String menuName) async {
    final uri = Uri.parse('$baseUrl/nutrition/$menuName');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('getNutrition failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // =============== Static shims (compat โค้ดเก่า) ===============

  /// เดิม: ApiService.uploadImage(File) -> Map<String,dynamic>?
  static Future<Map<String, dynamic>?> uploadImage(File imageFile) async {
    final api = ApiService(_globalBaseUrl);
    try {
      final map = await api.predict(
        filePath: imageFile.path,
        uid: 'public',
      );
      return map;
    } catch (e) {
      // ignore: avoid_print
      print('uploadImage compat failed: $e');
      return null;
    }
  }

  /// เดิม: ApiService.uploadImageAndGetUrl({imageFile, uid, bucket?}) -> String?
  static Future<String?> uploadImageAndGetUrl({
    required File imageFile,
    required String uid,
    String? bucket, // คงพารามิเตอร์เดิม (ยังไม่ใช้)
  }) async {
    final api = ApiService(_globalBaseUrl);
    try {
      final url = await api.uploadOnly(filePath: imageFile.path, uid: uid);
      return url;
    } catch (e) {
      // ignore: avoid_print
      print('uploadImageAndGetUrl compat failed: $e');
      return null;
    }
  }

  /// เดิม: ApiService.getNutritionByMenuName(String) -> Map<String,dynamic>?
  /// (static wrapper เรียก instance.fetchNutritionByMenuName เพื่อไม่พังโค้ดเดิม)
  static Future<Map<String, dynamic>?> getNutritionByMenuName(String menuName) async {
    final api = ApiService(_globalBaseUrl);
    try {
      final map = await api.fetchNutritionByMenuName(menuName); // ← ใช้ชื่อ instance ใหม่
      return map;
    } catch (e) {
      // ignore: avoid_print
      print('getNutritionByMenuName compat failed: $e');
      return null;
    }
  }

  /// POST /upload-image : อัปโหลดรูปเก็บไฟล์และได้ URL
  Future<String> uploadOnly({
    required String filePath,
    String? uid,
  }) async {
    final uri = Uri.parse('$baseUrl/upload-image');
    final req = http.MultipartRequest('POST', uri)
      ..fields['uid'] = uid ?? 'public'
      ..files.add(await http.MultipartFile.fromPath(
        'file', filePath, contentType: MediaType('image','jpeg'),
      ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception('upload failed: ${resp.statusCode} ${resp.body}');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final direct = (map['url'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final rel = (map['image_path'] as String?)?.trim();
    if (rel != null && rel.isNotEmpty) return _joinBase(baseUrl, rel);

    throw Exception('upload failed: no url in response');
  }

  // =============== helpers ===============
  static String _joinBase(String base, String rel) {
    if (rel.startsWith('http://') || rel.startsWith('https://')) return rel;
    if (base.endsWith('/') && rel.startsWith('/')) {
      return base.substring(0, base.length - 1) + rel;
    } else if (!base.endsWith('/') && !rel.startsWith('/')) {
      return '$base/$rel';
    }
    return '$base$rel';
  }
}
