enum MalpracticeCaseStatus { pending, underReview, resolved, dismissed }

extension MalpracticeCaseStatusLabel on MalpracticeCaseStatus {
  String get label {
    switch (this) {
      case MalpracticeCaseStatus.pending:
        return 'Pending';
      case MalpracticeCaseStatus.underReview:
        return 'Under Review';
      case MalpracticeCaseStatus.resolved:
        return 'Resolved';
      case MalpracticeCaseStatus.dismissed:
        return 'Dismissed';
    }
  }

  String get apiValue {
    switch (this) {
      case MalpracticeCaseStatus.pending:
        return 'pending';
      case MalpracticeCaseStatus.underReview:
        return 'under_review';
      case MalpracticeCaseStatus.resolved:
        return 'resolved';
      case MalpracticeCaseStatus.dismissed:
        return 'dismissed';
    }
  }
}

MalpracticeCaseStatus malpracticeCaseStatusFromApiValue(String? value) {
  switch (value) {
    case 'under_review':
      return MalpracticeCaseStatus.underReview;
    case 'resolved':
      return MalpracticeCaseStatus.resolved;
    case 'dismissed':
      return MalpracticeCaseStatus.dismissed;
    case 'pending':
    default:
      return MalpracticeCaseStatus.pending;
  }
}

class MalpracticeCase {
  const MalpracticeCase({
    required this.id,
    required this.studentId,
    required this.studentLevel,
    required this.courseTitle,
    required this.courseCode,
    required this.venue,
    required this.invigilatorName,
    required this.incidentDescription,
    required this.studentStatement,
    required this.forwardedStatus,
    required this.status,
    required this.createdAt,
    this.studentFaceImageUrl,
    this.foreignMaterialImageUrl,
    this.forwardedError,
    this.resolutionNotes,
    this.handledBy,
    this.handledAt,
  });

  final int id;
  final String studentId;
  final String studentLevel;
  final String courseTitle;
  final String courseCode;
  final String venue;
  final String invigilatorName;
  final String incidentDescription;
  final String studentStatement;
  final String forwardedStatus;
  final String? studentFaceImageUrl;
  final String? foreignMaterialImageUrl;
  final String? forwardedError;
  final MalpracticeCaseStatus status;
  final String? resolutionNotes;
  final String? handledBy;
  final String? handledAt;
  final String createdAt;

  factory MalpracticeCase.fromJson(
    Map<String, dynamic> json, {
    String? studentFaceImageUrl,
    String? foreignMaterialImageUrl,
  }) {
    return MalpracticeCase(
      id: json['id'] as int,
      studentId: json['student_id'] as String,
      studentLevel: json['student_level'] as String,
      courseTitle: json['course_title'] as String,
      courseCode: json['course_code'] as String,
      venue: json['venue'] as String,
      invigilatorName: json['invigilator_name'] as String,
      incidentDescription: json['incident_description'] as String,
      studentStatement: json['student_statement'] as String,
      forwardedStatus: json['forwarded_status'] as String? ?? 'pending',
      studentFaceImageUrl: studentFaceImageUrl,
      foreignMaterialImageUrl: foreignMaterialImageUrl,
      forwardedError: json['forwarded_error'] as String?,
      status: malpracticeCaseStatusFromApiValue(json['case_status'] as String?),
      resolutionNotes: json['resolution_notes'] as String?,
      handledBy: json['handled_by'] as String?,
      handledAt: json['handled_at'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}
