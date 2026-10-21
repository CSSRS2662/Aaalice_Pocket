import 'package:flutter/foundation.dart';

/// One field a tool call waiting for approval would change; the card shows
/// [before] and [after] as a diff.
@immutable
class AgentApprovalChange {
  const AgentApprovalChange({
    required this.field,
    required this.before,
    required this.after,
  });

  /// Stable field key such as `content` or `strength`, localized by the card.
  final String field;
  final String before;
  final String after;

  /// The fields whose requested value differs from the current one; a null
  /// request leaves the field as it is.
  static List<AgentApprovalChange> between(
    Map<String, (String current, String? requested)> fields,
  ) => [
    for (final MapEntry(key: field, value: (current, requested))
        in fields.entries)
      if (requested != null && requested != current)
        AgentApprovalChange(field: field, before: current, after: requested),
  ];

  /// A number as the card shows it: no trailing zeros.
  static String number(num? value) {
    if (value == null) return '';
    final text = value.toStringAsFixed(2);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentApprovalChange &&
      other.field == field &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(field, before, after);
}

/// What a confirmed call would change, read before it runs.
typedef AgentApprovalChangePreview =
    Future<List<AgentApprovalChange>> Function(Map<String, dynamic> params);
