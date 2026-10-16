import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/grid_column_count.dart';

void main() {
  int resolve(double width, int preferred, {double minCellWidth = 92}) =>
      GridColumnCount.resolve(
        width: width,
        preferred: preferred,
        spacing: 8,
        minCellWidth: minCellWidth,
      );

  test('手机宽度严格使用所选列数', () {
    for (final width in [296.0, 387.0, 420.0]) {
      expect(
        [
          for (final n in [1, 2, 3]) resolve(width, n),
        ],
        [1, 2, 3],
      );
    }
  });

  test('宽面板保持同一密度，增加列数而不拉宽格子', () {
    expect(resolve(956, 1), 2);
    expect(resolve(956, 2), 4);
    expect(resolve(956, 3), 6);
    for (final n in [1, 2, 3]) {
      final columns = resolve(1600, n);
      final cell = GridColumnCount.cellWidth(
        width: 1600,
        columns: columns,
        spacing: 8,
      );
      expect(cell, lessThanOrEqualTo([480, 240, 160][n - 1]));
    }
  });

  test('大字号下格子过窄时减少列数，至少保留一列', () {
    expect(resolve(296, 3, minCellWidth: 92 * 3), 1);
    expect(resolve(387, 3, minCellWidth: 92 * 1.5), 2);
    expect(resolve(0, 2), 1);
    expect(resolve(double.infinity, 2), 1);
  });

  test('列数在 1 到 3 之间循环', () {
    expect(GridColumnCount.next(1), 2);
    expect(GridColumnCount.next(2), 3);
    expect(GridColumnCount.next(3), 1);
    expect(GridColumnCount.clamp(9), 3);
    expect(GridColumnCount.clamp(0), 1);
  });

  group('瀑布流', () {
    int masonry(double width, int preferred, {double textScale = 1}) =>
        MasonryColumnCount.resolve(
          width: width,
          preferred: preferred,
          spacing: 12,
          minCellWidth: MasonryColumnCount.minCellWidthFor(textScale),
        );

    test('手机宽度严格使用所选的 2 到 4 列', () {
      for (final width in [296.0, 366.0, 388.0, 456.0]) {
        expect(
          [
            for (final n in [2, 3, 4]) masonry(width, n),
          ],
          [2, 3, 4],
          reason: '${width}px',
        );
      }
    });

    test('宽面板保持同样的列宽，增加列数', () {
      for (final n in [2, 3, 4]) {
        final columns = masonry(1576, n);
        expect(columns, greaterThan(n));
        final cell = GridColumnCount.cellWidth(
          width: 1576,
          columns: columns,
          spacing: 12,
        );
        expect(cell, lessThanOrEqualTo(480 / n));
      }
    });

    test('大字号可以减少列数，但不少于两列', () {
      expect(masonry(296, 4, textScale: 3), 2);
      expect(masonry(296, 4, textScale: 1.5), 3);
      expect(masonry(0, 3), 2);
      expect(masonry(double.infinity, 3), 2);
    });

    test('列数在 2 到 4 之间循环', () {
      expect(MasonryColumnCount.next(2), 3);
      expect(MasonryColumnCount.next(3), 4);
      expect(MasonryColumnCount.next(4), 2);
      expect(MasonryColumnCount.clamp(1), 2);
      expect(MasonryColumnCount.clamp(9), 4);
    });
  });
}
