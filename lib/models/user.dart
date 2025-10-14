//Firebase

class UserModel {
  final String username;
  final String? birthdate; // เก็บวันเกิด 'YYYY-MM-DD'
  final int gender;
  final int diabetes;
  final int height;
  final int weight;
  final int exerciseLevel;

  UserModel({
    required this.username,
    this.birthdate,
    required this.gender,
    required this.diabetes,
    required this.height,
    required this.weight,
    required this.exerciseLevel,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      username: map['username'],
      birthdate: map['birthdate'], // ตรงกับ DBusers.insertUser
      gender: map['gender'],
      diabetes: map['diabetes'],
      height: map['height'],
      weight: map['weight'],
      exerciseLevel: map['exerciseLevel'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'birthdate': birthdate,
      'gender': gender,
      'diabetes': diabetes,
      'height': height,
      'weight': weight,
      'exerciseLevel': exerciseLevel,
    };
  }

  /// ฟังก์ชันคำนวณอายุจาก DOB
  int? get age {
    if (birthdate == null || birthdate!.isEmpty) return null;
    final parts = birthdate!.split('-');
    if (parts.length != 3) return null;

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;

    final dob = DateTime(y, m, d);
    final today = DateTime.now();

    int age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }
}
