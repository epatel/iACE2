import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'manual_annotations.dart';
import 'manual_controller.dart';
import 'manual_page.dart';

/// The Jupiter ACE user manual: swipe between pages, jump with the slider,
/// tap annotations to type examples, follow links and open web pages.
class ManualView extends StatefulWidget {
  const ManualView({
    super.key,
    required this.controller,
    required this.annotations,
    required this.onAction,
    this.asset = 'assets/manual.pdf',
  });

  final ManualController controller;
  final ManualAnnotations annotations;

  /// Called for type and open actions; goto is handled here.
  final ValueChanged<ManualAction> onAction;
  final String asset;

  @override
  State<ManualView> createState() => _ManualViewState();
}

class _ManualViewState extends State<ManualView> {
  late final PageController _pages = PageController(
    initialPage: widget.controller.page - 1,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncPage);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPage);
    _pages.dispose();
    super.dispose();
  }

  /// Follows the controller when something other than a swipe changed the page.
  void _syncPage() {
    if (!_pages.hasClients) return;
    final shown = (_pages.page ?? _pages.initialPage.toDouble()).round() + 1;
    if (shown != widget.controller.page) {
      _pages.jumpToPage(widget.controller.page - 1);
    }
  }

  void _onAction(ManualAction action) => switch (action) {
    GotoAction(:final page) => widget.controller.goTo(page),
    _ => widget.onAction(action),
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: PdfDocumentViewBuilder.asset(
        widget.asset,
        builder: (context, document) {
          if (document == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final count = document.pages.length;
          if (widget.controller.pageCount != count) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => widget.controller.pageCount = count,
            );
          }
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: count,
                  onPageChanged: (index) => widget.controller.goTo(index + 1),
                  itemBuilder: (context, index) => ManualPage(
                    pageSize: widget.annotations.pageSize,
                    annotations: widget.annotations.onPage(index + 1),
                    content: PdfPageView(
                      document: document,
                      pageNumber: index + 1,
                    ),
                    onAction: _onAction,
                  ),
                ),
              ),
              _PageSlider(controller: widget.controller),
            ],
          );
        },
      ),
    );
  }
}

class _PageSlider extends StatelessWidget {
  const _PageSlider({required this.controller});

  final ManualController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = controller.pageCount;
        if (count < 2) return const SizedBox(height: 48);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('manual-slider'),
                  min: 1,
                  max: count.toDouble(),
                  divisions: count - 1,
                  value: controller.page.toDouble(),
                  label: '${controller.page}',
                  onChanged: (v) => controller.goTo(v.round()),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '${controller.page} / $count',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
