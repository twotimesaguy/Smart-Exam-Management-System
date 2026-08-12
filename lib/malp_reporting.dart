import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/module_shell.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

class MalpReporting extends StatefulWidget {
  const MalpReporting({this.currentUser, super.key});

  final LocalUser? currentUser;

  @override
  State<MalpReporting> createState() => _MalpReportingState();
}

class _MalpReportingState extends State<MalpReporting> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _studentLevelController = TextEditingController();
  final TextEditingController _courseTitleController = TextEditingController();
  final TextEditingController _courseCodeController = TextEditingController();
  final TextEditingController _venueController = TextEditingController();
  final TextEditingController _invigilatorController = TextEditingController();
  final TextEditingController _incidentController = TextEditingController();
  final TextEditingController _statementController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speechToText = SpeechToText();

  XFile? _studentFaceImage;
  Uint8List? _studentFacePreviewBytes;
  XFile? _foreignMaterialImage;
  Uint8List? _foreignMaterialPreviewBytes;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _isSubmitting = false;
  String _speechStatus = "Record the student's statement";

  @override
  void initState() {
    super.initState();
    _invigilatorController.text = widget.currentUser?.username ?? '';
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _studentLevelController.dispose();
    _courseTitleController.dispose();
    _courseCodeController.dispose();
    _venueController.dispose();
    _invigilatorController.dispose();
    _incidentController.dispose();
    _statementController.dispose();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _captureStudentFaceEvidence() async {
    await _captureEvidence((image, imageBytes) {
      _studentFaceImage = image;
      _studentFacePreviewBytes = imageBytes;
    });
  }

  Future<void> _captureForeignMaterialEvidence() async {
    await _captureEvidence((image, imageBytes) {
      _foreignMaterialImage = image;
      _foreignMaterialPreviewBytes = imageBytes;
    });
  }

  Future<void> _captureEvidence(
    void Function(XFile image, Uint8List imageBytes) onCaptured,
  ) async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (image == null) {
      return;
    }

    final imageBytes = await image.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      onCaptured(image, imageBytes);
    });
  }

  Future<void> _toggleVoiceNote() async {
    if (_isListening) {
      await _speechToText.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _speechStatus = "Voice note captured and transcribed";
      });
      return;
    }

    final available =
        _speechAvailable ||
        await _speechToText.initialize(
          onStatus: (status) {
            if (!mounted) {
              return;
            }
            if (status == "done" || status == "notListening") {
              setState(() {
                _isListening = false;
                _speechStatus = "Voice note captured and transcribed";
              });
            }
          },
          onError: (error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isListening = false;
              _speechStatus = "Voice note unavailable: ${error.errorMsg}";
            });
          },
        );

    if (!mounted) {
      return;
    }

    if (!available) {
      setState(() {
        _speechAvailable = false;
        _speechStatus = "Speech recognition is not available on this device";
      });
      return;
    }

    _speechAvailable = true;
    setState(() {
      _isListening = true;
      _speechStatus = "Listening to the student's statement...";
    });

    await _speechToText.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statementController.text = result.recognizedWords;
          _statementController.selection = TextSelection.fromPosition(
            TextPosition(offset: _statementController.text.length),
          );
        });
      },
    );
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.instance.submitMalpracticeReport(
        studentId: _studentIdController.text.trim(),
        studentLevel: _studentLevelController.text.trim(),
        courseTitle: _courseTitleController.text.trim(),
        courseCode: _courseCodeController.text.trim(),
        venue: _venueController.text.trim(),
        invigilatorName: _invigilatorController.text.trim(),
        incidentDescription: _incidentController.text.trim(),
        studentStatement: _statementController.text.trim(),
        studentFaceImagePath: _studentFaceImage?.path,
        foreignMaterialImagePath: _foreignMaterialImage?.path,
      );

      if (!mounted) {
        return;
      }

      _formKey.currentState!.reset();
      setState(() {
        _studentFaceImage = null;
        _studentFacePreviewBytes = null;
        _foreignMaterialImage = null;
        _foreignMaterialPreviewBytes = null;
        _invigilatorController.text = widget.currentUser?.username ?? '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Report submitted successfully")),
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
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModuleShell(
      title: 'Report Malpractice',
      description:
          'Record exam malpractice incidents with evidence and statements.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = (constraints.maxWidth * 0.05).clamp(
            16.0,
            32.0,
          );
          final verticalPadding = (constraints.maxHeight * 0.025).clamp(
            16.0,
            28.0,
          );
          final sectionGap = (constraints.maxHeight * 0.016).clamp(10.0, 18.0);
          final imageHeight = (constraints.maxHeight * 0.26).clamp(
            150.0,
            260.0,
          );
          final imageRadius = (constraints.maxWidth * 0.035).clamp(12.0, 18.0);

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    controller: _studentIdController,
                    decoration: const InputDecoration(labelText: "Student ID"),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Student ID is required"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _studentLevelController,
                    decoration: const InputDecoration(
                      labelText: "Student Level",
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Student level is required"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _courseTitleController,
                    decoration: const InputDecoration(
                      labelText: "Course Title",
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Course title is required"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _courseCodeController,
                    decoration: const InputDecoration(labelText: "Course Code"),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Course code is required"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _venueController,
                    decoration: const InputDecoration(labelText: "Exam Venue"),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Exam venue is required"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _invigilatorController,
                    decoration: const InputDecoration(
                      labelText: "Invigilator Name",
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Invigilator name is required"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _incidentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Incident Description",
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Describe the malpractice incident"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _statementController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: "Student Statement",
                      helperText: _speechStatus,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Add the student's statement or transcribe a voice note"
                        : null,
                  ),
                  SizedBox(height: sectionGap),
                  Wrap(
                    spacing: sectionGap,
                    runSpacing: sectionGap,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _captureStudentFaceEvidence,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _studentFaceImage == null
                              ? "Take Culprit Photo"
                              : "Retake Culprit Photo",
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _captureForeignMaterialEvidence,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text(
                          _foreignMaterialImage == null
                              ? "Take Foreign Material Photo"
                              : "Retake Foreign Material Photo",
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _toggleVoiceNote,
                        icon: Icon(
                          _isListening
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none,
                        ),
                        label: Text(
                          _isListening
                              ? "Stop Voice Note"
                              : "Record Voice Note",
                        ),
                      ),
                    ],
                  ),
                  if (_studentFacePreviewBytes != null) ...[
                    SizedBox(height: sectionGap),
                    Text(
                      "Student Facial Evidence",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: sectionGap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(imageRadius),
                      child: Image.memory(
                        _studentFacePreviewBytes!,
                        height: imageHeight,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  if (_foreignMaterialPreviewBytes != null) ...[
                    SizedBox(height: sectionGap),
                    Text(
                      "Foreign Material Evidence",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: sectionGap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(imageRadius),
                      child: Image.memory(
                        _foreignMaterialPreviewBytes!,
                        height: imageHeight,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  SizedBox(height: sectionGap * 1.25),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitReport,
                    child: Text(
                      _isSubmitting ? "Submitting..." : "Submit Report",
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
