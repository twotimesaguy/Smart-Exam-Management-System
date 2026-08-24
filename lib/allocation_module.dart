import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/file_export_service.dart';
import 'package:flutter_application_1/module_shell.dart';

class AllocationModule extends StatefulWidget {
  const AllocationModule({super.key});

  @override
  State<AllocationModule> createState() => _AllocationModuleState();
}

class _AllocationModuleState extends State<AllocationModule> {
  static const _semesterOptions = ['First Semester', 'Second Semester'];
  static const _wizardStepNames = [
    'Lecturers',
    'Venues',
    'Courses',
    'Programmes',
    'Course Lecturers',
    'Time Slots',
    'Semester',
    'Dates',
  ];
  static const _maxSessionDurationMinutes = 120;

  final _titleController = TextEditingController(
    text: 'Smart Allocation Timetable',
  );
  final _lecturersController = TextEditingController();
  final _venuesController = TextEditingController();
  final _coursesController = TextEditingController();
  final _programmesController = TextEditingController();
  final _courseLecturersController = TextEditingController();
  final _aiEditController = TextEditingController();
  final _timeSlotsController = TextEditingController(
    text: '07:00, 12:00, 16:00',
  );

  String _selectedSemester = _semesterOptions.first;
  int _currentStep = 0;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isCalculating = false;
  bool _isLoading = true;
  bool _isOpeningExcel = false;
  bool _isClearingTimetable = false;
  bool _isApplyingAiEdit = false;
  Timer? _timetablePollTimer;
  String? _timetableVersion;
  int _timetableLoadGeneration = 0;
  int _timetableVersionCheckGeneration = 0;
  List<Map<String, dynamic>> _timetables = const [];
  List<PlatformFile> _lecturerFiles = const [];
  List<PlatformFile> _venueFiles = const [];
  List<PlatformFile> _courseFiles = const [];
  List<PlatformFile> _programmeFiles = const [];
  List<PlatformFile> _courseLecturerFiles = const [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTimetables();
    _startTimetablePolling();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _lecturersController.dispose();
    _venuesController.dispose();
    _coursesController.dispose();
    _programmesController.dispose();
    _courseLecturersController.dispose();
    _aiEditController.dispose();
    _timeSlotsController.dispose();
    _timetablePollTimer?.cancel();
    super.dispose();
  }

  Future<bool> _loadTimetables({bool showLoading = true}) async {
    final loadGeneration = ++_timetableLoadGeneration;
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final timetables = await ApiService.instance.fetchTimetables();
      if (!mounted || loadGeneration != _timetableLoadGeneration) {
        return false;
      }
      final latestTimetables = timetables.take(1).toList();
      // A completed timetable response and its version describe the same
      // snapshot. Record them together so an older polling response cannot
      // replace a freshly applied AI edit in the UI.
      _timetableVersionCheckGeneration++;
      setState(() {
        _timetables = latestTimetables;
        _timetableVersion = latestTimetables.isEmpty
            ? 'none:0:'
            : _timetableVersionKey(latestTimetables.first);
        _errorMessage = null;
      });
      return true;
    } catch (error) {
      if (mounted && loadGeneration == _timetableLoadGeneration) {
        setState(() {
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
      }
      return false;
    } finally {
      if (mounted && loadGeneration == _timetableLoadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startTimetablePolling() {
    _checkForTimetableUpdate();
    _timetablePollTimer = Timer.periodic(
      const Duration(seconds: 9),
      (_) => _checkForTimetableUpdate(),
    );
  }

  Future<void> _checkForTimetableUpdate() async {
    final checkGeneration = ++_timetableVersionCheckGeneration;
    try {
      final version = await ApiService.instance.fetchTimetableVersion();
      final versionKey = _timetableVersionKey(version);
      final hasChanged =
          _timetableVersion != null && _timetableVersion != versionKey;
      if (hasChanged) {
        await _loadTimetables(showLoading: false);
      }
      if (mounted && checkGeneration == _timetableVersionCheckGeneration) {
        setState(() => _timetableVersion = versionKey);
      }
    } catch (_) {
      // Polling is opportunistic; visible requests continue to show errors.
    }
  }

  String _timetableVersionKey(Map<String, dynamic> version) {
    return '${version['timetable_id'] ?? 'none'}:'
        '${version['version'] ?? 0}:'
        '${version['last_updated'] ?? ''}';
  }

  Future<void> _pickFiles(_AllocationFileGroup group) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xlsm', 'csv', 'txt', 'docx', 'pdf'],
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() {
      switch (group) {
        case _AllocationFileGroup.lecturers:
          _lecturerFiles = [..._lecturerFiles, ...result.files];
          break;
        case _AllocationFileGroup.venues:
          _venueFiles = [..._venueFiles, ...result.files];
          break;
        case _AllocationFileGroup.courses:
          _courseFiles = [..._courseFiles, ...result.files];
          break;
        case _AllocationFileGroup.programmes:
          _programmeFiles = [..._programmeFiles, ...result.files];
          break;
        case _AllocationFileGroup.courseLecturers:
          _courseLecturerFiles = [..._courseLecturerFiles, ...result.files];
          break;
      }
    });
  }

  void _removeFile(_AllocationFileGroup group, PlatformFile file) {
    setState(() {
      switch (group) {
        case _AllocationFileGroup.lecturers:
          _lecturerFiles = _lecturerFiles
              .where((item) => item != file)
              .toList();
          break;
        case _AllocationFileGroup.venues:
          _venueFiles = _venueFiles.where((item) => item != file).toList();
          break;
        case _AllocationFileGroup.courses:
          _courseFiles = _courseFiles.where((item) => item != file).toList();
          break;
        case _AllocationFileGroup.programmes:
          _programmeFiles = _programmeFiles
              .where((item) => item != file)
              .toList();
          break;
        case _AllocationFileGroup.courseLecturers:
          _courseLecturerFiles = _courseLecturerFiles
              .where((item) => item != file)
              .toList();
          break;
      }
    });
  }

  Future<void> _selectDate({required bool isStartDate}) async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? _startDate ?? now
          : _endDate ?? _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      if (isStartDate) {
        _startDate = selectedDate;
        if (_endDate != null && _endDate!.isBefore(selectedDate)) {
          _endDate = selectedDate;
        }
      } else {
        _endDate = selectedDate;
      }
    });
  }

  Future<void> _runAutoAllocation() async {
    if (!_isWizardReady()) {
      setState(() {
        _errorMessage =
            'Complete the lecturers, venues, courses, programmes, course lecturers, time slots, and date range before running allocation.';
      });
      return;
    }

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
    });

    try {
      final timetable = await ApiService.instance.runWizardSmartAllocation(
        title: _titleController.text.trim().isEmpty
            ? 'Smart Allocation Timetable'
            : _titleController.text.trim(),
        startDate: _apiDate(_startDate!),
        endDate: _apiDate(_endDate!),
        semester: _selectedSemester,
        timeSlots: _timeSlotsController.text.trim(),
        lecturers: _lecturersController.text.trim(),
        venues: _venuesController.text.trim(),
        courses: _coursesController.text.trim(),
        programmes: _programmesController.text.trim(),
        courseLecturers: _courseLecturersController.text.trim(),
        files: _selectedUploads(),
        maxSessionDurationMinutes: _maxSessionDurationMinutes,
      );
      await _loadTimetables();
      if (!mounted) {
        return;
      }
      await _openTimetableExcel(timetable, showLoading: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Smart allocation timetable generated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage!)));
    } finally {
      if (mounted) {
        setState(() => _isCalculating = false);
      }
    }
  }

  Future<void> _openTimetableExcel(
    Map<String, dynamic> timetable, {
    bool showLoading = true,
  }) async {
    if (showLoading) {
      setState(() => _isOpeningExcel = true);
    }

    try {
      final timetableId = timetable['id'] as int;
      final title = timetable['title'] as String;
      final bytes = await ApiService.instance.downloadTimetableExcel(
        timetableId: timetableId,
      );
      await FileExportService.instance.saveAndOpen(
        fileName:
            '${title.toLowerCase().replaceAll(' ', '_')}_$timetableId.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _errorMessage = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted && showLoading) {
        setState(() => _isOpeningExcel = false);
      }
    }
  }

  Future<void> _submitAiTimetableEdit() async {
    final prompt = _aiEditController.text.trim();
    if (prompt.isEmpty || _isApplyingAiEdit) {
      return;
    }

    setState(() => _isApplyingAiEdit = true);
    try {
      final result = await ApiService.instance.askAiToEditTimetable(prompt);
      if (!mounted) {
        return;
      }
      _aiEditController.clear();
      final refreshed = await _loadTimetables(showLoading: false);
      if (!mounted) {
        return;
      }
      if (!refreshed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The AI edit was saved, but the live timetable could not be refreshed. Please try again.',
            ),
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI timetable update'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(child: Text(_aiEditSummary(result))),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isApplyingAiEdit = false);
      }
    }
  }

  String _aiEditSummary(Map<String, dynamic> result) {
    final sections = <String>[];
    final applied = (result['applied'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>();
    final rejected = (result['rejected'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>();
    final unresolved = (result['unresolved'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    if (applied.isNotEmpty) {
      sections.add('Applied\n${applied.map(_describeAiChange).join('\n')}');
    }
    if (rejected.isNotEmpty) {
      sections.add(
        'Not applied\n${rejected.map((change) => '${_describeAiChange(change)} — ${change['reason'] ?? 'Could not validate this change.'}').join('\n')}',
      );
    }
    if (unresolved.isNotEmpty) {
      sections.add(
        'Needs clarification\n${unresolved.map((item) => '• $item').join('\n')}',
      );
    }
    return sections.isEmpty
        ? 'The AI did not find a timetable change to apply.'
        : sections.join('\n\n');
  }

  String _describeAiChange(Map<dynamic, dynamic> change) {
    if (change['operation'] == 'create') {
      return '• Added ${change['course_code'] ?? 'a new exam'}';
    }
    final exam = change['exam_id'] == null
        ? 'exam'
        : 'exam ${change['exam_id']}';
    final field = change['field'] ?? 'change';
    if (change['new'] == null) {
      return '• $exam: $field';
    }
    return '• $exam: $field → ${change['new']}';
  }

  Future<void> _confirmClearTimetable() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear timetable?'),
        content: const Text(
          'This will remove the generated timetable and invigilator assignments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear'),
          ),
        ],
      ),
    );

    if (shouldClear == true) {
      await _clearTimetable();
    }
  }

  Future<void> _clearTimetable() async {
    setState(() {
      _isClearingTimetable = true;
      _errorMessage = null;
    });

    try {
      await ApiService.instance.clearGeneratedTimetables();
      if (!mounted) {
        return;
      }
      setState(() => _timetables = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generated timetable cleared.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _errorMessage = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isClearingTimetable = false);
      }
    }
  }

  bool _isWizardReady() {
    return _hasData(_lecturersController, _lecturerFiles) &&
        _hasData(_venuesController, _venueFiles) &&
        _hasData(_coursesController, _courseFiles) &&
        _hasData(_programmesController, _programmeFiles) &&
        _hasData(_courseLecturersController, _courseLecturerFiles) &&
        _timeSlotsController.text.trim().isNotEmpty &&
        _startDate != null &&
        _endDate != null &&
        !_endDate!.isBefore(_startDate!);
  }

  bool _hasData(TextEditingController controller, List<PlatformFile> files) {
    return controller.text.trim().isNotEmpty || files.isNotEmpty;
  }

  List<AllocationUpload> _selectedUploads() {
    AllocationUpload upload(PlatformFile file, String category) {
      return AllocationUpload(
        name: file.name,
        category: category,
        path: file.path,
        bytes: file.bytes,
      );
    }

    return [
      ..._lecturerFiles.map((file) => upload(file, 'lecturer')),
      ..._venueFiles.map((file) => upload(file, 'venue')),
      ..._courseFiles.map((file) => upload(file, 'course')),
      ..._programmeFiles.map((file) => upload(file, 'programme')),
      ..._courseLecturerFiles.map((file) => upload(file, 'course_lecturer')),
    ];
  }

  String _apiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime? date) {
    return date == null ? 'Select date' : _apiDate(date);
  }

  void _continueWizard() {
    if (_currentStep == 7) {
      _runAutoAllocation();
      return;
    }
    setState(() => _currentStep += 1);
  }

  void _cancelWizard() {
    if (_currentStep == 0) {
      return;
    }
    setState(() => _currentStep -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ModuleShell(
      title: 'Automated Allocation',
      description:
          'Generate exam timetables, venues, and invigilator allocations.',
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildWizard(colorScheme),
          const SizedBox(height: 20),
          _buildAiTimetableEditor(colorScheme),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(_errorMessage!, textAlign: TextAlign.center),
            ),
          if (!_isLoading) _buildTimetableState(colorScheme),
        ],
      ),
    );
  }

  Widget _buildAiTimetableEditor(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'AI timetable editor',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Describe the change you need. Changes are checked against rooms, '
            'invigilators, capacity, and student clashes before they are saved.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aiEditController,
            minLines: 2,
            maxLines: 4,
            enabled: !_isApplyingAiEdit,
            decoration: const InputDecoration(
              labelText: 'Ask AI to update the timetable...',
              hintText: 'Move all Physics exams to next week',
              prefixIcon: Icon(Icons.edit_calendar_outlined),
            ),
            onSubmitted: (_) => _submitAiTimetableEdit(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isApplyingAiEdit ? null : _submitAiTimetableEdit,
            icon: _isApplyingAiEdit
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _isApplyingAiEdit ? 'Checking changes...' : 'Apply AI request',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWizard(ColorScheme colorScheme) {
    final steps = _buildWizardSteps();
    final currentStep = steps[_currentStep];
    final isLastStep = _currentStep == steps.length - 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                child: Text('${_currentStep + 1}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _wizardStepNames[_currentStep],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('Step ${_currentStep + 1} of ${steps.length}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(value: (_currentStep + 1) / steps.length),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: steps.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ChoiceChip(
                label: Text('${index + 1}. ${_wizardStepNames[index]}'),
                selected: index == _currentStep,
                onSelected: _isCalculating
                    ? null
                    : (_) => setState(() => _currentStep = index),
              ),
            ),
          ),
          const Divider(height: 30),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey(_currentStep),
              child: currentStep.content,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _isCalculating ? null : _continueWizard,
                  icon: _isCalculating
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(isLastStep ? Icons.bolt : Icons.arrow_forward),
                  label: Text(
                    _isCalculating
                        ? 'Running...'
                        : isLastStep
                        ? 'Run Smart Allocation'
                        : 'Next',
                  ),
                ),
                if (_currentStep > 0)
                  TextButton(
                    onPressed: _isCalculating ? null : _cancelWizard,
                    child: const Text('Back'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Step> _buildWizardSteps() {
    return [
      Step(
        title: const Text('Lecturers'),
        isActive: _currentStep >= 0,
        content: _buildTextAndFilesStep(
          label: 'Lecturers',
          controller: _lecturersController,
          group: _AllocationFileGroup.lecturers,
          files: _lecturerFiles,
        ),
      ),
      Step(
        title: const Text('Venues'),
        isActive: _currentStep >= 1,
        content: _buildTextAndFilesStep(
          label: 'Venues',
          controller: _venuesController,
          group: _AllocationFileGroup.venues,
          files: _venueFiles,
        ),
      ),
      Step(
        title: const Text('Courses'),
        isActive: _currentStep >= 2,
        content: _buildTextAndFilesStep(
          label: 'Courses',
          controller: _coursesController,
          group: _AllocationFileGroup.courses,
          files: _courseFiles,
        ),
      ),
      Step(
        title: const Text('Programmes'),
        isActive: _currentStep >= 3,
        content: _buildTextAndFilesStep(
          label: 'Programme data',
          controller: _programmesController,
          group: _AllocationFileGroup.programmes,
          files: _programmeFiles,
          hintText:
              'Course code, Programme, Level\nCSC301, Computer Science, Level 300',
        ),
      ),
      Step(
        title: const Text('Course Lecturers'),
        isActive: _currentStep >= 4,
        content: _buildTextAndFilesStep(
          label: 'Course and lecturer data',
          controller: _courseLecturersController,
          group: _AllocationFileGroup.courseLecturers,
          files: _courseLecturerFiles,
          hintText: 'Course code, Lecturer\nCSC301, Dr. Ama Mensah',
        ),
      ),
      Step(
        title: const Text('Time Slots'),
        isActive: _currentStep >= 5,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('Time slots'),
            const SizedBox(height: 8),
            TextField(
              controller: _timeSlotsController,
              decoration: const InputDecoration(
                hintText: '07:00, 12:00, 16:00',
                prefixIcon: Icon(Icons.schedule),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Each exam session is limited to a maximum of 2 hours.'),
          ],
        ),
      ),
      Step(
        title: const Text('Semester'),
        isActive: _currentStep >= 6,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('Semester'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedSemester,
              decoration: const InputDecoration(
                hintText: 'Select semester',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              items: _semesterOptions
                  .map(
                    (semester) => DropdownMenuItem(
                      value: semester,
                      child: Text(semester),
                    ),
                  )
                  .toList(),
              onChanged: (semester) {
                if (semester == null) {
                  return;
                }
                setState(() => _selectedSemester = semester);
              },
            ),
          ],
        ),
      ),
      Step(
        title: const Text('Dates'),
        isActive: _currentStep >= 7,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('Timetable title'),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.title)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _selectDate(isStartDate: true),
                  icon: const Icon(Icons.event),
                  label: Text('Start: ${_displayDate(_startDate)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _selectDate(isStartDate: false),
                  icon: const Icon(Icons.event_available),
                  label: Text('End: ${_displayDate(_endDate)}'),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildTextAndFilesStep({
    required String label,
    required TextEditingController controller,
    required _AllocationFileGroup group,
    required List<PlatformFile> files,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            alignLabelWithHint: true,
            hintText: hintText,
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 82),
              child: Icon(Icons.notes),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickFiles(group),
          icon: const Icon(Icons.upload_file),
          label: const Text('Attach Excel, CSV, Word, or PDF'),
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: files
                .map(
                  (file) => InputChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(file.name),
                    onDeleted: () => _removeFile(group, file),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildTimetableState(ColorScheme colorScheme) {
    if (_timetables.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.15),
                    colorScheme.secondary.withValues(alpha: 0.22),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.meeting_room_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No allocation records available yet.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _timetables
          .map(
            (timetable) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timetable['title'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(timetable['exam_period'] as String),
                    const SizedBox(height: 10),
                    Text(
                      '${(timetable['entries'] as List<dynamic>).length} exam entries',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showLiveTimetable(timetable),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View Live Timetable'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isOpeningExcel
                              ? null
                              : () => _openTimetableExcel(timetable),
                          icon: _isOpeningExcel
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.table_view_outlined),
                          label: Text(
                            _isOpeningExcel
                                ? 'Opening Excel...'
                                : 'Open Excel Timetable',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isClearingTimetable
                              ? null
                              : _confirmClearTimetable,
                          icon: _isClearingTimetable
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          label: Text(
                            _isClearingTimetable
                                ? 'Clearing...'
                                : 'Clear Timetable',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _showLiveTimetable(Map<String, dynamic> timetable) async {
    final entries = (timetable['entries'] as List<dynamic>)
        .cast<Map<dynamic, dynamic>>();
    var search = '';

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matchingEntries = entries.where((entry) {
            if (search.isEmpty) {
              return true;
            }
            final searchable = [
              entry['id'],
              entry['course_code'],
              entry['course_title'],
              entry['exam_date'],
              entry['start_time'],
              entry['end_time'],
              entry['venue'],
              entry['invigilator_username'],
            ].join(' ').toLowerCase();
            return searchable.contains(search);
          }).toList();

          return AlertDialog(
            title: Text('Live timetable • ${matchingEntries.length} entries'),
            content: SizedBox(
              width: 760,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText:
                          'Find course, room, date, invigilator, or exam ID',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setDialogState(() => search = value.trim().toLowerCase());
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: matchingEntries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = matchingEntries[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${entry['course_code']} — ${entry['course_title']}',
                          ),
                          subtitle: Text(
                            'Exam ${entry['id']} • ${entry['exam_date']} • '
                            '${entry['start_time']}–${entry['end_time']} • '
                            '${entry['venue']} • ${entry['invigilator_username']}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _AllocationFileGroup {
  lecturers,
  venues,
  courses,
  programmes,
  courseLecturers,
}
