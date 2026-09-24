import 'dart:async';

import 'package:flutter/foundation.dart';

/// Which manual page is shown. Pages are PDF page numbers, 1-based.
///
/// [onPageSettled] is called when the page has not changed for
/// [settleDelay], so it can be saved without writing on every swipe.
class ManualController extends ChangeNotifier {
  ManualController({
    int initialPage = 1,
    this.onPageSettled,
    this.settleDelay = const Duration(seconds: 2),
  }) : _page = initialPage < 1 ? 1 : initialPage;

  final void Function(int page)? onPageSettled;
  final Duration settleDelay;

  int _page;
  int _pageCount = 0;
  Timer? _settle;

  int get page => _page;

  /// 0 until the document has loaded.
  int get pageCount => _pageCount;

  set pageCount(int count) {
    if (count == _pageCount) return;
    _pageCount = count;
    if (_page > count && count > 0) _page = count;
    notifyListeners();
  }

  void goTo(int page) {
    final clamped = _pageCount > 0 ? page.clamp(1, _pageCount) : page;
    if (clamped == _page || clamped < 1) return;
    _page = clamped;
    notifyListeners();
    _settle?.cancel();
    if (onPageSettled != null) {
      _settle = Timer(settleDelay, () => onPageSettled!(_page));
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }
}
