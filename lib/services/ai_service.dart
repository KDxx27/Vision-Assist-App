import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// A service that provides AI assistant functionality using free APIs
class AIService {
  final List<Map<String, String>> _conversationHistory = [];
  final String _baseUrl =
      'https://api.free-ai-provider.tech/v1/chat'; // This is a placeholder URL
  final Random _random = Random();

  // Initialize the conversation history with system prompt
  Future<void> initialize() async {
    // Add the system message to conversation history if it's empty
    if (_conversationHistory.isEmpty) {
      _conversationHistory.add({
        'role': 'system',
        'content':
            'You are Vision Assistant, an AI designed to help visually impaired people. Keep responses brief, clear, and helpful.',
      });
    }
  }

  // We'll use a simulated response approach since we're not connecting to a real API
  // In a real app, this would make HTTP requests to a free AI API
  Future<String> sendMessage(String message) async {
    await initialize();

    // Add user message to conversation history
    _conversationHistory.add({'role': 'user', 'content': message});

    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Check for predetermined responses first
    String response = _checkPredeterminedResponses(message);

    // If no predetermined response matched, use the smart response generator
    if (response.isEmpty) {
      response = _generateSmartResponse(message);
    }

    // Add response to conversation history
    _conversationHistory.add({'role': 'assistant', 'content': response});

    return response;
  }

  // Clear conversation history, keeping only the system message
  void clearConversation() {
    final systemMessage =
        _conversationHistory.isNotEmpty ? _conversationHistory.first : null;
    _conversationHistory.clear();
    if (systemMessage != null) {
      _conversationHistory.add(systemMessage);
    }
  }

  // Check for predetermined responses before using the smart response generator
  String _checkPredeterminedResponses(String message) {
    final lowercaseMessage = message.toLowerCase().trim();

    // Time related queries
    if (_containsAny(lowercaseMessage, [
      'what time',
      'current time',
      'tell me the time',
      'time now',
      'what is the time',
      'time',
    ])) {
      final now = DateTime.now();
      final timeString = DateFormat('h:mm a').format(now);
      return 'The current time is $timeString.';
    }

    // Date related queries
    if (_containsAny(lowercaseMessage, [
      'what date',
      'today\'s date',
      'what day',
      'current date',
      'what is the date',
      'what is today',
      'date',
    ])) {
      final now = DateTime.now();
      final dateString = DateFormat('EEEE, MMMM d, yyyy').format(now);
      return 'Today is $dateString.';
    }

    // Day of the week query
    if (_containsAny(lowercaseMessage, [
      'what day is it',
      'day of the week',
      'which day',
    ])) {
      final now = DateTime.now();
      final dayString = DateFormat('EEEE').format(now);
      return 'Today is $dayString.';
    }

    // Weather related queries - we'll give a general response since we don't have real weather data
    if (_containsAny(lowercaseMessage, [
      'weather',
      'temperature',
      'how hot',
      'how cold',
      'is it raining',
      'forecast',
    ])) {
      return 'I don\'t have access to real-time weather information. You could try asking for the weather on your phone\'s built-in assistant or a weather app.';
    }

    // Jokes - we'll have a few predefined clean, accessible jokes
    if (_containsAny(lowercaseMessage, [
      'tell joke',
      'joke',
      'make me laugh',
      'funny',
      'humor',
    ])) {
      final jokes = [
        "Why don't scientists trust atoms? Because they make up everything!",
        "What do you call a fake noodle? An impasta!",
        "Why did the scarecrow win an award? Because he was outstanding in his field!",
        "How do you organize a space party? You planet!",
        "What did one wall say to the other wall? I'll meet you at the corner!",
        "Why couldn't the bicycle stand up by itself? It was two tired!",
        "What do you call cheese that isn't yours? Nacho cheese!",
        "Why don't eggs tell jokes? They'd crack each other up!",
        "What's orange and sounds like a parrot? A carrot!",
        "How do you make a tissue dance? Put a little boogie in it!",
      ];
      return jokes[_random.nextInt(jokes.length)];
    }

    // Self-introduction
    if (_containsAny(lowercaseMessage, [
      'who are you',
      'introduce yourself',
      'what\'s your name',
      'tell me about you',
      'tell me about yourself',
    ])) {
      return 'I am Vision Assistant, an AI designed to help visually impaired users navigate and understand their surroundings. I can assist with object detection, text recognition, color identification, and answer general questions.';
    }

    // Calendar - current month, year
    if (_containsAny(lowercaseMessage, [
      'what month',
      'current month',
      'what year',
      'current year',
    ])) {
      final now = DateTime.now();
      final monthYearString = DateFormat('MMMM yyyy').format(now);
      return 'We are currently in $monthYearString.';
    }

    // Simple math calculations
    if (_containsAny(lowercaseMessage, [
          'calculate',
          'what is',
          'solve',
          'plus',
          'minus',
          'times',
          'divided by',
        ]) &&
        _containsMathOperation(lowercaseMessage)) {
      try {
        return _handleSimpleMath(lowercaseMessage);
      } catch (e) {
        // If calculation fails, continue to other response options
        return '';
      }
    }

    // Battery status - we don't have access to the device's battery, so provide a generic response
    if (_containsAny(lowercaseMessage, [
      'battery',
      'power level',
      'charging',
    ])) {
      return 'I don\'t have access to your device\'s battery information. You can check it through your device\'s settings or status bar.';
    }

    // Night/Day determination
    if (_containsAny(lowercaseMessage, [
      'is it day',
      'is it night',
      'daytime',
      'nighttime',
    ])) {
      final hour = DateTime.now().hour;
      if (hour >= 6 && hour < 18) {
        return 'It\'s currently daytime.';
      } else {
        return 'It\'s currently nighttime.';
      }
    }

    // Random facts
    if (_containsAny(lowercaseMessage, [
      'tell me a fact',
      'random fact',
      'did you know',
      'fun fact',
    ])) {
      final facts = [
        "The human eye can distinguish between approximately 10 million different colors.",
        "The Braille reading system was invented by Louis Braille, who was blinded in an accident as a child.",
        "Guide dogs are trained to disobey commands that would put their handler in danger.",
        "The white cane used by many visually impaired people was introduced in the 1930s.",
        "Honey never spoils. Archaeologists have found pots of honey in ancient Egyptian tombs that are over 3,000 years old and still perfectly good to eat.",
        "Octopuses have three hearts.",
        "A day on Venus is longer than a year on Venus. It takes Venus 243 Earth days to rotate once on its axis but only 225 Earth days to orbit the Sun.",
        "Bananas are berries, but strawberries aren't.",
        "The world's oldest known living tree is over 5,000 years old.",
        "Humans share 50% of their DNA with bananas.",
      ];
      return 'Here\'s a fun fact: ' + facts[_random.nextInt(facts.length)];
    }

    // If none of the predetermined responses matched
    return '';
  }

  // A more advanced response generator that considers the conversation context
  String _generateSmartResponse(String message) {
    final lowercaseMessage = message.toLowerCase();

    // Greeting detection
    if (_containsAny(lowercaseMessage, ['hello', 'hi ', 'hey', 'greetings'])) {
      return 'Hello! I\'m your Vision Assistant. How can I help you today?';
    }

    // Help request detection
    if (_containsAny(lowercaseMessage, [
      'help',
      'assist',
      'what can you do',
      'how to',
    ])) {
      return 'I can help with several vision tasks: object detection, text recognition, color identification, and navigation. I can also answer general questions, tell jokes, or give you the time and date. What would you like help with?';
    }

    // Navigation related
    if (_containsAny(lowercaseMessage, [
      'navigate',
      'direction',
      'find',
      'where',
      'location',
      'lost',
      'map',
      'guide me',
    ])) {
      return 'For navigation assistance, you can use our Navigation feature. It provides voice-guided directions and can help you find nearby places like hospitals and bus stops. Would you like to try that now?';
    }

    // Object detection related
    if (_containsAny(lowercaseMessage, [
      'object',
      'identify',
      'detect',
      'recognize object',
      'what is this',
    ])) {
      return 'To identify objects around you, try using the Object Detection feature from the main menu. Would you like me to explain how to use it?';
    }

    // Text recognition related
    if (_containsAny(lowercaseMessage, [
      'read',
      'text',
      'ocr',
      'document',
      'letter',
      'recognize text',
    ])) {
      return 'The Text Recognition feature can help you read text from documents, signs, or other printed materials. Would you like to try that now?';
    }

    // Color detection related
    if (_containsAny(lowercaseMessage, [
      'color',
      'colour',
      'identify color',
      'what color',
    ])) {
      return 'Our Color Detection feature can identify colors around you. Would you like to try that feature?';
    }

    // Gratitude response
    if (_containsAny(lowercaseMessage, [
      'thank',
      'thanks',
      'appreciate',
      'grateful',
    ])) {
      return 'You\'re welcome! I\'m happy to assist. Is there anything else you need help with?';
    }

    // Farewell response
    if (_containsAny(lowercaseMessage, [
      'bye',
      'goodbye',
      'see you',
      'farewell',
    ])) {
      return 'Goodbye! Feel free to return anytime you need assistance with vision tasks.';
    }

    // Feature comparison or questions about features
    if (_containsAny(lowercaseMessage, [
      'difference',
      'compare',
      'better',
      'feature',
      'which one',
    ])) {
      return 'Each feature serves a different purpose: Object Detection identifies things around you, Text Recognition reads written content, Color Detection identifies colors, and Navigation helps you find your way. Which one sounds most useful for your current need?';
    }

    // Question about the app
    if (_containsAny(lowercaseMessage, [
      'app',
      'application',
      'vision assist',
      'about',
      'how does',
      'work',
    ])) {
      return 'Vision Assist is designed to help visually impaired users navigate their world. We offer object detection, text recognition, color identification, and navigation - all with voice feedback to help you understand your surroundings.';
    }

    // Default response for unrecognized queries
    return 'I\'m here to help with vision-related tasks. Would you like to try our Object Detection, Text Recognition, Color Detection, or Navigation features?';
  }

  // Helper method to check if the message contains any of the keywords
  bool _containsAny(String message, List<String> keywords) {
    return keywords.any((keyword) => message.contains(keyword));
  }

  // Helper method to detect if a message contains a mathematical operation
  bool _containsMathOperation(String message) {
    return RegExp(
      r'\d+\s*[\+\-\*\/x]\s*\d+',
    ).hasMatch(message.replaceAll('times', '*').replaceAll('divided by', '/'));
  }

  // Handle simple math calculations
  String _handleSimpleMath(String message) {
    // Replace words with symbols
    String processedMessage = message
        .replaceAll('plus', '+')
        .replaceAll('minus', '-')
        .replaceAll('times', '*')
        .replaceAll('x', '*')
        .replaceAll('divided by', '/');

    // Extract numbers and operation using regex
    final regex = RegExp(r'(\d+)\s*([\+\-\*\/])\s*(\d+)');
    final match = regex.firstMatch(processedMessage);

    if (match != null) {
      int num1 = int.parse(match.group(1)!);
      String op = match.group(2)!;
      int num2 = int.parse(match.group(3)!);

      double result;

      switch (op) {
        case '+':
          result = num1 + num2.toDouble();
          break;
        case '-':
          result = num1 - num2.toDouble();
          break;
        case '*':
          result = num1 * num2.toDouble();
          break;
        case '/':
          if (num2 == 0) return 'I cannot divide by zero.';
          result = num1 / num2.toDouble();
          break;
        default:
          return 'I couldn\'t process that calculation.';
      }

      // Format the result to remove unnecessary decimal places
      String formattedResult =
          result % 1 == 0 ? result.toInt().toString() : result.toString();
      return 'The answer is $formattedResult.';
    }

    return 'I couldn\'t understand that calculation.';
  }
}
