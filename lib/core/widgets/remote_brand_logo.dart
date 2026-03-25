import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class RemoteBrandLogo extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const RemoteBrandLogo({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  bool get _isSvg {
    final normalized = imageUrl.toLowerCase().split('?').first;
    return normalized.endsWith('.svg');
  }

  @override
  Widget build(BuildContext context) {
    if (_isSvg) {
      return SvgPicture.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (_) => SizedBox(width: width, height: height),
      );
    }

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
