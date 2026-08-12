import 'package:flutter/foundation.dart';

class RegisteredStudent {
  const RegisteredStudent({
    required this.studentId,
    required this.fullName,
    required this.programme,
    required this.level,
    required this.registeredAt,
    this.faceImageBytes,
  });

  final String studentId;
  final String fullName;
  final String programme;
  final String level;
  final Uint8List? faceImageBytes;
  final DateTime registeredAt;

  factory RegisteredStudent.fromJson(
    Map<String, dynamic> json, {
    List<int>? faceImageBytes,
  }) {
    return RegisteredStudent(
      studentId: json['student_id'] as String,
      fullName: json['full_name'] as String,
      programme: json['programme'] as String,
      level: json['level'] as String,
      faceImageBytes: faceImageBytes == null
          ? null
          : Uint8List.fromList(faceImageBytes),
      registeredAt:
          DateTime.tryParse(json['registered_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class StudentRegistry extends ValueNotifier<List<RegisteredStudent>> {
  StudentRegistry._() : super(const []);

  static final StudentRegistry instance = StudentRegistry._();

  void registerStudent(RegisteredStudent student) {
    value = [student, ...value];
  }

  void setStudents(List<RegisteredStudent> students) {
    value = students;
  }
}
