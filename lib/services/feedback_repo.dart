// lib/services/feedback_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackRepo {
  FeedbackRepo._();
  static final instance = FeedbackRepo._();

  final _fs = FirebaseFirestore.instance;

  Future<void> savePredictionFeedback({
    required String uid,
    required String predictedName,
    required String userCorrection,
    String? username,
    String? imagePath, // ใช้คีย์เดียว imagePath (จะเป็น URL หรือ local path ก็ได้)
  }) async {
    await _fs.collection('prediction_feedback').add({
      'uid': uid,
      'username': username,
      'predictedName': predictedName,
      'userCorrection': userCorrection,
      'imagePath': imagePath ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
