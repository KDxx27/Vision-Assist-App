import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DetectedObject {
  final String label;
  final double confidence;
  final Rect boundingBox;
  final Color color;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.color,
  });
}

class DetectedColor {
  final Color color;
  final String name;
  final double score;
  final double pixelFraction;

  DetectedColor({
    required this.color,
    required this.name,
    required this.score,
    required this.pixelFraction,
  });
}

class CloudVisionService {
  static final List<Color> _colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
  ];

  // Google Cloud Vision API client
  vision.VisionApi? _visionApi;
  bool _isInitialized = false;

  // Credentials file information
  final String _credentialsFilePath =
      'assets/coral-idiom-448917-f6-59bf3582a49c.json';

  // Singleton pattern
  static final CloudVisionService _instance = CloudVisionService._internal();
  factory CloudVisionService() => _instance;
  CloudVisionService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load service account credentials
      final credentialsJson = await rootBundle.loadString(_credentialsFilePath);
      final credentials = json.decode(credentialsJson);

      final accountCredentials = ServiceAccountCredentials.fromJson(
        credentials,
      );

      // Get authenticated HTTP client
      final scopes = [vision.VisionApi.cloudVisionScope];
      final client = await clientViaServiceAccount(accountCredentials, scopes);

      // Create Vision API client
      _visionApi = vision.VisionApi(client);

      _isInitialized = true;
      print('Google Cloud Vision API initialized successfully');
    } catch (e) {
      print('Error initializing Google Cloud Vision API: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<List<DetectedObject>> detectObjectsFromImage(
    File imageFile, {
    double confidenceThreshold = 0.15,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_visionApi == null) {
      print('Google Cloud Vision API client is null, reinitializing...');
      await initialize();
      if (_visionApi == null) {
        print('Failed to initialize Google Cloud Vision API client');
        return [];
      }
    }

    try {
      print('Starting object detection with Google Cloud Vision API...');
      print('Image path: ${imageFile.path}');
      print('Image exists: ${await imageFile.exists()}');
      print('Image size: ${await imageFile.length()} bytes');
      print('Using confidence threshold: $confidenceThreshold');

      // Read image as bytes
      final imageBytes = await imageFile.readAsBytes();
      final encodedImage = base64Encode(imageBytes);

      // Create image request
      final request =
          vision.AnnotateImageRequest()
            ..image = (vision.Image()..content = encodedImage)
            ..features = [
              vision.Feature()
                ..type = 'OBJECT_LOCALIZATION'
                ..maxResults = 10,
              vision.Feature()
                ..type = 'LABEL_DETECTION'
                ..maxResults = 10,
            ];

      // Send request to Cloud Vision API
      final response = await _visionApi!.images.annotate(
        vision.BatchAnnotateImagesRequest()..requests = [request],
      );

      if (response.responses == null || response.responses!.isEmpty) {
        print('No response from Cloud Vision API');
        return [];
      }

      final annotateResponse = response.responses!.first;
      List<DetectedObject> detectedObjects = [];

      // Process localized objects
      if (annotateResponse.localizedObjectAnnotations != null) {
        for (
          int i = 0;
          i < annotateResponse.localizedObjectAnnotations!.length;
          i++
        ) {
          final object = annotateResponse.localizedObjectAnnotations![i];
          final confidence = object.score ?? 0.0;

          if (confidence >= confidenceThreshold) {
            // Create normalized bounding box (values are already normalized 0-1)
            Rect boundingBox = Rect.zero;
            if (object.boundingPoly != null &&
                object.boundingPoly!.normalizedVertices != null &&
                object.boundingPoly!.normalizedVertices!.length >= 4) {
              final vertices = object.boundingPoly!.normalizedVertices!;

              // Create rectangle from normalized vertices (x, y coordinates between 0-1)
              boundingBox = Rect.fromLTRB(
                vertices[0].x ?? 0.0,
                vertices[0].y ?? 0.0,
                vertices[2].x ?? 1.0,
                vertices[2].y ?? 1.0,
              );
            } else {
              // Default bounding box if vertices aren't available
              boundingBox = Rect.fromLTWH(0.2, 0.2 + (i * 0.1), 0.6, 0.2);
            }

            print(
              'Detected: ${object.name} (${(confidence * 100).toStringAsFixed(1)}%)',
            );

            detectedObjects.add(
              DetectedObject(
                label: object.name ?? 'Unknown',
                confidence: confidence,
                boundingBox: boundingBox,
                color: _colors[i % _colors.length],
              ),
            );
          }
        }
      }

      // If no localized objects were found, use label detection as fallback
      if (detectedObjects.isEmpty &&
          annotateResponse.labelAnnotations != null) {
        for (int i = 0; i < annotateResponse.labelAnnotations!.length; i++) {
          final label = annotateResponse.labelAnnotations![i];
          final confidence = label.score ?? 0.0;

          if (confidence >= confidenceThreshold) {
            // For label detection (no bounding boxes), create artificial positions
            final boundingBox = Rect.fromLTWH(
              0.2, // X position at 20% of width
              0.2 + (i * 0.1), // Y position at 20% with offset
              0.6, // Width 60% of image width
              0.1, // Height 10% of image height
            );

            print(
              'Detected label: ${label.description} (${(confidence * 100).toStringAsFixed(1)}%)',
            );

            detectedObjects.add(
              DetectedObject(
                label: label.description ?? 'Unknown',
                confidence: confidence,
                boundingBox: boundingBox,
                color: _colors[i % _colors.length],
              ),
            );
          }
        }
      }

      print('Returning ${detectedObjects.length} objects after filtering');
      return detectedObjects;
    } catch (e) {
      print('Error detecting objects with Google Cloud Vision API: $e');
      print(StackTrace.current);
      return [];
    }
  }

  Future<List<DetectedColor>> detectColorsFromImage(File imageFile) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_visionApi == null) {
      print('Google Cloud Vision API client is null, reinitializing...');
      await initialize();
      if (_visionApi == null) {
        print('Failed to initialize Google Cloud Vision API client');
        return [];
      }
    }

    try {
      print('Starting color detection with Google Cloud Vision API...');
      print('Image path: ${imageFile.path}');
      print('Image exists: ${await imageFile.exists()}');
      print('Image size: ${await imageFile.length()} bytes');

      // Read image as bytes
      final imageBytes = await imageFile.readAsBytes();
      final encodedImage = base64Encode(imageBytes);

      // Create image request for color detection
      final request =
          vision.AnnotateImageRequest()
            ..image = (vision.Image()..content = encodedImage)
            ..features = [
              vision.Feature()
                ..type = 'IMAGE_PROPERTIES'
                ..maxResults = 10,
            ];

      // Send request to Cloud Vision API
      final response = await _visionApi!.images.annotate(
        vision.BatchAnnotateImagesRequest()..requests = [request],
      );

      if (response.responses == null || response.responses!.isEmpty) {
        print('No response from Cloud Vision API');
        return [];
      }

      final annotateResponse = response.responses!.first;
      List<DetectedColor> detectedColors = [];

      // Process colors from image properties
      if (annotateResponse.imagePropertiesAnnotation?.dominantColors?.colors !=
          null) {
        final colors =
            annotateResponse.imagePropertiesAnnotation!.dominantColors!.colors!;

        for (int i = 0; i < colors.length; i++) {
          final colorInfo = colors[i];

          if (colorInfo.color != null) {
            final red = (colorInfo.color!.red ?? 0).toInt();
            final green = (colorInfo.color!.green ?? 0).toInt();
            final blue = (colorInfo.color!.blue ?? 0).toInt();

            final score = colorInfo.score ?? 0.0;
            final pixelFraction = colorInfo.pixelFraction ?? 0.0;

            // Create a Color object from RGB values
            final color = Color.fromRGBO(red, green, blue, 1.0);

            // Get a name for the color
            final colorName = _getColorName(red, green, blue);

            print(
              'Detected color: $colorName (${(score * 100).toStringAsFixed(1)}% of image)',
            );

            detectedColors.add(
              DetectedColor(
                color: color,
                name: colorName,
                score: score,
                pixelFraction: pixelFraction,
              ),
            );
          }
        }
      }

      print('Returning ${detectedColors.length} colors');
      return detectedColors;
    } catch (e) {
      print('Error detecting colors with Google Cloud Vision API: $e');
      print(StackTrace.current);
      return [];
    }
  }

  // Helper method to get a color name from RGB values
  String _getColorName(int r, int g, int b) {
    // Simple algorithm to determine color name based on RGB values
    if (r > 200 && g < 100 && b < 100) return 'Red';
    if (r > 200 && g > 150 && b < 100) return 'Orange';
    if (r > 200 && g > 200 && b < 100) return 'Yellow';
    if (r < 100 && g > 200 && b < 100) return 'Green';
    if (r < 100 && g < 100 && b > 200) return 'Blue';
    if (r > 200 && g < 100 && b > 200) return 'Purple';
    if (r < 100 && g > 200 && b > 200) return 'Cyan';
    if (r > 200 && g < 100 && b > 200) return 'Magenta';
    if (r > 200 && g > 200 && b > 200) return 'White';
    if (r < 50 && g < 50 && b < 50) return 'Black';
    if (r > 100 && g > 100 && b > 100 && r < 200 && g < 200 && b < 200)
      return 'Gray';
    if (r > g && r > b) return 'Reddish';
    if (g > r && g > b) return 'Greenish';
    if (b > r && b > g) return 'Bluish';

    return 'Unknown';
  }

  // Clean up resources
  Future<void> dispose() async {
    if (_isInitialized) {
      _isInitialized = false;
      print('Google Cloud Vision API client disposed');
    }
  }
}
