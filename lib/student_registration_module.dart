import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/module_shell.dart';
import 'package:flutter_application_1/pdf_export_service.dart';
import 'package:flutter_application_1/student_registry.dart';
import 'package:image_picker/image_picker.dart';

class StudentRegistrationModule extends StatefulWidget {
  const StudentRegistrationModule({super.key});

  @override
  State<StudentRegistrationModule> createState() =>
      _StudentRegistrationModuleState();
}

class _StudentRegistrationModuleState extends State<StudentRegistrationModule> {
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _programmeController = TextEditingController();
  final _levelController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  XFile? _faceImage;
  Uint8List? _faceImageBytes;
  bool _isCapturing = false;
  bool _isSaving = false;
  bool _isExportingPdf = false;
  bool _isLoadingStudents = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _programmeController.dispose();
    _levelController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        Icons.badge_outlined,
        color: colorScheme.primary.withValues(alpha: 0.75),
      ),
    );
  }

  Future<void> _captureFace() async {
    if (_isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null) {
        return;
      }

      final bytes = await image.readAsBytes();

      if (!mounted) {
        return;
      }

      setState(() {
        _faceImage = image;
        _faceImageBytes = bytes;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _loadStudents() async {
    try {
      final students = await ApiService.instance.fetchStudents();
      if (!mounted) {
        return;
      }
      StudentRegistry.instance.setStudents(students);
    } catch (_) {
      // Keep the screen usable if the backend is not running yet.
    } finally {
      if (mounted) {
        setState(() => _isLoadingStudents = false);
      }
    }
  }

  Future<void> _registerStudent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_faceImage == null || _faceImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capture a face photo before saving the student.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final student = await ApiService.instance.registerStudent(
        studentId: _studentIdController.text.trim(),
        fullName:
            '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
        programme: _programmeController.text.trim(),
        level: _levelController.text.trim(),
        faceImagePath: _faceImage!.path,
        faceImageBytes: _faceImageBytes!,
      );

      StudentRegistry.instance.registerStudent(student);
      if (!mounted) {
        return;
      }

      setState(() {
        _studentIdController.clear();
        _firstNameController.clear();
        _lastNameController.clear();
        _programmeController.clear();
        _levelController.clear();
        _faceImage = null;
        _faceImageBytes = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student registered successfully.')),
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
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openStudentsPdf() async {
    setState(() => _isExportingPdf = true);

    try {
      final bytes = await ApiService.instance.downloadRegisteredStudentsPdf();
      await PdfExportService.instance.saveAndOpen(
        fileName: 'registered_students.pdf',
        bytes: bytes,
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
        setState(() => _isExportingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ModuleShell(
      title: 'Student Registration',
      description:
          'Register student details and face profiles for attendance matching.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sectionGap = (constraints.maxHeight * 0.02).clamp(10.0, 18.0);
          final imageHeight = (constraints.maxHeight * 0.25).clamp(
            180.0,
            260.0,
          );

          return Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _studentIdController,
                  decoration: _fieldDecoration(context, 'Student ID'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Student ID is required'
                      : null,
                ),
                SizedBox(height: sectionGap),
                TextFormField(
                  controller: _firstNameController,
                  decoration: _fieldDecoration(context, 'First Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'First name is required'
                      : null,
                ),
                SizedBox(height: sectionGap),
                TextFormField(
                  controller: _lastNameController,
                  decoration: _fieldDecoration(context, 'Last Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Last name is required'
                      : null,
                ),
                SizedBox(height: sectionGap),
                TextFormField(
                  controller: _programmeController,
                  decoration: _fieldDecoration(context, 'Programme'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Programme is required'
                      : null,
                ),
                SizedBox(height: sectionGap),
                TextFormField(
                  controller: _levelController,
                  decoration: _fieldDecoration(context, 'Level'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Level is required'
                      : null,
                ),
                SizedBox(height: sectionGap),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face Enrollment Photo',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Capture a clear front-facing image with good lighting. This becomes the stored profile photo for later comparison.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _captureFace,
                        icon: _isCapturing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _isCapturing ? 'Opening Camera...' : 'Capture Face',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_faceImageBytes != null) ...[
                  SizedBox(height: sectionGap),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.memory(
                      _faceImageBytes!,
                      height: imageHeight,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                SizedBox(height: sectionGap),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _registerStudent,
                    child: Text(
                      _isSaving
                          ? 'Saving to database...'
                          : 'Save Registered Student',
                    ),
                  ),
                ),
                SizedBox(height: sectionGap),
                ValueListenableBuilder<List<RegisteredStudent>>(
                  valueListenable: StudentRegistry.instance,
                  builder: (context, students, _) {
                    if (students.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _isLoadingStudents
                                ? 'Loading registered students...'
                                : 'No students registered yet.',
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registered Students',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SizedBox(height: sectionGap),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _isExportingPdf
                                ? null
                                : _openStudentsPdf,
                            icon: _isExportingPdf
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(
                              _isExportingPdf
                                  ? 'Preparing PDF...'
                                  : 'Open Students PDF',
                            ),
                          ),
                        ),
                        SizedBox(height: sectionGap),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.10,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.groups_outlined,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${students.length}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'student${students.length == 1 ? '' : 's'} registered',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
