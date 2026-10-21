import 'package:flutter/material.dart';

/// Centers [child] like `Center` while it fits, and scrolls instead of
/// overflowing when it doesn't — small handhelds, landscape, large system
/// font sizes, or the keyboard being open.
class CenteredScrollView extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const CenteredScrollView({
    super.key,
    required this.child,
    this.maxWidth = 380,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
