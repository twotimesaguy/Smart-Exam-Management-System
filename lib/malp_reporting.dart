import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/module_shell.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;

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
  final TextEditingController _chiefInvigilatorController =
      TextEditingController();
  final TextEditingController _incidentController = TextEditingController();
  final TextEditingController _statementController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speechToText = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();

  XFile? _studentFaceImage;
  Uint8List? _studentFacePreviewBytes;
  XFile? _foreignMaterialImage;
  Uint8List? _foreignMaterialPreviewBytes;
  bool _isRecordingVoiceNote = false;
  bool _speechAvailable = false;
  bool _isSubmitting = false;
  bool _chiefInvigilatorApproved = false;
  String? _voiceRecordingPath;
  Uint8List? _voiceRecordingBytes;
  String? _voiceRecordingFileName;
  Completer<void>? _transcriptionFinished;
  bool _hasTranscription = false;
  bool _isStoppingVoiceNote = false;
  bool _isRestartingSpeech = false;
  final List<String> _transcriptSegments = [];
  String _activeTranscript = '';
  String _statementBeforeRecording = '';
  String? _speechError;
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
    _chiefInvigilatorController.dispose();
    _incidentController.dispose();
    _statementController.dispose();
    _transcriptionFinished?.complete();
    _speechToText.stop();
    unawaited(_audioRecorder.dispose());
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
    if (_isRecordingVoiceNote) {
      setState(() {
        _isStoppingVoiceNote = true;
        _speechStatus = 'Finishing transcription and saving the voice note...';
      });
      await _speechToText.stop();
      await _waitForTranscription();
      _finishCurrentSpeechSegment();
      final recordingPath = await _audioRecorder.stop();
      if (!mounted) {
        return;
      }

      if (recordingPath == null) {
        setState(() {
          _isRecordingVoiceNote = false;
          _isStoppingVoiceNote = false;
          _speechStatus = 'Voice recording could not be saved.';
        });
        return;
      }

      try {
        final recordingBytes = kIsWeb
            ? await _readWebRecording(recordingPath)
            : null;
        if (!mounted) {
          return;
        }
        setState(() {
          _isRecordingVoiceNote = false;
          _isStoppingVoiceNote = false;
          _voiceRecordingPath = kIsWeb ? null : recordingPath;
          _voiceRecordingBytes = recordingBytes;
          _voiceRecordingFileName = kIsWeb
              ? 'student_statement.webm'
              : 'student_statement.m4a';
          _speechStatus = _hasTranscription
              ? 'Voice note saved and transcribed.'
              : _speechError == null
              ? 'Voice note saved, but no speech was recognised. Try again or type the statement.'
              : 'Voice note saved, but transcription failed: $_speechError';
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _isRecordingVoiceNote = false;
            _isStoppingVoiceNote = false;
            _speechStatus =
                'The recording was made but could not be prepared for upload.';
          });
        }
      }
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
              _finishCurrentSpeechSegment();
              if (_isRecordingVoiceNote && !_isStoppingVoiceNote) {
                setState(() {
                  _speechStatus =
                      "Still recording. Continuing live transcription...";
                });
                unawaited(_restartLiveTranscription());
              } else {
                _completeTranscription();
              }
            }
          },
          onError: (error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _speechError = error.errorMsg;
              _speechStatus = "Voice note unavailable: ${error.errorMsg}";
            });
            if (_isRecordingVoiceNote && !_isStoppingVoiceNote) {
              unawaited(_restartLiveTranscription());
            } else {
              _completeTranscription();
            }
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
    _hasTranscription = false;
    _isStoppingVoiceNote = false;
    _isRestartingSpeech = false;
    _transcriptSegments.clear();
    _activeTranscript = '';
    _statementBeforeRecording = _statementController.text.trim();
    _speechError = null;
    if (!await _audioRecorder.hasPermission()) {
      if (mounted) {
        setState(() {
          _speechStatus =
              'Microphone permission is required to save the voice recording.';
        });
      }
      return;
    }
    try {
      final recordingPath = await _recordingPath();
      await _audioRecorder.start(
        RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
        path: recordingPath,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _speechStatus =
              'Unable to start the voice recorder. Check microphone permission.';
        });
      }
      return;
    }

    setState(() {
      _isRecordingVoiceNote = true;
      _speechStatus = "Recording and transcribing the student's statement...";
    });
    await _startLiveTranscription();
  }

  Future<void> _startLiveTranscription() async {
    if (!_isRecordingVoiceNote || _isStoppingVoiceNote || !mounted) {
      return;
    }

    _transcriptionFinished = Completer<void>();
    try {
      await _speechToText.listen(
        // Keep the recognizer open until the user taps Stop. Some devices end
        // a system speech session early; the status listener starts it again.
        listenFor: const Duration(hours: 24),
        pauseFor: const Duration(hours: 24),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          if (!mounted) {
            return;
          }
          final transcript = result.recognizedWords.trim();
          if (transcript.isEmpty) {
            if (result.finalResult) {
              _finishCurrentSpeechSegment();
              _completeTranscription();
            }
            return;
          }

          setState(() {
            _hasTranscription = true;
            _activeTranscript = transcript;
            _updateStudentStatementFromTranscript();
          });
          if (result.finalResult) {
            _finishCurrentSpeechSegment();
            _completeTranscription();
          }
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechError = error.toString();
        _speechStatus = 'Live transcription could not start: $_speechError';
      });
      _completeTranscription();
    }
  }

  Future<void> _restartLiveTranscription() async {
    if (_isRestartingSpeech || !_isRecordingVoiceNote || _isStoppingVoiceNote) {
      return;
    }

    _isRestartingSpeech = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _startLiveTranscription();
    } finally {
      _isRestartingSpeech = false;
    }
  }

  void _finishCurrentSpeechSegment() {
    final transcript = _activeTranscript.trim();
    if (transcript.isEmpty) {
      return;
    }
    if (_transcriptSegments.isEmpty || _transcriptSegments.last != transcript) {
      _transcriptSegments.add(transcript);
    }
    _activeTranscript = '';
    if (mounted) {
      setState(_updateStudentStatementFromTranscript);
    }
  }

  void _updateStudentStatementFromTranscript() {
    final transcript = [
      ..._transcriptSegments,
      if (_activeTranscript.trim().isNotEmpty) _activeTranscript.trim(),
    ].join(' ').trim();
    final statement = [
      if (_statementBeforeRecording.isNotEmpty) _statementBeforeRecording,
      if (transcript.isNotEmpty) transcript,
    ].join('\n').trim();
    _statementController.text = statement;
    _statementController.selection = TextSelection.fromPosition(
      TextPosition(offset: statement.length),
    );
  }

  void _completeTranscription() {
    final completer = _transcriptionFinished;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _waitForTranscription() async {
    final completer = _transcriptionFinished;
    if (completer == null) {
      return;
    }
    await completer.future.timeout(
      const Duration(milliseconds: 750),
      onTimeout: () {},
    );
  }

  Future<String> _recordingPath() async {
    if (kIsWeb) {
      return '';
    }
    final directory = await getTemporaryDirectory();
    return '${directory.path}/student_statement_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  Future<Uint8List> _readWebRecording(String path) async {
    final response = await http.get(Uri.parse(path));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Could not read the browser recording.');
    }
    return response.bodyBytes;
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_chiefInvigilatorApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chief invigilator approval is required.'),
        ),
      );
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
        chiefInvigilatorName: _chiefInvigilatorController.text.trim(),
        chiefInvigilatorApproved: _chiefInvigilatorApproved,
        incidentDescription: _incidentController.text.trim(),
        studentStatement: _statementController.text.trim(),
        studentFaceImagePath: _studentFaceImage?.path,
        foreignMaterialImagePath: _foreignMaterialImage?.path,
        studentStatementAudioPath: _voiceRecordingPath,
        studentStatementAudioBytes: _voiceRecordingBytes,
        studentStatementAudioFileName: _voiceRecordingFileName,
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
        _voiceRecordingPath = null;
        _voiceRecordingBytes = null;
        _voiceRecordingFileName = null;
        _invigilatorController.text = widget.currentUser?.username ?? '';
        _chiefInvigilatorController.clear();
        _chiefInvigilatorApproved = false;
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
                    controller: _chiefInvigilatorController,
                    decoration: const InputDecoration(
                      labelText: 'Chief Invigilator Name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Chief invigilator name is required'
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _chiefInvigilatorApproved,
                    onChanged: (value) {
                      setState(
                        () => _chiefInvigilatorApproved = value ?? false,
                      );
                    },
                    title: const Text('Chief invigilator approval'),
                  ),
                  SizedBox(height: sectionGap),
                  TextFormField(
                    controller: _incidentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Invigilator's Description",
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Add the invigilator's description"
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
                          _isRecordingVoiceNote
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none,
                        ),
                        label: Text(
                          _isRecordingVoiceNote
                              ? "Stop Voice Note"
                              : "Record Voice Note",
                        ),
                      ),
                    ],
                  ),
                  if (_voiceRecordingPath != null ||
                      _voiceRecordingBytes != null) ...[
                    SizedBox(height: sectionGap),
                    Text(
                      'Voice recording attached. The disciplinary officer can play it from the case.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
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
