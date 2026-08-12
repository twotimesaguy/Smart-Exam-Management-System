class ExamAssignment {
  const ExamAssignment({
    required this.id,
    required this.invigilatorUsername,
    required this.courseCode,
    required this.courseTitle,
    required this.venue,
    required this.examDate,
    required this.startTime,
    required this.endTime,
    required this.studentLevel,
    required this.studentCount,
    required this.status,
  });

  final String id;
  final String invigilatorUsername;
  final String courseCode;
  final String courseTitle;
  final String venue;
  final String examDate;
  final String startTime;
  final String endTime;
  final String studentLevel;
  final int studentCount;
  final AssignmentStatus status;

  ExamAssignment copyWith({AssignmentStatus? status}) {
    return ExamAssignment(
      id: id,
      invigilatorUsername: invigilatorUsername,
      courseCode: courseCode,
      courseTitle: courseTitle,
      venue: venue,
      examDate: examDate,
      startTime: startTime,
      endTime: endTime,
      studentLevel: studentLevel,
      studentCount: studentCount,
      status: status ?? this.status,
    );
  }

  factory ExamAssignment.fromJson(Map<String, dynamic> json) {
    return ExamAssignment(
      id: json['id'].toString(),
      invigilatorUsername: json['invigilator_username'] as String,
      courseCode: json['course_code'] as String,
      courseTitle: json['course_title'] as String,
      venue: json['venue'] as String,
      examDate: json['exam_date'].toString(),
      startTime: json['start_time'].toString(),
      endTime: json['end_time'].toString(),
      studentLevel: json['student_level'] as String,
      studentCount: json['student_count'] as int,
      status: assignmentStatusFromApiValue(json['status'] as String),
    );
  }
}

enum AssignmentStatus { pending, accepted, inProgress, completed }

extension AssignmentStatusLabel on AssignmentStatus {
  String get label {
    switch (this) {
      case AssignmentStatus.pending:
        return 'Pending';
      case AssignmentStatus.accepted:
        return 'Accepted';
      case AssignmentStatus.inProgress:
        return 'In Progress';
      case AssignmentStatus.completed:
        return 'Completed';
    }
  }
}

AssignmentStatus assignmentStatusFromApiValue(String value) {
  switch (value) {
    case 'pending':
      return AssignmentStatus.pending;
    case 'accepted':
      return AssignmentStatus.accepted;
    case 'in_progress':
      return AssignmentStatus.inProgress;
    case 'completed':
      return AssignmentStatus.completed;
    default:
      return AssignmentStatus.pending;
  }
}

extension AssignmentStatusApi on AssignmentStatus {
  String get apiValue {
    switch (this) {
      case AssignmentStatus.pending:
        return 'pending';
      case AssignmentStatus.accepted:
        return 'accepted';
      case AssignmentStatus.inProgress:
        return 'in_progress';
      case AssignmentStatus.completed:
        return 'completed';
    }
  }
}

class AssignmentRegistry {
  AssignmentRegistry._();

  static final AssignmentRegistry instance = AssignmentRegistry._();

  final List<ExamAssignment> _assignments = [];

  List<ExamAssignment> get assignments => List.unmodifiable(_assignments);

  List<ExamAssignment> assignmentsFor(String username) {
    final normalizedUsername = username.trim().toLowerCase();

    return _assignments
        .where(
          (assignment) =>
              assignment.invigilatorUsername.toLowerCase() ==
              normalizedUsername,
        )
        .toList();
  }

  void updateStatus(String assignmentId, AssignmentStatus status) {
    final index = _assignments.indexWhere(
      (assignment) => assignment.id == assignmentId,
    );

    if (index == -1) {
      return;
    }

    _assignments[index] = _assignments[index].copyWith(status: status);
  }

  void setAssignments(List<ExamAssignment> assignments) {
    _assignments
      ..clear()
      ..addAll(assignments);
  }
}
