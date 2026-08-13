import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/file_export_service.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/malpractice_case.dart';
import 'package:flutter_application_1/module_shell.dart';

class DisciplinaryOfficerModule extends StatefulWidget {
  const DisciplinaryOfficerModule({required this.currentUser, super.key});

  final LocalUser currentUser;

  @override
  State<DisciplinaryOfficerModule> createState() =>
      _DisciplinaryOfficerModuleState();
}

class _DisciplinaryOfficerModuleState extends State<DisciplinaryOfficerModule> {
  late Future<List<MalpracticeCase>> _casesFuture;
  MalpracticeCaseStatus? _statusFilter;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _casesFuture = ApiService.instance.fetchMalpracticeCases();
  }

  void _refreshCases() {
    setState(() {
      _casesFuture = ApiService.instance.fetchMalpracticeCases();
    });
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final bytes = await ApiService.instance.downloadMalpracticeCasesPdf();
      await FileExportService.instance.saveAndOpen(
        fileName: 'malpractice_cases.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openCase(MalpracticeCase report) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CaseHandlingSheet(
        report: report,
        officerName: widget.currentUser.username,
      ),
    );
    if (updated == true) {
      _refreshCases();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModuleShell(
      title: 'Disciplinary Cases',
      description: 'Review malpractice reports and generate case summaries.',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = [
                IconButton.filledTonal(
                  tooltip: 'Refresh cases',
                  onPressed: _refreshCases,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton.filled(
                  tooltip: 'Generate PDF report',
                  onPressed: _isExporting ? null : _exportPdf,
                  icon: _isExporting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                ),
              ];
              final filter = DropdownButtonFormField<MalpracticeCaseStatus?>(
                initialValue: _statusFilter,
                decoration: const InputDecoration(
                  labelText: 'Case Status',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Cases')),
                  ...MalpracticeCaseStatus.values.map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                  ),
                ],
                onChanged: (status) => setState(() => _statusFilter = status),
              );

              if (constraints.maxWidth < 420) {
                return Column(
                  children: [
                    filter,
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: 8, children: actions),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: filter),
                  const SizedBox(width: 12),
                  ...actions.expand((action) => [action, const SizedBox(width: 8)]),
                ]..removeLast(),
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<MalpracticeCase>>(
              future: _casesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _EmptyState(
                    icon: Icons.cloud_off_outlined,
                    message: snapshot.error
                        .toString()
                        .replaceFirst('Exception: ', ''),
                  );
                }

                final reports = (snapshot.data ?? [])
                    .where(
                      (report) =>
                          _statusFilter == null ||
                          report.status == _statusFilter,
                    )
                    .toList();
                if (reports.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.fact_check_outlined,
                    message: 'No malpractice cases match this view.',
                  );
                }

                return ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return _CaseTile(
                      report: report,
                      onTap: () => _openCase(report),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  const _CaseTile({required this.report, required this.onTap});

  final MalpracticeCase report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${report.studentId} - ${report.courseCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _StatusChip(status: report.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                report.incidentDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _MetaText(icon: Icons.place_outlined, text: report.venue),
                  _MetaText(
                    icon: Icons.person_outline,
                    text: report.invigilatorName,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseHandlingSheet extends StatefulWidget {
  const _CaseHandlingSheet({
    required this.report,
    required this.officerName,
  });

  final MalpracticeCase report;
  final String officerName;

  @override
  State<_CaseHandlingSheet> createState() => _CaseHandlingSheetState();
}

class _CaseHandlingSheetState extends State<_CaseHandlingSheet> {
  late MalpracticeCaseStatus _status;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.report.status;
    _notesController = TextEditingController(
      text: widget.report.resolutionNotes ?? '',
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ApiService.instance.updateMalpracticeCase(
        reportId: widget.report.id,
        status: _status,
        resolutionNotes: _notesController.text.trim(),
        handledBy: widget.officerName,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Case #${report.id}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _StatusChip(status: report.status),
                  Chip(label: Text(report.courseCode)),
                  Chip(label: Text(report.studentLevel)),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(label: 'Student ID', value: report.studentId),
              _DetailRow(label: 'Course', value: report.courseTitle),
              _DetailRow(label: 'Venue', value: report.venue),
              _DetailRow(label: 'Invigilator', value: report.invigilatorName),
              _DetailRow(label: 'Reported', value: report.createdAt),
              if (report.studentFaceImageUrl != null ||
                  report.foreignMaterialImageUrl != null) ...[
                const SizedBox(height: 8),
                _EvidenceImages(report: report),
              ],
              const Divider(height: 24),
              Text('Incident', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(report.incidentDescription),
              const SizedBox(height: 14),
              Text(
                'Student Statement',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(report.studentStatement),
              if (report.studentStatementAudioUrl != null) ...[
                const SizedBox(height: 12),
                _VoiceRecordingPlayer(audioUrl: report.studentStatementAudioUrl!),
              ],
              const SizedBox(height: 18),
              DropdownButtonFormField<MalpracticeCaseStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Handling Status',
                  prefixIcon: Icon(Icons.assignment_turned_in_outlined),
                ),
                items: MalpracticeCaseStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(),
                onChanged: (status) {
                  if (status != null) {
                    setState(() => _status = status);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Resolution Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceRecordingPlayer extends StatefulWidget {
  const _VoiceRecordingPlayer({required this.audioUrl});

  final String audioUrl;

  @override
  State<_VoiceRecordingPlayer> createState() => _VoiceRecordingPlayerState();
}

class _VoiceRecordingPlayerState extends State<_VoiceRecordingPlayer> {
  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<void> _completedSubscription;
  bool _isPlaying = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _completedSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _completedSubscription.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    setState(() => _isLoading = true);
    try {
      if (_isPlaying) {
        await _player.pause();
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      } else {
        await _player.play(UrlSource(widget.audioUrl));
        if (mounted) {
          setState(() => _isPlaying = true);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _togglePlayback,
      icon: _isLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline),
      label: Text(_isPlaying ? 'Pause student recording' : 'Play student recording'),
    );
  }
}

class _EvidenceImages extends StatelessWidget {
  const _EvidenceImages({required this.report});

  final MalpracticeCase report;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      if (report.studentFaceImageUrl != null)
        _EvidenceImageTile(
          label: 'Culprit Photo',
          imageUrl: report.studentFaceImageUrl!,
        ),
      if (report.foreignMaterialImageUrl != null)
        _EvidenceImageTile(
          label: 'Foreign Material',
          imageUrl: report.foreignMaterialImageUrl!,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 520;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles
              .map(
                (tile) => SizedBox(
                  width: isWide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth,
                  child: tile,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _EvidenceImageTile extends StatelessWidget {
  const _EvidenceImageTile({
    required this.label,
    required this.imageUrl,
  });

  final String label;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 180,
            width: double.infinity,
            color: colorScheme.surfaceContainerHighest,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image_outlined, size: 32),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MalpracticeCaseStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(status.label),
      backgroundColor: colorScheme.secondaryContainer,
      labelStyle: TextStyle(color: colorScheme.onSecondaryContainer),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
