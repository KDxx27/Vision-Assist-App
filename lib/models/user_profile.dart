class UserProfile {
  String name;
  String email;
  String bloodGroup;
  String address;
  double height; // height in cm
  String gender;
  String guardianInfo;
  String emergencyContact;
  String medicalCondition; // New field for medical conditions

  UserProfile({
    this.name = '',
    this.email = '',
    this.bloodGroup = '',
    this.address = '',
    this.height = 0.0,
    this.gender = '',
    this.guardianInfo = '',
    this.emergencyContact = '',
    this.medicalCondition = 'NA', // Default to 'NA' if none
  });

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'bloodGroup': bloodGroup,
      'address': address,
      'height': height,
      'gender': gender,
      'guardianInfo': guardianInfo,
      'emergencyContact': emergencyContact,
      'medicalCondition': medicalCondition,
    };
  }

  // Create from JSON
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      bloodGroup: json['bloodGroup'] ?? '',
      address: json['address'] ?? '',
      height: json['height']?.toDouble() ?? 0.0,
      gender: json['gender'] ?? '',
      guardianInfo: json['guardianInfo'] ?? '',
      emergencyContact: json['emergencyContact'] ?? '',
      medicalCondition: json['medicalCondition'] ?? 'NA',
    );
  }

  // Copy with function for immutability
  UserProfile copyWith({
    String? name,
    String? email,
    String? bloodGroup,
    String? address,
    double? height,
    String? gender,
    String? guardianInfo,
    String? emergencyContact,
    String? medicalCondition,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      address: address ?? this.address,
      height: height ?? this.height,
      gender: gender ?? this.gender,
      guardianInfo: guardianInfo ?? this.guardianInfo,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      medicalCondition: medicalCondition ?? this.medicalCondition,
    );
  }
}
