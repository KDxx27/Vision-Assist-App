import 'package:dio/dio.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class GoogleMapsService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api';
  static const String apiKey = 'YOUR_APIKEY'; // Add your API Key here

  final Dio _dio = Dio();

  // Initialize and verify API key is working
  Future<bool> verifyApiKey() async {
    try {
      // Try a simple Directions API request to verify the key works
      final response = await _dio.get(
        '$_baseUrl/directions/json',
        queryParameters: {
          'origin': '40.712776,-74.005974', // New York City coordinates
          'destination': '40.758896,-73.985130', // Times Square coordinates
          'mode': 'driving',
          'alternatives': 'true',
          'key': apiKey,
        },
      );

      debugPrint('Google Maps API verification status: ${response.statusCode}');
      debugPrint(
        'Google Maps API verification response: ${response.data['status']}',
      );

      // Also log the error message if available for debugging
      if (response.data['status'] != 'OK') {
        debugPrint(
          'API error message: ${response.data['error_message'] ?? 'No error message provided'}',
        );
      }

      return response.statusCode == 200 && response.data['status'] == 'OK';
    } catch (e) {
      debugPrint('Error verifying Google Maps API key: $e');
      return false;
    }
  }

  // Get directions between two points with enhanced road-by-road navigation
  Future<Map<String, dynamic>> getDirections({
    required LatLng origin,
    required LatLng destination,
    String mode = 'driving', // Default to driving for road navigation
    String? language,
    List<LatLng>? waypoints,
    bool alternatives = true,
    bool avoidHighways = false,
    bool avoidTolls = false,
    bool avoidFerries = false,
  }) async {
    try {
      debugPrint(
        'Getting directions from ${origin.latitude},${origin.longitude} to ${destination.latitude},${destination.longitude}',
      );

      // Build waypoints parameter if provided
      String? waypointsParam;
      if (waypoints != null && waypoints.isNotEmpty) {
        waypointsParam = waypoints
            .map((point) => '${point.latitude},${point.longitude}')
            .join('|');
      }

      final Map<String, dynamic> queryParameters = {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': mode,
        'language': language ?? 'en',
        'alternatives': alternatives ? 'true' : 'false',
        'key': apiKey,
      };

      // Add optional parameters
      if (waypointsParam != null) {
        queryParameters['waypoints'] = waypointsParam;
      }

      // Add avoidance parameters
      List<String> avoidance = [];
      if (avoidHighways) avoidance.add('highways');
      if (avoidTolls) avoidance.add('tolls');
      if (avoidFerries) avoidance.add('ferries');

      if (avoidance.isNotEmpty) {
        queryParameters['avoid'] = avoidance.join('|');
      }

      // Request detailed instructions
      queryParameters['traffic_model'] = 'best_guess';
      queryParameters['departure_time'] = 'now';

      final response = await _dio.get(
        '$_baseUrl/directions/json',
        queryParameters: queryParameters,
      );

      debugPrint('Directions API response status: ${response.statusCode}');
      debugPrint(
        'Directions API response data status: ${response.data['status']}',
      );

      // Log full response for debugging if there's an issue
      if (response.data['status'] != 'OK') {
        debugPrint(
          'API error message: ${response.data['error_message'] ?? 'No error message provided'}',
        );
        debugPrint('Full response: ${response.data}');
      }

      if (response.statusCode == 200) {
        // Log error message if present
        if (response.data['status'] != 'OK') {
          debugPrint(
            'Directions API error: ${response.data['status']} - ${response.data['error_message'] ?? 'No error message'}',
          );
          return {
            'status': response.data['status'],
            'error': response.data['error_message'] ?? 'Unknown error',
            'polylinePoints': <PointLatLng>[],
            'distance': '0 km',
            'duration': '0 min',
            'steps': [],
            'routes': [],
          };
        }

        // Create polyline decoder
        final polylinePoints = PolylinePoints();

        // Extract points from the response for the primary route
        List<PointLatLng> decodedPoints = [];
        List<Map<String, dynamic>> routes = [];

        if (response.data['routes'].isNotEmpty) {
          // Get primary route polyline
          decodedPoints = polylinePoints.decodePolyline(
            response.data['routes'][0]['overview_polyline']['points'],
          );

          // Extract all routes for alternatives
          for (var route in response.data['routes']) {
            routes.add({
              'summary': route['summary'],
              'warnings': route['warnings'],
              'waypoint_order': route['waypoint_order'],
              'distance': route['legs'][0]['distance']['text'],
              'duration': route['legs'][0]['duration']['text'],
              'polyline': polylinePoints.decodePolyline(
                route['overview_polyline']['points'],
              ),
              'legs': route['legs'],
            });
          }

          debugPrint(
            'Successfully decoded polyline with ${decodedPoints.length} points',
          );
          debugPrint('Found ${routes.length} alternative routes');
        } else {
          debugPrint('No routes found in directions response');
        }

        // Extract detailed steps from the primary route
        List<Map<String, dynamic>> steps = [];
        if (response.data['routes'].isNotEmpty &&
            response.data['routes'][0]['legs'].isNotEmpty) {
          steps = List<Map<String, dynamic>>.from(
            response.data['routes'][0]['legs'][0]['steps'] ?? [],
          );

          // Enhance step information with additional details
          for (var i = 0; i < steps.length; i++) {
            // Add human-readable maneuver descriptions
            String instruction = steps[i]['html_instructions'] ?? '';
            String maneuver = steps[i]['maneuver'] ?? '';

            // Clean up HTML tags
            instruction = instruction.replaceAll(RegExp(r'<[^>]*>'), ' ');
            instruction = instruction.replaceAll(RegExp(r'\s+'), ' ').trim();

            steps[i]['clean_instructions'] = instruction;
            steps[i]['maneuver_type'] = maneuver;

            // Add start and end coordinates for each step
            if (steps[i]['start_location'] != null) {
              steps[i]['start_coordinates'] = LatLng(
                steps[i]['start_location']['lat'],
                steps[i]['start_location']['lng'],
              );
            }

            if (steps[i]['end_location'] != null) {
              steps[i]['end_coordinates'] = LatLng(
                steps[i]['end_location']['lat'],
                steps[i]['end_location']['lng'],
              );
            }

            // Add estimated time in minutes for TTS
            if (steps[i]['duration'] != null &&
                steps[i]['duration']['text'] != null) {
              steps[i]['duration_minutes'] = _extractMinutes(
                steps[i]['duration']['text'],
              );
            }
          }
        }

        return {
          'status': response.data['status'],
          'polylinePoints': decodedPoints,
          'distance':
              response.data['routes'].isNotEmpty
                  ? response.data['routes'][0]['legs'][0]['distance']['text']
                  : '0 km',
          'duration':
              response.data['routes'].isNotEmpty
                  ? response.data['routes'][0]['legs'][0]['duration']['text']
                  : '0 min',
          'duration_in_traffic':
              response.data['routes'].isNotEmpty &&
                      response.data['routes'][0]['legs'][0]['duration_in_traffic'] !=
                          null
                  ? response
                      .data['routes'][0]['legs'][0]['duration_in_traffic']['text']
                  : null,
          'steps': steps,
          'routes': routes,
          'bounds':
              response.data['routes'].isNotEmpty
                  ? {
                    'northeast': {
                      'lat':
                          response
                              .data['routes'][0]['bounds']['northeast']['lat'],
                      'lng':
                          response
                              .data['routes'][0]['bounds']['northeast']['lng'],
                    },
                    'southwest': {
                      'lat':
                          response
                              .data['routes'][0]['bounds']['southwest']['lat'],
                      'lng':
                          response
                              .data['routes'][0]['bounds']['southwest']['lng'],
                    },
                  }
                  : null,
        };
      } else {
        debugPrint(
          'Directions API request failed with status: ${response.statusCode}',
        );
        return {
          'status': 'FAILED',
          'polylinePoints': <PointLatLng>[],
          'distance': '0 km',
          'duration': '0 min',
          'steps': [],
          'routes': [],
        };
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
      return {
        'status': 'ERROR',
        'error': e.toString(),
        'polylinePoints': <PointLatLng>[],
        'distance': '0 km',
        'duration': '0 min',
        'steps': [],
        'routes': [],
      };
    }
  }

  // Extract minutes from a duration string like "5 mins" or "1 hour 20 mins"
  int _extractMinutes(String durationText) {
    // Handle hours and minutes pattern like "1 hour 20 mins"
    final hoursRegex = RegExp(r'(\d+)\s+hour');
    final minutesRegex = RegExp(r'(\d+)\s+min');

    int totalMinutes = 0;

    // Extract hours
    final hoursMatch = hoursRegex.firstMatch(durationText);
    if (hoursMatch != null && hoursMatch.groupCount >= 1) {
      final hours = int.tryParse(hoursMatch.group(1) ?? '0') ?? 0;
      totalMinutes += hours * 60;
    }

    // Extract minutes
    final minutesMatch = minutesRegex.firstMatch(durationText);
    if (minutesMatch != null && minutesMatch.groupCount >= 1) {
      final minutes = int.tryParse(minutesMatch.group(1) ?? '0') ?? 0;
      totalMinutes += minutes;
    }

    return totalMinutes > 0 ? totalMinutes : 1; // At least 1 minute
  }

  // Search nearby places
  Future<List<Map<String, dynamic>>> searchNearbyPlaces({
    required LatLng location,
    required String type,
    int radius = 1000,
    String? language,
  }) async {
    try {
      debugPrint(
        'Searching for places of type "$type" near ${location.latitude},${location.longitude}',
      );

      final response = await _dio.get(
        '$_baseUrl/place/nearbysearch/json',
        queryParameters: {
          'location': '${location.latitude},${location.longitude}',
          'radius': radius.toString(),
          'type': type,
          'language': language ?? 'en',
          'key': apiKey,
        },
      );

      debugPrint('Places API response status: ${response.statusCode}');
      debugPrint('Places API response data status: ${response.data['status']}');

      // Log full response data for debugging
      if (response.data['status'] != 'OK') {
        debugPrint(
          'API error message: ${response.data['error_message'] ?? 'No error message provided'}',
        );
        debugPrint('Full response: ${response.data}');
      }

      if (response.statusCode == 200) {
        if (response.data['status'] != 'OK' &&
            response.data['status'] != 'ZERO_RESULTS') {
          debugPrint(
            'Places API error: ${response.data['status']} - ${response.data['error_message'] ?? 'No error message'}',
          );
          return [];
        }

        final places = <Map<String, dynamic>>[];
        if (response.data['results'] != null) {
          for (final place in response.data['results']) {
            places.add({
              'name': place['name'],
              'vicinity': place['vicinity'],
              'location': LatLng(
                place['geometry']['location']['lat'],
                place['geometry']['location']['lng'],
              ),
              'placeId': place['place_id'],
              'types': place['types'],
            });
          }
        }

        debugPrint('Found ${places.length} places nearby');
        return places;
      }
      debugPrint(
        'Places API request failed with status: ${response.statusCode}',
      );
      return [];
    } catch (e) {
      debugPrint('Error searching nearby places: $e');
      return [];
    }
  }

  // Get place details
  Future<Map<String, dynamic>> getPlaceDetails({
    required String placeId,
    String? language,
  }) async {
    try {
      debugPrint('Getting details for place ID: $placeId');

      final response = await _dio.get(
        '$_baseUrl/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields':
              'name,formatted_address,geometry,formatted_phone_number,opening_hours,website',
          'language': language ?? 'en',
          'key': apiKey,
        },
      );

      debugPrint('Place Details API response status: ${response.statusCode}');
      debugPrint(
        'Place Details API response data status: ${response.data['status']}',
      );

      // Log full response for debugging
      if (response.data['status'] != 'OK') {
        debugPrint(
          'API error message: ${response.data['error_message'] ?? 'No error message provided'}',
        );
        debugPrint('Full response: ${response.data}');
      }

      if (response.statusCode == 200) {
        if (response.data['status'] != 'OK') {
          debugPrint(
            'Place Details API error: ${response.data['status']} - ${response.data['error_message'] ?? 'No error message'}',
          );
          return {};
        }

        final result = response.data['result'];
        return {
          'name': result['name'],
          'address': result['formatted_address'],
          'location': LatLng(
            result['geometry']['location']['lat'],
            result['geometry']['location']['lng'],
          ),
          'phone': result['formatted_phone_number'] ?? 'N/A',
          'website': result['website'] ?? 'N/A',
          'openNow':
              result['opening_hours'] != null
                  ? result['opening_hours']['open_now']
                  : null,
        };
      }
      debugPrint(
        'Place Details API request failed with status: ${response.statusCode}',
      );
      return {};
    } catch (e) {
      debugPrint('Error getting place details: $e');
      return {};
    }
  }
}
