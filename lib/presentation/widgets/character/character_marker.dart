import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/character/character_prompt.dart';

/// Fill, symbol colour and gender of one character's marker.
typedef CharacterMarkerColors = ({
  CharacterGender gender,
  Color fill,
  Color ink,
});

/// Character colours: the gender picks the colour family and the order among
/// characters of that gender picks the shade, so two girls never share a
/// colour while both still read as girls.
abstract final class CharacterMarkerPalette {
  static const int shadeCount = 6;

  /// Symbol colour on the light shades.
  static const Color darkInk = Color(0xFF1B1B1F);

  static const Map<CharacterGender, List<Color>> _families = {
    CharacterGender.female: [
      Color(0xFFE0457B),
      Color(0xFFF07A3A),
      Color(0xFFA8235A),
      Color(0xFFF6A5C0),
      Color(0xFFC2412D),
      Color(0xFFF8BE95),
    ],
    CharacterGender.male: [
      Color(0xFF2F6FE0),
      Color(0xFF0E9BC2),
      Color(0xFF273C93),
      Color(0xFF9CC7F5),
      Color(0xFF3E5C76),
      Color(0xFF9EDCEB),
    ],
    CharacterGender.other: [
      Color(0xFF8B5CF6),
      Color(0xFFBE4FD6),
      Color(0xFF5A2CB0),
      Color(0xFFCDB8FB),
      Color(0xFF9E5C8F),
      Color(0xFFE6B5F2),
    ],
  };

  static Color shade(CharacterGender gender, int index) =>
      _families[gender]![index % shadeCount];

  static Color base(CharacterGender gender) => shade(gender, 0);

  static Color inkFor(int index) => switch (index % shadeCount) {
    3 || 5 => darkInk,
    _ => Colors.white,
  };

  /// Shade index of [character] among the characters of its gender, in list
  /// order. Genders follow the prompt's first tag like the rest of the UI.
  static int shadeIndex(
    List<CharacterPrompt> characters,
    CharacterPrompt character,
  ) {
    final gender = character.effectiveGender;
    var index = 0;
    for (final item in characters) {
      if (item.id == character.id) break;
      if (item.effectiveGender == gender) index++;
    }
    return index % shadeCount;
  }

  static CharacterMarkerColors of(
    List<CharacterPrompt> characters,
    CharacterPrompt character,
  ) {
    final index = shadeIndex(characters, character);
    final gender = character.effectiveGender;
    return (gender: gender, fill: shade(gender, index), ink: inkFor(index));
  }

  static CharacterMarkerColors forGender(CharacterGender gender) =>
      (gender: gender, fill: base(gender), ink: inkFor(0));
}

/// Rounded gender symbol: a ring with a cross for female, an arrow for male
/// and both plus a second arrow for other.
///
/// The symbol is drawn in a 24-unit box and its ink bounds, round caps
/// included, are centred on the canvas, so it sits exactly in the middle of
/// its disc whichever way its arms point.
class CharacterGenderGlyph extends StatelessWidget {
  const CharacterGenderGlyph({
    super.key,
    required this.gender,
    required this.color,
    required this.size,
  });

  final CharacterGender gender;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: CharacterGenderGlyphPainter(gender: gender, color: color),
      ),
    );
  }
}

class CharacterGenderGlyphPainter extends CustomPainter {
  const CharacterGenderGlyphPainter({
    required this.gender,
    required this.color,
  });

  final CharacterGender gender;
  final Color color;

  static const double unit = 24;

  static double strokeWidth(CharacterGender gender) =>
      gender == CharacterGender.other ? 2.3 : 2.8;

  static Path path(CharacterGender gender) {
    Path ring(double x, double y, double radius) =>
        Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));
    switch (gender) {
      case CharacterGender.female:
        return ring(12, 9, 4.6)
          ..moveTo(12, 13.6)
          ..lineTo(12, 19.6)
          ..moveTo(9.2, 16.8)
          ..lineTo(14.8, 16.8);
      case CharacterGender.male:
        const centre = Offset(10.3, 13.7);
        final edge = centre + const Offset(1, -1) * (4.6 / math.sqrt2);
        return ring(centre.dx, centre.dy, 4.6)
          ..moveTo(edge.dx, edge.dy)
          ..lineTo(18.3, 5.7)
          ..moveTo(14.6, 5.7)
          ..lineTo(18.3, 5.7)
          ..lineTo(18.3, 9.4);
      case CharacterGender.other:
        const centre = Offset(12, 11);
        const reach = 3.6 / math.sqrt2;
        return ring(centre.dx, centre.dy, 3.6)
          ..moveTo(12, 14.6)
          ..lineTo(12, 19)
          ..moveTo(10, 17.2)
          ..lineTo(14, 17.2)
          ..moveTo(centre.dx + reach, centre.dy - reach)
          ..lineTo(18, 5)
          ..moveTo(15.4, 5)
          ..lineTo(18, 5)
          ..lineTo(18, 7.6)
          ..moveTo(centre.dx - reach, centre.dy - reach)
          ..lineTo(6, 5)
          ..moveTo(8.6, 5)
          ..lineTo(6, 5)
          ..lineTo(6, 7.6);
    }
  }

  /// Extent of the painted symbol in [unit] space, stroke caps included.
  static Rect inkBounds(CharacterGender gender) =>
      path(gender).getBounds().inflate(strokeWidth(gender) / 2);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = inkBounds(gender);
    final scale = math.min(size.width, size.height) / unit;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy)
      ..drawPath(
        path(gender),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth(gender)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(CharacterGenderGlyphPainter oldDelegate) =>
      oldDelegate.gender != gender || oldDelegate.color != color;
}

/// A character's coloured disc with its gender symbol in the middle.
///
/// [ringWidth] draws a white ring for markers placed over images; [outlined]
/// shows a character that is left out of the generation.
class CharacterMarkerDisc extends StatelessWidget {
  const CharacterMarkerDisc({
    super.key,
    required this.colors,
    required this.diameter,
    this.ringWidth = 0,
    this.outlined = false,
    this.elevated = false,
  });

  /// Symbol size relative to the space inside the ring.
  static const double glyphRatio = 0.62;

  final CharacterMarkerColors colors;
  final double diameter;
  final double ringWidth;
  final bool outlined;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final border = ringWidth > 0 ? ringWidth : (outlined ? 2.0 : 0.0);
    final inner = diameter - border * 2;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: outlined ? Colors.transparent : colors.fill,
        border: border == 0
            ? null
            : Border.all(
                color: ringWidth > 0 ? Colors.white : colors.fill,
                width: border,
              ),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x47000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: CharacterGenderGlyph(
        gender: colors.gender,
        color: outlined ? colors.fill : colors.ink,
        size: inner * glyphRatio,
      ),
    );
  }
}

/// A small frame in the generation's aspect ratio with the character's spot.
///
/// The dot is inset by its radius plus a gap, so it stays inside the frame
/// even for a character at the very edge.
class CharacterPositionMiniMap extends StatelessWidget {
  const CharacterPositionMiniMap({
    super.key,
    required this.aspectRatio,
    required this.extent,
    this.position,
    this.color,
    this.dotDiameter = 8,
  });

  final double aspectRatio;

  /// Length of the frame's longer side.
  final double extent;

  /// Column and row in 0–1; null leaves the frame empty.
  final Offset? position;
  final Color? color;
  final double dotDiameter;

  static Size frameSize(double aspectRatio, double extent) => aspectRatio >= 1
      ? Size(extent, extent / aspectRatio)
      : Size(extent * aspectRatio, extent);

  static Offset dotCenter(Size frame, Offset position, double dotDiameter) {
    final inset = dotDiameter / 2 + 2;
    return Offset(
      inset + (frame.width - inset * 2) * position.dx.clamp(0.0, 1.0),
      inset + (frame.height - inset * 2) * position.dy.clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final frame = frameSize(aspectRatio, extent);
    return CustomPaint(
      size: frame,
      painter: _MiniMapPainter(
        surface: colors.surface,
        outline: colors.outlineVariant,
        position: position,
        dotColor: color ?? colors.primary,
        dotDiameter: dotDiameter,
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter({
    required this.surface,
    required this.outline,
    required this.position,
    required this.dotColor,
    required this.dotDiameter,
  });

  final Color surface;
  final Color outline;
  final Offset? position;
  final Color dotColor;
  final double dotDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas
      ..drawRRect(frame, Paint()..color = surface)
      ..drawRRect(
        frame.deflate(0.5),
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    final spot = position;
    if (spot == null) return;
    canvas.drawCircle(
      CharacterPositionMiniMap.dotCenter(size, spot, dotDiameter),
      dotDiameter / 2,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(_MiniMapPainter oldDelegate) =>
      oldDelegate.surface != surface ||
      oldDelegate.outline != outline ||
      oldDelegate.position != position ||
      oldDelegate.dotColor != dotColor ||
      oldDelegate.dotDiameter != dotDiameter;
}
