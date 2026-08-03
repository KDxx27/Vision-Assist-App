import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:vision_assist/screens/object_detection_screen.dart';
import 'package:vision_assist/screens/color_detection_screen.dart';
import 'package:vision_assist/screens/text_recognition_screen.dart';
import 'package:vision_assist/screens/ai_assistant_screen.dart';
import 'package:vision_assist/screens/navigation_screen.dart';
import 'package:vision_assist/screens/profile_screen.dart';
import 'package:vision_assist/screens/qr_code_scanner_screen.dart';
import 'package:vision_assist/services/cloud_vision_service.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vision_assist/services/profile_service.dart';
import 'package:vision_assist/models/user_profile.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Validate Google Cloud Speech-to-Text service account credentials
  try {
    // Load credentials from file
    final String jsonContent = await rootBundle.loadString(
      'coral-idiom-448917-f6-59bf3582a49c.json',
    );
    final Map<String, dynamic> credentialsJson = json.decode(jsonContent);

    // Verify the file contains the expected fields
    if (!_verifyCredentials(credentialsJson)) {
      debugPrint('⚠️ Service account credentials file missing required fields');
    } else {
      // Try to create a valid service account credentials object
      final accountCredentials = ServiceAccountCredentials.fromJson(
        credentialsJson,
      );

      // Define the scopes we need
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];

      // Attempt to get a token to validate credentials (we don't save it now, just testing)
      try {
        final client = http.Client();
        try {
          debugPrint('Validating service account credentials...');
          await obtainAccessCredentialsViaServiceAccount(
            accountCredentials,
            scopes,
            client,
          );
          debugPrint('✅ Successfully validated service account credentials');

          // Initialize the Cloud Vision service
          await _initializeCloudVision();
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error validating service account credentials: $e');
      }
    }
  } catch (e) {
    debugPrint('⚠️ Error loading service account credentials: $e');
  }

  runApp(const MyApp());
}

// Initialize Google Cloud Vision API service
Future<void> _initializeCloudVision() async {
  try {
    final cloudVisionService = CloudVisionService();
    await cloudVisionService.initialize();
    debugPrint('✅ Successfully initialized Cloud Vision API service');
  } catch (e) {
    debugPrint('⚠️ Error initializing Cloud Vision API service: $e');
  }
}

// Helper function to verify if credentials contain required fields
bool _verifyCredentials(Map<String, dynamic> credentials) {
  final requiredFields = [
    'type',
    'project_id',
    'private_key_id',
    'private_key',
    'client_email',
    'client_id',
  ];

  for (final field in requiredFields) {
    if (!credentials.containsKey(field) || credentials[field] == null) {
      debugPrint('⚠️ Missing required field in credentials: $field');
      return false;
    }
  }

  return true;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision Assist',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Text-to-speech
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  String _instructionsText = '';

  // Speech-to-text
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  bool _speechEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTts();
    _initializeSpeech();

    // Start speaking the complete welcome instructions after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _speakInstructions();
    });

    // Remove the double tap listener announcement so it doesn't interrupt the welcome speech
    // The double tap information is already included in the welcome message
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flutterTts.stop();
    _speech.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App is in background
      _stopSpeaking();
      if (_isListening) {
        _speech.stop();
        setState(() => _isListening = false);
      }
    }
  }

  // Initialize text-to-speech
  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });
  }

  // Initialize speech recognition
  Future<void> _initializeSpeech() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      try {
        _speechEnabled = await _speech.initialize(
          onStatus: (status) {
            print('Speech status: $status');
            if (status == 'done' || status == 'notListening') {
              if (mounted) {
                setState(() => _isListening = false);
                _processCommand(_recognizedText);
                _recognizedText = '';
              }
            }
          },
          onError: (error) {
            print('Speech recognition error: $error');
            if (error.errorMsg == 'error_speech_timeout') {
              // Handle timeout by stopping listening and showing a message
              if (mounted) {
                setState(() => _isListening = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Listening timed out. Please try again.'),
                  ),
                );
              }
            }
          },
          debugLogging: true,
        );
        print('Speech recognition initialized: $_speechEnabled');
      } catch (e) {
        print('Error initializing speech recognition: $e');
      }
    } else {
      print('Microphone permission denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed for voice commands'),
          ),
        );
      }
    }
  }

  // Speak the instruction text
  Future<void> _speakInstructions() async {
    if (_isSpeaking) {
      await _stopSpeaking();
    }

    const instructions =
        '''Welcome to Vision Assist. To use this app, please say the COMPLETE commands exactly as follows:        
- Say "Open Object Detection" to detect objects around you
- Say "Open Text Recognition" to read text
- Say "Open Color Detection" to identify colors
- Say "Open QR Code Scanner" to scan QR codes and barcodes
- Say "Open AI Assistant" to chat with our AI
- Say "Open Navigation" for assistance with navigation
- Say "Open Profile" to manage your personal information
- Say "Call Emergency" to call your emergency contact
Tap anywhere on the screen to activate voice recognition.
Double tap anywhere for quick access to object detection.''';

    setState(() {
      _instructionsText = instructions;
      _isSpeaking = true;
    });

    await _flutterTts.speak(instructions);
  }

  // Stop speaking
  Future<void> _stopSpeaking() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  // Start listening for commands
  Future<void> _startListening() async {
    // Don't start if already listening
    if (_isListening) return;

    // Stop speaking if needed
    await _stopSpeaking();

    if (_speechEnabled) {
      setState(() {
        _isListening = true;
        _recognizedText = '';
      });

      try {
        await _speech.listen(
          onResult: (result) {
            if (mounted) {
              setState(() {
                _recognizedText = result.recognizedWords;
              });
            }
          },
          listenFor: const Duration(
            seconds: 60,
          ), // Increased from 15 to 60 seconds
          pauseFor: const Duration(
            seconds: 10,
          ), // Increased from 3 to 10 seconds
          partialResults: true,
          localeId: 'en_US',
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listening for command...')),
        );
      } catch (e) {
        print('Error starting speech recognition: $e');
        setState(() => _isListening = false);
      }
    } else {
      // Try to initialize again if it failed previously
      await _initializeSpeech();
      if (!_speechEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available')),
        );
      }
    }
  }

  // Stop listening
  void _stopListening() async {
    if (!_isListening) return;

    try {
      await _speech.stop();
    } catch (e) {
      print('Error stopping speech recognition: $e');
    }

    setState(() => _isListening = false);
  }

  // Process the recognized command
  void _processCommand(String command) {
    if (command.isEmpty) return;

    final lowerCommand = command.toLowerCase().trim();
    print('Processing command: $lowerCommand');

    // Use exact phrase matching instead of flexible matching
    if (lowerCommand == "open object detection") {
      _flutterTts.speak('Opening object detection');
      _navigateTo(const ObjectDetectionScreen());
    } else if (lowerCommand == "open text recognition") {
      _flutterTts.speak('Opening text recognition');
      _navigateTo(const TextRecognitionScreen());
    } else if (lowerCommand == "open color detection" ||
        lowerCommand == "open colour detection") {
      // Support both spellings
      _flutterTts.speak('Opening color detection');
      _navigateTo(const ColorDetectionScreen());
    } else if (lowerCommand == "open ai assistant") {
      _flutterTts.speak('Opening AI assistant');
      _navigateTo(const AIAssistantScreen());
    } else if (lowerCommand == "open navigation" ||
        lowerCommand == "open navigation assistant") {
      _flutterTts.speak('Opening navigation assistant');
      _navigateTo(const NavigationScreen());
    } else if (lowerCommand == "open profile") {
      _flutterTts.speak('Opening profile');
      _navigateTo(const ProfileScreen());
    } else if (lowerCommand == "open qr code scanner" ||
        lowerCommand == "open qr scanner") {
      _flutterTts.speak('Opening QR code scanner');
      _navigateTo(const QrCodeScannerScreen());
    } else if (lowerCommand == "call emergency" ||
        lowerCommand == "emergency call" ||
        lowerCommand == "call emergency contact") {
      _flutterTts.speak('Calling emergency contact');
      _callEmergencyContact();
    } else {
      // If no exact match, try to find the closest matching command
      // This allows for slight variations but still requires most of the exact phrase
      if (_findBestMatchForExactCommands(lowerCommand)) {
        return; // Successfully found and executed a command match
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Command not recognized. Please try again with a complete command.',
          ),
        ),
      );

      // Speak the error message
      _flutterTts.speak(
        'Command not recognized. Please use complete commands like "Open Object Detection".',
      );
    }
  }

  // Find the best matching command when exact match fails
  // This function requires more specific commands than before
  bool _findBestMatchForExactCommands(String command) {
    // Define the exact phrases we're looking for
    final Map<String, List<String>> validCommandVariations = {
      'object': [
        'open object detection',
        'start object detection',
        'launch object detection',
        'begin object detection',
      ],
      'text': [
        'open text recognition',
        'start text recognition',
        'launch text recognition',
        'begin text recognition',
      ],
      'color': [
        'open color detection',
        'open colour detection',
        'start color detection',
        'launch color detection',
        'begin color detection',
      ],
      'ai': [
        'open ai assistant',
        'start ai assistant',
        'launch ai assistant',
        'begin ai assistant',
      ],
      'navigation': [
        'open navigation',
        'open navigation assistant',
        'start navigation',
        'launch navigation',
        'begin navigation',
      ],
      'profile': [
        'open profile',
        'open my profile',
        'start profile',
        'launch profile',
        'begin profile',
        'view profile',
        'show profile',
      ],
      'qr': [
        'open qr code scanner',
        'open qr scanner',
        'start qr code scanner',
        'launch qr code scanner',
        'begin qr code scanner',
        'scan qr code',
        'scan qr',
      ],
      'emergency': [
        'call emergency',
        'call emergency contact',
        'emergency call',
        'make emergency call',
        'dial emergency',
        'contact emergency',
      ],
    };

    // Try to find a close match using string similarity
    int highestWordsMatched = 0;
    String bestCommand = '';
    String bestCategory = '';

    // For each category of commands
    for (final category in validCommandVariations.keys) {
      // For each valid variation of this category
      for (final validCommand in validCommandVariations[category]!) {
        // Calculate how many words match between the user command and this valid command
        final commandWords = command.split(' ');
        final validWords = validCommand.split(' ');

        int wordMatches = 0;
        bool hasOpenWord = false;

        // Count matching words
        for (final word in commandWords) {
          if (validWords.contains(word)) {
            wordMatches++;

            // Check specifically for 'open', 'start', etc. at the beginning
            if (word == 'open' ||
                word == 'start' ||
                word == 'launch' ||
                word == 'begin') {
              hasOpenWord = true;
            }
          }
        }

        // We require the action word (open/start/etc) and at least 2 total matching words
        // Also require at least 60% of the user's words to match a valid command
        final percentMatch = wordMatches / commandWords.length;
        if (hasOpenWord &&
            wordMatches >= 2 &&
            percentMatch >= 0.6 &&
            wordMatches > highestWordsMatched) {
          highestWordsMatched = wordMatches;
          bestCommand = validCommand;
          bestCategory = category;
        }
      }
    }

    // If we found a good match, execute the command
    if (bestCommand.isNotEmpty) {
      print('Found close match: $bestCommand (category: $bestCategory)');

      switch (bestCategory) {
        case 'object':
          _flutterTts.speak('Opening object detection');
          _navigateTo(const ObjectDetectionScreen());
          return true;
        case 'text':
          _flutterTts.speak('Opening text recognition');
          _navigateTo(const TextRecognitionScreen());
          return true;
        case 'color':
          _flutterTts.speak('Opening color detection');
          _navigateTo(const ColorDetectionScreen());
          return true;
        case 'ai':
          _flutterTts.speak('Opening AI assistant');
          _navigateTo(const AIAssistantScreen());
          return true;
        case 'navigation':
          _flutterTts.speak('Opening navigation assistant');
          _navigateTo(const NavigationScreen());
          return true;
        case 'profile':
          _flutterTts.speak('Opening profile');
          _navigateTo(const ProfileScreen());
          return true;
        case 'qr':
          _flutterTts.speak('Opening QR code scanner');
          _navigateTo(const QrCodeScannerScreen());
          return true;
        case 'emergency':
          _flutterTts.speak('Calling emergency contact');
          _callEmergencyContact();
          return true;
      }
    }

    return false;
  }

  // Make an emergency call
  Future<void> _callEmergencyContact() async {
    try {
      // Load user profile to get emergency contact
      final profileService = ProfileService();
      final userProfile = await profileService.loadProfile();

      final phoneNumber = userProfile.emergencyContact.trim();

      if (phoneNumber.isEmpty) {
        _flutterTts.speak(
          'No emergency contact number found. Please set up your profile first.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No emergency contact number found. Please set up your profile first.',
            ),
          ),
        );
        return;
      }

      // Check and request the CALL_PHONE permission
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        _flutterTts.speak('Permission to make phone calls is required.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission to make phone calls is required'),
          ),
        );
        return;
      }

      // Make the call using the tel: scheme
      final String telScheme = 'tel:$phoneNumber';
      _flutterTts.speak('Calling emergency contact now');

      // Launch directly without checking canLaunchUrl first
      await launchUrl(
        Uri.parse(telScheme),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _flutterTts.speak('Error making emergency call. Please try again.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // This function is kept for reference and fallback functionality
  bool _findBestMatch(String command) {
    // Define weights for different features - higher means more important
    const objectTerms = ['object', 'detect', 'detection', 'identify'];
    const textTerms = ['text', 'read', 'ocr', 'recognize', 'recognition'];
    const colorTerms = ['color', 'colour', 'colors', 'colours'];
    const aiTerms = ['ai', 'assistant', 'chat', 'talk'];
    const navTerms = ['navigation', 'navigate', 'direction', 'map', 'go to'];
    const qrTerms = ['qr', 'code', 'scan', 'scanner', 'barcode'];
    const emergencyTerms = ['emergency', 'call', 'contact', 'help', 'sos'];

    // Count matches for each feature
    int objectScore = _countMatches(command, objectTerms);
    int textScore = _countMatches(command, textTerms);
    int colorScore = _countMatches(command, colorTerms);
    int aiScore = _countMatches(command, aiTerms);
    int navScore = _countMatches(command, navTerms);
    int qrScore = _countMatches(command, qrTerms);
    int emergencyScore = _countMatches(command, emergencyTerms);

    // Find the highest score
    int maxScore = [
      objectScore,
      textScore,
      colorScore,
      aiScore,
      navScore,
      qrScore,
      emergencyScore,
    ].reduce((a, b) => a > b ? a : b);

    // Only match if we have at least one match
    if (maxScore > 0) {
      if (objectScore == maxScore) {
        _flutterTts.speak('Opening object detection');
        _navigateTo(const ObjectDetectionScreen());
        return true;
      } else if (textScore == maxScore) {
        _flutterTts.speak('Opening text recognition');
        _navigateTo(const TextRecognitionScreen());
        return true;
      } else if (colorScore == maxScore) {
        _flutterTts.speak('Opening color detection');
        _navigateTo(const ColorDetectionScreen());
        return true;
      } else if (aiScore == maxScore) {
        _flutterTts.speak('Opening AI assistant');
        _navigateTo(const AIAssistantScreen());
        return true;
      } else if (navScore == maxScore) {
        _flutterTts.speak('Opening navigation assistant');
        _navigateTo(const NavigationScreen());
        return true;
      } else if (qrScore == maxScore) {
        _flutterTts.speak('Opening QR code scanner');
        _navigateTo(const QrCodeScannerScreen());
        return true;
      } else if (emergencyScore == maxScore) {
        _flutterTts.speak('Calling emergency contact');
        _callEmergencyContact();
        return true;
      }
    }

    return false;
  }

  // Count how many terms from the list appear in the command
  int _countMatches(String command, List<String> terms) {
    int count = 0;
    for (String term in terms) {
      if (command.contains(term)) {
        count++;
      }
    }
    return count;
  }

  // Navigate to a specific screen
  void _navigateTo(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vision Assist'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _speakInstructions,
            tooltip: 'Instructions',
          ),
        ],
      ),
      body: GestureDetector(
        onTap: _startListening,
        onDoubleTap: () {
          // Navigate directly to object detection on double tap
          _flutterTts.speak('Opening object detection');
          _navigateTo(const ObjectDetectionScreen());
        },
        behavior:
            HitTestBehavior.opaque, // Makes sure taps are detected everywhere
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Vision Assist',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Listening status text - make it tappable too
                  GestureDetector(
                    onTap: _startListening,
                    onDoubleTap: () {
                      // Navigate directly to object detection on double tap
                      _flutterTts.speak('Opening object detection');
                      _navigateTo(const ObjectDetectionScreen());
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _isListening
                                ? Colors.deepPurple.withOpacity(0.1)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isListening ? 'Listening: $_recognizedText' : '',
                        style: TextStyle(
                          fontSize: 18,
                          color:
                              _isListening ? Colors.deepPurple : Colors.black54,
                          fontWeight:
                              _isListening
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Voice activation indicator - make it tappable as a button
                  GestureDetector(
                    onTap: _startListening,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _isListening ? 150 : 100,
                        height: _isListening ? 150 : 100,
                        decoration: BoxDecoration(
                          color:
                              _isListening
                                  ? Colors.deepPurple.withOpacity(0.2)
                                  : Colors.grey.withOpacity(0.1),
                          shape: BoxShape.circle,
                          boxShadow:
                              _isListening
                                  ? [
                                    BoxShadow(
                                      color: Colors.deepPurple.withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ]
                                  : null,
                        ),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          size: _isListening ? 80 : 50,
                          color: _isListening ? Colors.deepPurple : Colors.grey,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Display the complete welcome instructions text
                  Expanded(
                    child: GestureDetector(
                      onTap: _startListening,
                      onDoubleTap: () {
                        // Navigate directly to object detection on double tap
                        _flutterTts.speak('Opening object detection');
                        _navigateTo(const ObjectDetectionScreen());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            '''Welcome to Vision Assist
    
To use this app, please say the COMPLETE commands exactly as follows:
                            
- Say "Open Object Detection" to detect objects around you
- Say "Open Text Recognition" to read text
- Say "Open Color Detection" to identify colors
- Say "Open QR Code Scanner" to scan QR codes and barcodes
- Say "Open AI Assistant" to chat with our AI
- Say "Open Navigation" for assistance with navigation
- Say "Open Profile" to manage your personal information
- Say "Call Emergency" to call your emergency contact
    
Tap anywhere on the screen to activate voice recognition.
Double tap anywhere for quick access to object detection.''',
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isSpeaking
                              ? Icons.volume_up
                              : _isListening
                              ? Icons.mic
                              : Icons.volume_off,
                          color:
                              _isSpeaking
                                  ? Colors.blue
                                  : _isListening
                                  ? Colors.deepPurple
                                  : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isSpeaking
                              ? 'Speaking...'
                              : _isListening
                              ? 'Listening...'
                              : 'Ready',
                          style: TextStyle(
                            color:
                                _isSpeaking
                                    ? Colors.blue
                                    : _isListening
                                    ? Colors.deepPurple
                                    : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: ElevatedButton.icon(
          onPressed: _callEmergencyContact,
          icon: const Icon(Icons.phone, size: 24),
          label: const Text(
            'EMERGENCY CALL',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: Colors.redAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
