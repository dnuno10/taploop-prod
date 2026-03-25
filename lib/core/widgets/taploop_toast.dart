import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

enum TapLoopToastType { success, error, warning }

class TapLoopToast {
  TapLoopToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message,
    TapLoopToastType type,
  ) {
    _current?.remove();
    _current = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastEntry(
        message: message,
        type: type,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );

    _current = entry;
    Overlay.of(context).insert(entry);
  }
}

class _ToastEntry extends StatefulWidget {
  final String message;
  final TapLoopToastType type;
  final VoidCallback onDismiss;

  const _ToastEntry({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_ToastEntry> createState() => _ToastEntryState();
}

class _ToastEntryState extends State<_ToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.viewPaddingOf(context).top;
    return Positioned(
      top: topPadding + 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360, minWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon, color: AppColors.white, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.message,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.white,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _dismiss,
                  child: const Icon(
                    Icons.close,
                    color: AppColors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get _backgroundColor {
    switch (widget.type) {
      case TapLoopToastType.success:
        return AppColors.success;
      case TapLoopToastType.error:
        return AppColors.error;
      case TapLoopToastType.warning:
        return AppColors.warning;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case TapLoopToastType.success:
        return Icons.check_circle_outline;
      case TapLoopToastType.error:
        return Icons.error_outline;
      case TapLoopToastType.warning:
        return Icons.warning_amber_outlined;
    }
  }
}
