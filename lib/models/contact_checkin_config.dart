import 'package:flutter/foundation.dart';

/// Configuration for per-stop contacts and custom check-in messages.
@immutable
class ContactCheckInConfig {
  const ContactCheckInConfig({
    required this.id,
    required this.contactName,
    required this.phoneNumber,
    this.customMessage = 'I have reached my stop safely.',
    this.sendDirectSms = false,
    this.isNotified = false,
    this.notifiedAt,
  }) : assert(id.length > 0, 'Contact id cannot be empty'),
       assert(contactName.length > 0, 'Contact name cannot be empty'),
       assert(phoneNumber.length > 0, 'Phone number cannot be empty');

  final String id;
  final String contactName;
  final String phoneNumber;
  final String customMessage;
  final bool sendDirectSms;
  final bool isNotified;
  final DateTime? notifiedAt;

  ContactCheckInConfig copyWith({
    String? id,
    String? contactName,
    String? phoneNumber,
    String? customMessage,
    bool? sendDirectSms,
    bool? isNotified,
    DateTime? notifiedAt,
  }) {
    return ContactCheckInConfig(
      id: id ?? this.id,
      contactName: contactName ?? this.contactName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      customMessage: customMessage ?? this.customMessage,
      sendDirectSms: sendDirectSms ?? this.sendDirectSms,
      isNotified: isNotified ?? this.isNotified,
      notifiedAt: notifiedAt ?? this.notifiedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactName': contactName,
      'phoneNumber': phoneNumber,
      'customMessage': customMessage,
      'sendDirectSms': sendDirectSms,
      'isNotified': isNotified,
      'notifiedAt': notifiedAt?.toIso8601String(),
    };
  }

  factory ContactCheckInConfig.fromJson(Map<String, dynamic> json) {
    return ContactCheckInConfig(
      id: json['id'] as String,
      contactName: json['contactName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      customMessage:
          json['customMessage'] as String? ?? 'I have reached my stop safely.',
      sendDirectSms: json['sendDirectSms'] as bool? ?? false,
      isNotified: json['isNotified'] as bool? ?? false,
      notifiedAt: json['notifiedAt'] != null
          ? DateTime.tryParse(json['notifiedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactCheckInConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          contactName == other.contactName &&
          phoneNumber == other.phoneNumber &&
          customMessage == other.customMessage &&
          sendDirectSms == other.sendDirectSms &&
          isNotified == other.isNotified &&
          notifiedAt == other.notifiedAt;

  @override
  int get hashCode => Object.hash(
    id,
    contactName,
    phoneNumber,
    customMessage,
    sendDirectSms,
    isNotified,
    notifiedAt,
  );
}
