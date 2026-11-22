import 'package:flutter/material.dart';

import '../../backend/models/onboarding_data.dart';
import '../../backend/models/reminder.dart';
import '../../backend/services/reminder_scheduler.dart';
import '../../backend/services/reminder_service.dart';
import '../../backend/services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Settings for reminders: all on or off, the priority ranking they follow,
/// and each kind on its own.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    this.profile,
    this.requestPermission = ReminderService.requestPermission,
    this.sendTest = ReminderService.showTest,
    this.onSetEnabled = ReminderSettingsService.setEnabled,
    this.onSetKind = ReminderSettingsService.setKind,
    this.onSetPriorities = ReminderSettingsService.setPriorities,
    super.key,
  });

  /// Replaces the live profile. Used by tests.
  final Stream<Map<String, dynamic>?>? profile;

  final Future<bool> Function() requestPermission;
  final Future<bool> Function() sendTest;
  final void Function(bool enabled) onSetEnabled;
  final void Function(ReminderKind kind, bool? on) onSetKind;
  final void Function(List<FinancialPriority> priorities) onSetPriorities;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late final Stream<Map<String, dynamic>?> _profile =
      widget.profile ??
      UserProfileService.watchProfile().map((snapshot) => snapshot.data());

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setEnabled(bool enabled) async {
    if (enabled && !await widget.requestPermission()) {
      if (mounted) {
        _tell(
          'Notifications are blocked for FinAssist. Allow them in your '
          "phone's Settings, then turn reminders on here.",
        );
      }
      return;
    }
    widget.onSetEnabled(enabled);
  }

  Future<void> _sendTest() async {
    final shown = await widget.sendTest();
    if (!mounted) return;
    _tell(
      shown
          ? 'A test reminder arrives in about 10 seconds. You can leave the '
                'app.'
          : "Notifications are blocked for FinAssist in your phone's Settings.",
    );
  }

  void _move(List<FinancialPriority> priorities, int from, int to) {
    final ordered = [...priorities];
    ordered.insert(to, ordered.removeAt(from));
    widget.onSetPriorities(ordered);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Reminders',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final settings = ReminderSettings.fromProfile(snapshot.data);
          final on = settings.enabled;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // The phone's side of it together: on or off, and a test that
              // shows notifications really arrive.
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      value: on,
                      onChanged: _setEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Allow reminders',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Works offline. Nothing leaves your phone.',
                      ),
                    ),
                    // A solid blue button, so it reads as something to tap.
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _sendTest,
                          style: openButtonStyle(height: 46),
                          icon: const Icon(
                            Icons.notifications_active_outlined,
                            size: 20,
                          ),
                          label: const Text(
                            'Send a test reminder',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _Heading(
                'What matters most to you?',
                'Higher on the list gets more reminders.',
              ),
              _Card(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < settings.priorities.length; i++)
                      _PriorityRow(
                        rank: i + 1,
                        priority: settings.priorities[i],
                        onUp: i == 0
                            ? null
                            : () => _move(settings.priorities, i, i - 1),
                        onDown: i == settings.priorities.length - 1
                            ? null
                            : () => _move(settings.priorities, i, i + 1),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _Heading('When they come', null),
              // One card, as in Settings, so four reminders read as one list.
              Opacity(
                opacity: on ? 1 : 0.5,
                child: _Card(
                  child: Column(
                    children: [
                      for (final (index, kind)
                          in ReminderKind.values.indexed) ...[
                        if (index > 0) Divider(height: 1, color: colors.border),
                        _KindRow(
                          kind: kind,
                          settings: settings,
                          enabled: on,
                          // Every reminder starts on, so turning one back on
                          // just clears the choice and it follows the
                          // ranking again.
                          onChanged: (value) =>
                              widget.onSetKind(kind, value ? null : false),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Material rather than a decorated box, so switch rows show their tap
    // ripple on the card.
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.rank,
    required this.priority,
    required this.onUp,
    required this.onDown,
  });

  final int rank;
  final FinancialPriority priority;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          // The rank in a round badge, so the order reads at a glance.
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colors.primaryText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  priority.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  reminderCountText(rank),
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Move "${priority.label}" up',
            onPressed: onUp,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: 'Move "${priority.label}" down',
            onPressed: onDown,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.settings,
    required this.enabled,
    required this.onChanged,
  });

  final ReminderKind kind;
  final ReminderSettings settings;

  /// False while reminders as a whole are off.
  final bool enabled;
  final ValueChanged<bool> onChanged;

  static String titleOf(ReminderKind kind) => switch (kind) {
    ReminderKind.bills => 'Bills due',
    ReminderKind.goals => 'Saving plans',
    ReminderKind.dailyLog => 'Log your spending',
    ReminderKind.interest => 'Interest paid',
  };

  /// Why it gets what it gets, in a few words: its place in the ranking
  /// above, or that interest follows no ranking.
  String get _badge {
    if (!settings.isOn(kind)) return 'Off';
    final priority = ReminderSettings.priorityFor(kind);
    if (priority == null) return 'Not ranked';
    final rank = settings.rankOf(priority) + 1;
    return '#$rank · ${reminderCountText(rank)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isOn = settings.isOn(kind);

    return SwitchListTile(
      value: isOn,
      onChanged: enabled ? onChanged : null,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Flexible(
            child: Text(
              titleOf(kind),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isOn ? colors.primaryTint : colors.track,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isOn ? colors.primaryText : colors.textMuted,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          reminderTimingText(kind, settings.timesFor(kind)),
          style: TextStyle(fontSize: 13, height: 1.35, color: colors.textBody),
        ),
      ),
    );
  }
}
