import 'package:flutter/material.dart';

const appName = '拾日';

/// Shared export of assets/brand/app_icon.svg, also used by the launcher.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => Semantics(
    label: appName,
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: Image.asset(
        'assets/brand/brand_mark.png',
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}
