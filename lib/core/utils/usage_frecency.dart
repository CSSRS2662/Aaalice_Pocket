import 'dart:math' as math;

/// How often something has been used lately: every use adds one, and a use
/// counts for half as much after each [halfLife].
///
/// The score is kept as a running total, so remembering it takes one number
/// and the time of the last use.
class UsageFrecency {
  const UsageFrecency({
    required this.score,
    required this.lastUsedAt,
    required this.count,
  });

  static const empty = UsageFrecency(score: 0, lastUsedAt: null, count: 0);

  static const Duration halfLife = Duration(days: 14);

  /// The decayed score as of [lastUsedAt].
  final double score;
  final DateTime? lastUsedAt;

  /// All uses ever recorded, without decay.
  final int count;

  double scoreAt(DateTime now) {
    final last = lastUsedAt;
    if (last == null) return 0;
    return score * decay(now.difference(last));
  }

  UsageFrecency record(DateTime now, {int uses = 1}) => UsageFrecency(
    score: scoreAt(now) + uses,
    lastUsedAt: now,
    count: count + uses,
  );

  /// The weight left on a use made [age] ago.
  static double decay(Duration age) {
    if (age <= Duration.zero) return 1;
    return math.pow(0.5, age.inSeconds / halfLife.inSeconds).toDouble();
  }

  /// A score for things that only keep a total and the last use, treating
  /// every use as if it happened at [lastUsedAt].
  static double estimate({
    required int count,
    required DateTime? lastUsedAt,
    required DateTime now,
  }) {
    if (lastUsedAt == null || count <= 0) return 0;
    return count * decay(now.difference(lastUsedAt));
  }

  Map<String, Object?> toJson() => {
    's': score,
    't': lastUsedAt?.millisecondsSinceEpoch,
    'c': count,
  };

  static UsageFrecency? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final score = raw['s'];
    final time = raw['t'];
    final count = raw['c'];
    if (score is! num || time is! int || count is! int) return null;
    return UsageFrecency(
      score: score.toDouble(),
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(time),
      count: count,
    );
  }
}
