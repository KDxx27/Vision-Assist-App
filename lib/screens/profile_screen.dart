import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vision_assist/models/user_profile.dart';
import 'package:vision_assist/services/profile_service.dart';
import 'package:permission_handler/permission_handler.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _profileService = ProfileService();
  final FlutterTts _flutterTts = FlutterTts();

  late UserProfile _userProfile;
  bool _isLoading = true;
  bool _isSaving = false;

  // Text controllers for form fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _bloodGroupController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _guardianInfoController = TextEditingController();
  final TextEditingController _emergencyContactController =
      TextEditingController();
  final TextEditingController _medicalConditionController =
      TextEditingController();

  // Gender selection
  String _selectedGender = '';
  final List<String> _genders = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _bloodGroupController.dispose();
    _addressController.dispose();
    _heightController.dispose();
    _guardianInfoController.dispose();
    _emergencyContactController.dispose();
    _medicalConditionController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // Initialize text-to-speech
  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
  }

  // Speak the given text
  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  // Load user profile from storage
  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await _profileService.loadProfile();

      setState(() {
        _userProfile = profile;
        _nameController.text = profile.name;
        _emailController.text = profile.email;
        _bloodGroupController.text = profile.bloodGroup;
        _addressController.text = profile.address;
        _heightController.text =
            profile.height > 0 ? profile.height.toString() : '';
        _selectedGender = profile.gender;
        _guardianInfoController.text = profile.guardianInfo;
        _emergencyContactController.text = profile.emergencyContact;
        _medicalConditionController.text = profile.medicalCondition;
        _isLoading = false;
      });

      _speak('Profile screen loaded. Please update your information.');
    } catch (e) {
      setState(() {
        _userProfile = UserProfile();
        _isLoading = false;
      });
      _speak('Error loading profile. Please enter your information.');
    }
  }

  // Save user profile to storage
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      _speak('Please correct the errors in the form.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Update profile with form values
      final updatedProfile = UserProfile(
        name: _nameController.text,
        email: _emailController.text,
        bloodGroup: _bloodGroupController.text,
        address: _addressController.text,
        height: double.tryParse(_heightController.text) ?? 0.0,
        gender: _selectedGender,
        guardianInfo: _guardianInfoController.text,
        emergencyContact: _emergencyContactController.text,
        medicalCondition: _medicalConditionController.text,
      );

      final success = await _profileService.saveProfile(updatedProfile);

      setState(() {
        _isSaving = false;
        _userProfile = updatedProfile;
      });

      if (success) {
        _speak('Profile saved successfully.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully')),
        );
      } else {
        _speak('Failed to save profile. Please try again.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save profile')));
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      _speak('Error saving profile. Please try again.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Make a phone call to emergency contact
  Future<void> _callEmergencyContact() async {
    final phoneNumber = _emergencyContactController.text.trim();

    if (phoneNumber.isEmpty) {
      _speak('No emergency contact number provided.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No emergency contact number provided')),
      );
      return;
    }

    // Check and request the CALL_PHONE permission
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      _speak('Permission to make phone calls is required.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission to make phone calls is required'),
        ),
      );
      return;
    }

    // Build the tel: URI
    final String telScheme = 'tel:$phoneNumber';
    try {
      _speak('Opening phone dialer with emergency contact number');

      // Launch directly without checking canLaunchUrl first
      await launchUrl(
        Uri.parse(telScheme),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _speak('Error opening phone dialer. Please try again.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_off),
            onPressed: () => _flutterTts.stop(),
            tooltip: 'Stop Speech',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Profile avatar or icon
                      const Center(
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.deepPurple,
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Personal Information Section
                      const Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Name field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                        onTap: () => _speak('Enter your full name'),
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            // Simple email validation
                            final emailRegex = RegExp(
                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                            );
                            if (!emailRegex.hasMatch(value)) {
                              return 'Please enter a valid email';
                            }
                          }
                          return null;
                        },
                        onTap: () => _speak('Enter your email address'),
                      ),
                      const SizedBox(height: 16),

                      // Gender dropdown
                      DropdownButtonFormField<String>(
                        value:
                            _selectedGender.isNotEmpty ? _selectedGender : null,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.people),
                        ),
                        items:
                            _genders.map((gender) {
                              return DropdownMenuItem<String>(
                                value: gender,
                                child: Text(gender),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedGender = value;
                            });
                          }
                        },
                        validator: (value) {
                          // Gender is optional
                          return null;
                        },
                        onTap: () => _speak('Select your gender'),
                      ),
                      const SizedBox(height: 16),

                      // Height field
                      TextFormField(
                        controller: _heightController,
                        decoration: const InputDecoration(
                          labelText: 'Height (cm)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.height),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final height = double.tryParse(value);
                            if (height == null || height <= 0 || height > 300) {
                              return 'Please enter a valid height';
                            }
                          }
                          return null;
                        },
                        onTap: () => _speak('Enter your height in centimeters'),
                      ),
                      const SizedBox(height: 16),

                      // Blood group field
                      TextFormField(
                        controller: _bloodGroupController,
                        decoration: const InputDecoration(
                          labelText: 'Blood Group',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.bloodtype),
                        ),
                        validator: (value) {
                          // Blood group is optional but should be valid if provided
                          if (value != null && value.isNotEmpty) {
                            final validGroups = [
                              'A+',
                              'A-',
                              'B+',
                              'B-',
                              'AB+',
                              'AB-',
                              'O+',
                              'O-',
                            ];
                            if (!validGroups.contains(value.toUpperCase())) {
                              return 'Please enter a valid blood group (A+, B-, etc.)';
                            }
                          }
                          return null;
                        },
                        onTap:
                            () => _speak(
                              'Enter your blood group, such as A positive or O negative',
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Medical Condition field
                      TextFormField(
                        controller: _medicalConditionController,
                        decoration: const InputDecoration(
                          labelText: 'Medical Condition (NA if none)',
                          hintText: 'e.g. Diabetes, Asthma, None, etc.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.medical_services),
                        ),
                        maxLines: 2,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter NA if no medical conditions';
                          }
                          return null;
                        },
                        onTap:
                            () => _speak(
                              'Enter your medical condition, or NA if none',
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Address field
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.home),
                        ),
                        maxLines: 3,
                        validator: (value) {
                          // Address is optional
                          return null;
                        },
                        onTap: () => _speak('Enter your home address'),
                      ),
                      const SizedBox(height: 24),

                      // Emergency Contact Section
                      const Text(
                        'Emergency Contact Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Guardian info field
                      TextFormField(
                        controller: _guardianInfoController,
                        decoration: const InputDecoration(
                          labelText: 'Guardian Name & Relationship',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.family_restroom),
                        ),
                        validator: (value) {
                          // Guardian info is optional
                          return null;
                        },
                        onTap:
                            () => _speak(
                              'Enter your guardian\'s name and relationship, such as John Smith, Father',
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Emergency contact field
                      TextFormField(
                        controller: _emergencyContactController,
                        decoration: const InputDecoration(
                          labelText: 'Emergency Contact Number',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            // Basic phone number validation
                            final phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');
                            if (!phoneRegex.hasMatch(value)) {
                              return 'Please enter a valid phone number';
                            }
                          }
                          return null;
                        },
                        onTap:
                            () =>
                                _speak('Enter emergency contact phone number'),
                      ),
                      const SizedBox(height: 32),

                      // Action buttons
                      Row(
                        children: [
                          // Save button
                          Expanded(
                            flex: 1,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveProfile,
                              icon:
                                  _isSaving
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : const Icon(Icons.save),
                              label: const Text('SAVE'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Emergency call button
                          Expanded(
                            flex: 1,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _emergencyContactController.text.isEmpty
                                      ? null
                                      : _callEmergencyContact,
                              icon: const Icon(Icons.phone),
                              label: const Text('EMERGENCY CALL'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
    );
  }
}
