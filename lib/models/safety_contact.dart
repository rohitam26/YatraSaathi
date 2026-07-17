import 'package:flutter/foundation.dart';

/// Represents a trusted emergency contact configured for safety check-ins.
@immutable
class SafetyContact {
  SafetyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.countryCode = '+91',
    this.relationship = 'Emergency Contact',
    this.isPrimary = false,
    this.notes,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        assert(id.isNotEmpty, 'Contact id cannot be empty'),
        assert(name.isNotEmpty, 'Contact name cannot be empty'),
        assert(phoneNumber.isNotEmpty, 'Phone number cannot be empty');

  final String id;
  final String name;
  final String phoneNumber;
  final String countryCode;
  final String relationship;
  final bool isPrimary;
  final String? notes;
  final DateTime createdAt;

  /// Full clean phone number with country code formatted for SMS dispatch.
  String get formattedPhoneNumber {
    final cleanPhone = phoneNumber.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanPhone.startsWith('+')) return cleanPhone;
    final cleanCc = countryCode.trim();
    if (cleanCc.isNotEmpty) {
      return '$cleanCc $cleanPhone';
    }
    return cleanPhone;
  }

  /// Privacy-safe masked phone for UI and audit logging.
  String get maskedPhoneNumber {
    final clean = phoneNumber.trim();
    if (clean.length <= 4) return clean;
    final visiblePart = clean.substring(clean.length - 4);
    return '••••••$visiblePart';
  }

  SafetyContact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? countryCode,
    String? relationship,
    bool? isPrimary,
    String? notes,
    DateTime? createdAt,
  }) {
    return SafetyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      relationship: relationship ?? this.relationship,
      isPrimary: isPrimary ?? this.isPrimary,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'relationship': relationship,
      'isPrimary': isPrimary,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SafetyContact.fromJson(Map<String, dynamic> json) {
    return SafetyContact(
      id: json['id'] as String? ?? 'contact_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Contact',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '+91',
      relationship: json['relationship'] as String? ?? 'Emergency Contact',
      isPrimary: json['isPrimary'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
