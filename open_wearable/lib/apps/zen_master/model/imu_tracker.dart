import 'dart:async';
import 'dart:math' as math;

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/zen_master/model/filters/ewma_filter.dart';
import 'package:open_wearable/apps/zen_master/model/filters/low_pass_filter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

/// Tracks IMU motion and emits deadzone state changes.
///
/// Uses accelerometer magnitude as a motion proxy, with an EWMA to smooth
/// noise, and compares it against a fixed threshold to detect movement.
class ZenMasterImuTracker {
  // Threshold for "still" vs "moving" after smoothing.
  static const double _deadzoneThreshold = 0.01;
  // EWMA smoothing factor for linear-accel magnitude.
  static const double _ewmaAlpha = 0.2;
  // Low-pass filter for gravity estimate in device frame.
  static const double _gravityFilterAlpha = 0.9;

  // Earable device and configuration provider for IMU streaming.
  final Wearable? _wearable;
  final SensorConfigurationProvider? _sensorConfigurationProvider;
  // Callback to inform the view model/UI of deadzone transitions.
  final void Function(bool) _onDeadzoneChanged;

  StreamSubscription<SensorValue>? _accelSubscription;
  Sensor? _accelSensor;
  late final EwmaFilter _magnitudeFilter = EwmaFilter(alpha: _ewmaAlpha);
  late final LowPassFilter _gravX = LowPassFilter(alpha: _gravityFilterAlpha);
  late final LowPassFilter _gravY = LowPassFilter(alpha: _gravityFilterAlpha);
  late final LowPassFilter _gravZ = LowPassFilter(alpha: _gravityFilterAlpha);
  bool _isInDeadzone = true;

  ZenMasterImuTracker({
    required Wearable? wearable,
    required SensorConfigurationProvider? sensorConfigurationProvider,
    required void Function(bool) onDeadzoneChanged,
  })  : _wearable = wearable,
        _sensorConfigurationProvider = sensorConfigurationProvider,
        _onDeadzoneChanged = onDeadzoneChanged;

  /// Begin streaming accelerometer data and detecting motion.
  void start() {
    if (_wearable == null) return;
    if (!_wearable.hasCapability<SensorManager>()) return;

    final SensorManager sensorManager =
        _wearable.requireCapability<SensorManager>();
    _accelSensor ??= _findAccelerometer(sensorManager.sensors);
    if (_accelSensor == null) return;

    _configureSensorStream(_accelSensor!);

    // Reset state for a fresh session.
    _resetState();
    _accelSubscription?.cancel();

    _accelSubscription = _accelSensor!.sensorStream.listen((data) {
      if (data is! SensorDoubleValue) return;
      final double ax = data.values[0];
      final double ay = data.values[1];
      final double az = data.values[2];

      // Estimate gravity in device frame with a low-pass filter.
      final double gravX = _gravX.update(ax);
      final double gravY = _gravY.update(ay);
      final double gravZ = _gravZ.update(az);

      // Linear acceleration magnitude after gravity removal.
      final double linX = ax - gravX;
      final double linY = ay - gravY;
      final double linZ = az - gravZ;
      final double magnitude =
          math.sqrt(linX * linX + linY * linY + linZ * linZ);

      final double filteredMagnitude = _magnitudeFilter.update(magnitude);
      final bool nextInDeadzone = filteredMagnitude <= _deadzoneThreshold;
      if (nextInDeadzone != _isInDeadzone) {
        _isInDeadzone = nextInDeadzone;
        _onDeadzoneChanged(_isInDeadzone);
      }
    });
  }

  /// Stop IMU streaming and reset internal state.
  void stop() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _resetState();
  }

  /// Find an accelerometer sensor by name (case-insensitive).
  Sensor? _findAccelerometer(List<Sensor> sensors) {
    for (final sensor in sensors) {
      if (sensor.sensorName.toLowerCase() == "accelerometer") {
        return sensor;
      }
    }
    return null;
  }

  /// Enable streaming options on the sensor configuration, if available.
  void _configureSensorStream(Sensor sensor) {
    final SensorConfigurationProvider? configProvider =
        _sensorConfigurationProvider;
    if (configProvider == null) return;

    final Set<SensorConfiguration> configurations = {};
    configurations.addAll(sensor.relatedConfigurations);
    for (final SensorConfiguration configuration in configurations) {
      if (configuration is ConfigurableSensorConfiguration &&
          configuration.availableOptions.contains(StreamSensorConfigOption())) {
        configProvider.addSensorConfigurationOption(
          configuration,
          StreamSensorConfigOption(),
        );
      }
      final List<SensorConfigurationValue> values =
          configProvider.getSensorConfigurationValues(
        configuration,
        distinct: true,
      );
      if (values.isNotEmpty) {
        configProvider.addSensorConfiguration(configuration, values.first);
        configuration.setConfiguration(
          configProvider.getSelectedConfigurationValue(configuration)!,
        );
      }
    }
  }

  void _resetState() {
    _magnitudeFilter.reset();
    _gravX.reset();
    _gravY.reset();
    _gravZ.reset();
    _isInDeadzone = true;
  }
}
