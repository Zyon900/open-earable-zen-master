/// Signal smoothing filter using EWMA
class EwmaFilter {
  final double _alpha;
  bool _hasValue = false;
  double _value = 0.0;

  /// [alpha] controls smoothing: higher = less smoothing
  EwmaFilter({required double alpha}) : _alpha = alpha;

  /// Push a new sample and return the filtered value
  double update(double input) {
    if (!_hasValue) {
      _value = input;
      _hasValue = true;
      return _value;
    }
    _value = _alpha * input + (1 - _alpha) * _value;
    return _value;
  }

  /// Last filtered value
  double get value => _value;

  /// Reset internal state
  void reset([double? value]) {
    _value = 0.0;
    _hasValue = false;
    return;
  }
}
