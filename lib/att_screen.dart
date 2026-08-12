import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/module_shell.dart';
import 'package:flutter_application_1/pdf_export_service.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class AttendanceModule extends StatefulWidget {
  const AttendanceModule({required this.currentUser, super.key});

  final LocalUser currentUser;

  @override
  State<AttendanceModule> createState() => _AttendanceModuleState();
}

class _AttendanceModuleState extends State<AttendanceModule>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
    ),
  );

  bool _isInitializingCamera = true;
  bool _isScanning = false;
  bool _isSwitchingCamera = false;
  bool _isExportingPdf = false;
  int _activeCameraIndex = 0;
  String _result = 'Open the camera and capture a student face.';
  String? _cameraError;
  String? _lastCourseCode;
  String? _lastCourseTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializingCamera = true;
      _cameraError = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraError = 'No camera found on this device.';
          _isInitializingCamera = false;
        });
        return;
      }

      _cameras = cameras;
      final frontIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (_activeCameraIndex >= cameras.length) {
        _activeCameraIndex = 0;
      }
      if (frontIndex != -1 && _cameraController == null) {
        _activeCameraIndex = frontIndex;
      }

      await _setCameraController(cameras[_activeCameraIndex]);
    } on CameraException catch (error) {
      setState(() {
        _cameraError = _cameraMessageFor(error);
        _isInitializingCamera = false;
      });
    } catch (_) {
      setState(() {
        _cameraError = 'Unable to start the camera on this device.';
        _isInitializingCamera = false;
      });
    }
  }

  Future<void> _setCameraController(CameraDescription description) async {
    final previousController = _cameraController;
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = controller;
    await previousController?.dispose();
    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _isInitializingCamera = false;
      _cameraError = null;
      _result = 'Camera ready. Capture a student face for detection.';
    });
  }

  String _cameraMessageFor(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'Camera permission was denied.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera access was denied earlier. Enable it from device settings.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return error.description ?? 'Unable to initialize the camera.';
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera) {
      return;
    }

    setState(() {
      _isSwitchingCamera = true;
      _result = 'Switching camera...';
    });

    try {
      _activeCameraIndex = (_activeCameraIndex + 1) % _cameras.length;
      await _setCameraController(_cameras[_activeCameraIndex]);
    } on CameraException catch (error) {
      setState(() {
        _cameraError = _cameraMessageFor(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _captureAndDetectFace() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
      _result = 'Capturing image and detecting face...';
    });

    try {
      final image = await controller.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) {
        return;
      }

      if (faces.isEmpty) {
        setState(() {
          _result =
              'No face detected. Ask the student to look directly at the camera.';
        });
        return;
      }
      if (faces.length > 1) {
        setState(() {
          _result =
              '${faces.length} faces detected. Ensure only one student is in frame.';
        });
        return;
      }

      final student = await ApiService.instance.recognizeStudent(
        faceImagePath: image.path,
        recordedBy: widget.currentUser.username,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _result =
            'Attendance recorded\n\n'
            'Name: ${student['full_name']}\n'
            'Student ID: ${student['student_id']}\n'
            'Programme: ${student['programme']}\n'
            'Level: ${student['level']}\n'
            'Paper: ${student['course_title']} (${student['course_code']})\n'
            'Venue: ${student['venue']}\n'
            'Exam time: ${student['start_time']} - ${student['end_time']}\n'
            'Match confidence: ${((student['confidence'] as num) * 100).toStringAsFixed(1)}%';
        _lastCourseCode = student['course_code'] as String;
        _lastCourseTitle = student['course_title'] as String;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _result = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _openAttendancePdf() async {
    final courseCode = _lastCourseCode;
    if (courseCode == null) {
      return;
    }

    setState(() {
      _isExportingPdf = true;
      _result = 'Preparing attendance PDF...';
    });

    try {
      final bytes = await ApiService.instance.downloadAttendancePdf(
        courseCode: courseCode,
        courseTitle: _lastCourseTitle,
      );
      await PdfExportService.instance.saveAndOpen(
        fileName: 'attendance_${courseCode.replaceAll(' ', '_')}.pdf',
        bytes: bytes,
      );
      if (mounted) {
        setState(() => _result = 'Attendance PDF opened.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _result = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Widget _buildCameraPanel(double panelRadius) {
    final controller = _cameraController;

    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (_isInitializingCamera ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(panelRadius.clamp(16.0, 28.0)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = controller.value.previewSize;
          final previewWidth = previewSize?.height ?? constraints.maxWidth;
          final previewHeight = previewSize?.width ?? constraints.maxHeight;
          final maxGuideWidth = math.max(96.0, constraints.maxWidth * 0.72);
          final guideWidth = (constraints.maxWidth * 0.48)
              .clamp(math.min(120.0, maxGuideWidth), maxGuideWidth)
              .toDouble();
          final maxGuideHeight = math.max(96.0, constraints.maxHeight * 0.86);
          final guideHeight = (guideWidth * 1.24)
              .clamp(math.min(120.0, maxGuideHeight), maxGuideHeight)
              .toDouble();

          return Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: CameraPreview(controller),
                ),
              ),
              Center(
                child: Container(
                  width: guideWidth,
                  height: guideHeight,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.cyanAccent, width: 2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ModuleShell(
      title: 'Biometric Attendance',
      description:
          'Scan a face to identify the student and automatically record today’s scheduled paper.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = constraints.maxHeight * 0.5;
          final panelRadius = constraints.maxWidth * 0.05;

          return ListView(
            children: [
              Container(
                height: panelHeight.clamp(180.0, 360.0),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF12303A), Color(0xFF0F766E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(
                    panelRadius.clamp(16.0, 28.0),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2212303A),
                      blurRadius: 24,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: _buildCameraPanel(panelRadius),
              ),
              SizedBox(
                height: (constraints.maxHeight * 0.03).clamp(12.0, 22.0),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  _result,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: (constraints.maxWidth * 0.035).clamp(16.0, 20.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: (constraints.maxHeight * 0.03).clamp(12.0, 22.0),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isInitializingCamera || _isScanning
                        ? null
                        : _captureAndDetectFace,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.face_retouching_natural),
                    label: Text(_isScanning ? 'Capturing...' : 'Capture Face'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isInitializingCamera || _isSwitchingCamera
                        ? null
                        : _switchCamera,
                    icon: const Icon(Icons.cameraswitch_outlined),
                    label: const Text('Switch Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isExportingPdf || _lastCourseCode == null
                        ? null
                        : _openAttendancePdf,
                    icon: _isExportingPdf
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _lastCourseCode == null
                          ? 'Attendance PDF'
                          : 'Paper Attendance PDF',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
