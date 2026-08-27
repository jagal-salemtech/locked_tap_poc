/// lib/core/action_lock/locked_tap.dart
///
/// [LockedTap] — makes ANY widget (a button, a `Card`, a `ListTile` row, a
/// bare `Icon`, an image thumbnail, a custom-painted shape...) participate
/// in the page-wide "one action at a time" lock defined in `action_lock.dart`.
///
/// Requires a [PageActionLockScope] above it in the tree — normally
/// provided by wrapping the page in `ActionLockedPage` (see action_lock.dart).
library locked_tap;

import 'package:flutter/material.dart';
import 'action_lock.dart' show PageActionLock, PageActionLockScope;

/// Wraps [child] in a tap handler that:
///  1. Is disabled (and visually dimmed) while ANY OTHER [LockedTap] /
///     locked action under the same [PageActionLockScope] is running.
///  2. While its OWN [onTap] is running, ignores further taps on itself
///     and (optionally) shows a small spinner overlay.
///  3. Once [onTap] completes (or throws), the lock is released and every
///     other locked widget on the page re-enables automatically.
///
/// Every [LockedTap] (and `LockedButton`, if you're using both) needs a
/// unique [id] within its scope — it's how the widget tells "am I the one
/// running?" apart from "is something else blocking me?".
///
/// ### Basic usage — wrapping a whole Card
/// ```dart
/// LockedTap(
///   id: 'order.open.1001',
///   onTap: () => repository.openOrder('1001'),
///   borderRadius: BorderRadius.circular(12),
///   child: Card(
///     child: ListTile(title: Text('Order #1001')),
///   ),
/// )
/// ```
///
/// ### Wrapping non-ripple content (e.g. an image)
/// ```dart
/// LockedTap(
///   id: 'order.reorder.1003',
///   onTap: () => repository.reorder('1003'),
///   useRipple: false, // no material splash — content provides its own feel
///   child: Image.network(thumbnailUrl),
/// )
/// ```
///
/// ### Using it AS a button
/// Since [LockedTap] accepts any child, it can wrap a plain button too —
/// useful if you want to avoid a separate `LockedButton` type entirely and
/// keep one mental model for "anything clickable":
/// ```dart
/// LockedTap(
///   id: 'order.submit',
///   onTap: () => repository.submitOrder(),
///   child: ElevatedButton.icon(
///     onPressed: null, // LockedTap drives the tap; button just renders
///     icon: const Icon(Icons.check),
///     label: const Text('Submit'),
///   ),
/// )
/// ```
class LockedTap extends StatelessWidget {
  /// Unique id for this tappable within the nearest [PageActionLockScope].
  final String id;

  /// The content to make tappable — any widget.
  final Widget child;

  /// The (usually async) action to run when tapped and the lock is free.
  final Future<void> Function() onTap;

  /// Called if [onTap] throws. If omitted, the error is rethrown to
  /// whatever calls this widget's internal handler (i.e. it surfaces as an
  /// unhandled async error) — supply this in real features to show a
  /// SnackBar/dialog instead.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Opacity applied to [child] while blocked by another running action.
  /// `1.0` disables the dimming effect entirely.
  final double blockedOpacity;

  /// Whether to overlay a small [CircularProgressIndicator] on top of
  /// [child] while THIS tap's own action is running.
  final bool showRunningOverlay;

  /// `true` (default): wrap in [InkWell] for a material ripple — good for
  /// Cards, rows, containers acting as buttons.
  /// `false`: wrap in [GestureDetector] instead — good for images, custom
  /// shapes, or content that already renders its own pressed/feedback state.
  final bool useRipple;

  /// Ripple clip shape when [useRipple] is true. Ignored otherwise.
  final BorderRadius? borderRadius;

  const LockedTap({
    super.key,
    required this.id,
    required this.child,
    required this.onTap,
    this.onError,
    this.blockedOpacity = 0.4,
    this.showRunningOverlay = true,
    this.useRipple = true,
    this.borderRadius,
  });

  Future<void> _handleTap(PageActionLock lock) async {
    try {
      await lock.run(id, onTap);
    } catch (e, st) {
      if (onError != null) {
        onError!(e, st);
      } else {
        rethrow;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = PageActionLockScope.of(context);

    return AnimatedBuilder(
      animation: lock,
      builder: (context, _) {
        final isRunning = lock.isThisRunning(id);
        final isBlocked = lock.isBlockedByOther(id);
        final tapHandler = isBlocked ? null : () => _handleTap(lock);

        final content = AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isBlocked ? blockedOpacity : 1.0,
          child: IgnorePointer(
            // Prevents a fast repeat tap on THIS SAME widget while its own
            // action is still running (belt-and-braces on top of the lock).
            ignoring: isRunning,
            child: child,
          ),
        );

        final tappable = useRipple
            ? InkWell(
                borderRadius: borderRadius,
                onTap: tapHandler,
                child: content,
              )
            : GestureDetector(
                onTap: tapHandler,
                behavior: HitTestBehavior.opaque,
                child: content,
              );

        if (!showRunningOverlay || !isRunning) return tappable;

        return Stack(
          alignment: Alignment.center,
          children: [
            tappable,
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        );
      },
    );
  }
}
