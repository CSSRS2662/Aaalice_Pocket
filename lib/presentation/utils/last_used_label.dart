import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/utils/localization_extension.dart';

/// When something was last used, in words: 今天, 昨天, n 天前, then the date.
String lastUsedLabel(BuildContext context, DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return context.l10n.common_today;
  if (days == 1) return context.l10n.common_yesterday;
  if (days < 7) return context.l10n.common_daysAgo(days);
  final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag();
  return DateFormat.MMMd(locale).format(date);
}
