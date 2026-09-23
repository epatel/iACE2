import 'package:flutter/material.dart';

/// Lays the app out in portrait proportions. When the window is wider than
/// that (a landscape tablet on Android 16, a resized iPad window), the
/// portrait layout is centred with black bars at the sides.
class PortraitFrame extends StatelessWidget {
  const PortraitFrame({super.key, required this.child});

  /// Width / height of the portrait layout (an iPad in portrait is 3:4).
  static const aspectRatio = 3 / 4;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxHeight * aspectRatio;
          if (constraints.maxWidth <= maxWidth) return child;
          return Center(
            child: SizedBox(width: maxWidth, child: child),
          );
        },
      ),
    );
  }
}
