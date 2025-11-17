import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:smart_liveliness_detection/src/config/app_config.dart';

/// Service for motion tracking and spoofing detection
class MotionService {
  /// Accelerometer readings
  final List<AccelerometerEvent> _accelerometerReadings = [];

  /// Subscription to accelerometer events
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  /// Configuration for liveness detection
  LivenessConfig _config;

  /// Constructor with optional configuration
  MotionService({
    LivenessConfig? config,
  }) : _config = config ?? const LivenessConfig();

  /// Start tracking device motion
  void startAccelerometerTracking() {
    _accelerometerSubscription =
        accelerometerEventStream().listen((AccelerometerEvent event) {
      _accelerometerReadings.add(event);
      if (_accelerometerReadings.length > _config.maxMotionReadings) {
        _accelerometerReadings.removeAt(0);
      }
    });
  }

  /// Update configuration
  void updateConfig(LivenessConfig config) {
    _config = config;

    // Trim readings if the max count was reduced
    if (_accelerometerReadings.length > _config.maxMotionReadings) {
      _accelerometerReadings.removeRange(
          0, _accelerometerReadings.length - _config.maxMotionReadings);
    }
  }

  /// Check if head motion correlates with device motion (anti-spoofing).
  /// This is improved to be more robust against spoofing attempts.
  /// It accounts for the device's movement in all directions and fails safely if there is insufficient data.
  bool verifyMotionCorrelation(List<Offset> headAngleReadings) {
    // Fail-safe: if not enough data is available, consider it a potential issue.
    if (headAngleReadings.length < 5 || _accelerometerReadings.length < 5) {
      debugPrint('Not enough motion data to verify correlation, failing check.');
      return false;
    }

    // Calculate the range of head movement for both X and Y axes.
    double maxHeadAngleX = headAngleReadings.map((o) => o.dx).reduce(math.max);
    double minHeadAngleX = headAngleReadings.map((o) => o.dx).reduce(math.min);
    double headAngleRangeX = maxHeadAngleX - minHeadAngleX;

    double maxHeadAngleY = headAngleReadings.map((o) => o.dy).reduce(math.max);
    double minHeadAngleY = headAngleReadings.map((o) => o.dy).reduce(math.min);
    double headAngleRangeY = maxHeadAngleY - minHeadAngleY;

    // Calculate the magnitude of accelerometer vector for each reading.
    final motionMagnitudes = _accelerometerReadings
        .map((e) => math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z))
        .toList();

    // Calculate the range of device motion based on vector magnitudes.
    double maxDeviceMotion = motionMagnitudes.reduce(math.max);
    double minDeviceMotion = motionMagnitudes.reduce(math.min);
    double deviceMotionRange = maxDeviceMotion - minDeviceMotion;

    debugPrint(
        'Head angle range X: $headAngleRangeX, Y: $headAngleRangeY, Device motion range: $deviceMotionRange');

    // Spoofing is suspected if the head moved significantly in either axis, but the device did not.
    bool isSpoofingAttempt = (headAngleRangeX > _config.significantHeadAngleRange ||
        headAngleRangeY > _config.significantHeadAngleRange) &&
        deviceMotionRange < _config.minDeviceMovementThreshold;

    if (isSpoofingAttempt) {
      debugPrint('Potential spoofing detected: Significant head motion with minimal device motion.');
    }

    // The check is valid if no spoofing is detected.
    return !isSpoofingAttempt;
  }

  /// Reset all motion tracking
  void resetTracking() {
    _accelerometerReadings.clear();
  }

  /// Clean up resources
  void dispose() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }

  /// Get raw accelerometer readings
  List<AccelerometerEvent> get accelerometerReadings =>
      List<AccelerometerEvent>.unmodifiable(_accelerometerReadings);
}
