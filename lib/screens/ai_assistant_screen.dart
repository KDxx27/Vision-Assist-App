import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'package:vision_assist/services/ai_service.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _flutterTts = FlutterTts();
  final List<ChatMessage> _messages = [];
  final AIService _aiService = AIService();

  // Speech to text properties
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _lastWords = '';
  bool _speechEnabled = false;
  Timer? _speechTimeoutTimer;
  DateTime _lastSoundDetectedTime = DateTime.now();

  bool _isTyping = false;
  bool _isReadingResponse = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeAI();
    _initializeSpeech();
  }

  // Initialize speech recognition
  Future<void> _initializeSpeech() async {
    // Check microphone permission
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      try {
        // Initialize speech to text
        _speechEnabled = await _speech.initialize(
          onStatus: (status) => _onSpeechStatus(status),
          onError:
              (errorNotification) =>
                  print('Speech recognition error: $errorNotification'),
        );

        if (_speechEnabled) {
          print('Speech recognition initialized successfully');
        } else {
          print('Failed to initialize speech recognition');
        }
      } catch (e) {
        print('Error initializing speech recognition: $e');
      }
    } else {
      print('Microphone permission denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed for voice input'),
          ),
        );
      }
    }
  }

  // Handle speech status changes
  void _onSpeechStatus(String status) {
    print('Speech status: $status');
    if (status == 'done' || status == 'notListening') {
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }

      // Process the recognized text if we have any
      if (_lastWords.isNotEmpty) {
        _handleSubmitted(_lastWords);
        setState(() {
          _lastWords = '';
          _messageController.clear(); // Clear the text field
        });

        // Reset speech recognition to ensure it's ready for the next session
        Future.delayed(const Duration(milliseconds: 500), () {
          _resetSpeechRecognition();
        });
      }
    }
  }

  // Reset speech recognition if it gets stuck
  void _resetSpeechRecognition() async {
    if (_speech.isAvailable) {
      await _speech.stop();
    }

    // Reinitialize
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) => _onSpeechStatus(status),
        onError:
            (errorNotification) =>
                print('Speech recognition error: $errorNotification'),
      );
      print('Speech recognition reset: $_speechEnabled');
    } catch (e) {
      print('Error resetting speech recognition: $e');
    }
  }

  // Start listening for speech input
  void _startListening() async {
    // Stop any ongoing TTS to avoid conflict
    await _stopReading();

    // If already listening, stop first
    if (_isListening) {
      _stopListening();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Reset speech recognition to ensure clean state
    _resetSpeechRecognition();
    await Future.delayed(const Duration(milliseconds: 300));

    if (_speechEnabled) {
      setState(() {
        _isListening = true;
        _lastWords = ''; // Clear last words
        _messageController.clear(); // Clear any text in the field
      });

      try {
        await _speech.listen(
          onResult: (result) {
            setState(() {
              _lastWords = result.recognizedWords;

              // Update text field with recognized words in real-time
              _messageController.text = _lastWords;

              // Move cursor to the end
              _messageController.selection = TextSelection.fromPosition(
                TextPosition(offset: _messageController.text.length),
              );
            });
          },
          listenFor: const Duration(seconds: 30), // Max listening time
          pauseFor: const Duration(seconds: 3), // Stop after this much silence
          partialResults: true,
          localeId: 'en_US',
          onSoundLevelChange: (level) {
            // Track sound level to detect when user has stopped speaking
            if (level > 0) {
              _lastSoundDetectedTime = DateTime.now();
            }
          },
        );

        // Start a timer to check if user has stopped speaking
        _speechTimeoutTimer = Timer.periodic(Duration(milliseconds: 500), (
          timer,
        ) {
          if (_lastWords.isNotEmpty &&
              DateTime.now().difference(_lastSoundDetectedTime).inSeconds >=
                  2) {
            // If we have text and no sound for 2 seconds, auto-submit
            timer.cancel();
            _stopListening();
            if (_lastWords.isNotEmpty) {
              _handleSubmitted(_lastWords);
              setState(() {
                _lastWords = '';
                _messageController.clear(); // Clear the text field
              });
            }
          }
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Listening...')));
      } catch (e) {
        print('Error listening: $e');
        setState(() {
          _isListening = false;
        });
        _resetSpeechRecognition(); // Try to reset if there was an error
      }
    } else {
      print('Speech recognition not available');
      // Try to initialize again
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
    _speechTimeoutTimer?.cancel();

    if (!_speech.isListening) return;

    try {
      await _speech.stop();
    } catch (e) {
      print('Error stopping speech recognition: $e');
      _resetSpeechRecognition();
    }

    setState(() {
      _isListening = false;
    });
  }

  Future<void> _initializeAI() async {
    await _aiService.initialize();

    // Add welcome message with tap functionality
    final welcomeMessage = await _aiService.sendMessage('Hello');
    _addAssistantMessage(welcomeMessage);
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _stopReading() async {
    await _flutterTts.stop();
    if (mounted) {
      setState(() {
        _isReadingResponse = false;
      });
    }
  }

  Future<void> _readText(String text) async {
    // Don't read text if it's empty
    if (text.isEmpty) return;

    // First stop any ongoing speech
    await _stopReading();

    setState(() {
      _isReadingResponse = true;
    });

    // Create a completer to track when speech is done
    Completer<void> completer = Completer<void>();

    // Set up completion handler
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
        if (mounted) {
          setState(() {
            _isReadingResponse = false;
          });
        }
      }
    });

    try {
      print('Starting to speak: ${text.substring(0, min(50, text.length))}...');

      // Speak the text
      await _flutterTts.speak(text);
    } catch (e) {
      print('Error reading text: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error reading text: $e')));

        setState(() {
          _isReadingResponse = false;
        });
      }
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    // Return the future that completes when speech is done
    return completer.future;
  }

  void _handleSubmitted(String text) async {
    _messageController.clear();

    if (text.trim().isEmpty) return;

    // Add user message
    _addUserMessage(text);

    // Clear the last words
    setState(() {
      _lastWords = '';
    });

    // Simulate typing
    setState(() {
      _isTyping = true;
    });

    // Scroll to bottom
    await _scrollToBottom();

    // Get response from AI service
    final response = await _aiService.sendMessage(text);

    // Add assistant response
    _addAssistantMessage(response);

    setState(() {
      _isTyping = false;
    });

    await _scrollToBottom();

    // Reset the speech service to ensure it's in a clean state for the next interaction
    _resetSpeechRecognition();
  }

  void _addUserMessage(String message) {
    setState(() {
      _messages.add(ChatMessage(text: message, isUser: true));
    });
  }

  void _addAssistantMessage(String message) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: message,
          isUser: false,
          onTap: () => _toggleReadingMessage(message),
        ),
      );
    });

    // Always read the assistant's response
    _readText(message).then((_) {
      // Reset UI state after speaking is done
      if (mounted) {
        setState(() {
          _isReadingResponse = false;
          _isListening = false; // Ensure listening state is reset
          _lastWords = ''; // Clear any previous recognized words
        });
      }
    });
  }

  // Toggle reading a specific message
  void _toggleReadingMessage(String message) {
    if (_isReadingResponse) {
      _stopReading();
    } else {
      _readText(message);
    }
  }

  void _clearConversation() {
    setState(() {
      // Keep only the first welcome message
      if (_messages.isNotEmpty) {
        final firstMessage = _messages.first;
        _messages.clear();
        _messages.add(firstMessage);
      }

      // Clear conversation history in AIService
      _aiService.clearConversation();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Conversation cleared')));
  }

  Future<void> _scrollToBottom() async {
    // Add a small delay to ensure the list is updated
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Add tap-to-listen functionality on the entire screen
      onTap: () {
        // If we're currently reading text, stop reading
        if (_isReadingResponse) {
          _stopReading();
          return;
        }

        // If we're already listening or typing, don't do anything
        if (_isListening || _isTyping || _messageController.text.isNotEmpty)
          return;

        // Otherwise, start listening
        _startListening();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI Assistant'),
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          actions: [
            if (_isListening)
              IconButton(
                icon: const Icon(Icons.mic_off),
                onPressed: _stopListening,
                tooltip: 'Stop listening',
              ),
            if (_isReadingResponse)
              IconButton(
                icon: const Icon(Icons.stop_circle),
                onPressed: _stopReading,
                tooltip: 'Stop reading',
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _clearConversation,
              tooltip: 'Clear conversation',
            ),
          ],
        ),
        body: Column(
          children: [
            // Status indicator bar at the top
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color:
                  _isListening
                      ? Colors.purple.shade50
                      : _isReadingResponse
                      ? Colors.blue.shade50
                      : Colors.transparent,
              child:
                  _isListening
                      ? Row(
                        children: [
                          const Icon(Icons.mic, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastWords.isEmpty
                                  ? 'Listening...'
                                  : 'Heard: $_lastWords',
                              style: TextStyle(
                                color: Colors.purple.shade800,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: _stopListening,
                            iconSize: 20,
                          ),
                        ],
                      )
                      : _isReadingResponse
                      ? Row(
                        children: [
                          const Icon(Icons.volume_up, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Speaking response...',
                              style: TextStyle(
                                color: Colors.blue,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.blue),
                            onPressed: _stopReading,
                            iconSize: 20,
                          ),
                        ],
                      )
                      : const SizedBox.shrink(),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8.0),
                itemCount: _messages.length,
                itemBuilder: (_, int index) {
                  final message = _messages[index];
                  // If it's not a user message and doesn't already have an onTap,
                  // create a new instance with the onTap handler
                  if (!message.isUser && message.onTap == null) {
                    return ChatMessage(
                      text: message.text,
                      isUser: message.isUser,
                      onTap: () => _toggleReadingMessage(message.text),
                    );
                  }
                  return message;
                },
              ),
            ),
            if (_isTyping)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.purple,
                      child: Icon(
                        Icons.smart_toy,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    SizedBox(width: 12),
                    SizedBox(
                      width: 45,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.purple,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            // Add a helper text when there's no activity happening
            if (!_isListening && !_isTyping && !_isReadingResponse)
              Container(
                padding: const EdgeInsets.all(12.0),
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.purple.shade200, width: 1),
                ),
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 18,
                      color: Colors.purple.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tap anywhere to start listening',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1.0),
            Container(
              decoration: BoxDecoration(color: Theme.of(context).cardColor),
              child: _buildTextComposer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.secondary),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(color: Colors.purple.shade200),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Ask me anything...',
                    border: InputBorder.none,
                  ),
                  onSubmitted: _handleSubmitted,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.red : Colors.purple,
              ),
              onPressed: () {
                if (_isListening) {
                  _stopListening();
                } else {
                  _startListening();
                }
              },
              tooltip: _isListening ? 'Stop listening' : 'Start voice input',
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.purple),
                onPressed: () => _handleSubmitted(_messageController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  const ChatMessage({
    super.key,
    required this.text,
    required this.isUser,
    this.onTap,
  });

  final String text;
  final bool isUser;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final messageAlignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final messageColor = isUser ? Colors.purple.shade100 : Colors.grey.shade100;
    final textColor = isUser ? Colors.purple.shade900 : Colors.black87;
    final avatarWidget =
        isUser
            ? const CircleAvatar(
              backgroundColor: Colors.purple,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            )
            : const CircleAvatar(
              backgroundColor: Colors.purple,
              child: Icon(Icons.smart_toy, color: Colors.white, size: 18),
            );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) avatarWidget,
          if (!isUser) const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: messageAlignment,
              children: [
                GestureDetector(
                  onTap:
                      !isUser
                          ? onTap
                          : null, // Only add tap functionality for AI messages
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    decoration: BoxDecoration(
                      color: messageColor,
                      borderRadius: BorderRadius.circular(20.0),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 2,
                          spreadRadius: 0,
                          offset: const Offset(0, 1),
                          color: Colors.black.withOpacity(0.1),
                        ),
                      ],
                    ),
                    child: Text(text, style: TextStyle(color: textColor)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: 4.0,
                    left: 4.0,
                    right: 4.0,
                  ),
                  child: Text(
                    isUser ? 'You' : 'Vision AI',
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 12),
          if (isUser) avatarWidget,
        ],
      ),
    );
  }
}
