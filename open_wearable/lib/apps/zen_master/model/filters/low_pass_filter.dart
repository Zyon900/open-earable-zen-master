class LowPassFilter {
  final double _alpha;
  bool _hasValue = false;
  double _value = 0.0;

  /// [alpha] controls smoothing: higher = more smoothing.
  LowPassFilter({required double alpha}) : _alpha = alpha;

  /// Push a new sample and return the filtered value.
  double update(double input) {
    if (!_hasValue) {
      _value = input;
      _hasValue = true;
      return _value;
    }
    _value = _alpha * _value + (1 - _alpha) * input;
    return _value;
  }

  /// Last filtered value
  double get value => _value;

  /// Reset internal state
  void reset() {
    _value = 0.0;
    _hasValue = false;
    return;
  }
}
