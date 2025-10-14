import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:main/services/api_service.dart';
import 'package:main/screen/food_result.dart';

class PredictPage extends StatefulWidget {
  const PredictPage({super.key});

  @override
  State<PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<PredictPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _chooseImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);

      try {
        // 1. ส่งรูปภาพไปยัง API เพื่อทำนายเมนู
        final resultPredict = await ApiService.uploadImage(imageFile);
        print("/predict/: $resultPredict");

        if (resultPredict != null && resultPredict.containsKey('menu_name')) {
          final menuName = resultPredict['menu_name'];

          // 2. ดึงข้อมูลโภชนาการจากชื่อเมนู
          final result = await ApiService.getNutritionByMenuName(menuName);
          print("/nutrition/$menuName: $result");

          if (result != null &&
              result.containsKey('sugar_nutrition') &&
              result.containsKey('nosugar_nutrition')) {

            // 3. ส่งข้อมูลไปยังหน้าแสดงผล
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FoodResultPage(
                  menuName: menuName,
                  imagePath: imageFile.path,
                  menuData: result,
                ),
              ),
            );
          } else {
            _showSnackBar('ไม่พบข้อมูลโภชนาการของเมนูนี้');
          }
        } else {
          _showSnackBar('ไม่สามารถทำนายเมนูจากภาพได้');
        }
      } catch (e) {
        print('เกิดข้อผิดพลาด: $e');
        _showSnackBar('เกิดข้อผิดพลาด: $e');
      }
    }
  }

  void _showPickOptionsDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('ถ่ายภาพด้วยกล้อง'),
              onTap: () {
                Navigator.pop(context);
                _chooseImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('เลือกรูปจากคลังภาพ'),
              onTap: () {
                Navigator.pop(context);
                _chooseImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Scan')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add_a_photo),
          label: const Text('เพิ่มเมนูจากภาพ'),
          onPressed: _showPickOptionsDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      ),
    );
  }
}
