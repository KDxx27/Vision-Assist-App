import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vision_assist/services/cloud_vision_service.dart';
import 'dart:ui' as ui;

class ObjectDetectionView extends StatelessWidget {
  final File? imageFile;
  final List<DetectedObject> detectedObjects;
  final List<DetectedColor>? detectedColors;
  final VoidCallback onDetectPressed;
  final VoidCallback onReset;
  final bool isProcessing;
  final List<String> detectionHistory;

  const ObjectDetectionView({
    Key? key,
    required this.imageFile,
    required this.detectedObjects,
    this.detectedColors,
    required this.onDetectPressed,
    required this.onReset,
    required this.isProcessing,
    required this.detectionHistory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageFile == null) {
      return const Center(child: Text('No image captured'));
    }

    return Stack(
      children: [
        // Image with overlay
        Positioned.fill(
          child: Column(children: [Expanded(child: _buildResultView(context))]),
        ),

        // Bottom action bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: _buildBottomBar(context),
        ),

        // Processing indicator
        if (isProcessing)
          Positioned.fill(
            child: Container(
              color: Colors.black38,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Processing image...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultView(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The captured image
        Image.file(imageFile!, fit: BoxFit.contain),

        // Object detection overlay (bounding boxes)
        if (detectedObjects.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: BoundingBoxPainter(
                  detectedObjects: detectedObjects,
                  widgetSize: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              );
            },
          ),

        // Additional information panel
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Results card
              Card(
                color: Colors.white.withOpacity(0.8),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detectedObjects.isEmpty
                            ? 'No objects detected'
                            : 'Detected ${detectedObjects.length} object${detectedObjects.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Object list
                      for (var obj in detectedObjects)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${obj.label} (${(obj.confidence * 100).toInt()}%)',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Color information
                      if (detectedColors != null &&
                          detectedColors!.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'Detected Colors:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              detectedColors!.map((color) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.color,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.black12,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '${color.name} (${color.score.toStringAsFixed(2)})',
                                    style: TextStyle(
                                      color: _contrastColor(color.color),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ],

                      // History
                      if (detectionHistory.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'Recent detections:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detectionHistory.take(5).join(', '),
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Back to Camera'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  // Helper method to get a contrasting text color
  Color _contrastColor(Color backgroundColor) {
    // Calculate the perceptive luminance
    double luminance =
        (0.299 * backgroundColor.red +
            0.587 * backgroundColor.green +
            0.114 * backgroundColor.blue) /
        255;

    // Return black for bright colors and white for dark ones
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> detectedObjects;
  final Size widgetSize;

  BoundingBoxPainter({required this.detectedObjects, required this.widgetSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.red
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);

    // Background fill for the text
    final backgroundPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.7)
          ..style = PaintingStyle.fill;

    for (final object in detectedObjects) {
      // The coordinates are normalized (0-1), so we scale them to canvas size
      final rect = Rect.fromLTWH(
        object.boundingBox.left * size.width,
        object.boundingBox.top * size.height,
        object.boundingBox.width * size.width,
        object.boundingBox.height * size.height,
      );

      // Draw bounding box
      canvas.drawRect(rect, paint);

      // Prepare label text
      final labelText = '${object.label} ${(object.confidence * 100).toInt()}%';
      textPainter.text = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );

      textPainter.layout();

      // Draw text background
      final textBackgroundRect = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      canvas.drawRect(textBackgroundRect, backgroundPaint);

      // Draw label text
      textPainter.paint(
        canvas,
        Offset(rect.left + 4, rect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
