# Vision Assist

## 🔍 Overview

Vision Assist is a comprehensive Flutter application designed to assist visually impaired individuals in navigating their environment and understanding the world around them. The app leverages modern mobile device capabilities like camera, GPS, and AI to provide a suite of accessibility tools that help users perceive and interact with their surroundings.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter Version](https://img.shields.io/badge/Flutter-%5E3.7.2-blue.svg)](https://flutter.dev/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

## 📱 Key Features

### 🔍 Object Detection
Helps identify objects in the user's surroundings using the device camera. The app provides audio feedback about detected objects and their positions.


**Technical Implementation:**
- Uses Google Cloud Vision API for advanced object recognition
- Detects multiple objects with position information
- Classifies objects with confidence scores
- Custom UI with camera preview and detection overlays
- Real-time audio feedback using Flutter TTS
- Handles offline scenarios with graceful degradation

### 📖 Text Recognition (OCR)
Identifies and reads text from printed materials, signs, or displays. 


**Features:**
- Capture images with the camera or select from gallery
- Extract text from images using Google ML Kit
- Have text read aloud using text-to-speech
- Copy recognized text to clipboard
- Share recognized text with other apps

**Technical Implementation:**
- Uses Google ML Kit Text Recognition for accurate OCR
- On-device processing for privacy and offline functionality
- Multi-language text detection and recognition
- Custom text block visualization with TextRecognitionPainter
- Hierarchical text extraction (blocks, lines, elements)
- Optimized image processing for better recognition results
- Image rotation correction for text at different orientations

### 🎨 Color Detection
Helps identify colors in the user's surroundings using the device camera. The app provides audio feedback about dominant colors detected.


**Technical Implementation:**
- Advanced image processing with pixel sampling
- Color quantization and clustering algorithms for accurate detection
- HSV color space analysis for better color differentiation
- Custom color naming database with over 1,500 named colors
- Contrast detection between foreground and background
- Percentage calculation of each dominant color
- Optimized for real-time processing on mobile devices
- Works in various lighting conditions with automatic adjustment

### 📱 QR Code Scanner
Scans and interprets QR codes and barcodes with accessibility features for visually impaired users.

**Features:**
- Scan QR codes and barcodes using device camera
- Audio feedback about the scanned content
- Haptic feedback when codes are detected
- Accessible gestures for various actions (double tap to open, swipe to copy/share)
- Works with different QR code types (URLs, phone numbers, emails, text)
- Automatic content detection and appropriate handling
- Flashlight toggle for low-light environments

**Technical Implementation:**
- Uses mobile_scanner for reliable and fast code detection
- Real-time scanning with continuous feedback
- Voice guidance throughout the scanning process
- Flutter's built-in haptic feedback for tactile confirmation
- Adapts to different lighting conditions
- Type detection and contextual handling of scanned content
- Periodic audio cues for proper camera positioning
- Accessible UI with large touch targets and high contrast

### 🗺️ Navigation Assistant
Provides real-time navigation assistance for visually impaired users.


**Features:**
- Voice-guided turn-by-turn directions with distance and cardinal orientation
- Initial voice announcement of direction and bearing to destination
- Real-time updates on remaining distance and direction
- Search for destinations by voice input
- Nearby points of interest search (hospitals, bus stops, etc.)
- Automatic rerouting and progress tracking
- Fully accessible interface with voice feedback
- Works with Google Maps APIs or in simplified mode without internet

**Technical Implementation:**
- Google Maps Platform integration with Directions API
- Custom navigation algorithm optimized for pedestrians
- Real-time geolocation tracking with position filtering
- Bearing and orientation calculation using device sensors
- Intelligent voice instruction generation with context awareness
- Background service for continued navigation even when app is minimized
- Geofencing for point-of-interest detection
- Offline map caching for areas with poor connectivity
- Specialized route planning for accessibility (avoiding stairs, etc.)
- Battery optimization techniques for extended navigation sessions

### 🤖 AI Assistant
An intelligent conversational assistant that can help with various tasks.


**Features:**
- Answer questions about the user's environment
- Provide contextual help with other app features
- Offer general assistance for visually impaired users
- Uses a completely free on-device solution (no paid APIs required)

**Technical Implementation:**
- On-device TensorFlow Lite conversational AI model
- Natural language processing for intent recognition
- Context-aware responses with conversation history tracking
- Integration with device sensors for environmental awareness
- Voice activity detection to determine when user is speaking
- Noise cancellation for better speech recognition in noisy environments
- Custom wake word detection for hands-free activation
- Seamless integration with other app features
- Multi-turn conversation support with memory of previous exchanges
- Customizable voice characteristics (speed, pitch, gender)

## 🛠️ Technical Architecture

Vision Assist follows a modular architecture with clear separation of concerns:

```
lib/
  ├── config/         # Configuration constants and theme data
  ├── models/         # Data models and business logic
  ├── screens/        # UI screens for each feature
  ├── services/       # Services for camera, ML, TTS, etc.
  ├── widgets/        # Reusable UI components
  └── main.dart       # Application entry point
```

### Key Dependencies

- **Flutter SDK ^3.7.2**: Core framework
- **Camera ^0.10.5+9**: Camera access and control
- **Google ML Kit**: Text recognition
- **Google Cloud Vision API**: Object detection and recognition
- **Flutter TTS ^3.8.5**: Text-to-speech capabilities
- **Google Maps Flutter ^2.5.0**: Mapping and navigation
- **Speech-to-Text ^7.0.0**: Voice input processing
- **Location ^5.0.3**: Location services
- **Permission Handler ^11.0.1**: Permission management
- **TensorFlow Lite**: On-device AI processing
- **Dio ^5.3.3**: Network requests handling
- **Flutter Polyline Points ^2.1.0**: Route visualization
- **Geolocator ^10.1.0**: Precise location tracking
- **Share Plus ^7.2.2**: Content sharing capabilities
- **Mobile Scanner ^3.5.5**: QR code and barcode scanning
- **System Haptic Feedback**: For physical response when QR codes are detected

## 📋 Prerequisites

- Flutter SDK (^3.7.2 or later)
- Android Studio or Visual Studio Code with Flutter extensions
- An Android or iOS device/emulator for testing
- Google Maps API key for navigation features
- Google Cloud credentials with Vision API and Speech-to-Text API enabled
- Internet connection for initial setup and API-dependent features

## 🚀 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Cyb3rWr4i7h/vision-assist-app.git
   ```

2. **Navigate to the project directory:**
   ```bash
   cd vision-assist-app
   ```

3. **Set up your API keys:**
   
   Create a `.env` file in the root directory with the following variables:
   ```
   GOOGLE_MAPS_API_KEY=your_google_maps_api_key
   ```
   
   Add your Google Cloud credentials JSON file to the project root and update the assets section in pubspec.yaml to include it.

4. **Install dependencies:**
   ```bash
   flutter pub get
   ```

5. **Configure platform-specific settings:**
   
   For Android:
   - Update AndroidManifest.xml with required permissions
   - Configure Google Maps API key in app/src/main/AndroidManifest.xml
   
   For iOS:
   - Update Info.plist with required permissions
   - Add the Google Maps API key to AppDelegate.swift

6. **Run the app:**
   ```bash
   flutter run
   ```

## 📖 Usage

### Object Detection
1. Launch the app and select "Object Detection"
2. Point your camera at objects
3. The app will identify objects and speak their names
4. Tap the screen to capture and analyze objects in more detail

### Text Recognition
1. Launch the app and select "Text Recognition"
2. Point your camera at text or select an image from your gallery
3. Tap the "Capture & Recognize" button
4. The app will extract text and display it on screen
5. Use the "Read Text" button to have the text read aloud
6. Use the "Copy" button to copy text to clipboard
7. Use the "Share" button to share text with other apps

### Color Detection
1. Launch the app and select "Color Detection"
2. Point your camera at colored objects
3. The app will identify dominant colors and speak their names
4. Tap the screen to capture and analyze colors in more detail

### QR Code Scanner
1. Launch the app and select "QR Code Scanner"
2. Point your camera at a QR code or barcode
3. The app will automatically detect and scan the code
4. Listen to the audio feedback describing the content
5. Use the following gestures:
   - Double tap to open links, make calls, or send emails
   - Swipe left to copy content to clipboard
   - Swipe right to share content with other apps
6. Toggle the flashlight using the button in the top-right corner
7. Use the refresh button to scan another code

### Navigation Assistant
1. Launch the app and select "Navigation Assistant"
2. Use the microphone button to speak your destination
3. The app will find the location and generate a route
4. Listen to the initial direction and distance announcement
5. Follow turn-by-turn voice instructions as you walk
6. Receive regular updates on your remaining distance and direction
7. Use bottom buttons to find nearby hospitals or bus stops
8. Tap "My Location" to recenter the map on your current position
9. Tap "Stop" to end navigation

### AI Assistant
1. Launch the app and select "AI Assistant"
2. Type a question or tap the microphone for voice input
3. The assistant will respond to your queries using our free on-device AI solution
4. All processing happens locally on your device - no API keys or internet connection required

## ♿ Accessibility

Vision Assist is specifically designed with accessibility in mind:

- **High contrast interface**: Easy to see for users with low vision
- **Large touch targets**: Makes interaction easier for users with motor difficulties
- **Text-to-speech feedback**: Provides audio information about the app's state and environment
- **Simple, intuitive navigation**: Consistent layout across screens
- **Compatibility with screen readers**: Works with TalkBack and VoiceOver
- **Voice-controlled features**: Hands-free operation throughout the app

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

*Vision Assist: Empowering the visually impaired through technology.*
