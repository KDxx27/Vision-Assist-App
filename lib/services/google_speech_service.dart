import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class GoogleSpeechService {
  final Dio _dio = Dio();
  final _audioRecorder = AudioRecorder();
  bool _isListening = false;
  String _lastRecognizedText = '';
  String _audioFilePath = '';
  ServiceAccountCredentials? _credentials;
  String? _accessToken;
  DateTime? _tokenExpiryTime;

  // URL for Google Cloud Speech-to-Text API
  static const String apiUrl =
      'https://speech.googleapis.com/v1/speech:recognize';

  // Initialize the API with credentials
  Future<bool> initialize() async {
    try {
      // Check and request microphone permission first
      final micStatus = await Permission.microphone.request();
      if (micStatus != PermissionStatus.granted) {
        debugPrint('Microphone permission not granted');
        return false;
      }

      // Initialize credentials if not already done
      if (_credentials == null) {
        try {
          // Load the credentials from JSON file
          final String jsonContent = await rootBundle.loadString(
            'coral-idiom-448917-f6-59bf3582a49c.json',
          );
          final credentialsJson = json.decode(jsonContent);
          _credentials = ServiceAccountCredentials.fromJson(credentialsJson);

          // Get access token
          await _getAccessToken();
        } catch (e) {
          debugPrint('Error loading credentials: $e');
          return false;
        }
      }

      // Check if token needs to be refreshed
      if (_tokenExpiryTime == null ||
          DateTime.now().isAfter(
            _tokenExpiryTime!.subtract(const Duration(minutes: 5)),
          )) {
        await _getAccessToken();
      }

      return _accessToken != null;
    } catch (e) {
      debugPrint('Error initializing speech service: $e');
      return false;
    }
  }

  // Get OAuth 2.0 access token for Google Cloud API
  Future<void> _getAccessToken() async {
    try {
      if (_credentials == null) {
        debugPrint('No credentials available for token generation');
        return;
      }

      // Define the scopes we need
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];

      // Get the client
      final client = http.Client();

      try {
        // Obtain credentials
        final accessCredentials =
            await obtainAccessCredentialsViaServiceAccount(
              _credentials!,
              scopes,
              client,
            );

        _accessToken = accessCredentials.accessToken.data;
        _tokenExpiryTime = accessCredentials.accessToken.expiry;

        debugPrint(
          'Successfully obtained access token, expires: ${_tokenExpiryTime?.toIso8601String()}',
        );
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Error getting access token: $e');
      _accessToken = null;
    }
  }

  // Start recording audio
  Future<void> startListening({
    required Function(String) onResult,
    String? locale,
  }) async {
    if (_isListening) return;

    bool available = await initialize();
    if (!available) {
      onResult('Could not initialize speech service. Check your credentials.');
      return;
    }

    try {
      // Get temporary directory to store audio file
      final tempDir = await getTemporaryDirectory();
      _audioFilePath = '${tempDir.path}/audio_recording.wav';

      // Configure the recorder
      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 16000,
        sampleRate: 16000,
        numChannels: 1,
      );

      // Start recording
      await _audioRecorder.start(config, path: _audioFilePath);

      _isListening = true;
      debugPrint('Recording started');

      // Set a timeout of 5 seconds for recording
      await Future.delayed(const Duration(seconds: 5));

      // Stop recording and process the audio
      if (_isListening) {
        final result = await stopListening();
        onResult(result);
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _isListening = false;
      onResult('Error starting recording: $e');
    }
  }

  // Stop recording and send audio to Google Cloud Speech-to-Text API
  Future<String> stopListening() async {
    if (!_isListening) return _lastRecognizedText;

    try {
      // Stop recording
      await _audioRecorder.stop();
      _isListening = false;
      debugPrint('Recording stopped');

      // Read audio file
      File audioFile = File(_audioFilePath);
      if (!await audioFile.exists()) {
        debugPrint('Audio file not found');
        return 'Error: Audio file not found';
      }

      List<int> audioBytes = await audioFile.readAsBytes();
      String base64Audio = base64Encode(audioBytes);
      debugPrint('Audio file encoded, size: ${audioBytes.length} bytes');

      if (_accessToken == null) {
        debugPrint('No access token available, cannot send request');
        return 'Authentication error: No access token available';
      }

      // Send request to Google Cloud Speech-to-Text API
      final response = await _dio.post(
        apiUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => true, // For debugging
        ),
        data: {
          'config': {
            'encoding': 'LINEAR16',
            'sampleRateHertz': 16000,
            'languageCode': 'en-US',
            'model': 'command_and_search',
            'speechContexts': [
              {
                'phrases': [
                  'navigate',
                  'go to',
                  'take me to',
                  'directions to',
                  'find',
                  'search',
                  'nearby',
                  'hospital',
                  'bus stop',
                  'restaurant',
                  'pharmacy',
                  'store',
                  'home',
                  'work',
                  'school',
                  'street',
                  'avenue',
                  'road',
                  'drive',
                  'lane',
                ],
              },
            ],
          },
          'audio': {'content': base64Audio},
        },
      );

      // Log response for debugging
      debugPrint('Speech API response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('Speech API error: ${response.data}');
        if (response.statusCode == 401 || response.statusCode == 403) {
          // Token may be expired, try to refresh
          await _getAccessToken();
          return 'Authorization error (${response.statusCode}). Token refreshed, please try again.';
        }
        return 'Error: Speech recognition failed with status ${response.statusCode}';
      }

      // Process the response
      if (response.data != null) {
        if (response.data['results'] != null &&
            response.data['results'].isNotEmpty &&
            response.data['results'][0]['alternatives'] != null &&
            response.data['results'][0]['alternatives'].isNotEmpty) {
          final transcript =
              response.data['results'][0]['alternatives'][0]['transcript'];
          if (transcript != null) {
            _lastRecognizedText = transcript.toString();
            debugPrint('Recognized text: $_lastRecognizedText');
            return _lastRecognizedText;
          }
        }

        // Print full response for debugging
        debugPrint('Full response data: ${response.data}');
      }

      debugPrint('No speech recognized or empty results');
      return 'No speech recognized';
    } catch (e) {
      debugPrint('Error in speech recognition: $e');
      return 'Error in speech recognition: $e';
    }
  }

  // Cancel listening
  Future<void> cancelListening() async {
    if (_isListening) {
      await _audioRecorder.stop();
      _isListening = false;
    }
  }

  // Check if listening
  bool get isListening => _isListening;

  // Get last recognized text
  String get lastRecognizedText => _lastRecognizedText;

  // Dispose resources
  Future<void> dispose() async {
    await cancelListening();
    await _audioRecorder.dispose();
  }

  // Reset the service state for reuse
  Future<bool> reset() async {
    try {
      // First, ensure we're not listening
      if (_isListening) {
        await cancelListening();
      }

      // Release and recreate resources
      await _audioRecorder.dispose();

      // Reset the state variables
      _isListening = false;
      _lastRecognizedText = '';
      _audioFilePath = '';

      // Reinitialize the recorder
      await Future.delayed(const Duration(milliseconds: 500));

      // Re-initialize the service
      return await initialize();
    } catch (e) {
      debugPrint('Error resetting speech service: $e');
      return false;
    }
  }
}
