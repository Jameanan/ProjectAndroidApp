// lib/services/api_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  //192.168.1.100 เน็ตห้อง
  //172.20.10.4 เน็ตทรศ.
  static const String baseUrl = 'http://172.20.10.4:8000';

  /// Predict เมนูจากรูป (ของเดิม)
  static Future<Map<String, dynamic>?> uploadImage(File imageFile) async {
    final uri = Uri.parse('$baseUrl/predict/');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          contentType: MediaType('image', _inferExt(imageFile.path)),
        ),
      );

    try {
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        return json.decode(resp.body) as Map<String, dynamic>;
      }
      // ล็อกไว้ดูตอนดีบัก (ไม่ throw เพื่อไม่กระทบ flow เดิม)
      // ignore: avoid_print
      print('Predict error: ${resp.statusCode} ${resp.body}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Predict exception: $e');
      return null;
    }
  }

  /// ดึงโภชนาการตามชื่อเมนู (ของเดิม)
  static Future<Map<String, dynamic>?> getNutritionByMenuName(String menuName) async {
    final uri = Uri.parse('$baseUrl/nutrition/$menuName');
    try {
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        return json.decode(resp.body) as Map<String, dynamic>;
      }
      // ignore: avoid_print
      print('getNutrition error: ${resp.statusCode} ${resp.body}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('getNutrition exception: $e');
      return null;
    }
  }

  /// ========= ใหม่/สำคัญ: อัปโหลดรูปไป FastAPI → ได้ **URL** กลับมา =========
  ///
  /// - ถ้าเซิร์ฟเวอร์คืน `url` (absolute) จะใช้ค่านั้นเลย
  /// - ถ้าคืน `image_path` (relative) จะประกอบเป็น `$baseUrl + image_path`
  static Future<String?> uploadImageAndGetUrl({
    required File imageFile,
    required String uid, // ใช้เฉพาะผู้ใช้ที่ล็อกอิน
    String? bucket,      // ถ้าส่งมา เช่น 'my_menus' จะถูกส่งไปยังเซิร์ฟเวอร์
  }) async {
    final uri = Uri.parse('$baseUrl/upload-image');

    final request = http.MultipartRequest('POST', uri)
      ..fields['uid'] = uid
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          contentType: MediaType('image', _inferExt(imageFile.path)),
        ),
      );

    if (bucket != null && bucket.isNotEmpty) {
      request.fields['bucket'] = bucket;
    }

    try {
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(resp.body) as Map<String, dynamic>;

        // 1) ใช้ absolute URL ถ้ามี
        final direct = (body['url'] as String?)?.trim();
        if (direct != null && direct.isNotEmpty) return direct;

        // 2) fallback ต่อจาก relative path
        final rel = (body['image_path'] as String?)?.trim();
        if (rel != null && rel.isNotEmpty) {
          return _joinBase(baseUrl, rel);
        }
        return null;
      } else {
        // ignore: avoid_print
        print('uploadImageAndGetUrl error: ${resp.statusCode} ${resp.body}');
        return null;
      }
    } catch (e) {
      // ignore: avoid_print
      print('uploadImageAndGetUrl exception: $e');
      return null;
    }
  }

  // ----------------- helpers -----------------
  static String _inferExt(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.bmp')) return 'bmp';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.tif') || lower.endsWith('.tiff')) return 'tiff';
    return 'jpeg';
  }

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
