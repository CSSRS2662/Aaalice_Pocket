import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/usage_frecency.dart';

void main() {
  final start = DateTime(2026, 10, 1);

  test('a use counts half as much after each half-life', () {
    final usage = UsageFrecency.empty.record(start, uses: 4);

    expect(usage.scoreAt(start), 4);
    expect(usage.scoreAt(start.add(UsageFrecency.halfLife)), closeTo(2, 1e-9));
    expect(
      usage.scoreAt(start.add(UsageFrecency.halfLife * 2)),
      closeTo(1, 1e-9),
    );
  });

  test('recording decays the old score before adding', () {
    final later = start.add(UsageFrecency.halfLife);
    final usage = UsageFrecency.empty
        .record(start, uses: 2)
        .record(later, uses: 3);

    expect(usage.scoreAt(later), closeTo(4, 1e-9));
    expect(usage.count, 5);
    expect(usage.lastUsedAt, later);
  });

  test('recent heavy use outranks old heavy use', () {
    final now = start.add(const Duration(days: 60));
    final old = UsageFrecency.empty.record(start, uses: 30);
    final recent = UsageFrecency.empty.record(
      now.subtract(const Duration(days: 1)),
      uses: 5,
    );

    expect(recent.scoreAt(now), greaterThan(old.scoreAt(now)));
  });

  test('estimate treats every use as happening at the last use', () {
    expect(UsageFrecency.estimate(count: 6, lastUsedAt: start, now: start), 6);
    expect(
      UsageFrecency.estimate(
        count: 6,
        lastUsedAt: start,
        now: start.add(UsageFrecency.halfLife),
      ),
      closeTo(3, 1e-9),
    );
    expect(UsageFrecency.estimate(count: 6, lastUsedAt: null, now: start), 0);
  });

  test('json round-trips and rejects malformed values', () {
    final usage = UsageFrecency.empty.record(start, uses: 3);
    final restored = UsageFrecency.fromJson(usage.toJson())!;

    expect(restored.score, usage.score);
    expect(restored.count, 3);
    expect(restored.lastUsedAt, start);
    expect(UsageFrecency.fromJson({'s': 'x', 't': 1, 'c': 1}), isNull);
    expect(UsageFrecency.fromJson('nope'), isNull);
  });
}
