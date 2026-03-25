import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/widgets/remote_brand_logo.dart';

class QrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color foregroundColor;
  final Color backgroundColor;
  final bool showLogo;
  final String? embeddedLogoUrl;

  const QrCodeWidget({
    super.key,
    required this.data,
    this.size = 200,
    this.foregroundColor = AppColors.black,
    this.backgroundColor = AppColors.white,
    this.showLogo = true,
    this.embeddedLogoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBackground = backgroundColor == AppColors.white
        ? context.bgCard
        : backgroundColor;
    final logoUrl = embeddedLogoUrl?.trim();
    final hasLogo = showLogo && logoUrl != null && logoUrl.isNotEmpty;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: effectiveBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: data,
            version: QrVersions.auto,
            size: size - 24,
            gapless: true,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: foregroundColor,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: foregroundColor,
            ),
          ),
          if (hasLogo)
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: effectiveBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.borderColor.withValues(alpha: 0.9),
                ),
              ),
              child: RemoteBrandLogo(imageUrl: logoUrl, fit: BoxFit.contain),
            ),
        ],
      ),
    );
  }
}
