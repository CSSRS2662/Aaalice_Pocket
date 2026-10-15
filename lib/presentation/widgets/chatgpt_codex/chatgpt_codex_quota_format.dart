import 'package:flutter/material.dart';

import '../../../data/services/chatgpt_codex/chatgpt_codex_usage.dart';
import '../../../l10n/app_localizations.dart';

const _week = Duration(days: 7);

/// Compact window label for the header pill: `5h`, `7d`.
String chatGptCodexWindowShortLabel(Duration? length) {
  if (length == null) return '';
  if (length.inHours < 24 || length.inMinutes % Duration.minutesPerDay != 0) {
    return '${(length.inMinutes / 60).round()}h';
  }
  return '${length.inDays}d';
}

/// Window name for the details: by length, since plans differ.
String chatGptCodexWindowName(
  AppLocalizations l10n,
  Duration? length, {
  required bool primary,
}) {
  if (length == null) {
    return primary
        ? l10n.chatgptCodex_windowShortTerm
        : l10n.chatgptCodex_windowLongTerm;
  }
  if (length == _week) return l10n.chatgptCodex_windowWeekly;
  if (length.inHours < 24 || length.inMinutes % Duration.minutesPerDay != 0) {
    return l10n.chatgptCodex_windowHours((length.inMinutes / 60).round());
  }
  return l10n.chatgptCodex_windowDays(length.inDays);
}

/// Remaining percent as shown everywhere: whole numbers, never negative.
String chatGptCodexPercentText(ChatGptCodexUsageWindow window) =>
    '${window.remainingPercent.floor()}%';

/// When [resetsAt] falls, in the device time zone, plus how long until then.
String chatGptCodexResetText(
  AppLocalizations l10n,
  DateTime resetsAt,
  DateTime now,
) {
  final local = resetsAt.toLocal();
  final today = DateUtils.dateOnly(now.toLocal());
  final days = DateUtils.dateOnly(local).difference(today).inDays;
  final when = switch (days) {
    0 => l10n.chatgptCodex_resetToday(local),
    1 => l10n.chatgptCodex_resetTomorrow(local),
    _ => l10n.chatgptCodex_resetOn(local, local),
  };
  var left = local.difference(now.toLocal());
  if (left.isNegative) left = Duration.zero;
  final duration = left.inDays > 0
      ? l10n.chatgptCodex_durationDaysHours(left.inDays, left.inHours % 24)
      : left.inHours > 0
      ? l10n.chatgptCodex_durationHoursMinutes(
          left.inHours,
          left.inMinutes % 60,
        )
      : l10n.chatgptCodex_durationMinutes(left.inMinutes < 1 ? 1 : left.inMinutes);
  return l10n.chatgptCodex_resetWithRemaining(when, duration);
}
