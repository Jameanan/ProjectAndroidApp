// lib/services/user_profile_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:main/models/user.dart';

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('users');

  /// ดึงโปรไฟล์จาก Firestore (ถ้าไม่มี = null)
  Future<UserModel?> getProfile({required String uid}) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    final d = snap.data()!;
    return _fromMap(d);
  }

  /// อัปเดตโปรไฟล์ (merge)
  Future<void> updateProfile({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    await _col.doc(uid).set(data, SetOptions(merge: true));
  }

  /// (ทางเลือก) สร้างเอกสารเริ่มต้นถ้ายังไม่มี
  Future<void> ensureProfile({
    required String uid,
    required UserModel defaultProfile,
  }) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) {
      await _col.doc(uid).set(_toMap(defaultProfile));
    }
  }

  // ----------------- mapper -----------------
  UserModel _fromMap(Map<String, dynamic> d) {
    return UserModel(
      // username/password เก็บไว้เฉย ๆ (ถ้าใช้ Firebase Auth อาจไม่จำเป็น)
      username: (d['username'] ?? '') as String,
      birthdate: d['birthdate'] as String?,
      gender: (d['gender'] ?? 0) as int,
      diabetes: (d['diabetes'] ?? 0) as int,
      height: (d['height'] ?? 0) as int,
      weight: (d['weight'] ?? 0) as int,
      exerciseLevel: (d['exerciselevel'] ?? 0) as int,
    );
  }

  Map<String, dynamic> _toMap(UserModel u) {
    return {
      'username': u.username,
      'birthdate': u.birthdate,
      'gender': u.gender,
      'diabetes': u.diabetes,
      'height': u.height,
      'weight': u.weight,
      'exercise_level': u.exerciseLevel,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
