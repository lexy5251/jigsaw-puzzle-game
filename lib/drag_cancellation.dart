import 'package:flame/events.dart';

/// Flame routes onDragCancel through onDragEnd, so a system touch cancel
/// (e.g. palm rejection near the screen's bottom edge) arrives as a normal
/// drop. The flag lets that synthetic drop be told apart from a deliberate
/// release — a cancelled drop must not return a piece to the tray.
mixin CancelAwareDrag on DragCallbacks {
  bool _dragCancelled = false;

  /// True only while the synthetic onDragEnd from a cancel is running.
  bool get dragWasCancelled => _dragCancelled;

  @override
  void onDragCancel(DragCancelEvent event) {
    _dragCancelled = true;
    super.onDragCancel(event);
    _dragCancelled = false;
  }
}
