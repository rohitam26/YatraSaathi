import 'package:flutter/foundation.dart';
import 'contact_checkin_config.dart';

/// User profile and default safety contact configuration.
///
/// Configured once in Settings ("MY SAFETY PROFILE") and automatically
/// inherited when creating journeys and stops, while permitting stop-specific
/// overrides.
@immutable
class UserProfile {
  const UserProfile({
    this.userName = '',
    this.userPhone = '',
    this.countryCode = '+91',
    this.defaultContactName = '',
    this.defaultContactPhone = '',
    this.defaultContactRelation = 'Emergency Contact',
    this.defaultMessage = 'Hi! I have safely reached my stop. - Sent via YatraSaathi',
    this.autoCheckInOnArrival = true,
    this.defaultRingtone = 'Classic Ring',
    this.defaultVolume = 1.0,
    this.defaultRepeatUntilDismissed = true,
    this.enableDirectSms = false,
    this.directSmsConsentGiven = false,
    this.optedInDirectSmsContactIds = const [],
  });

  final String userName;
  final String userPhone;
  final String countryCode;
  final String defaultContactName;
  final String defaultContactPhone;
  final String defaultContactRelation;
  final String defaultMessage;
  final bool autoCheckInOnArrival;

  // Ringtone defaults
  final String defaultRingtone;
  final double defaultVolume;
  final bool defaultRepeatUntilDismissed;

  // Direct SMS configuration
  final bool enableDirectSms;
  final bool directSmsConsentGiven;
  final List<String> optedInDirectSmsContactIds;

  bool get hasUserProfile => userName.trim().isNotEmpty || userPhone.trim().isNotEmpty;
  bool get hasDefaultContact =>
      defaultContactName.trim().isNotEmpty && defaultContactPhone.trim().isNotEmpty;

  /// Whether direct SMS can be used for this profile (requires both switch and explicit consent).
  bool get isDirectSmsActive => enableDirectSms && directSmsConsentGiven;

  /// Checks if a given contact ID is opted-in for direct background SMS.
  bool isContactOptedInForDirectSms(String contactId) {
    if (!isDirectSmsActive) return false;
    return optedInDirectSmsContactIds.contains(contactId);
  }

  /// Formatted user phone with country code if not already included.
  String get formattedUserPhone {
    final clean = userPhone.trim().replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return '';
    if (clean.startsWith('+')) return clean;
    final cleanCc = countryCode.trim();
    return '$cleanCc$clean';
  }

  /// Formatted contact phone with country code if not already included.
  String get formattedContactPhone {
    final clean = defaultContactPhone.trim().replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return '';
    if (clean.startsWith('+')) return clean;
    final cleanCc = countryCode.trim();
    return '$cleanCc$clean';
  }

  /// Formats check-in message personalized with the passenger's name/phone.
  String formatPersonalizedMessage({
    required String stopName,
    String? nextStopName,
  }) {
    final buffer = StringBuffer();
    if (userName.trim().isNotEmpty) {
      buffer.write('Hi! This is ${userName.trim()}. ');
    } else {
      buffer.write('Hi! ');
    }

    buffer.write('I have safely reached my stop: $stopName.');
    if (nextStopName != null && nextStopName.isNotEmpty) {
      buffer.write(' Next stop: $nextStopName.');
    }
    buffer.write(' - Sent via YatraSaathi');
    return buffer.toString();
  }

  /// Creates a [ContactCheckInConfig] populated from this profile's default contact.
  ContactCheckInConfig? toDefaultContactConfig({String? stopName, String? nextStopName}) {
    if (!hasDefaultContact) return null;
    final defaultId = 'contact_default_${DateTime.now().millisecondsSinceEpoch}';
    return ContactCheckInConfig(
      id: defaultId,
      contactName: defaultContactName.trim(),
      phoneNumber: formattedContactPhone,
      customMessage: stopName != null
          ? formatPersonalizedMessage(stopName: stopName, nextStopName: nextStopName)
          : defaultMessage.trim(),
      sendDirectSms: isDirectSmsActive,
    );
  }

  UserProfile copyWith({
    String? userName,
    String? userPhone,
    String? countryCode,
    String? defaultContactName,
    String? defaultContactPhone,
    String? defaultContactRelation,
    String? defaultMessage,
    bool? autoCheckInOnArrival,
    String? defaultRingtone,
    double? defaultVolume,
    bool? defaultRepeatUntilDismissed,
    bool? enableDirectSms,
    bool? directSmsConsentGiven,
    List<String>? optedInDirectSmsContactIds,
  }) {
    return UserProfile(
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      countryCode: countryCode ?? this.countryCode,
      defaultContactName: defaultContactName ?? this.defaultContactName,
      defaultContactPhone: defaultContactPhone ?? this.defaultContactPhone,
      defaultContactRelation:
          defaultContactRelation ?? this.defaultContactRelation,
      defaultMessage: defaultMessage ?? this.defaultMessage,
      autoCheckInOnArrival: autoCheckInOnArrival ?? this.autoCheckInOnArrival,
      defaultRingtone: defaultRingtone ?? this.defaultRingtone,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      defaultRepeatUntilDismissed:
          defaultRepeatUntilDismissed ?? this.defaultRepeatUntilDismissed,
      enableDirectSms: enableDirectSms ?? this.enableDirectSms,
      directSmsConsentGiven: directSmsConsentGiven ?? this.directSmsConsentGiven,
      optedInDirectSmsContactIds:
          optedInDirectSmsContactIds ?? this.optedInDirectSmsContactIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'userPhone': userPhone,
      'countryCode': countryCode,
      'defaultContactName': defaultContactName,
      'defaultContactPhone': defaultContactPhone,
      'defaultContactRelation': defaultContactRelation,
      'defaultMessage': defaultMessage,
      'autoCheckInOnArrival': autoCheckInOnArrival,
      'defaultRingtone': defaultRingtone,
      'defaultVolume': defaultVolume,
      'defaultRepeatUntilDismissed': defaultRepeatUntilDismissed,
      'enableDirectSms': enableDirectSms,
      'directSmsConsentGiven': directSmsConsentGiven,
      'optedInDirectSmsContactIds': optedInDirectSmsContactIds,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userName: json['userName'] as String? ?? '',
      userPhone: json['userPhone'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '+91',
      defaultContactName: json['defaultContactName'] as String? ?? '',
      defaultContactPhone: json['defaultContactPhone'] as String? ?? '',
      defaultContactRelation:
          json['defaultContactRelation'] as String? ?? 'Emergency Contact',
      defaultMessage: json['defaultMessage'] as String? ??
          'Hi! I have safely reached my stop. - Sent via YatraSaathi',
      autoCheckInOnArrival: json['autoCheckInOnArrival'] as bool? ?? true,
      defaultRingtone: json['defaultRingtone'] as String? ?? 'Classic Ring',
      defaultVolume: (json['defaultVolume'] as num?)?.toDouble() ?? 1.0,
      defaultRepeatUntilDismissed:
          json['defaultRepeatUntilDismissed'] as bool? ?? true,
      enableDirectSms: json['enableDirectSms'] as bool? ?? false,
      directSmsConsentGiven: json['directSmsConsentGiven'] as bool? ?? false,
      optedInDirectSmsContactIds: (json['optedInDirectSmsContactIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}
