# Action Lock

A tiny, dependency-free Flutter pattern for preventing **double taps, race
conditions, and duplicate API calls** — across an entire page, not just a
single button.

Most "prevent double tap" solutions only guard one widget at a time (a
`bool _isLoading` flag on a single button). That stops that *one* button
from firing twice, but does nothing if the user taps a **different** button
while the first request is still in flight — e.g. tapping "Delete" then
immediately "Submit" in another card. Action Lock solves that by sharing
one lock across every clickable on the page: **only one action can run at
a time, anywhere in the scope.**

---

## Contents

| File | Purpose |
|---|---|
| `lib/core/action_lock/action_lock.dart` | Core: `PageActionLock`, `PageActionLockScope`, `ActionLockedPage` |
| `lib/core/action_lock/locked_tap.dart` | `LockedTap` — generic wrapper for any clickable widget |
| `lib/main.dart` | POC app — 3 containers × 3 buttons, all sharing one lock |

---

## Installation

No external packages required — it's built entirely on Flutter SDK
primitives (`ChangeNotifier`, `InheritedNotifier`).

1. Copy `action_lock.dart` and `locked_tap.dart` into your project under
   `lib/core/action_lock/`.
2. Import them wherever you build a page:
   ```dart
   import 'core/action_lock/action_lock.dart';
   import 'core/action_lock/locked_tap.dart';
   ```

---

## Quick start

```dart
class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ActionLockedPage(
      child: Scaffold(
        body: _CheckoutBody(),
      ),
    );
  }
}
```

```dart
LockedTap(
  id: 'order.submit',                    // unique within this scope
  onTap: () => repository.submitOrder(), // your async action
  onError: (e, st) => showSnackBar(context, 'Failed: $e'),
  child: ElevatedButton.icon(
    onPressed: null,                     // LockedTap drives the tap
    icon: const Icon(Icons.check),
    label: const Text('Submit Order'),
  ),
)
```

Wrap **every** tappable action on the page this way — buttons, cards, list
rows, icons, images — and they'll all coordinate automatically: tap one,
and every other one disables (dimmed + unresponsive) until it finishes.

---

## How it works

```
ActionLockedPage
 └─ PageActionLockScope   (InheritedNotifier — holds one PageActionLock)
     └─ ... your page ...
         ├─ LockedTap(id: 'order.submit')
         ├─ LockedTap(id: 'order.cancel')
         └─ LockedTap(id: 'profile.update')
```

- **`PageActionLock`** — a `ChangeNotifier` holding a single nullable
  `activeActionId`. `run(id, action)` sets it, awaits the action, then
  clears it. If the lock is already busy, `run()` is a no-op — the action
  is never invoked, no matter how many times it's called.
- **`PageActionLockScope`** — an `InheritedNotifier` that hands the lock
  down the tree so widgets can find it via `context` instead of having it
  passed through every constructor.
- **`ActionLockedPage`** — convenience `StatefulWidget` that creates a
  `PageActionLock`, wraps `child` in a `PageActionLockScope`, and disposes
  the lock automatically. This is what you wrap a page in.
- **`LockedTap`** — the widget you actually use throughout your UI. Reads
  the nearest lock, disables itself while any *other* `LockedTap` id is
  running, and shows a spinner overlay while it is the one running.

---

## API reference

### `PageActionLock`

| Member | Description |
|---|---|
| `isBusy` | `true` if any action is currently running |
| `activeActionId` | id of the running action, or `null` |
| `isThisRunning(id)` | is `id` the one currently running? |
| `isBlockedByOther(id)` | is something *else* running (so `id` should disable)? |
| `run(id, action)` | runs `action` if idle; no-op if busy; errors propagate to caller |
| `runWithResult<T>(id, action)` | same as `run`, but returns the action's value (or `null` if ignored) |

### `PageActionLockScope`

| Member | Description |
|---|---|
| `PageActionLockScope.of(context)` | get the lock, **subscribing** to rebuilds — use in `build()` |
| `PageActionLockScope.read(context)` | get the lock **without** subscribing — use in callbacks (`onRefresh`, event handlers) |

### `ActionLockedPage`

Wraps `child` in a freshly created, auto-disposed `PageActionLock` +
`PageActionLockScope`. Use one per page/screen by default.

### `LockedTap`

| Param | Description |
|---|---|
| `id` | unique id for this tappable within its scope (**required**) |
| `child` | any widget to make tappable (**required**) |
| `onTap` | the async action to run (**required**) |
| `onError` | called if `onTap` throws; if omitted, the error rethrows |
| `blockedOpacity` | opacity applied while blocked by another action (default `0.4`) |
| `showRunningOverlay` | show a small spinner while *this* tap is running (default `true`) |
| `useRipple` | `true` → `InkWell` (material ripple); `false` → `GestureDetector` (no ripple, e.g. for images/custom content) |
| `borderRadius` | ripple clip shape, only used when `useRipple: true` |

`LockedTap` accepts **any** child — including a plain button — so it also
covers "button" use cases without needing a separate `LockedButton` type
(see the POC, which builds every button as `LockedTap` + `ElevatedButton`).

---

## Non-button triggers (pull-to-refresh, timers, Bloc/Cubit events)

Anything can participate, not just taps — grab the lock with `read()` and
call `run()` directly:

```dart
Future<void> _onRefresh(BuildContext context) async {
  final lock = PageActionLockScope.read(context);
  await lock.run('cart.refresh', repository.refreshCart);
}
```

If a button on the same page is mid-request, the refresh is silently
ignored — same "one at a time" guarantee.

---

## Choosing the lock's scope

| Scope | When to use | How |
|---|---|---|
| **Per-page** (default) | Most cases — a slow action on one screen shouldn't block another screen | Wrap each page in its own `ActionLockedPage` |
| **App-wide** | Only one mutation should ever be in flight across the whole app (e.g. never allow a payment and a profile update simultaneously) | Create one `PageActionLock` above `MaterialApp`, wrap the whole app in one `PageActionLockScope` instead of using `ActionLockedPage` per page |
| **Section-scoped** | Only a specific card/panel needs "one at a time", not the whole page | Wrap just that region in its own `PageActionLockScope` |

---

## Error handling

`LockedTap` **always releases the lock**, even if `onTap` throws (via
`finally` inside `PageActionLock.run`) — the UI can never get stuck locked.

- Pass `onError` to handle failures locally (SnackBar, dialog, retry logic).
- If you omit `onError`, the exception rethrows to the caller — pair this
  with a global error boundary / zone handler if that's your app's
  convention.

---

## Running the POC

The POC (`lib/main.dart`) renders 3 containers — **Order Actions**,
**Profile Actions**, **Payment Actions** — each with 3 buttons, all
sharing one page-wide lock, plus a live status banner and a counter of how
many real ("API") calls actually fired.

```
flutter create tap_guard_poc
cd tap_guard_poc
mkdir -p lib/core/action_lock
# copy action_lock.dart and locked_tap.dart into lib/core/action_lock/
# replace lib/main.dart with the POC main.dart
flutter run
```

**Try it:** rapid-tap several buttons across different containers. Only
the first tap's action runs (simulated 1.4s "API call") — every other
button, in every container, disables and dims until it finishes, then the
page unlocks and any button becomes tappable again.

---

## Design notes / things to decide before rolling this out broadly

- **Unique ids** — `id` only needs to be unique *within a scope*, but using
  a consistent convention (`feature.action`, e.g. `order.submit`,
  `profile.delete`) avoids collisions as the app grows.
- **Error handling convention** — decide whether `LockedTap.onError` should
  be required at every call site, or whether you'll rely on a global error
  handler for the rethrow case.
- **State management integration** — `PageActionLock` is a plain
  `ChangeNotifier`; it composes fine with `provider`, `riverpod`, or a
  Bloc/Cubit that exposes `isBlockedByOther` through its own state class if
  you'd rather not touch `context` directly from business logic.
