import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vision_assist/services/google_maps_service.dart';
import 'package:vision_assist/services/google_speech_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  final GoogleMapsService _mapsService = GoogleMapsService();
  final GoogleSpeechService _speechService = GoogleSpeechService();
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _destinationController = TextEditingController();

  // State variables
  bool _isLoading = true;
  bool _isNavigating = false;
  bool _isListening = false;
  String _feedbackText = 'Loading...';
  String _distanceText = '';
  String _durationText = '';
  bool _areGoogleApisAvailable = false;

  // Location data
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<Map<String, dynamic>> _navigationSteps = [];
  int _currentStepIndex = 0;

  // Timers for periodic location updates and navigation instructions
  Timer? _locationUpdateTimer;
  Timer? _navigationInstructionTimer;

  // Add counter for location updates
  int _locationUpdateCount = 0;

  String? _error;
  List<Map<String, dynamic>> _alternativeRoutes = [];
  Timer? _navigationUpdateTimer;
  LatLng? _nextWaypoint;
  double _remainingDistance = 0.0;
  String _nextManeuver = '';
  String _remainingTime = '';
  bool _showAlternativeRoutes = false;

  // Use a single map controller
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _destinationController.dispose();
    _speechService.dispose();
    _locationUpdateTimer?.cancel();
    _navigationInstructionTimer?.cancel();
    _stopTts();
    _navigationUpdateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause navigation when app is in background
    if (state == AppLifecycleState.paused) {
      _locationUpdateTimer?.cancel();
      _navigationInstructionTimer?.cancel();
      _stopTts();
    } else if (state == AppLifecycleState.resumed && _isNavigating) {
      // Resume navigation when app is back in foreground
      _startLocationUpdates();
      _startNavigationInstructions();
    }
  }

  // Initialize all required services
  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);

    // Try to get a default location (either stored or a common one)
    // This ensures we have a valid location for the map to start with
    LatLng defaultLocation = const LatLng(
      28.6139,
      77.2090,
    ); // New Delhi as default
    setState(() {
      _currentLocation = defaultLocation;
    });

    // Initialize text-to-speech
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(
      0.5,
    ); // Slower rate for clearer instructions
    await _flutterTts.setVolume(1.0);

    // Verify Google Maps API key is working
    _areGoogleApisAvailable = await _mapsService.verifyApiKey();
    if (!_areGoogleApisAvailable) {
      await _speak(
        'Google Maps APIs are not available. Some navigation features may be limited.',
      );
      debugPrint(
        'Google Maps APIs are not available, using limited functionality',
      );
    } else {
      debugPrint('Google Maps APIs are available, using full functionality');
    }

    // Initialize speech recognition
    bool speechAvailable = await _speechService.initialize();
    if (!speechAvailable) {
      await _speak('Speech recognition is not available on this device.');
    }

    // Request location permissions
    bool locationPermissionGranted = await _requestLocationPermission();
    if (!locationPermissionGranted) {
      return;
    }

    // Get current location
    bool locationObtained = await _getCurrentLocation();
    if (!locationObtained) {
      return;
    }

    setState(() => _isLoading = false);
    await _speak(
      'Navigation screen ready. Tap the mic button and say your destination.',
    );
  }

  // Request location permission
  Future<bool> _requestLocationPermission() async {
    var status = await Permission.location.request();
    if (status != PermissionStatus.granted) {
      await _speak('Location permission is required for navigation.');
      setState(() {
        _feedbackText = 'Location permission denied';
        _isLoading = false;
      });
      return false;
    }
    return true;
  }

  // Get current location
  Future<bool> _getCurrentLocation() async {
    try {
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _speak(
          'Location services are disabled. Please enable location services.',
        );
        setState(() {
          _error = 'Location services are disabled';
          _isLoading = false;
        });
        return false;
      }

      // Request permission if needed
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _speak('Location permission denied');
          setState(() {
            _error = 'Location permission denied';
            _isLoading = false;
          });
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _speak(
          'Location permissions are permanently denied. Please enable them in settings.',
        );
        setState(() {
          _error = 'Location permissions permanently denied';
          _isLoading = false;
        });
        return false;
      }

      // Get the current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _error = null; // Clear any previous errors
      });

      // Update markers
      _updateMarkers();

      // Center map on current location if controller is available
      if (_mapController != null && _currentLocation != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation!, 16),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Error getting location: $e');
      _speak(
        'Unable to get your current location. Please check location permissions.',
      );
      setState(() {
        _error = 'Error getting location: $e';
        _isLoading = false;
      });
      return false;
    }
  }

  // Update map markers
  void _updateMarkers() {
    Set<Marker> markers = {};

    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    if (_destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          infoWindow: InfoWindow(title: _destinationController.text),
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  // Search for destination and get directions
  Future<void> _searchAndNavigate(String query) async {
    if (query.isEmpty || _currentLocation == null) return;

    setState(() {
      _isLoading = true;
      _feedbackText = 'Searching for $query...';
    });

    try {
      // Convert address to coordinates
      List<Location> locations = [];

      try {
        locations = await locationFromAddress(query);
      } catch (e) {
        debugPrint('Error with locationFromAddress: $e');
        _speak(
          'Could not find the location. Please try again with a different address.',
        );
        setState(() {
          _isLoading = false;
          _feedbackText = 'Location not found';
        });
        return;
      }

      if (locations.isEmpty) {
        _speak(
          'Could not find the location. Please try again with a different address.',
        );
        setState(() {
          _isLoading = false;
          _feedbackText = 'Location not found';
        });
        return;
      }

      // Set destination
      _destinationLocation = LatLng(
        locations.first.latitude,
        locations.first.longitude,
      );

      // Update markers
      _updateMarkers();

      // Get directions
      await _getDirections();

      // Start navigation
      _startNavigation();
    } catch (e) {
      _speak(
        'An error occurred while searching for the destination. Please try again.',
      );
      setState(() {
        _isLoading = false;
        _feedbackText = 'Search error: $e';
      });
    }
  }

  // Get directions between current location and destination
  Future<void> _getDirections() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_currentLocation == null || _destinationLocation == null) {
        setState(() {
          _error = 'Current location or destination is missing';
          _isLoading = false;
        });
        return;
      }

      final response = await _mapsService.getDirections(
        origin: _currentLocation!,
        destination: _destinationLocation!,
        mode: 'driving', // Use driving mode for road navigation
        alternatives: true, // Request alternative routes
      );

      if (response['status'] == 'OK') {
        setState(() {
          _isLoading = false;
          _polylines.clear();
          _markers.clear();

          // Add main route polyline
          final polyline = Polyline(
            polylineId: const PolylineId('route'),
            points:
                response['polylinePoints']
                    .map<LatLng>(
                      (point) => LatLng(point.latitude, point.longitude),
                    )
                    .toList(),
            color: Colors.blue,
            width: 5,
          );
          _polylines.add(polyline);

          // Store navigation steps
          _navigationSteps = List<Map<String, dynamic>>.from(response['steps']);
          _currentStepIndex = 0;

          // Store alternative routes
          _alternativeRoutes = List<Map<String, dynamic>>.from(
            response['routes'],
          );

          // Store total distance and duration for display
          _distanceText = response['distance'] ?? 'Unknown';
          _durationText = response['duration'] ?? 'Unknown';

          // Add alternative routes if enabled
          if (_showAlternativeRoutes && _alternativeRoutes.length > 1) {
            for (var i = 1; i < _alternativeRoutes.length; i++) {
              final alternativePolyline = Polyline(
                polylineId: PolylineId('route_$i'),
                points:
                    _alternativeRoutes[i]['polyline']
                        .map<LatLng>(
                          (point) => LatLng(point.latitude, point.longitude),
                        )
                        .toList(),
                color: Colors.grey,
                width: 3,
              );
              _polylines.add(alternativePolyline);
            }
          }

          // Add markers for origin, destination and waypoints
          _markers.add(
            Marker(
              markerId: const MarkerId('origin'),
              position: _currentLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: const InfoWindow(title: 'Starting Point'),
            ),
          );

          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: _destinationLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: InfoWindow(title: _destinationController.text),
            ),
          );

          // If there are navigation steps, add markers for key turns
          if (_navigationSteps.isNotEmpty) {
            for (var i = 0; i < _navigationSteps.length; i += 4) {
              // Add markers for every 4th step to avoid clutter
              if (_navigationSteps[i]['maneuver_type'] != null &&
                  _navigationSteps[i]['maneuver_type'] != '') {
                _markers.add(
                  Marker(
                    markerId: MarkerId('step_$i'),
                    position: LatLng(
                      _navigationSteps[i]['start_location']['lat'],
                      _navigationSteps[i]['start_location']['lng'],
                    ),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueYellow,
                    ),
                    infoWindow: InfoWindow(
                      title: 'Step ${i + 1}',
                      snippet: _navigationSteps[i]['clean_instructions'],
                    ),
                  ),
                );
              }
            }
          }

          // Calculate route bounds for camera
          final bounds = response['bounds'];
          if (bounds != null && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(
                    bounds['southwest']['lat'],
                    bounds['southwest']['lng'],
                  ),
                  northeast: LatLng(
                    bounds['northeast']['lat'],
                    bounds['northeast']['lng'],
                  ),
                ),
                100, // Padding
              ),
            );
          } else if (_mapController != null && _currentLocation != null) {
            // Fallback camera position
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(_currentLocation!, 15),
            );
          }

          // Announce the route information
          final distance = response['distance'] ?? 'unknown distance';
          final duration = response['duration'] ?? 'unknown time';
          final trafficDuration = response['duration_in_traffic'];

          String routeAnnouncement =
              'Route found. $distance, taking about $duration';
          if (trafficDuration != null) {
            routeAnnouncement += ' in current traffic conditions';
          }

          _speak(routeAnnouncement);
        });
      } else {
        setState(() {
          _error = 'Could not get directions: ${response['status']}';
          _isLoading = false;
          // Fallback to a straight line if API returns error
          _generateStraightLineRoute();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error getting directions: $e';
        _isLoading = false;
        // Fallback to a straight line if there's an exception
        _generateStraightLineRoute();
      });
    }
  }

  // Create a straight line route when Directions API is unavailable
  void _generateStraightLineRoute() {
    if (_currentLocation == null || _destinationLocation == null) return;

    setState(() {
      _polylines.clear();

      // Create a simple straight line route
      final polyline = Polyline(
        polylineId: const PolylineId('straight_route'),
        points: [_currentLocation!, _destinationLocation!],
        color: Colors.red,
        width: 3,
      );

      _polylines.add(polyline);

      _markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Starting Point'),
        ),
      );

      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: _destinationController.text),
        ),
      );

      // Calculate direct distance
      final distanceInMeters = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );

      final distanceText =
          distanceInMeters >= 1000
              ? '${(distanceInMeters / 1000).toStringAsFixed(1)} km'
              : '${distanceInMeters.round()} m';

      _speak(
        'Using simplified straight-line navigation. Distance to destination: $distanceText',
      );

      _isLoading = false;
    });
  }

  // Calculate bounds for the route
  LatLngBounds _getBounds(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;

    for (LatLng point in points) {
      if (minLat == null || point.latitude < minLat) {
        minLat = point.latitude;
      }
      if (maxLat == null || point.latitude > maxLat) {
        maxLat = point.latitude;
      }
      if (minLng == null || point.longitude < minLng) {
        minLng = point.longitude;
      }
      if (maxLng == null || point.longitude > maxLng) {
        maxLng = point.longitude;
      }
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  // Start navigation with turn-by-turn directions
  void _startNavigation() {
    if (_navigationSteps.isEmpty) {
      _speak('No navigation steps available. Please try again.');
      return;
    }

    setState(() {
      _isNavigating = true;

      // Make sure we display the total distance and time information
      if (_distanceText.isEmpty) {
        _distanceText = 'Calculating...';
      }
      if (_durationText.isEmpty) {
        _durationText = 'Calculating...';
      }
    });

    // Speak initial instructions
    _announceCurrentStep();

    // Start periodic updates for navigation
    _startLocationUpdates();
    _startNavigationInstructions();

    // Set up timer to periodically check location and update navigation
    _navigationUpdateTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateNavigation(),
    );

    // Zoom to show current location and next waypoint
    _updateMapForNavigation();
  }

  // Stop active navigation
  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _currentStepIndex = 0;
      _distanceText = '';
      _durationText = '';
    });

    _navigationUpdateTimer?.cancel();
    _navigationUpdateTimer = null;
    _speak('Navigation stopped');
  }

  // Update navigation based on current location
  Future<void> _updateNavigation() async {
    if (!_isNavigating ||
        _currentLocation == null ||
        _navigationSteps.isEmpty) {
      return;
    }

    // Get current step
    final currentStep = _navigationSteps[_currentStepIndex];

    // Extract end coordinates of current step
    final stepEndLat = currentStep['end_location']['lat'];
    final stepEndLng = currentStep['end_location']['lng'];
    final stepEndPoint = LatLng(stepEndLat, stepEndLng);

    // Calculate distance to the end of current step
    final distanceToStepEnd = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      stepEndPoint.latitude,
      stepEndPoint.longitude,
    );

    // Update UI with remaining info
    setState(() {
      _nextWaypoint = stepEndPoint;
      _remainingDistance = distanceToStepEnd;
      _nextManeuver = currentStep['clean_instructions'] ?? '';
      _remainingTime = currentStep['duration']['text'] ?? '';
    });

    // If we're close enough to the end of this step, move to next step
    if (distanceToStepEnd < 30 &&
        _currentStepIndex < _navigationSteps.length - 1) {
      _currentStepIndex++;
      _announceCurrentStep();
      _updateMapForNavigation();
    }

    // Check if we've reached the destination
    final distanceToDestination = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _destinationLocation!.latitude,
      _destinationLocation!.longitude,
    );

    if (distanceToDestination < 30) {
      _speak('You have arrived at your destination');
      _stopNavigation();
    }
  }

  // Announce the current navigation step
  void _announceCurrentStep() {
    if (_currentStepIndex >= _navigationSteps.length) {
      return;
    }

    final currentStep = _navigationSteps[_currentStepIndex];
    final instruction =
        currentStep['clean_instructions'] ?? 'Continue on the current road';
    final distance = currentStep['distance']['text'] ?? '';

    String announcement = instruction;
    if (distance.isNotEmpty) {
      announcement += ' for $distance';
    }

    _speak(announcement);
  }

  // Update map view during navigation
  void _updateMapForNavigation() {
    if (_currentLocation == null ||
        _nextWaypoint == null ||
        _mapController == null) {
      return;
    }

    // Calculate bearing for the map camera
    final bearing = Geolocator.bearingBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _nextWaypoint!.latitude,
      _nextWaypoint!.longitude,
    );

    // Update camera position
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentLocation!,
          zoom: 18.0,
          tilt: 45.0,
          bearing: bearing,
        ),
      ),
    );

    // Update current location marker to include heading
    setState(() {
      _markers.removeWhere(
        (marker) => marker.markerId == const MarkerId('origin'),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _currentLocation!,
          rotation: bearing,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Current Location'),
        ),
      );
    });
  }

  // Toggle showing alternative routes
  void _toggleAlternativeRoutes() {
    setState(() {
      _showAlternativeRoutes = !_showAlternativeRoutes;
      // Refresh the directions to update polylines
      _getDirections();
    });
  }

  // Text to speech helper
  Future<void> _speak(String text) async {
    // Don't speak if we're currently listening
    if (_isListening) {
      debugPrint('Skipping TTS while listening: $text');
      return;
    }

    await _stopTts(); // Stop any ongoing speech

    // Create a completer to track when speech is done
    Completer<void> completer = Completer<void>();

    // Set up completion callback
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Set up error handler
    _flutterTts.setErrorHandler((error) {
      debugPrint('TTS Error: $error');
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    // Speak the text
    await _flutterTts.speak(text);

    // For very short phrases, add a small delay to ensure the speech starts
    if (text.split(' ').length <= 3) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Return the future that completes when speaking is done
    return completer.future;
  }

  // Stop TTS
  Future<void> _stopTts() async {
    await _flutterTts.stop();
  }

  // Start listening for voice commands
  void _startListening() async {
    try {
      // Stop any ongoing TTS to avoid conflict
      await _stopTts();

      // Reset the speech service to ensure a fresh state
      await _speechService.reset();

      // Reset the state
      setState(() {
        _isListening = true;
        _feedbackText = 'Listening...';
        _destinationController.clear(); // Clear previous input
      });

      // Start listening for voice input
      _speechService.startListening(
        onResult: (text) async {
          if (text.isNotEmpty) {
            setState(() {
              _destinationController.text = text;
              _feedbackText = 'You said: $text';
              _isListening =
                  false; // Mark as not listening once we get a result
            });

            // Process the result
            await _searchAndNavigate(text);
          } else {
            setState(() {
              _isListening = false;
              _feedbackText = 'Sorry, I didn\'t catch that.';
            });
          }
        },
      );

      // Add a timer to stop listening after 10 seconds if no result
      Future.delayed(const Duration(seconds: 10), () {
        if (_isListening) {
          _stopSpeechRecognition();
          if (_destinationController.text.isEmpty) {
            // Show visual feedback instead of speaking
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No speech detected. Please try again.'),
                ),
              );
            }
            setState(() {
              _feedbackText = 'No speech detected. Please try again.';
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Error starting speech recognition: $e');
      setState(() {
        _isListening = false;
        _feedbackText = 'Error starting speech recognition';
      });
    }
  }

  // Stop listening for voice commands
  void _stopSpeechRecognition() async {
    try {
      await _speechService.stopListening();
      setState(() {
        _isListening = false;
        _feedbackText = 'Listening stopped';
      });
    } catch (e) {
      debugPrint('Error stopping speech recognition: $e');
    }
  }

  // Search for nearby places of interest
  Future<void> _searchNearbyPlaces(String type) async {
    if (_currentLocation == null) return;

    setState(() {
      _isLoading = true;
      _feedbackText = 'Searching for nearby $type...';
    });

    if (!_areGoogleApisAvailable) {
      _speak('Sorry, the places search feature is currently unavailable.');
      setState(() {
        _isLoading = false;
        _feedbackText = 'Places API not available';
      });
      return;
    }

    try {
      List<Map<String, dynamic>> places = await _mapsService.searchNearbyPlaces(
        location: _currentLocation!,
        type: type,
        radius: 500, // Search within 500 meters
      );

      if (places.isEmpty) {
        _speak('No $type found nearby.');
        setState(() {
          _isLoading = false;
          _feedbackText = 'No $type found nearby';
        });
        return;
      }

      // Announce the number of places found
      _speak(
        'Found ${places.length} $type nearby. The closest one is ${places.first['name']}, about ${_calculateDistance(_currentLocation!, places.first['location'])} meters away.',
      );

      setState(() {
        _isLoading = false;
        _feedbackText = 'Found ${places.length} nearby $type';
      });

      // Show dialog with list of places
      _showPlacesDialog(places, type);
    } catch (e) {
      _speak('An error occurred while searching for nearby places.');
      setState(() {
        _isLoading = false;
        _feedbackText = 'Search error: $e';
      });
    }
  }

  // Calculate distance between two points
  int _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    ).round();
  }

  // Show dialog with list of nearby places
  void _showPlacesDialog(List<Map<String, dynamic>> places, String type) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Nearby $type'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount:
                    places.length > 5 ? 5 : places.length, // Limit to 5 places
                itemBuilder: (context, index) {
                  final place = places[index];
                  final distance = _calculateDistance(
                    _currentLocation!,
                    place['location'],
                  );

                  return ListTile(
                    title: Text(place['name']),
                    subtitle: Text('${place['vicinity']} • ${distance}m away'),
                    onTap: () {
                      Navigator.pop(context);
                      _destinationLocation = place['location'];
                      _destinationController.text = place['name'];
                      _updateMarkers();
                      _getDirections();
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _speakInstructions,
            tooltip: 'Instructions',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Instructions text
                Padding(
                  padding: const EdgeInsets.only(left: 12.0, bottom: 6.0),
                  child: Text(
                    'Tap the microphone icon to speak your destination',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
                // Enhanced search bar
                TextField(
                  controller: _destinationController,
                  decoration: InputDecoration(
                    labelText: 'Where do you want to go?',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Container(
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.red[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      margin: const EdgeInsets.all(5.0),
                      child: IconButton(
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? Colors.red : Colors.blue,
                          size: 30, // Larger icon
                        ),
                        onPressed: () {
                          if (_isListening) {
                            _stopSpeechRecognition();
                          } else {
                            _startListening();
                          }
                        },
                        tooltip:
                            _isListening ? 'Stop listening' : 'Voice search',
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: BorderSide(color: Colors.blue, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: BorderSide(color: Colors.blue, width: 2.0),
                    ),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _searchAndNavigate(value);
                    }
                  },
                ),
              ],
            ),
          ),

          // Map View
          Expanded(
            child: Stack(
              children: [
                // Google Map
                GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: CameraPosition(
                    target:
                        _currentLocation ??
                        const LatLng(
                          28.6139,
                          77.2090,
                        ), // Default to New Delhi if location not available
                    zoom: 15,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  compassEnabled: true,
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: _onMapCreated,
                  padding: const EdgeInsets.only(
                    bottom: 120,
                  ), // Add padding to account for bottom UI elements
                ),

                // Loading indicator
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),

                // Listening indicator
                if (_isListening)
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 16.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic, color: Colors.red, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Listening...',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Error message
                if (_error != null)
                  Positioned(
                    bottom: 200,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                // Navigation info panel (when actively navigating)
                if (_isNavigating && _nextManeuver.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Column(
                      children: [
                        // Current step navigation box
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nextManeuver,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'In ${_remainingDistance.toStringAsFixed(0)} meters',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  Text(
                                    _remainingTime,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Small gap between boxes
                        const SizedBox(height: 8),

                        // Total distance and time box
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                spreadRadius: 1,
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Total distance section
                              Row(
                                children: [
                                  const Icon(
                                    Icons.directions,
                                    color: Colors.blue,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _distanceText.isNotEmpty
                                        ? _distanceText
                                        : 'Calculating...',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),

                              // Vertical divider
                              Container(
                                height: 24,
                                width: 1,
                                color: Colors.grey.withOpacity(0.5),
                              ),

                              // Total time section
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    color: Colors.blue,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _durationText.isNotEmpty
                                        ? _durationText
                                        : 'Calculating...',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isNavigating ? _stopNavigation : _startNavigation,
                  icon: Icon(_isNavigating ? Icons.stop : Icons.navigation),
                  label: Text(_isNavigating ? 'Stop' : 'Start Navigation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isNavigating ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleAlternativeRoutes,
                  icon: Icon(
                    _showAlternativeRoutes ? Icons.route : Icons.alt_route,
                  ),
                  label: Text(
                    _showAlternativeRoutes
                        ? 'Hide Alternatives'
                        : 'Show Alternatives',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _speakCurrentLocation,
        tooltip: 'Speak Current Location',
        child: const Icon(Icons.record_voice_over),
      ),
    );
  }

  void _speakInstructions() {
    _speak('''
      Navigation Screen Instructions:
      - Enter a destination in the search bar and press enter to search
      - The map will show your route with turn-by-turn directions
      - Tap "Start Navigation" to begin guided navigation
      - The app will announce each turn as you approach it
      - Tap "Show Alternatives" to view other possible routes
      - Tap the microphone button to hear your current location
      - Use the navigation controls on the map to zoom and pan
    ''');
  }

  void _centerOnCurrentLocation() {
    if (_currentLocation != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLocation!, zoom: 16.0),
        ),
      );
    } else {
      // If current location is not available yet, get it and then center
      _getCurrentLocation().then((_) {
        if (_currentLocation != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: _currentLocation!, zoom: 16.0),
            ),
          );
        }
      });
    }
  }

  // Make the onMapCreated callback more robust
  void _onMapCreated(GoogleMapController controller) {
    setState(() {
      _mapController = controller;
    });

    // Ensure we center on the current location immediately after map creation
    // with a slight delay to allow the map to initialize fully
    Future.delayed(const Duration(milliseconds: 300), () {
      _centerOnCurrentLocation();
    });
  }

  void _speakCurrentLocation() {
    if (_currentLocation != null) {
      _speak(
        'Current location is ${_currentLocation!.latitude}, ${_currentLocation!.longitude}',
      );
    }
  }

  // Start location updates for navigation
  void _startLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _getCurrentLocation();
      _updateNavigation();
    });
  }

  // Start periodic navigation instructions
  void _startNavigationInstructions() {
    _navigationInstructionTimer?.cancel();
    _navigationInstructionTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      if (_isNavigating && _currentStepIndex < _navigationSteps.length) {
        _announceCurrentStep();
      }
    });
  }
}
