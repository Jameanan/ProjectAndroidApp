import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class PredictService {
  final String baseUrl; // e.g. https://your-api-domain
  PredictService(this.baseUrl);

  Future<Map<String, dynamic>> predict({
    required String filePath,
    required bool useNoSugar,
    required String? uid,
  }) async {
    final uri = Uri.parse('$baseUrl/predict');
    final req = http.MultipartRequest('POST', uri)
      ..fields['use_nosugar'] = useNoSugar.toString()
      ..fields['save_image']  = 'true'
      ..fields['uid']         = uid ?? 'public'
      ..files.add(await http.MultipartFile.fromPath(
        'file', filePath, contentType: MediaType('image','jpeg'),
      ));
    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) {
      throw Exception('predict failed: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<String> uploadOnly({
    required String filePath,
    required String? uid,
  }) async {
    final uri = Uri.parse('$baseUrl/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['uid'] = uid ?? 'public'
      ..files.add(await http.MultipartFile.fromPath(
        'file', filePath, contentType: MediaType('image','jpeg'),
      ));
    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) throw Exception('upload failed: $body');
    return (jsonDecode(body) as Map<String, dynamic>)['imageUrl'] as String;
  }
}
