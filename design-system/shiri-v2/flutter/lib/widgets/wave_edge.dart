// WaveEdge：两层静态波浪，曲线取自新图标 app_icon.svg 底部波浪（按比例归一化）。
// 放在天空头部、引导页、空状态底边。不做常驻漂移动画。
import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';

class WaveEdge extends StatelessWidget {
  const WaveEdge({super.key, this.height = 72, this.dark = false});

  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: WavePainter(dark: dark),
      ),
    ),
  );
}

class WavePainter extends CustomPainter {
  const WavePainter({this.dark = false});

  final bool dark;

  // 图标坐标：x ∈ [104, 920]，y ∈ [698, 912]，归一化到 0..1。
  static const _back = [
    [0.0, 0.1495], // M104 730
    [0.1103, 0.0, 0.2316, 0.0514, 0.3529, 0.2617], // C194 698 293 709 392 754
    [0.4706, 0.4673, 0.5895, 0.5841, 0.6973, 0.5000], // C488 798 585 823 673 805
    [0.8088, 0.4112, 0.9007, 0.1776, 1.0, 0.1308], // C764 786 839 736 920 726
  ];
  static const _front = [
    [0.0, 0.4907], // M104 803
    [0.1299, 0.2150, 0.2831, 0.2523, 0.4326, 0.4766], // C210 744 335 752 457 800
    [0.5392, 0.6402, 0.6434, 0.7570, 0.7537, 0.7009], // C544 835 629 860 719 848
    [0.8615, 0.6449, 0.9412, 0.4393, 1.0, 0.3785], // C807 836 872 792 920 779
  ];

  Path _path(List<List<double>> spec, Size s) {
    final p = Path()..moveTo(spec[0][0] * s.width, spec[0][1] * s.height);
    for (final c in spec.skip(1)) {
      p.cubicTo(c[0] * s.width, c[1] * s.height, c[2] * s.width, c[3] * s.height,
          c[4] * s.width, c[5] * s.height);
    }
    return p
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    void layer(List<List<double>> spec, LinearGradient g, double opacity) {
      canvas.drawPath(
        _path(spec, size),
        Paint()
          ..shader = g.createShader(rect)
          ..color = const Color(0xFF000000).withValues(alpha: opacity),
      );
    }

    layer(
      _back,
      dark ? ShiriGradients.waveBackDark : ShiriGradients.waveBack,
      ShiriGradients.waveBackOpacity,
    );
    layer(
      _front,
      dark ? ShiriGradients.waveFrontDark : ShiriGradients.waveFront,
      ShiriGradients.waveFrontOpacity,
    );
  }

  @override
  bool shouldRepaint(covariant WavePainter old) => old.dark != dark;
}
