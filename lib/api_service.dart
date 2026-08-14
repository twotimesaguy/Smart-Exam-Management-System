import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/assignment_registry.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/malpractice_case.dart';
import 'package:flutter_application_1/student_registry.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AllocationUpload {
  const AllocationUpload({
    required this.name,
    required this.category,
    this.path,
    this.bytes,
  });

  final String name;
  final String category;
  final String? path;
  final List<int>? bytes;
}

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();
  static const Duration _requestTimeout = Duration(minutes: 2);

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    final configuredBaseUrl = _configuredBaseUrl.trim();
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl.replaceAll(RegExp(r'/+$'), '');
    }

    if (kReleaseMode) {
      return '';
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'https://flutterapplication1-production-8866.up.railway.app';
    }

    return 'https://flutterapplication1-production-8866.up.railway.app';
  }

  Uri _uri(String path, [Map<String, String?> query = const {}]) {
    if (baseUrl.isEmpty) {
      throw ApiException(_missingApiBaseUrlMessage());
    }

    final filteredQuery = {
      for (final entry in query.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };

    return Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: filteredQuery.isEmpty ? null : filteredQuery);
  }

  Future<LocalUser> login({
    required String username,
    required String password,
  }) async {
    final data = await _postJson('/auth/login', {
      'username': username,
      'password': password,
    });
    return _authUserFromResponse(data);
  }

  Future<LocalUser> signUp({
    required String username,
    required String password,
    required AppUserRole role,
  }) async {
    final data = await _postJson('/auth/signup', {
      'username': username,
      'password': password,
      'role': role.apiValue,
    });
    return _authUserFromResponse(data);
  }

  Future<List<RegisteredStudent>> fetchStudents() async {
    final data = await _getJson('/students') as List<dynamic>;
    return data
        .map((item) => RegisteredStudent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Uint8List> downloadRegisteredStudentsPdf() {
    return _getBytes('/students/export/pdf');
  }

  Future<Uint8List> downloadAttendancePdf({
    required String courseCode,
    required String examDate,
    String? courseTitle,
  }) {
    return _getBytes('/attendance/export/pdf', {
      'course_code': courseCode,
      'exam_date': examDate,
      'course_title': courseTitle,
    });
  }

  Future<RegisteredStudent> registerStudent({
    required String studentId,
    required String fullName,
    required String programme,
    required String level,
    required String faceImagePath,
    required List<int> faceImageBytes,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/students'))
      ..fields.addAll({
        'student_id': studentId,
        'full_name': fullName,
        'programme': programme,
        'level': level,
      })
      ..files.add(
        await http.MultipartFile.fromPath('face_image', faceImagePath),
      );

    final data = await _sendMultipart(request);
    return RegisteredStudent.fromJson(
      data as Map<String, dynamic>,
      faceImageBytes: faceImageBytes,
    );
  }

  Future<List<ExamAssignment>> fetchAssignments(String username) async {
    final data = await _getJson('/assignments/$username') as List<dynamic>;
    return data
        .map((item) => ExamAssignment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateAssignmentStatus({
    required String assignmentId,
    required AssignmentStatus status,
  }) async {
    await _patchJson('/assignments/$assignmentId/status', {
      'status': status.apiValue,
    });
  }

  Future<List<Map<String, dynamic>>> fetchTimetables() async {
    final data = await _getJson('/allocation/timetables') as List<dynamic>;
    return data.map((item) => item as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> runStoredSmartAllocation() async {
    final data = await _postJson('/allocation/generate/stored', {});
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runWizardSmartAllocation({
    required String title,
    required String startDate,
    required String endDate,
    required String semester,
    required String timeSlots,
    required String lecturers,
    required String venues,
    required String courses,
    required String programmes,
    required String courseLecturers,
    required List<AllocationUpload> files,
    int maxSessionDurationMinutes = 120,
  }) async {
    if (maxSessionDurationMinutes <= 0 || maxSessionDurationMinutes > 120) {
      throw const ApiException(
        'An exam session must be between 1 and 120 minutes long.',
      );
    }

    final request =
        http.MultipartRequest('POST', _uri('/allocation/generate/wizard'))
          ..fields.addAll({
            'title': title,
            'start_date': startDate,
            'end_date': endDate,
            'semester': semester,
            'time_slots': timeSlots,
            'lecturers': lecturers,
            'venues': venues,
            'courses': courses,
            'programmes': programmes,
            'course_lecturers': courseLecturers,
            'max_session_duration_minutes': maxSessionDurationMinutes
                .toString(),
          });

    for (final file in files) {
      if (file.path != null && file.path!.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath(
            '${file.category}_files',
            file.path!,
            filename: file.name,
          ),
        );
      } else if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            '${file.category}_files',
            file.bytes!,
            filename: file.name,
          ),
        );
      }
    }

    final data = await _sendMultipart(request);
    return data as Map<String, dynamic>;
  }

  Future<Uint8List> downloadTimetableExcel({required int timetableId}) {
    return _getBytes('/allocation/timetable/$timetableId/excel');
  }

  Future<void> clearGeneratedTimetables() async {
    await _deleteJson('/allocation/timetables');
  }

  Future<LocalUser> uploadProfilePicture({
    required int userId,
    required String imagePath,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/auth/users/$userId/profile-picture'),
          )
          ..files.add(
            await http.MultipartFile.fromPath('profile_picture', imagePath),
          );

    final data = await _sendMultipart(request) as Map<String, dynamic>;
    return _userFromMap(data, token: null);
  }

  Future<Map<String, dynamic>> recognizeStudent({
    required String faceImagePath,
    required String recordedBy,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/attendance/recognize'))
      ..fields['recorded_by'] = recordedBy
      ..files.add(
        await http.MultipartFile.fromPath('face_image', faceImagePath),
      );

    return await _sendMultipart(request) as Map<String, dynamic>;
  }

  Future<void> submitMalpracticeReport({
    required String studentId,
    required String studentLevel,
    required String courseTitle,
    required String courseCode,
    required String venue,
    required String invigilatorName,
    required String incidentDescription,
    required String studentStatement,
    String? studentFaceImagePath,
    String? foreignMaterialImagePath,
    String? studentStatementAudioPath,
    List<int>? studentStatementAudioBytes,
    String? studentStatementAudioFileName,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/malpractice/reports'))
      ..fields.addAll({
        'student_id': studentId,
        'student_level': studentLevel,
        'course_title': courseTitle,
        'course_code': courseCode,
        'venue': venue,
        'invigilator_name': invigilatorName,
        'incident_description': incidentDescription,
        'student_statement': studentStatement,
      });

    if (studentFaceImagePath != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'student_face_image',
          studentFaceImagePath,
        ),
      );
    }
    if (foreignMaterialImagePath != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foreign_material_image',
          foreignMaterialImagePath,
        ),
      );
    }
    if (studentStatementAudioBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'student_statement_audio',
          studentStatementAudioBytes,
          filename: studentStatementAudioFileName ?? 'student_statement.webm',
        ),
      );
    } else if (studentStatementAudioPath != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'student_statement_audio',
          studentStatementAudioPath,
          filename: studentStatementAudioFileName ?? 'student_statement.m4a',
        ),
      );
    }

    await _sendMultipart(request);
  }

  Future<List<MalpracticeCase>> fetchMalpracticeCases() async {
    final data = await _getJson('/malpractice/reports') as List<dynamic>;
    return data
        .map((item) => _malpracticeCaseFromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<MalpracticeCase> updateMalpracticeCase({
    required int reportId,
    required MalpracticeCaseStatus status,
    required String resolutionNotes,
    required String handledBy,
  }) async {
    final data = await _patchJson('/malpractice/reports/$reportId', {
      'case_status': status.apiValue,
      'resolution_notes': resolutionNotes,
      'handled_by': handledBy,
    });
    return _malpracticeCaseFromMap(data as Map<String, dynamic>);
  }

  Future<MalpracticeCase> forwardMalpracticeCase(int reportId) async {
    final data = await _postJson('/malpractice/reports/$reportId/forward', {});
    return _malpracticeCaseFromMap(data as Map<String, dynamic>);
  }

  Future<Uint8List> downloadMalpracticeCasesPdf() {
    return _getBytes('/malpractice/reports/export/pdf');
  }

  Future<dynamic> _getJson(
    String path, [
    Map<String, String?> query = const {},
  ]) async {
    final response = await _withApiErrorMessage(
      http.get(_uri(path, query)).timeout(_requestTimeout),
    );
    return _decodeResponse(response);
  }

  Future<Uint8List> _getBytes(
    String path, [
    Map<String, String?> query = const {},
  ]) async {
    final response = await _withApiErrorMessage(
      http.get(_uri(path, query)).timeout(_requestTimeout),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeResponse(response);
    }
    return response.bodyBytes;
  }

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) async {
    final response = await _withApiErrorMessage(
      http
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> _patchJson(String path, Map<String, dynamic> body) async {
    final response = await _withApiErrorMessage(
      http
          .patch(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> _deleteJson(String path) async {
    final response = await _withApiErrorMessage(
      http.delete(_uri(path)).timeout(_requestTimeout),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> _sendMultipart(http.MultipartRequest request) async {
    try {
      final streamedResponse = await request.send().timeout(_requestTimeout);
      final response = await http.Response.fromStream(
        streamedResponse,
      ).timeout(_requestTimeout);
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(_connectionErrorMessage());
    } on Exception catch (error) {
      throw ApiException(_connectionErrorMessage(error));
    }
  }

  Future<http.Response> _withApiErrorMessage(
    Future<http.Response> request,
  ) async {
    try {
      return await request;
    } on TimeoutException {
      throw ApiException(_connectionErrorMessage());
    } on Exception catch (error) {
      throw ApiException(_connectionErrorMessage(error));
    }
  }

  String _connectionErrorMessage([Object? details]) {
    if (baseUrl.isEmpty) {
      return _missingApiBaseUrlMessage();
    }

    final detailsText = details == null ? '' : ' Details: $details';
    return 'Could not reach the server at $baseUrl. '
        'Make sure the FastAPI backend is online and reachable from this device. '
        'For phones away from your Wi-Fi, use a hosted HTTPS API URL as '
        'API_BASE_URL.$detailsText';
  }

  String _missingApiBaseUrlMessage() {
    return 'No API server is configured. Deploy the FastAPI backend, then run '
        'or build the app with --dart-define=API_BASE_URL=https://your-api-url.';
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        body = response.body.trim();
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (body is Map<String, dynamic> && body['detail'] != null) {
        throw ApiException(body['detail'].toString());
      }
      final responseMessage = body is String && body.isNotEmpty
          ? ' $body'
          : '';
      throw ApiException(
        'The server returned an error (${response.statusCode}).$responseMessage',
      );
    }
    return body;
  }

  LocalUser _authUserFromResponse(dynamic data) {
    final map = data as Map<String, dynamic>;
    final user = map['user'] as Map<String, dynamic>;
    return _userFromMap(user, token: map['token'] as String?);
  }

  LocalUser _userFromMap(Map<String, dynamic> user, {String? token}) {
    final id = user['id'] as int?;
    return LocalUser(
      id: id,
      username: user['username'] as String,
      role: appUserRoleFromApiValue(user['role'] as String),
      token: token,
      profileImageUrl: _profileImageUrl(id, user['profile_image_path']),
    );
  }

  String? _profileImageUrl(int? userId, Object? profileImagePath) {
    if (userId == null || profileImagePath == null) {
      return null;
    }
    if (profileImagePath.toString().trim().isEmpty) {
      return null;
    }
    return _uri('/auth/users/$userId/profile-picture').toString();
  }

  MalpracticeCase _malpracticeCaseFromMap(Map<String, dynamic> data) {
    final id = data['id'] as int;
    return MalpracticeCase.fromJson(
      data,
      studentFaceImageUrl: _malpracticeEvidenceImageUrl(
        id,
        'student-face',
        data['student_face_image_path'],
      ),
      foreignMaterialImageUrl: _malpracticeEvidenceImageUrl(
        id,
        'foreign-material',
        data['foreign_material_image_path'],
      ),
      studentStatementAudioUrl: _malpracticeStatementAudioUrl(
        id,
        data['student_statement_audio_filename'],
      ),
    );
  }

  String? _malpracticeEvidenceImageUrl(
    int reportId,
    String evidenceType,
    Object? imagePath,
  ) {
    if (imagePath == null || imagePath.toString().trim().isEmpty) {
      return null;
    }
    return _uri(
      '/malpractice/reports/$reportId/evidence/$evidenceType',
    ).toString();
  }

  String? _malpracticeStatementAudioUrl(int reportId, Object? filename) {
    if (filename == null || filename.toString().trim().isEmpty) {
      return null;
    }
    return _uri('/malpractice/reports/$reportId/statement-audio').toString();
  }
}
