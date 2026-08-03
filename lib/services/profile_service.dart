import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vision_assist/models/user_profile.dart';

class ProfileService {
  static const String _profileKey = 'user_profile';

  // Save user profile to SharedPreferences
  Future<bool> saveProfile(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = jsonEncode(profile.toJson());
      return await prefs.setString(_profileKey, profileJson);
    } catch (e) {
      print('Error saving profile: $e');
      return false;
    }
  }

  // Load user profile from SharedPreferences
  Future<UserProfile> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString(_profileKey);

      if (profileJson == null) {
        return UserProfile(); // Return default profile if none exists
      }

      final profileMap = jsonDecode(profileJson) as Map<String, dynamic>;
      return UserProfile.fromJson(profileMap);
    } catch (e) {
      print('Error loading profile: $e');
      return UserProfile(); // Return default profile on error
    }
  }

  // Clear user profile from SharedPreferences
  Future<bool> clearProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_profileKey);
    } catch (e) {
      print('Error clearing profile: $e');
      return false;
    }
  }
}
