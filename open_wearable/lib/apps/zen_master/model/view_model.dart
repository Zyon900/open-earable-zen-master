import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/zen_master/model/imu_tracker.dart';
import 'package:open_wearable/apps/zen_master/services/audio_numb_service.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

enum ZenMasterPhase {
  // Idle shows play + dial, countdown shows 5s, running shows timer.
  idle,
  countdown,
  running,
}

/// View model for Zen Master: manages session timing and IMU state.
class ZenMasterViewModel extends ChangeNotifier {
  static const int _countdownSeconds = 5;
  // Device and sensor config are optional to allow UI-only testing.
  final Wearable? wearable;
  final SensorConfigurationProvider? sensorConfigurationProvider;

  // Public UI state.
  ZenMasterPhase phase = ZenMasterPhase.idle;
  Duration selectedDuration = const Duration(minutes: 1);
  Duration remainingDuration = Duration.zero;
  int countdownRemaining = _countdownSeconds;
  bool isInDeadzone = true;

  // Internal timers and services.
  Timer? _countdownTimer;
  Timer? _sessionTimer;
  late final ZenMasterImuTracker _imuTracker;
  late final AudioNumbService _audioService;
  bool _isDisposed = false;
  bool _isAudioNumbed = false;

  ZenMasterViewModel({
    required this.wearable,
    required this.sensorConfigurationProvider,
  }) {
    _imuTracker = ZenMasterImuTracker(
      wearable: wearable,
      sensorConfigurationProvider: sensorConfigurationProvider,
      onDeadzoneChanged: _handleDeadzoneChanged,
    );
    _audioService = AudioNumbService();
  }

  @override
  void dispose() {
    _isDisposed = true;
    cancelTimers();
    stopImuTracking();
    super.dispose();
  }

  /// Cancel any running countdown or session timers.
  void cancelTimers() {
    // Ensure only one timing loop runs at a time.
    _countdownTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer = null;
    _sessionTimer = null;
  }

  /// Start the 5-second countdown and IMU tracking.
  void startCountdown() {
    if (selectedDuration.inSeconds <= 0) return;

    // Reset and begin the 5-second countdown.
    cancelTimers();
    phase = ZenMasterPhase.countdown;
    countdownRemaining = _countdownSeconds;
    remainingDuration = selectedDuration;
    isInDeadzone = true;
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) return;
      countdownRemaining -= 1;
      notifyListeners();
      if (countdownRemaining <= 0) {
        timer.cancel();
        startSessionTimer();
      }
    });
  }

  /// Start the main timer after countdown completes.
  void startSessionTimer() {
    // Begin main timer after countdown completes.
    cancelTimers();
    phase = ZenMasterPhase.running;
    remainingDuration = selectedDuration;
    isInDeadzone = true;
    startImuTracking();
    notifyListeners();

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) return;
      remainingDuration -= const Duration(seconds: 1);
      notifyListeners();
      if (remainingDuration.inSeconds <= 0) {
        timer.cancel();
        resetToIdle();
      }
    });
  }

  /// Stop the current session and return to idle.
  void stopSession() {
    cancelTimers();
    stopImuTracking();
    _restoreAudioIfNeeded();
    resetToIdle();
  }

  /// Reset the UI state to idle.
  void resetToIdle() {
    // Restore default UI state after stop or completion.
    stopImuTracking();
    _restoreAudioIfNeeded();
    phase = ZenMasterPhase.idle;
    countdownRemaining = _countdownSeconds;
    remainingDuration = Duration.zero;
    isInDeadzone = true;
    notifyListeners();
  }

  /// Update the duration selected in the dial.
  void updateSelectedDuration(Duration duration) {
    selectedDuration = duration;
    notifyListeners();
  }

  /// Begin IMU tracking (no-op if no wearable).
  void startImuTracking() {
    _imuTracker.start();
  }

  /// Stop IMU tracking and clear IMU state.
  void stopImuTracking() {
    _imuTracker.stop();
  }

  /// React to IMU deadzone changes and apply/restore audio.
  void _handleDeadzoneChanged(bool nextInDeadzone) {
    if (_isDisposed) return;
    if (nextInDeadzone != isInDeadzone) {
      isInDeadzone = nextInDeadzone;
      if (nextInDeadzone) {
        _restoreAudioIfNeeded();
      } else {
        _applyAudioIfNeeded();
      }
      notifyListeners();
    }
  }

  // Apply numbing audio effect once when leaving deadzone.
  void _applyAudioIfNeeded() {
    if (_isAudioNumbed) return;
    _audioService.applyNumbedAudio();
    _isAudioNumbed = true;
  }

  // Restore audio once when re-entering deadzone or ending session.
  void _restoreAudioIfNeeded() {
    if (!_isAudioNumbed) return;
    _audioService.restoreAudio();
    _isAudioNumbed = false;
  }

  /// User-facing helper text shown above the main button.
  String statusLabelText() {
    switch (phase) {
      case ZenMasterPhase.idle:
        return "";
      case ZenMasterPhase.countdown:
        return "Get in position";
      case ZenMasterPhase.running:
        return "Don't move!";
    }
  }
}
