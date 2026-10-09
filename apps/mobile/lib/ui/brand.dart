import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const appName = '拾日';

/// Interface SVG mark. The launcher is generated from app_icon.svg separately.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => Semantics(
    label: appName,
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        'assets/brand/mark.svg',
        excludeFromSemantics: true,
      ),
    ),
  );
}
