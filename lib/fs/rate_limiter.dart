/// A shared token-bucket rate limiter. All concurrent transfers acquire from a
/// single instance, so the cap is on *aggregate* throughput, not per-transfer.
///
/// Acquisitions are serialised through an internal gate, so the token maths runs
/// one caller at a time and contending transfers queue fairly. The clock and
/// sleep are injectable for deterministic tests.
class RateLimiter {
  RateLimiter({
    this.bytesPerSecond,
    int Function()? clockMs,
    Future<void> Function(Duration)? sleep,
  }) : _clockMs = clockMs ?? _defaultClock,
       _sleep = sleep ?? _realSleep;

  /// The aggregate cap in bytes/second. `null` or `<= 0` means unlimited.
  int? bytesPerSecond;

  final int Function() _clockMs;
  final Future<void> Function(Duration) _sleep;

  double _tokens = 0;
  int _lastMs = 0;
  Future<void> _gate = Future<void>.value();

  static final Stopwatch _sw = Stopwatch()..start();
  static int _defaultClock() => _sw.elapsedMilliseconds;
  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  bool get _unlimited => bytesPerSecond == null || bytesPerSecond! <= 0;

  /// Waits until [bytes] worth of tokens are available, then consumes them.
  /// Returns immediately when unlimited. Calls are serialised, so two transfers
  /// acquiring at once share the cap instead of each getting the full rate.
  Future<void> acquire(int bytes) {
    if (_unlimited || bytes <= 0) return Future<void>.value();
    final next = _gate.then((_) => _consume(bytes));
    _gate = next.catchError((_) {}); // keep the chain alive if a caller throws
    return next;
  }

  Future<void> _consume(int bytes) async {
    if (_unlimited) return; // limit may have been lifted while queued
    final rate = bytesPerSecond!.toDouble();
    final now = _clockMs();
    _tokens += (now - _lastMs) / 1000.0 * rate;
    _lastMs = now;
    // Cap idle accumulation to ~1s of burst so a paused queue can't surge.
    if (_tokens > rate) _tokens = rate;

    if (_tokens >= bytes) {
      _tokens -= bytes;
      return;
    }
    final deficit = bytes - _tokens;
    final waitMs = (deficit / rate * 1000).ceil();
    _tokens = 0;
    await _sleep(Duration(milliseconds: waitMs));
    _lastMs = _clockMs(); // the wait covered the deficit
  }
}
