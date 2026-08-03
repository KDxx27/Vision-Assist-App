import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:vision_assist/services/cloud_vision_service.dart';

class ColorDetectionScreen extends StatefulWidget {
  const ColorDetectionScreen({super.key});

  @override
  State<ColorDetectionScreen> createState() => _ColorDetectionScreenState();
}

class _ColorDetectionScreenState extends State<ColorDetectionScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  FlutterTts _flutterTts = FlutterTts();
  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  File? _imageFile;

  // Color detection related
  List<IdentifiedColor> _detectedColors = [];
  final CloudVisionService _visionService = CloudVisionService();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeTts();
    _initializeVisionApi();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _initializeVisionApi() async {
    try {
      await _visionService.initialize();
    } catch (e) {
      print('Error initializing Google Cloud Vision API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize Vision API: $e')),
        );
      }
    }
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      try {
        _cameras = await availableCameras();
        if (_cameras.isNotEmpty) {
          _cameraController = CameraController(
            _cameras.first,
            ResolutionPreset.high,
            enableAudio: false,
          );

          await _cameraController!.initialize();

          if (mounted) {
            setState(() {
              _isCameraInitialized = true;
            });
          }
        }
      } catch (e) {
        print('Camera initialization error: $e');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is needed for color detection'),
          ),
        );
      }
    }
  }

  Future<void> _captureAndDetectColors() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Capture the entire image
      final XFile photo = await _cameraController!.takePicture();

      // Save image to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/color_detection_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(photo.path).copy(tempFile.path);

      // Update the UI with the captured image
      setState(() {
        _imageFile = tempFile;
      });

      // Analyze the entire image using Google Cloud Vision API
      _speak('Analyzing image colors');
      await _processImageWithCloudVision(tempFile);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error during detection: $e')));
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Use Google Cloud Vision API for color detection on the entire image
  Future<void> _processImageWithCloudVision(File imageFile) async {
    try {
      // Call Google Cloud Vision API for color detection on the whole image
      final detectedColors = await _visionService.detectColorsFromImage(
        imageFile,
      );

      if (detectedColors.isEmpty) {
        _speak('No colors detected in the image');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No colors detected in the image')),
        );
        return;
      }

      // Convert the API response to our app's format
      final List<IdentifiedColor> colors =
          detectedColors.map((detectedColor) {
            return IdentifiedColor(
              color: detectedColor.color,
              name: detectedColor.name,
              hexCode:
                  '#${detectedColor.color.red.toRadixString(16).padLeft(2, '0')}${detectedColor.color.green.toRadixString(16).padLeft(2, '0')}${detectedColor.color.blue.toRadixString(16).padLeft(2, '0')}',
              percentage:
                  detectedColor.score * 100, // Convert score to percentage
            );
          }).toList();

      // Sort by score (highest first)
      colors.sort((a, b) => b.percentage.compareTo(a.percentage));

      setState(() {
        _detectedColors = colors;
      });

      // Announce the dominant colors
      if (colors.isNotEmpty) {
        final mainColor = colors.first;
        await _speak(
          'The dominant color is ${mainColor.name}, which makes up ${mainColor.percentage.round()}% of the image',
        );
      }
    } catch (e) {
      print('Error processing image with Cloud Vision: $e');
      _speak('Error detecting colors. Please try again.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error detecting colors: $e')));
    }
  }

  // Speak the given text
  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  // Find a name for a color (legacy method, only used as fallback)
  String _findColorName(Color color) {
    // Map of color names to their RGB values
    final colorMap = {
      'Red': Colors.red,
      'Pink': Colors.pink,
      'Purple': Colors.purple,
      'Deep Purple': Colors.deepPurple,
      'Indigo': Colors.indigo,
      'Blue': Colors.blue,
      'Light Blue': Colors.lightBlue,
      'Cyan': Colors.cyan,
      'Teal': Colors.teal,
      'Green': Colors.green,
      'Light Green': Colors.lightGreen,
      'Lime': Colors.lime,
      'Yellow': Colors.yellow,
      'Amber': Colors.amber,
      'Orange': Colors.orange,
      'Deep Orange': Colors.deepOrange,
      'Brown': Colors.brown,
      'Grey': Colors.grey,
      'Blue Grey': Colors.blueGrey,
      'Black': Colors.black,
      'White': Colors.white,
    };

    // Find the color with the smallest distance
    String closestColorName = 'Unknown';
    double minDistance = double.infinity;

    for (final entry in colorMap.entries) {
      final namedColor = entry.value;

      // Calculate Euclidean distance in RGB space
      final rDiff = (color.red - namedColor.red).toDouble();
      final gDiff = (color.green - namedColor.green).toDouble();
      final bDiff = (color.blue - namedColor.blue).toDouble();

      final distance = math.sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff);

      if (distance < minDistance) {
        minDistance = distance;
        closestColorName = entry.key;
      }
    }

    return closestColorName;
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Color Detection'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _imageFile = null;
                _detectedColors = [];
              });
            },
            tooltip: 'Reset camera view',
          ),
        ],
      ),
      body: SafeArea(
        child:
            _isCameraInitialized
                ? _imageFile == null
                    ? _buildCameraPreview()
                    : _buildResultsView()
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
      floatingActionButton:
          _imageFile == null && _isCameraInitialized
              ? FloatingActionButton.extended(
                onPressed: _captureAndDetectColors,
                backgroundColor: Colors.orange,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Capture & Detect'),
              )
              : _imageFile != null
              ? FloatingActionButton.extended(
                onPressed: () {
                  setState(() {
                    _imageFile = null;
                    _detectedColors = [];
                  });
                  _speak('Ready to detect new colors');
                },
                backgroundColor: Colors.orange,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCameraPreview() {
    return Stack(
      children: [
        // Camera preview
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CameraPreview(_cameraController!),
          ),
        ),

        // Center text overlay
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Tap "Capture & Detect" to analyze colors',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        // API powered badge
        Positioned(
          bottom: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'Google Cloud Vision',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView() {
    return Column(
      children: [
        // Display the captured image
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(_imageFile!, fit: BoxFit.cover),
            ),
          ),
        ),

        // Display detected colors
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Text(
                        'Detected Colors:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      // API Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_done,
                              color: Colors.deepPurple,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Cloud Vision API',
                              style: TextStyle(
                                color: Colors.deepPurple,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child:
                      _isProcessing
                          ? const Center(child: CircularProgressIndicator())
                          : _detectedColors.isEmpty
                          ? const Center(child: Text('No colors detected'))
                          : ListView.builder(
                            itemCount: _detectedColors.length,
                            itemBuilder: (context, index) {
                              final color = _detectedColors[index];
                              return ColorListItem(
                                color: color,
                                onTap: () {
                                  _speak(
                                    'This is ${color.name} with hex code ${color.hexCode}',
                                  );
                                },
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class IdentifiedColor {
  final Color color;
  final String name;
  final String hexCode;
  final double percentage;

  IdentifiedColor({
    required this.color,
    required this.name,
    required this.hexCode,
    required this.percentage,
  });
}

class ColorListItem extends StatelessWidget {
  final IdentifiedColor color;
  final VoidCallback onTap;

  const ColorListItem({super.key, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Color swatch
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.color,
                  border: Border.all(color: Colors.black, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 16),
              // Color information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      color.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hex: ${color.hexCode}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              // Percentage
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${color.percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
