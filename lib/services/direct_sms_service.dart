import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Status outcomes for direct SMS transmissions via Android SmsManager.
enum DirectSmsStatus {
  sent,
  failed,
  permissionDenied,
  simUnavailable,
  notSupported,
}

/// Diagnostic snapshot of device cellular SIM state.
@immutable
class SimStatus {
  const SimStatus({
    required this.isAvailable,
    required this.simState,
    required this.isDualSim,
    required this.simCount,
  });

  final bool isAvailable;
  final String simState;
  final bool isDualSim;
  final int simCount;

  factory SimStatus.unavailable() => const SimStatus(
        isAvailable: false,
        simState: 'UNAVAILABLE',
        isDualSim: false,
        simCount: 0,
      );

  factory SimStatus.fromMap(Map<dynamic, dynamic> map) {
    return SimStatus(
      isAvailable: map['isAvailable'] as bool? ?? false,
      simState: map['state'] as String? ?? 'UNKNOWN',
      isDualSim: map['isDualSim'] as bool? ?? false,
      simCount: map['simCount'] as int? ?? 1,
    );
  }

  @override
  String toString() =>
      'SimStatus(available: $isAvailable, state: $simState, dualSim: $isDualSim, count: $simCount)';
}

/// Result of a direct SMS transmission attempt.
@immutable
class DirectSmsResult {
  const DirectSmsResult({
    required this.status,
    required this.message,
    this.errorCode,
    this.resultCode,
  });

  final DirectSmsStatus status;
  final String message;
  final String? errorCode;
  final int? resultCode;

  bool get isSuccess => status == DirectSmsStatus.sent;

  @override
  String toString() =>
      'DirectSmsResult(status: $status, error: $errorCode, message: $message)';
}

/// Service providing direct cellular SMS transmission via native Android SmsManager.
///
/// Designed exclusively for privately distributed safety companion APKs.
/// Google Play Store restricts apps requesting `android.permission.SEND_SMS`;
/// production Play Store builds must default to native SMS composer fallback.
class DirectSmsService {
  const DirectSmsService({
    this.channel = const MethodChannel('com.example.pathsaathi/direct_sms'),
  });

  final MethodChannel channel;

  /// Checks if the device has cellular telephony hardware capable of sending SMS.
  Future<bool> isSupported() async {
    try {
      final supported = await channel.invokeMethod<bool>('isDirectSmsSupported');
      return supported ?? false;
    } catch (e) {
      debugPrint('[DirectSmsService] isSupported query handled: $e');
      return false;
    }
  }

  /// Checks if the user has granted runtime `SEND_SMS` permission.
  Future<bool> checkPermission() async {
    try {
      final granted = await channel.invokeMethod<bool>('checkSmsPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('[DirectSmsService] checkPermission query handled: $e');
      return false;
    }
  }

  /// Requests `SEND_SMS` permission from the user.
  Future<bool> requestPermission() async {
    try {
      final granted = await channel.invokeMethod<bool>('requestSmsPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('[DirectSmsService] requestPermission call handled: $e');
      return false;
    }
  }

  /// Checks the active SIM card status and dual-SIM capability.
  Future<SimStatus> getSimStatus() async {
    try {
      final map = await channel.invokeMapMethod<dynamic, dynamic>('getSimStatus');
      if (map != null) {
        return SimStatus.fromMap(map);
      }
      return SimStatus.unavailable();
    } catch (e) {
      debugPrint('[DirectSmsService] getSimStatus call handled: $e');
      return SimStatus.unavailable();
    }
  }

  /// Transmits a direct SMS message using native Android SmsManager.
  ///
  /// Strictly verifies:
  /// 1. Phone number format validity.
  /// 2. `SEND_SMS` permission grant.
  /// 3. Cellular SIM readiness.
  /// 4. Carrier radio acknowledgment via BroadcastReceiver.
  Future<DirectSmsResult> sendDirectSms({
    required String phoneNumber,
    required String message,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '').trim();
    if (cleanPhone.isEmpty || cleanPhone.length < 5) {
      return const DirectSmsResult(
        status: DirectSmsStatus.failed,
        errorCode: 'INVALID_PHONE',
        message: 'Destination phone number is empty or contains too few digits.',
      );
    }

    if (message.trim().isEmpty) {
      return const DirectSmsResult(
        status: DirectSmsStatus.failed,
        errorCode: 'EMPTY_MESSAGE',
        message: 'Cannot send an empty SMS message.',
      );
    }

    try {
      final response = await channel.invokeMapMethod<dynamic, dynamic>(
        'sendDirectSms',
        <String, dynamic>{
          'phoneNumber': cleanPhone,
          'message': message.trim(),
        },
      );

      if (response == null) {
        return const DirectSmsResult(
          status: DirectSmsStatus.failed,
          errorCode: 'NULL_RESPONSE',
          message: 'Received empty response from native SMS manager.',
        );
      }

      final statusStr = response['status'] as String? ?? 'FAILED';
      final msg = response['message'] as String? ?? '';
      final error = response['error'] as String?;
      final resultCode = response['resultCode'] as int?;

      if (statusStr == 'SENT') {
        return DirectSmsResult(
          status: DirectSmsStatus.sent,
          message: msg,
          resultCode: resultCode,
        );
      }

      if (error == 'PERMISSION_DENIED') {
        return DirectSmsResult(
          status: DirectSmsStatus.permissionDenied,
          errorCode: error,
          message: msg,
        );
      }

      if (error == 'SIM_NOT_READY') {
        return DirectSmsResult(
          status: DirectSmsStatus.simUnavailable,
          errorCode: error,
          message: msg,
        );
      }

      return DirectSmsResult(
        status: DirectSmsStatus.failed,
        errorCode: error ?? 'UNKNOWN_ERROR',
        message: msg,
        resultCode: resultCode,
      );
    } catch (e) {
      debugPrint('[DirectSmsService] Exception sending direct SMS: $e');
      return DirectSmsResult(
        status: DirectSmsStatus.failed,
        errorCode: 'PLATFORM_EXCEPTION',
        message: 'Native platform communication failed: $e',
      );
    }
  }
}
