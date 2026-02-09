import 'dart:async';

import 'package:volume_controller/volume_controller.dart';

/// Service for applying and restoring audio numbing. Currently only halves volume,
/// a system-level equalizer would be more effective, but is not yet implemented.
///
/// The first call captures the current system volume and stores it
/// as the "original" level for the session. Subsequent applies will
/// set volume to half of that initial level.
class AudioNumbService {
  static const Duration _debounceDuration = Duration(seconds: 2);

  final VolumeController _volumeController = VolumeController();
  final bool _showSystemUI = false;

  double? _initialVolume;
  Timer? _debounceTimer;
  bool _restoreQueued = false;

  /// Apply a numbed audio level (half the initial volume).
  ///
  /// This also resets a 2-second debounce timer that delays restoration
  /// so rapid movement changes don't cause jittery volume changes.
  Future<void> applyNumbedAudio() async {
    _restoreQueued = false;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _handleDebounceExpired);

    if (_initialVolume == null) {
      _initialVolume = await _volumeController.getVolume();
      _volumeController.showSystemUI = _showSystemUI;
    }

    final double target = (_initialVolume!) * 0.5;
    _volumeController.setVolume(target);
  }

  /// Request restoration to the initial volume after the debounce window
  void restoreAudio() {
    _restoreQueued = true;
    if (_debounceTimer == null || !_debounceTimer!.isActive) {
      _handleDebounceExpired();
    }
  }

  /// Restore the audio to the initial volume after the debounce window
  void _handleDebounceExpired() async {
    if (!_restoreQueued) return;
    _restoreQueued = false;
    if (_initialVolume == null) return;
    _volumeController.setVolume(_initialVolume!);
  }
}
