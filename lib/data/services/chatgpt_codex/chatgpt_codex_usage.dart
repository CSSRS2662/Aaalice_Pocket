/// One ChatGPT Codex rate-limit window, as the backend reports it.
class ChatGptCodexUsageWindow {
  const ChatGptCodexUsageWindow({
    required this.usedPercent,
    this.length,
    this.resetsAt,
  });

  final double usedPercent;

  /// Window length; 5 hours and 7 days on current plans, but plans differ,
  /// so the UI names a window by this value.
  final Duration? length;
  final DateTime? resetsAt;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100).toDouble();

  /// Parses `{used_percent, limit_window_seconds, reset_after_seconds,
  /// reset_at}` from `/wham/usage`.
  static ChatGptCodexUsageWindow? fromJson(Object? raw, DateTime now) {
    if (raw is! Map) return null;
    final used = _number(raw['used_percent']);
    if (used == null) return null;
    final seconds = _number(raw['limit_window_seconds']);
    final minutes = _number(raw['window_minutes']);
    return ChatGptCodexUsageWindow(
      usedPercent: used.toDouble(),
      length: seconds != null
          ? Duration(seconds: seconds.round())
          : minutes != null
          ? Duration(minutes: minutes.round())
          : null,
      resetsAt:
          _epoch(raw['reset_at'] ?? raw['resets_at']) ??
          _after(now, raw['reset_after_seconds']),
    );
  }
}

/// Codex quota of one ChatGPT account at [observedAt].
class ChatGptCodexUsage {
  const ChatGptCodexUsage({
    required this.observedAt,
    this.primary,
    this.secondary,
    this.additional = const [],
    this.planType,
    this.limitReached = false,
  });

  final DateTime observedAt;
  final ChatGptCodexUsageWindow? primary;
  final ChatGptCodexUsageWindow? secondary;

  /// Per-model limits some plans add, each named by the backend.
  final List<ChatGptCodexNamedLimit> additional;
  final String? planType;
  final bool limitReached;

  bool get hasWindows => primary != null || secondary != null;

  /// Response headers only carry the two main windows; keep the plan and
  /// per-model limits from the last full read.
  ChatGptCodexUsage withDetailsFrom(ChatGptCodexUsage? previous) =>
      previous == null
      ? this
      : ChatGptCodexUsage(
          observedAt: observedAt,
          primary: primary ?? previous.primary,
          secondary: secondary ?? previous.secondary,
          additional: additional.isNotEmpty ? additional : previous.additional,
          planType: planType ?? previous.planType,
          limitReached: limitReached,
        );

  /// Reads `x-codex-primary-*` / `x-codex-secondary-*` response headers.
  static ChatGptCodexUsage? fromHeaders(
    Map<String, List<String>> headers,
    DateTime now,
  ) {
    String? header(String name) {
      final values = headers[name] ?? headers[name.toLowerCase()];
      return values == null || values.isEmpty ? null : values.first.trim();
    }

    ChatGptCodexUsageWindow? window(String prefix) {
      final used = num.tryParse(header('x-codex-$prefix-used-percent') ?? '');
      if (used == null) return null;
      final minutes = num.tryParse(
        header('x-codex-$prefix-window-minutes') ?? '',
      );
      return ChatGptCodexUsageWindow(
        usedPercent: used.toDouble(),
        length: minutes == null ? null : Duration(minutes: minutes.round()),
        resetsAt:
            _epoch(num.tryParse(header('x-codex-$prefix-reset-at') ?? '')) ??
            _after(
              now,
              num.tryParse(
                header('x-codex-$prefix-reset-after-seconds') ?? '',
              ),
            ),
      );
    }

    final primary = window('primary');
    final secondary = window('secondary');
    if (primary == null && secondary == null) return null;
    final reachedType = header('x-codex-rate-limit-reached-type');
    return ChatGptCodexUsage(
      observedAt: now,
      primary: primary,
      secondary: secondary,
      limitReached: reachedType != null && reachedType.isNotEmpty,
    );
  }

  /// Reads the `GET /wham/usage` body.
  static ChatGptCodexUsage? fromJson(Object? raw, DateTime now) {
    if (raw is! Map) return null;
    final limits = raw['rate_limit'];
    final windows = _windows(limits, now);
    final additional = <ChatGptCodexNamedLimit>[];
    if (raw['additional_rate_limits'] case final List items) {
      for (final item in items) {
        if (item is! Map) continue;
        final name = item['limit_name'] ?? item['metered_feature'];
        final named = _windows(item['rate_limit'] ?? item, now);
        if (name is String && (named.$1 != null || named.$2 != null)) {
          additional.add(
            ChatGptCodexNamedLimit(
              name: name,
              primary: named.$1,
              secondary: named.$2,
            ),
          );
        }
      }
    }
    if (windows.$1 == null && windows.$2 == null && additional.isEmpty) {
      return null;
    }
    final plan = raw['plan_type'];
    return ChatGptCodexUsage(
      observedAt: now,
      primary: windows.$1,
      secondary: windows.$2,
      additional: additional,
      planType: plan is String && plan.isNotEmpty ? plan : null,
      limitReached: limits is Map && limits['limit_reached'] == true,
    );
  }

  static (ChatGptCodexUsageWindow?, ChatGptCodexUsageWindow?) _windows(
    Object? limits,
    DateTime now,
  ) {
    if (limits is! Map) return (null, null);
    return (
      ChatGptCodexUsageWindow.fromJson(limits['primary_window'], now),
      ChatGptCodexUsageWindow.fromJson(limits['secondary_window'], now),
    );
  }
}

class ChatGptCodexNamedLimit {
  const ChatGptCodexNamedLimit({
    required this.name,
    this.primary,
    this.secondary,
  });

  final String name;
  final ChatGptCodexUsageWindow? primary;
  final ChatGptCodexUsageWindow? secondary;
}

num? _number(Object? value) => switch (value) {
  final num number when number.isFinite => number,
  final String text => num.tryParse(text.trim()),
  _ => null,
};

/// The backend sends Unix seconds; a millisecond value is accepted too.
DateTime? _epoch(Object? value) {
  final number = _number(value);
  if (number == null || number <= 0) return null;
  final millis = number > 100000000000 ? number : number * 1000;
  return DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: true);
}

DateTime? _after(DateTime now, Object? seconds) {
  final number = _number(seconds);
  if (number == null || number < 0) return null;
  return now.add(Duration(milliseconds: (number * 1000).round()));
}
