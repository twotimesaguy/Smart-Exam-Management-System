import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/assignment_registry.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/module_shell.dart';

class MyAssignmentModule extends StatefulWidget {
  const MyAssignmentModule({required this.currentUser, super.key});

  final LocalUser currentUser;

  @override
  State<MyAssignmentModule> createState() => _MyAssignmentModuleState();
}

class _MyAssignmentModuleState extends State<MyAssignmentModule> {
  final AssignmentRegistry _registry = AssignmentRegistry.instance;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final assignments = await ApiService.instance.fetchAssignments(
        widget.currentUser.username,
      );
      _registry.setAssignments(assignments);
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(
    ExamAssignment assignment,
    AssignmentStatus status,
  ) async {
    try {
      await ApiService.instance.updateAssignmentStatus(
        assignmentId: assignment.id,
        status: status,
      );
      _registry.updateStatus(assignment.id, status);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignments = _registry.assignmentsFor(widget.currentUser.username);

    return ModuleShell(
      title: 'My Assignment',
      description: 'View and update your assigned exam invigilation duties.',
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _AssignmentErrorState(
              message: _errorMessage!,
              onRetry: _loadAssignments,
            )
          : assignments.isEmpty
          ? const _EmptyAssignmentState()
          : ListView.separated(
              itemCount: assignments.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final assignment = assignments[index];

                return _AssignmentCard(
                  assignment: assignment,
                  onAccept: () =>
                      _updateStatus(assignment, AssignmentStatus.accepted),
                  onStart: () =>
                      _updateStatus(assignment, AssignmentStatus.inProgress),
                  onComplete: () =>
                      _updateStatus(assignment, AssignmentStatus.completed),
                );
              },
            ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.onAccept,
    required this.onStart,
    required this.onComplete,
  });

  final ExamAssignment assignment;
  final VoidCallback onAccept;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final leading = Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.16),
                      colorScheme.secondary.withValues(alpha: 0.24),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.assignment_ind, color: colorScheme.primary),
              );
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignment.courseCode,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(assignment.courseTitle),
                ],
              );

              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        leading,
                        const SizedBox(width: 14),
                        Expanded(child: title),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StatusPill(status: assignment.status),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 14),
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  _StatusPill(status: assignment.status),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AssignmentDetail(
                icon: Icons.meeting_room_outlined,
                label: 'Venue',
                value: assignment.venue,
              ),
              _AssignmentDetail(
                icon: Icons.calendar_month_outlined,
                label: 'Date',
                value: assignment.examDate,
              ),
              _AssignmentDetail(
                icon: Icons.schedule_outlined,
                label: 'Time',
                value: '${assignment.startTime} - ${assignment.endTime}',
              ),
              _AssignmentDetail(
                icon: Icons.school_outlined,
                label: 'Level',
                value: assignment.studentLevel,
              ),
              _AssignmentDetail(
                icon: Icons.groups_outlined,
                label: 'Students',
                value: '${assignment.studentCount}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: assignment.status == AssignmentStatus.pending
                    ? onAccept
                    : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Accept'),
              ),
              ElevatedButton.icon(
                onPressed: assignment.status == AssignmentStatus.accepted
                    ? onStart
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start'),
              ),
              FilledButton.icon(
                onPressed: assignment.status == AssignmentStatus.inProgress
                    ? onComplete
                    : null,
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Complete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignmentDetail extends StatelessWidget {
  const _AssignmentDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth < 190 ? constraints.maxWidth : 190,
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final AssignmentStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _backgroundColor(colorScheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: _foregroundColor(colorScheme),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _backgroundColor(ColorScheme colorScheme) {
    switch (status) {
      case AssignmentStatus.pending:
        return colorScheme.secondary.withValues(alpha: 0.20);
      case AssignmentStatus.accepted:
        return colorScheme.primary.withValues(alpha: 0.12);
      case AssignmentStatus.inProgress:
        return colorScheme.tertiary.withValues(alpha: 0.16);
      case AssignmentStatus.completed:
        return const Color(0xFF16A34A).withValues(alpha: 0.14);
    }
  }

  Color _foregroundColor(ColorScheme colorScheme) {
    switch (status) {
      case AssignmentStatus.pending:
        return const Color(0xFF6B4A00);
      case AssignmentStatus.accepted:
        return colorScheme.primary;
      case AssignmentStatus.inProgress:
        return const Color(0xFF9D174D);
      case AssignmentStatus.completed:
        return const Color(0xFF166534);
    }
  }
}

class _EmptyAssignmentState extends StatelessWidget {
  const _EmptyAssignmentState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_late_outlined,
              size: 46,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No assignment yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Your assigned venue, course, and exam time will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentErrorState extends StatelessWidget {
  const _AssignmentErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
