import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vision_assist/services/cloud_vision_service.dart';
import 'package:vision_assist/widgets/object_detection_view.dart';
import 'dart:io';
import 'dart:async';
import 'package:image/image.dart' as img_lib;

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({super.key});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  FlutterTts _flutterTts = FlutterTts();
  bool _isDetecting = false;
  bool _isCameraInitialized = false;
  bool _isContinuousDetection = false;
  bool _isFlashOn = false;
  int _selectedCameraIndex = 0;
  Timer? _continuousDetectionTimer;

  // Object detection related - updated to use Cloud Vision
  final CloudVisionService _cloudVisionService = CloudVisionService();
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  List<DetectedColor> _detectedColors = [];

  // Detection confidence threshold
  double _confidenceThreshold = 0.15; // Initial value (15%)

  // UI Controls visibility
  bool _showSettings = false;
  bool _showColors = false;

  // Store the detection history for tracking objects over time
  List<String> _detectionHistory = [];
  final int _maxHistoryItems = 5;

  // New variables for the new processing logic
  bool _canProcess = true;
  bool _isBusy = false;
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastNoObjectTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _shouldSpeak = true;
  bool _isListening = true;
  String _feedbackText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeObjectDetector();
    _initializeCamera();
    _initializeTts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed - handle camera resources
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopContinuousDetection();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      try {
        _cameras = await availableCameras();
        if (_cameras.isNotEmpty) {
          // Use the selected camera index, or default to 0 if out of bounds
          _selectedCameraIndex =
              _selectedCameraIndex < _cameras.length ? _selectedCameraIndex : 0;

          _cameraController = CameraController(
            _cameras[_selectedCameraIndex],
            ResolutionPreset.medium,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.yuv420,
          );

          try {
            await _cameraController!.initialize();

            // We don't want to process the image stream automatically anymore
            // only when the user taps the capture button

            if (mounted) {
              setState(() {
                _isCameraInitialized = true;
              });
            }

            _speak(
              "Camera initialized. Point the camera at objects and tap the capture button.",
            );
          } catch (e) {
            print('Error initializing camera: $e');
            _speak("Could not initialize camera. ${e.toString()}");
          }
        }
      } catch (e) {
        print('Camera initialization error: $e');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is needed for object detection'),
          ),
        );
      }
    }
  }

  Future<void> _toggleCameraDirection() async {
    if (_cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No secondary camera available')),
      );
      return;
    }

    // Stop continuous detection during camera switch
    final wasContinuous = _isContinuousDetection;
    _stopContinuousDetection();

    // Toggle between front and back cameras
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;

    // Dispose current controller
    await _cameraController?.dispose();
    _cameraController = null;

    setState(() {
      _isCameraInitialized = false;
      _isFlashOn = false; // Reset flash when switching camera
    });

    // Initialize with new camera
    await _initializeCamera();

    // Resume continuous detection if it was on
    if (wasContinuous && _isCameraInitialized) {
      _startContinuousDetection();
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.description.lensDirection !=
            CameraLensDirection.back) {
      // Flash is typically only available on back cameras
      return;
    }

    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      print('Error toggling flash: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Flash control error: $e')));
    }
  }

  void _startContinuousDetection() {
    if (_continuousDetectionTimer != null) {
      _continuousDetectionTimer!.cancel();
    }

    // Run detection every 2 seconds
    _continuousDetectionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _detectObjects(),
    );

    setState(() {
      _isContinuousDetection = true;
    });

    // Feedback to user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Continuous detection enabled')),
    );
  }

  void _stopContinuousDetection() {
    if (_continuousDetectionTimer != null) {
      _continuousDetectionTimer!.cancel();
      _continuousDetectionTimer = null;
    }

    setState(() {
      _isContinuousDetection = false;
    });
  }

  void _toggleContinuousDetection() {
    if (_isContinuousDetection) {
      _stopContinuousDetection();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Continuous detection disabled')),
      );
    } else {
      _startContinuousDetection();
    }
  }

  Future<void> _detectObjects() async {
    if (_isDetecting ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isDetecting = true;
      _detectedObjects = []; // Clear previous detections
      _detectedColors = []; // Clear previous colors
    });

    try {
      // Capture image
      print('Taking picture for object detection...');
      final XFile photo = await _cameraController!.takePicture();
      print('Picture taken: ${photo.path}');

      // Save image to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/object_detection_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(photo.path).copy(tempFile.path);
      print('Image copied to temporary file: ${tempFile.path}');

      // Update the UI with the captured image
      setState(() {
        _imageFile = tempFile;
      });

      // Provide feedback to the user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing image with Google Cloud Vision API...'),
          duration: Duration(seconds: 1),
        ),
      );

      // Perform object detection with the current confidence threshold
      print(
        'Starting object detection process with threshold: $_confidenceThreshold',
      );
      final detectedObjects = await _cloudVisionService.detectObjectsFromImage(
        tempFile,
        confidenceThreshold: _confidenceThreshold, // Pass the current threshold
      );
      print('Detection completed, found ${detectedObjects.length} objects');

      // Perform color detection
      print('Starting color detection process');
      final detectedColors = await _cloudVisionService.detectColorsFromImage(
        tempFile,
      );
      print('Color detection completed, found ${detectedColors.length} colors');

      // Update UI and detect history only if we have new results
      if (mounted) {
        setState(() {
          // If we have objects, keep only the first one (most confident)
          if (detectedObjects.isNotEmpty) {
            _detectedObjects = [detectedObjects.first];
          } else {
            _detectedObjects = [];
          }

          _detectedColors = detectedColors;

          // Update detection history with new objects
          if (detectedObjects.isNotEmpty) {
            final Set<String> newLabels =
                detectedObjects.map((obj) => obj.label).toSet();
            _detectionHistory.addAll(newLabels);
            // Keep history at reasonable size
            if (_detectionHistory.length > _maxHistoryItems) {
              _detectionHistory = _detectionHistory.sublist(
                _detectionHistory.length - _maxHistoryItems,
              );
            }
          }
        });

        // Speak the detected objects and colors
        if (detectedObjects.isNotEmpty) {
          // Get the primary object
          final primaryObject = detectedObjects.first;
          String objectText =
              'I see a ${primaryObject.label} with confidence ${(primaryObject.confidence * 100).toInt()}%';

          // If we have color information, add the first detected color
          if (detectedColors.isNotEmpty) {
            objectText += '. The main color is ${detectedColors.first.name}';
          }

          await _flutterTts.speak(objectText);
        } else {
          print('No objects detected in the image');
          await _flutterTts.speak(
            'No objects detected. Please try pointing the camera at a different object.',
          );

          // Show a helpful message to the user
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Try pointing the camera at a clearer object or in better lighting',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Error during object detection: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during detection: $e'),
            backgroundColor: Colors.red,
          ),
        );

        // Still provide feedback even if there was an error
        await _flutterTts.speak(
          'Sorry, there was a problem detecting objects. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });

        // We don't automatically go back to camera view now
        // The user must explicitly tap the "Back to Camera" button
        _stopContinuousDetection(); // Always stop continuous detection after capture
      }
    }
  }

  Future<void> _initializeObjectDetector() async {
    try {
      print('Initializing Google Cloud Vision API for object detection...');
      await _cloudVisionService.initialize();
      print('Google Cloud Vision API initialized successfully');
    } catch (e) {
      print('Error initializing Cloud Vision API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing Cloud Vision API: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopContinuousDetection();
    _cameraController?.dispose();
    _flutterTts.stop();
    _cloudVisionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Object & Color Detection'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Settings button
          IconButton(
            icon: Icon(
              _showSettings ? Icons.settings : Icons.settings_outlined,
            ),
            onPressed: () {
              setState(() {
                _showSettings = !_showSettings;
              });
            },
            tooltip: 'Detection Settings',
          ),
          // Color toggle button
          if (_imageFile != null && _detectedColors.isNotEmpty)
            IconButton(
              icon: Icon(_showColors ? Icons.palette : Icons.palette_outlined),
              onPressed: () {
                setState(() {
                  _showColors = !_showColors;
                });
              },
              tooltip: 'Toggle Color Info',
            ),
          // Camera switch button
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _toggleCameraDirection,
              tooltip: 'Switch camera',
            ),
          // Flash toggle
          if (_cameraController?.description.lensDirection ==
              CameraLensDirection.back)
            IconButton(
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleFlash,
              tooltip: 'Toggle flash',
            ),
          // Reset button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _imageFile = null;
                _detectedObjects = [];
                _detectedColors = [];
                // Don't clear history
              });
            },
            tooltip: 'Reset camera view',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Settings panel
            if (_showSettings) _buildSettingsPanel(),

            // Main content
            Expanded(
              child:
                  _isCameraInitialized
                      ? _imageFile == null
                          ? _buildCameraPreview()
                          : ObjectDetectionView(
                            imageFile: _imageFile,
                            detectedObjects: _detectedObjects,
                            detectedColors:
                                _showColors ? _detectedColors : null,
                            onDetectPressed: _detectObjects,
                            isProcessing: _isDetecting,
                            detectionHistory: _detectionHistory,
                            onReset: () {
                              setState(() {
                                _imageFile = null;
                                _detectedObjects = [];
                                _detectedColors = [];
                              });
                            },
                          )
                      : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Initializing camera...'),
                          ],
                        ),
                      ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _imageFile == null && _isCameraInitialized
              ? FloatingActionButton.extended(
                onPressed: _detectObjects,
                backgroundColor: Colors.blue,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Capture & Detect'),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Detection Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _showSettings = false;
                  });
                },
                tooltip: 'Close settings',
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Confidence threshold slider
          Row(
            children: [
              const Text('Confidence threshold: '),
              Expanded(
                child: Slider(
                  value: _confidenceThreshold,
                  min: 0.05,
                  max: 0.5,
                  divisions: 9,
                  label: '${(_confidenceThreshold * 100).toInt()}%',
                  onChanged: (value) {
                    setState(() {
                      _confidenceThreshold = value;
                      // Apply new threshold to existing detections if we have any
                      if (_detectedObjects.isNotEmpty && _imageFile != null) {
                        _detectedObjects =
                            _detectedObjects
                                .where(
                                  (obj) =>
                                      obj.confidence >= _confidenceThreshold,
                                )
                                .toList();
                      }
                    });
                  },
                ),
              ),
              Text('${(_confidenceThreshold * 100).toInt()}%'),
            ],
          ),

          const Text(
            'Lower values show more objects with less certainty. Higher values show fewer, more certain objects.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Stack(
      children: [
        // Camera preview
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CameraPreview(_cameraController!),
          ),
        ),

        // Instructions overlay
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text(
                    'Point camera at objects to detect',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap the capture button to analyze',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Help information
        Positioned(
          top: 100,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: const [
                Text(
                  'Tips for better detection:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '• Center the object in frame\n• Ensure good lighting\n• Hold device steady\n• Try different angles',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // Recently detected objects history
        if (_detectionHistory.isNotEmpty)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Recently detected:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _detectionHistory.take(3).join(', '),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _speakResults(String text) async {
    if (!_isListening) return;

    try {
      print('Speaking: $text');
      await _flutterTts.speak(text);
    } catch (e) {
      print('Error speaking results: $e');
    }
  }

  void _speak(String text) async {
    if (!_isListening) return;

    try {
      print('Speaking: $text');
      await _flutterTts.speak(text);
    } catch (e) {
      print('Error speaking: $e');
    }
  }
}
