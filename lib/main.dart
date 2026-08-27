/// lib/main.dart
///
/// POC — page-wide "one action at a time" lock, demonstrated with multiple
/// buttons spread across multiple containers ("Order Actions", "Profile
/// Actions", "Payment Actions"). Every button on the page is a [LockedTap]
/// sharing one [PageActionLock] via [ActionLockedPage].
///
/// Try it: tap several buttons across different containers quickly.
/// Only the first tap runs — every other button on the page disables
/// itself (dimmed + unresponsive) until that one finishes, then the page
/// unlocks again.
///
/// Run with:
///   flutter create tap_guard_poc
///   # replace lib/main.dart with this file, and add action_lock.dart /
///   # locked_tap.dart under lib/core/action_lock/
///   flutter run

import 'package:flutter/material.dart';
import 'core/action_lock/action_lock.dart';
import 'core/action_lock/locked_tap.dart';

void main() => runApp(const PageLockPocApp());

class PageLockPocApp extends StatelessWidget {
  const PageLockPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Page Lock POC',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const DemoPage(),
    );
  }
}

/// Stand-in for a real API — logs every call it actually makes so the POC
/// can prove how many real network calls would have fired.
class FakeApi {
  static int totalCallsFired = 0;

  static Future<void> call(String label) async {
    totalCallsFired++;
    debugPrint('--> $label started (call #$totalCallsFired)');
    await Future.delayed(const Duration(milliseconds: 1400));
    debugPrint('<-- $label finished');
  }
}

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Everything below this point shares ONE PageActionLock, created and
    // disposed automatically by ActionLockedPage.
    return const ActionLockedPage(
      child: _DemoView(),
    );
  }
}

class _DemoView extends StatefulWidget {
  const _DemoView();

  @override
  State<_DemoView> createState() => _DemoViewState();
}

class _DemoViewState extends State<_DemoView> {
  void _showError(Object error, StackTrace st) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $error')),
    );
  }

  void _reset() {
    setState(() => FakeApi.totalCallsFired = 0);
  }

  @override
  Widget build(BuildContext context) {
    // Read the lock just to display a live status banner. `of()` subscribes
    // this widget to rebuilds whenever the lock changes.
    final lock = PageActionLockScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('One-Action-At-A-Time — Multi Button POC'),
        actions: [
          IconButton(onPressed: _reset, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // Live status banner — visible regardless of which container
          // triggered the lock.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            color: lock.isBusy ? Colors.orange.shade100 : Colors.green.shade50,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  lock.isBusy ? Icons.lock_clock : Icons.lock_open,
                  size: 18,
                  color: lock.isBusy ? Colors.orange.shade800 : Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lock.isBusy
                        ? 'Busy: "${lock.activeActionId}" is running — every '
                          'other button on the page is disabled.'
                        : 'Idle — any button can be tapped.',
                    style: TextStyle(
                      color: lock.isBusy ? Colors.orange.shade900 : Colors.green.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Tap several buttons across different containers quickly. '
                  'Only the first tap runs; the rest are blocked until it finishes.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                _buildContainer(
                  title: 'Container 1 — Order Actions',
                  buttons: [
                    _lockedButton(
                      id: 'order.submit',
                      label: 'Submit Order',
                      icon: Icons.check,
                    ),
                    _lockedButton(
                      id: 'order.cancel',
                      label: 'Cancel Order',
                      icon: Icons.close,
                      color: Colors.redAccent,
                    ),
                    _lockedButton(
                      id: 'order.save_draft',
                      label: 'Save Draft',
                      icon: Icons.save,
                      color: Colors.blueGrey,
                    ),
                  ],
                ),
                _buildContainer(
                  title: 'Container 2 — Profile Actions',
                  buttons: [
                    _lockedButton(
                      id: 'profile.update',
                      label: 'Update Profile',
                      icon: Icons.person,
                    ),
                    _lockedButton(
                      id: 'profile.upload_avatar',
                      label: 'Upload Avatar',
                      icon: Icons.image,
                    ),
                    _lockedButton(
                      id: 'profile.delete',
                      label: 'Delete Account',
                      icon: Icons.delete,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
                _buildContainer(
                  title: 'Container 3 — Payment Actions',
                  buttons: [
                    _lockedButton(
                      id: 'payment.pay',
                      label: 'Pay Now',
                      icon: Icons.payment,
                      color: Colors.green,
                    ),
                    _lockedButton(
                      id: 'payment.refund',
                      label: 'Refund',
                      icon: Icons.undo,
                      color: Colors.orange,
                    ),
                    _lockedButton(
                      id: 'payment.add_card',
                      label: 'Add Card',
                      icon: Icons.credit_card,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.indigo.withOpacity(0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Total real API calls fired: ${FakeApi.totalCallsFired}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds one button using LockedTap wrapping an ElevatedButton — proving
  /// LockedTap alone (no separate "LockedButton" type) is enough to cover
  /// button-shaped clickables too.
  Widget _lockedButton({
    required String id,
    required String label,
    required IconData icon,
    Color? color,
  }) {
    return LockedTap(
      id: id,
      onTap: () => FakeApi.call(label),
      onError: _showError,
      showRunningOverlay: false, // the button shows its own "Running…" state
      child: _AnimatedActionButton(id: id, label: label, icon: icon, color: color),
    );
  }

  Widget _buildContainer({required String title, required List<Widget> buttons}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: buttons),
          ],
        ),
      ),
    );
  }
}

/// Renders the button's visual state (idle / running / blocked) by reading
/// the lock directly. Kept separate from `_lockedButton` just so the POC
/// reads clearly — in your own code this can be as simple as an
/// ElevatedButton with `onPressed: null` (see LockedTap's "Using it AS a
/// button" doc example).
class _AnimatedActionButton extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final Color? color;

  const _AnimatedActionButton({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final lock = PageActionLockScope.of(context);
    final isRunning = lock.isThisRunning(id);

    return ElevatedButton.icon(
      onPressed: null, // LockedTap (the parent) drives the actual tap
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color ?? Theme.of(context).colorScheme.primary,
        disabledForegroundColor: Colors.white,
      ),
      icon: isRunning
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon, size: 18),
      label: Text(isRunning ? 'Running…' : label),
    );
  }
}
