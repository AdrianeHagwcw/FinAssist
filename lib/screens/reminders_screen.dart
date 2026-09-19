import 'package:flutter/material.dart';

import '../models/onboarding_data.dart';
import '../models/reminder.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_service.dart';
import '../services/user_profile_service.dart';
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
    this.onSetBillLeadDays = ReminderSettingsService.setBillLeadDays,
    this.onSetPriorities = ReminderSettingsService.setPriorities,
    super.key,
  });

  /// Replaces the live profile. Used by tests.
  final Stream<Map<String, dynamic>?>? profile;

  final Future<bool> Function() requestPermission;
  final Future<bool> Function() sendTest;
  final void Function(bool enabled) onSetEnabled;
  final void Function(ReminderKind kind, bool? on) onSetKind;
  final void Function(int? days) onSetBillLeadDays;
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
              _Card(
                child: SwitchListTile(
                  value: on,
                  onChanged: _setEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Reminders on this phone',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'They work offline. Nothing is sent anywhere.',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _Heading(
                'What matters most to you',
                'Reminders follow this order. Your top two decide which ones '
                    'start on.',
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
              const _Heading('Reminders', null),
              for (final kind in ReminderKind.values) ...[
                _KindCard(
                  kind: kind,
                  settings: settings,
                  enabled: on,
                  // Matching the suggestion again hands it back to the
                  // priorities, so later re-ranking still moves it.
                  onChanged: (value) => widget.onSetKind(
                    kind,
                    value == settings.suggested(kind) ? null : value,
                  ),
                  onFollowPriorities: () => widget.onSetKind(kind, null),
                  onLeadDays: widget.onSetBillLeadDays,
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _sendTest,
                style: openOutlineStyle(context),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send a Test Reminder'),
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
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: rank <= 2 ? colors.primaryText : colors.textBody,
              ),
            ),
          ),
          Expanded(
            child: Text(
              priority.label,
              style: TextStyle(color: colors.textPrimary),
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

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.kind,
    required this.settings,
    required this.enabled,
    required this.onChanged,
    required this.onFollowPriorities,
    required this.onLeadDays,
  });

  final ReminderKind kind;
  final ReminderSettings settings;

  /// False while reminders as a whole are off.
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onFollowPriorities;
  final ValueChanged<int?> onLeadDays;

  static String titleOf(ReminderKind kind) => switch (kind) {
    ReminderKind.bills => 'Bills due',
    ReminderKind.payday => 'Payday',
    ReminderKind.goals => 'Saving plans',
    ReminderKind.leftover => 'Leftover money',
    ReminderKind.dailyLog => 'Log your spending',
  };

  static String whenOf(ReminderKind kind) => switch (kind) {
    ReminderKind.bills => 'Before and on the due date, at 9 AM.',
    ReminderKind.payday =>
      'On payday at 12 PM, then daily for 3 days until you log it.',
    ReminderKind.goals => "On your goal's saving days, at 9 AM.",
    ReminderKind.leftover => 'When a pay period ends, to save or spend it.',
    ReminderKind.dailyLog => '8 PM on days nothing was logged yet.',
  };

  String get _why {
    final priority = ReminderSettings.priorityFor(kind);
    if (priority == null) {
      return kind == ReminderKind.payday
          ? 'Always suggested: logged pay keeps Safe to Spend right.'
          : 'Always suggested: a missed bill costs money.';
    }

    final rank = settings.rankOf(priority) + 1;
    return settings.suggested(kind)
        ? 'Suggested: "${priority.label}" is #$rank for you.'
        : 'Off by default: "${priority.label}" is #$rank for you.';
  }

  static String _leadLabel(int days) => switch (days) {
    0 => 'On the day',
    1 => '1 day before',
    _ => '$days days before',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final byHand = settings.overrides.containsKey(kind);
    final isOn = settings.isOn(kind);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: isOn,
              onChanged: enabled ? onChanged : null,
              contentPadding: EdgeInsets.zero,
              title: Text(
                titleOf(kind),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(whenOf(kind)),
            ),
            if (kind == ReminderKind.bills && isOn) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final days in billLeadDayChoices)
                    ChoiceChip(
                      label: Text(_leadLabel(days)),
                      selected: settings.billLeadDays == days,
                      showCheckmark: false,
                      selectedColor: appPrimaryBlue,
                      labelStyle: TextStyle(
                        color: settings.billLeadDays == days
                            ? Colors.white
                            : colors.textBody,
                      ),
                      onSelected: enabled
                          ? (_) => onLeadDays(
                              days == settings.suggestedBillLeadDays
                                  ? null
                                  : days,
                            )
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Suggested: ${_leadLabel(settings.suggestedBillLeadDays).toLowerCase()}'
                '${settings.suggestedBillLeadDays == 3 ? ', since paying bills on time is your top priority' : ''}.',
                style: TextStyle(fontSize: 12, color: colors.textBody),
              ),
              // Room at the bottom of the card when nothing follows.
              if (!byHand) const SizedBox(height: 14),
            ],
            // An active bill reminder already explains itself in its timing
            // line, so the reason isn't repeated under it.
            if (kind != ReminderKind.bills || !isOn || byHand)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        byHand
                            ? 'You chose this. It no longer follows your '
                                  'priorities.'
                            : _why,
                        style: TextStyle(fontSize: 12, color: colors.textBody),
                      ),
                    ),
                    if (byHand)
                      TextButton(
                        onPressed: enabled ? onFollowPriorities : null,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.primaryText,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Follow priorities'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
