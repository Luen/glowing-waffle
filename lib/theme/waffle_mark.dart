import 'package:flutter/material.dart';

import 'brand_theme.dart';

/// Heights of the lit columns in the 5×5 waffle, centred vertically so they
/// read as a voice waveform. Mirrors `MARK_HEIGHTS` in
/// scripts/branding/export.mjs, which draws the app icons.
const List<int> kWaffleMarkHeights = [3, 5, 3, 1, 3];

const int _rows = 5;
const double _cell = 100;
const double _gap = 26;
const double _cellRadius = 22;
const double _markSize = 5 * _cell + 4 * _gap; // 604, as in export.mjs

/// The share of the icon tile the mark fills (604 of 1024).
const double _markInTile = _markSize / 1024;

/// The Waffle mark: the app icon drawn as vectors, so it needs no asset and
/// stays sharp at any size.
///
/// Decorative: it is excluded from semantics, so place it next to text that
/// names the app.
class WaffleMark extends StatelessWidget {
  const WaffleMark({super.key, this.size = 32, this.tile = true});

  /// Width and height in logical pixels.
  final double size;

  /// Draws the night tile behind the grid, as on the app icon. Without it the
  /// grid is drawn alone, filling [size].
  final bool tile;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _WaffleMarkPainter(tile: tile)),
      ),
    );
  }
}

class _WaffleMarkPainter extends CustomPainter {
  const _WaffleMarkPainter({required this.tile});

  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    var markSide = side;
    if (tile) {
      final rect = Offset.zero & Size.square(side);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.225)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BrandColors.nightRaised, BrandColors.nightDeep],
          ).createShader(rect),
      );
      markSide = side * _markInTile;
    }

    final scale = markSide / _markSize;
    canvas.save();
    canvas.translate((side - markSide) / 2, (side - markSide) / 2);
    canvas.scale(scale);

    final cellPaint = Paint()..color = BrandColors.grid;
    final bars = <RRect>[];
    for (var col = 0; col < kWaffleMarkHeights.length; col++) {
      final height = kWaffleMarkHeights[col];
      final top = ((_rows - height) / 2).round();
      final x = col * (_cell + _gap);
      for (var row = 0; row < _rows; row++) {
        if (row >= top && row < top + height) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, row * (_cell + _gap), _cell, _cell),
            const Radius.circular(_cellRadius),
          ),
          cellPaint,
        );
      }
      bars.add(RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          top * (_cell + _gap),
          _cell,
          height * _cell + (height - 1) * _gap,
        ),
        const Radius.circular(_cell / 2),
      ));
    }

    // One gradient across the whole mark, so short bars take the middle tone.
    final glow = Paint()
      ..color = BrandColors.honey.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);
    final honey = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [BrandColors.honeyLight, BrandColors.honeyDeep],
      ).createShader(const Rect.fromLTWH(0, 0, _markSize, _markSize));
    for (final bar in bars) {
      canvas.drawRRect(bar, glow);
    }
    for (final bar in bars) {
      canvas.drawRRect(bar, honey);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaffleMarkPainter oldDelegate) =>
      oldDelegate.tile != tile;
}
