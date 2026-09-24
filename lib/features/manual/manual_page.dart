import 'package:flutter/material.dart';

import 'manual_annotations.dart';

/// One manual page with its tappable annotations on top.
///
/// [content] is the rendered page; it is laid out at the page's aspect ratio
/// so annotation rectangles (in PDF points) can be scaled onto it.
class ManualPage extends StatelessWidget {
  const ManualPage({
    super.key,
    required this.pageSize,
    required this.annotations,
    required this.content,
    required this.onAction,
  });

  final Size pageSize;
  final List<ManualAnnotation> annotations;
  final Widget content;
  final ValueChanged<ManualAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: pageSize.width / pageSize.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / pageSize.width;
            return Stack(
              fit: StackFit.expand,
              children: [
                content,
                for (final (i, a) in annotations.indexed)
                  Positioned(
                    left: a.rect.left * scale,
                    top: a.rect.top * scale,
                    width: a.rect.width * scale,
                    height: a.rect.height * scale,
                    child: _AnnotationButton(
                      key: ValueKey('annotation-${a.page}-$i'),
                      annotation: a,
                      scale: scale,
                      onTap: () => onAction(a.action),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AnnotationButton extends StatelessWidget {
  const _AnnotationButton({
    super.key,
    required this.annotation,
    required this.scale,
    required this.onTap,
  });

  final ManualAnnotation annotation;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final action = annotation.action;
    return Semantics(
      button: true,
      label: switch (action) {
        TypeAction(:final text) => 'Type into the ACE: ${text.trim()}',
        GotoAction(:final page) => 'Go to page $page',
        OpenUrlAction(:final url) => 'Open $url',
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // As in iACE 1.x: "type" examples get a visible Enter button in the
        // margin; links are invisible areas over the printed text.
        child: action is TypeAction
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: scale),
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Center(
                  child: Text(
                    'Enter',
                    style: TextStyle(color: Colors.black, fontSize: 14 * scale),
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
