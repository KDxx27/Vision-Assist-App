import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:clipboard/clipboard.dart';
import 'dart:io';
import 'dart:async';

class TextRecognitionScreen extends StatefulWidget {
  const TextRecognitionScreen({super.key});

  @override
  State<TextRecognitionScreen> createState() => _TextRecognitionScreenState();
}

class _TextRecognitionScreenState extends State<TextRecognitionScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  FlutterTts _flutterTts = FlutterTts();
  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  File? _imageFile;

  // Text recognition related
  final _textRecognizer = TextRecognizer();
  RecognizedText? _recognizedTextObject;
  String _recognizedText = '';
  bool _isReading = false;

  // Image picker for gallery images
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeTts();
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
            content: Text('Camera permission is needed for text recognition'),
          ),
        );
      }
    }
  }

  Future<void> _captureAndRecognizeText() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Capture image
      final XFile photo = await _cameraController!.takePicture();

      // Save image to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/text_recognition_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(photo.path).copy(tempFile.path);

      // Update the UI with the captured image
      setState(() {
        _imageFile = tempFile;
      });

      // Process image to extract text using ML Kit
      await _processImageForText(tempFile);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during text recognition: $e')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile? pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
      );

      if (pickedImage == null) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final imageFile = File(pickedImage.path);
      setState(() {
        _imageFile = imageFile;
      });

      await _processImageForText(imageFile);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Process image for text using Google ML Kit
  Future<void> _processImageForText(File imageFile) async {
    try {
      // Create input image from file
      final inputImage = InputImage.fromFile(imageFile);

      // Process the image
      final recognizedText = await _textRecognizer.processImage(inputImage);

      String extractedText = recognizedText.text;

      setState(() {
        _recognizedTextObject = recognizedText;
        _recognizedText = extractedText;
      });

      // Announce the recognized text count
      final wordCount =
          extractedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (wordCount > 0) {
        await _flutterTts.speak(
          'Recognized $wordCount words. Tap Read Text to hear them.',
        );
      } else {
        await _flutterTts.speak('No text detected in this image.');
      }
    } catch (e) {
      setState(() {
        _recognizedText = 'Error recognizing text: $e';
      });
    }
  }

  Future<void> _readRecognizedText() async {
    if (_recognizedText.isEmpty) return;

    setState(() {
      _isReading = true;
    });

    try {
      await _flutterTts.speak(_recognizedText);

      // Wait for speech to complete with a small delay
      await Future.delayed(const Duration(seconds: 1));

      // For text of average length, estimate speech duration
      final wordCount =
          _recognizedText
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
      final estimatedDuration = Duration(
        milliseconds: wordCount * 250,
      ); // ~250ms per word

      await Future.delayed(estimatedDuration);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error while reading text: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isReading = false;
        });
      }
    }
  }

  Future<void> _stopReading() async {
    await _flutterTts.stop();
    if (mounted) {
      setState(() {
        _isReading = false;
      });
    }
  }

  Future<void> _copyToClipboard() async {
    if (_recognizedText.isEmpty) return;

    try {
      await FlutterClipboard.copy(_recognizedText);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Text copied to clipboard')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error copying to clipboard: $e')));
    }
  }

  Future<void> _shareRecognizedText() async {
    if (_recognizedText.isEmpty) return;

    try {
      await Share.share(
        _recognizedText,
        subject: 'Recognized Text from Vision Assist',
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sharing text: $e')));
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _flutterTts.stop();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Recognition'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _imageFile = null;
                _recognizedText = '';
                _recognizedTextObject = null;
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
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget? _buildFloatingActionButton() {
    if (!_isCameraInitialized) return null;

    if (_imageFile == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'pickImage',
            onPressed: _pickImageFromGallery,
            backgroundColor: Colors.amber,
            child: const Icon(Icons.photo_library),
            tooltip: 'Pick image from gallery',
          ),
          const SizedBox(width: 16),
          FloatingActionButton.extended(
            heroTag: 'takePhoto',
            onPressed: _captureAndRecognizeText,
            backgroundColor: Colors.green,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Capture & Recognize'),
          ),
        ],
      );
    } else if (_recognizedText.isNotEmpty) {
      return _isReading
          ? FloatingActionButton.extended(
            onPressed: _stopReading,
            backgroundColor: Colors.red,
            icon: const Icon(Icons.stop),
            label: const Text('Stop Reading'),
          )
          : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'copy',
                onPressed: _copyToClipboard,
                backgroundColor: Colors.blue,
                child: const Icon(Icons.copy),
                tooltip: 'Copy to clipboard',
              ),
              const SizedBox(width: 16),
              FloatingActionButton.extended(
                heroTag: 'read',
                onPressed: _readRecognizedText,
                backgroundColor: Colors.green,
                icon: const Icon(Icons.volume_up),
                label: const Text('Read Text'),
              ),
              const SizedBox(width: 16),
              FloatingActionButton(
                heroTag: 'share',
                onPressed: _shareRecognizedText,
                backgroundColor: Colors.purple,
                child: const Icon(Icons.share),
                tooltip: 'Share text',
              ),
            ],
          );
    }

    return null;
  }

  Widget _buildCameraPreview() {
    return Stack(
      children: [
        // Camera preview
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 2),
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
              child: const Text(
                'Position camera over text to recognize',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
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
              border: Border.all(color: Colors.green, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_imageFile!, fit: BoxFit.contain),
                ),
                if (_recognizedTextObject != null)
                  CustomPaint(
                    painter: TextRecognitionPainter(
                      recognizedText: _recognizedTextObject!,
                      originalImageSize: Size(
                        _imageFile!.readAsBytesSync().length.toDouble(),
                        _imageFile!.readAsBytesSync().length.toDouble(),
                      ), // This is an approximation - ideally we'd get actual image dimensions
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Display recognized text
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(11),
                      topRight: Radius.circular(11),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.text_fields, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Recognized Text:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child:
                      _isProcessing
                          ? const Center(child: CircularProgressIndicator())
                          : _recognizedText.isEmpty
                          ? const Center(child: Text('No text recognized'))
                          : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _recognizedText,
                              style: const TextStyle(fontSize: 16, height: 1.5),
                            ),
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

class TextRecognitionPainter extends CustomPainter {
  final RecognizedText recognizedText;
  final Size originalImageSize;

  TextRecognitionPainter({
    required this.recognizedText,
    required this.originalImageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..color = Colors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    for (TextBlock block in recognizedText.blocks) {
      // Scale the bounding box to match the display size
      final scaledRect = _scaleRect(block.boundingBox, size);

      // Draw rectangle around text block
      canvas.drawRect(scaledRect, paint);
    }
  }

  Rect _scaleRect(Rect rect, Size canvasSize) {
    double scaleX = canvasSize.width / originalImageSize.width;
    double scaleY = canvasSize.height / originalImageSize.height;

    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(TextRecognitionPainter oldDelegate) {
    return recognizedText != oldDelegate.recognizedText;
  }
}
