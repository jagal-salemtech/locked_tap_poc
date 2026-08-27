/// lib/core/action_lock/action_lock.dart
///
/// Core of the "one action at a time" pattern.
///
/// This file defines:
///   - [PageActionLock]      the state: which action (if any) is running
///   - [PageActionLockScope] makes a lock available to a widget subtree
///   - [ActionLockedPage]    convenience wrapper that creates + disposes a
///                           lock and scopes it to a page in one step
///
/// Pair this with `locked_tap.dart` ([LockedTap]) to make any clickable
/// widget — buttons, cards, list rows, icons, images — participate in the
/// same page-wide lock.
///
/// ### Why a lock instead of per-button state?
/// A `bool _isLoading` flag per button only stops that ONE button from
/// double-firing. It does nothing to stop a DIFFERENT button on the same
/// page from firing while the first request is still in flight (e.g. user
/// taps "Delete" then immediately taps "Submit" in another card). This
/// lock is shared across the whole scope, so only one action can be
/// in-flight anywhere under it at a time.
library action_lock;

import 'package:flutter/material.dart';

// -----------------------------------------------------------------------
// PageActionLock
// -----------------------------------------------------------------------

/// Tracks which single action (if any) is currently running within a
/// [PageActionLockScope].
///
/// Extends [ChangeNotifier] so it can be listened to directly, dropped into
/// `provider`/`riverpod`, or wrapped in an [InheritedNotifier] (which is
/// exactly what [PageActionLockScope] does).
///
/// Usage is almost always indirect — via [LockedButton]/[LockedTap] — but
/// you can also call [run] directly for non-widget triggers such as
/// pull-to-refresh, a keyboard shortcut, or a Bloc/Cubit event handler:
///
/// ```dart
/// final lock = PageActionLockScope.read(context);
/// await lock.run('cart.refresh', repository.refreshCart);
/// ```
class PageActionLock extends ChangeNotifier {
  String? _activeActionId;

  /// Whether ANY action is currently running under this lock.
  bool get isBusy => _activeActionId != null;

  /// The id of the action currently running, or `null` if idle.
  String? get activeActionId => _activeActionId;

  /// True if the action identified by [id] is the one currently running.
  bool isThisRunning(String id) => _activeActionId == id;

  /// True if some *other* action is running — i.e. this [id] should be
  /// disabled right now to enforce "one at a time".
  bool isBlockedByOther(String id) => isBusy && _activeActionId != id;

  /// Runs [action] under the given [actionId].
  ///
  /// - If the lock is already busy (with this id or any other), the call
  ///   is a no-op: [action] is never invoked. This is what makes rapid
  ///   double-taps and cross-widget races harmless.
  /// - While [action] runs, [isBusy] is true and [activeActionId] is
  ///   [actionId]; listeners are notified on both start and completion so
  ///   UI can rebuild (spinner / disabled state).
  /// - If [action] throws, the exception propagates to the caller so it
  ///   can be handled at the call site (e.g. show a SnackBar) — the lock
  ///   is still released via `finally`, so the app never gets stuck.
  Future<void> run(String actionId, Future<void> Function() action) async {
    if (isBusy) return;
    _activeActionId = actionId;
    notifyListeners();
    try {
      await action();
    } finally {
      _activeActionId = null;
      notifyListeners();
    }
  }

  /// Same contract as [run], but returns the action's result. Returns
  /// `null` if the call was ignored because the lock was already busy.
  Future<T?> runWithResult<T>(
    String actionId,
    Future<T> Function() action,
  ) async {
    if (isBusy) return null;
    _activeActionId = actionId;
    notifyListeners();
    try {
      return await action();
    } finally {
      _activeActionId = null;
      notifyListeners();
    }
  }
}

// -----------------------------------------------------------------------
// PageActionLockScope
// -----------------------------------------------------------------------

/// Exposes a [PageActionLock] to every widget below it in the tree via
/// [InheritedNotifier], so [LockedButton]/[LockedTap] instances don't need
/// the lock threaded through their constructors.
///
/// You rarely construct this directly — prefer [ActionLockedPage], which
/// creates and disposes the lock for you. Construct it directly only if
/// you need to control the lock's lifecycle yourself (e.g. a lock that
/// outlives a single page, or is shared app-wide).
class PageActionLockScope extends InheritedNotifier<PageActionLock> {
  const PageActionLockScope({
    super.key,
    required PageActionLock lock,
    required Widget child,
  }) : super(notifier: lock, child: child);

  /// Retrieves the nearest [PageActionLock] and subscribes the calling
  /// widget to its changes (use inside `build`).
  static PageActionLock of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<PageActionLockScope>();
    assert(
      scope != null,
      'No PageActionLockScope found in context.\n'
      'Wrap this part of the tree with ActionLockedPage(child: ...) or '
      'PageActionLockScope(lock: ..., child: ...) first.',
    );
    return scope!.notifier!;
  }

  /// Retrieves the nearest [PageActionLock] WITHOUT subscribing to
  /// rebuilds. Use this inside callbacks / event handlers (e.g.
  /// `onRefresh`, a button's `onPressed`) rather than inside `build`.
  static PageActionLock read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<PageActionLockScope>();
    assert(
      element != null,
      'No PageActionLockScope found in context.\n'
      'Wrap this part of the tree with ActionLockedPage(child: ...) or '
      'PageActionLockScope(lock: ..., child: ...) first.',
    );
    final widget = element!.widget as PageActionLockScope;
    return widget.notifier!;
  }
}

// -----------------------------------------------------------------------
// ActionLockedPage
// -----------------------------------------------------------------------

/// Convenience wrapper for the common case: "this page needs its own
/// one-action-at-a-time lock."
///
/// Creates a [PageActionLock], scopes it to [child] via
/// [PageActionLockScope], and disposes the lock when this widget is
/// removed from the tree — so you don't manage a [StatefulWidget] +
/// lock lifecycle by hand in every feature.
///
/// ### Usage
/// ```dart
/// class CheckoutPage extends StatelessWidget {
///   const CheckoutPage({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return const ActionLockedPage(
///       child: Scaffold(
///         body: _CheckoutBody(), // LockedButton/LockedTap go inside here
///       ),
///     );
///   }
/// }
/// ```
///
/// ### Scope notes
/// - **Default (shown above):** one lock per page/screen. A slow action on
///   one screen never blocks buttons on a different screen.
/// - **App-wide lock:** if you need only one mutation in flight across the
///   *entire app*, create a single [PageActionLock] above `MaterialApp`
///   and wrap the whole app in one [PageActionLockScope] instead of using
///   [ActionLockedPage] per page.
/// - **Section-scoped lock:** to limit "one at a time" to a smaller region
///   (e.g. just one card) rather than the whole page, wrap just that
///   region with its own [PageActionLockScope].
class ActionLockedPage extends StatefulWidget {
  final Widget child;

  const ActionLockedPage({super.key, required this.child});

  @override
  State<ActionLockedPage> createState() => _ActionLockedPageState();
}

class _ActionLockedPageState extends State<ActionLockedPage> {
  late final PageActionLock _lock = PageActionLock();

  @override
  void dispose() {
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageActionLockScope(lock: _lock, child: widget.child);
  }
}
