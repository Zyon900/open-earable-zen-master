import 'dart:async';
import 'dart:math' as math;

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

/// Tracks IMU motion and emits deadzone state changes.
///
/// Uses accelerometer magnitude as a motion proxy, with an EWMA to smooth
/// noise, and compares it against a fixed threshold to detect movement.
class ZenMasterImuTracker {
  // Threshold in m/s^2 (or sensor units) for "still" vs "moving".
  static const double _deadzoneThreshold = 0.2;
  // EWMA smoothing factor for motion magnitude delta.
  static const double _ewmaAlpha = 0.2;

  // Earable device and configuration provider for IMU streaming.
  final Wearable? _wearable;
  final SensorConfigurationProvider? _sensorConfigurationProvider;
  // Callback to inform the view model/UI of deadzone transitions.
  final void Function(bool) _onDeadzoneChanged;

  StreamSubscription<SensorValue>? _imuSubscription;
  Sensor? _accelSensor;
  double _filteredDelta = 0.0;
  double? _baselineMagnitude;

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

    // Reset baseline and filter for a fresh session.
    _baselineMagnitude = null;
    _filteredDelta = 0.0;
    _imuSubscription?.cancel();
    _imuSubscription = _accelSensor!.sensorStream.listen((data) {
      if (data is! SensorDoubleValue) return;
      final double ax = data.values[0];
      final double ay = data.values[1];
      final double az = data.values[2];
      // Use magnitude to ignore axis orientation (see eSense IMU axes doc).
      final double magnitude = math.sqrt(ax * ax + ay * ay + az * az);
      _baselineMagnitude ??= magnitude;
      // Motion delta from the initial baseline magnitude.
      final double delta = (magnitude - _baselineMagnitude!).abs();
      _filteredDelta = _ewmaAlpha * delta + (1 - _ewmaAlpha) * _filteredDelta;
      final bool nextInDeadzone = _filteredDelta <= _deadzoneThreshold;
      _onDeadzoneChanged(nextInDeadzone);
    });
  }

  /// Stop IMU streaming and reset internal state.
  void stop() {
    _imuSubscription?.cancel();
    _imuSubscription = null;
    _baselineMagnitude = null;
    _filteredDelta = 0.0;
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
}
