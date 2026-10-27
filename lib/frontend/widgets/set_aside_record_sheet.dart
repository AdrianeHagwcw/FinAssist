import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import 'savings_guide.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/text_limits.dart';
import '../../backend/utils/unique_name.dart';
import 'check_after_save.dart';
import 'goal_funding_picker.dart';
import 'wallet_picker.dart';
import 'savings_form_parts.dart';

/// Lets the user fix a savings or bills record they set up earlier: its name,
/// and the balance they declared.
///
/// Correcting the balance is not a payment. It assumes the figure was typed
/// wrongly, so nothing is recorded as income or spending.
Future<bool?> showSetAsideRecordSheet(
  BuildContext context, {
  Wallet? wallet,
  List<Wallet> wallets = const [],
  SavingsKind? initialKind,
  double minimumBalance = 0,
  void Function(String name, double recorded)? onSave,
  Stream<List<Goal>>? goals,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SetAsideRecordSheet(
      wallet: wallet,
      wallets: wallets,
      initialKind: initialKind,
      minimumBalance: minimumBalance,
      onSave: onSave,
      goals: goals,
    ),
  );
}

class SetAsideRecordSheet extends StatefulWidget {
  const SetAsideRecordSheet({
    this.wallet,
    this.wallets = const [],
    this.initialKind,
    this.minimumBalance = 0,
    this.onSave,
    this.onMoveIn,
    this.goals,
    super.key,
  });

  /// The record being fixed, or null when adding a new one.
  final Wallet? wallet;

  /// Everything already saved, used to give a new record its place in the
  /// list. Only needed when adding.
  final List<Wallet> wallets;

  /// The kind to open on, for a new record started from the savings guide.
  final SavingsKind? initialKind;

  /// Money in this savings record already assigned to goals.
  final double minimumBalance;

  /// Replaces the write. Used by tests.
  final void Function(String name, double recorded)? onSave;

  /// Replaces the write for new savings moved in from the user's wallets,
  /// with the amount from each. Used by tests.
  final void Function(String name, Map<String, double> from)? onMoveIn;

  /// Replaces the live goals, for what each wallet has free. Used by tests.
  final Stream<List<Goal>>? goals;

  @override
  State<SetAsideRecordSheet> createState() => _SetAsideRecordSheetState();
}

class _SetAsideRecordSheetState extends State<SetAsideRecordSheet>
    with CheckAfterSave, WatchesGoals {
  late final _nameController = TextEditingController(
    text: widget.wallet?.name ?? '',
  );
  late final _balanceController = TextEditingController(
    text: widget.wallet == null
        ? ''
        : formatAmountInput(widget.wallet!.balance),
  );
  late SavingsKind _kind = widget.wallet != null
      ? SavingsKind.fromName(widget.wallet?.savingsKind)
      : widget.initialKind ?? SavingsKind.savingsDeposit;
  late final _rateController = TextEditingController(
    text: widget.wallet?.annualInterestRatePercent?.toString() ?? '',
  );
  late DateTime? _depositStartDate = widget.wallet?.depositStartDate;
  late DateTime? _maturityDate = widget.wallet?.maturityDate;
  late InterestPayout _payout =
      widget.wallet?.interestPayout ?? InterestPayout.monthly;

  bool get _isNew => widget.wallet == null;

  bool get _canEditSavingsMetadata {
    if (_isNew) return true;
    final wallet = widget.wallet!;
    if (wallet.savingsType == SavingsKind.savingsDeposit ||
        wallet.savingsType == SavingsKind.demandDeposit) {
      return true;
    }
    return wallet.savingsType == SavingsKind.timeDeposit &&
        wallet.annualInterestRatePercent != null &&
        wallet.depositStartDate != null;
  }

  String get _addLabel => 'Add Savings';

  static const _timeDepositNeedsMoney =
      'A time deposit is opened with its money in it. Enter the amount you '
      'placed.';

  bool get _asksRate => _canEditSavingsMetadata && _kind.isInterestBearing;

  /// What is wrong with each field as it stands, or null where it is right.
  /// Shown under its field once Save has been tapped, so each one goes as
  /// soon as its field is fixed.
  ({String? name, String? balance, String? rate, String? start, String? end})
  get _problems {
    final text = _balanceController.text.trim().replaceAll(',', '');
    final recorded = double.tryParse(text);
    final rate = double.tryParse(_rateController.text.trim());
    // Moved in from the wallets: what they give, each within what it has
    // free, is the balance.
    final String? movingProblem = !_isMovingIn
        ? null
        : _movingTotal <= 0
        ? 'Pick the wallets it comes from and how much from each.'
        : !fundingFits(
            amounts: _from,
            wallets: widget.wallets,
            otherGoals: heldGoals,
          )
        ? 'An amount is more than its wallet has free.'
        : null;
    return (
      // Only an existing record has to keep a name; a new one can be left to
      // the type.
      name: itemNameProblem(_finalName(), maxLength: maxItemNameLength),
      balance: _isMovingIn
          ? movingProblem
          : text.isEmpty
          ? 'Enter the balance, or 0 if empty.'
          : recorded == null || !recorded.isFinite || recorded < 0
          ? 'Enter an amount of zero or more.'
          // A time deposit is opened with the money placed in it, all at
          // once; it can't start empty and be filled later.
          : _isNew && _kind == SavingsKind.timeDeposit && recorded <= 0
          ? _timeDepositNeedsMoney
          : recorded + 0.005 < widget.minimumBalance
          ? 'At least ${formatPeso(widget.minimumBalance)} is already '
                'assigned to goals. Reduce the goal contributions first.'
          : null,
      rate: _asksRate && !isValidAnnualInterestRatePercent(rate)
          ? 'Enter a rate from 0% to '
                '${maximumAnnualInterestRatePercent.toInt()}%.'
          : null,
      start: _asksRate && _depositStartDate == null
          ? 'Choose the start date.'
          : null,
      end:
          _canEditSavingsMetadata &&
              _kind == SavingsKind.timeDeposit &&
              (_maturityDate == null ||
                  (_depositStartDate != null &&
                      !_maturityDate!.isAfter(_depositStartDate!)))
          ? 'Choose an end date after the start date.'
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    recheckWhenChanged(_nameController);
    recheckWhenChanged(_balanceController);
    recheckWhenChanged(_rateController);
    // Only new savings can take money from the wallets, so only they need
    // to know what goals hold there.
    if (_asksSource) {
      watchGoals(
        given: widget.goals,
        walletsGiven: widget.onSave != null || widget.onMoveIn != null,
      );
    }
  }

  /// New savings can be money already in the account, recorded as it is,
  /// or money moved in now from the user's own wallets. Setup only records
  /// what is there today, so it never asks; this is the place money moves.
  bool _movingIn = false;
  Map<String, double> _from = const {};

  bool get _asksSource => _isNew;

  bool get _isMovingIn => _asksSource && _movingIn;

  double get _movingTotal =>
      _from.values.fold<double>(0, (sum, amount) => sum + amount);

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  /// The same plain-language guide that used to sit on the Goals screen,
  /// read here beside the choice it describes.
  Future<void> _explain(SavingsKind kind) async {
    await showSavingsOptionSheet(
      context,
      option: savingsOptionFor(kind),
      actionLabel: 'Use this',
      onAct: () => setState(() => _kind = kind),
    );
  }

  Future<void> _pickMaturity() async {
    final today = DateTime.now();
    final start = _depositStartDate ?? today;
    final suggested = DateTime(start.year, start.month + 6, start.day);
    final selected = _maturityDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: selected != null && selected.isAfter(start)
          ? selected
          : suggested,
      firstDate: DateTime(start.year, start.month, start.day + 1),
      lastDate: DateTime(today.year + 40),
      helpText: 'When can you take it out?',
    );
    if (picked != null) setState(() => _maturityDate = picked);
  }

  Future<void> _pickDepositStart() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _depositStartDate ?? today,
      firstDate: DateTime(today.year - 20),
      lastDate: DateTime(today.year + 20),
      helpText: 'When did or will this deposit start?',
    );
    if (picked != null) {
      setState(() {
        _depositStartDate = picked;
        if (_maturityDate != null && !_maturityDate!.isAfter(picked)) {
          _maturityDate = null;
        }
      });
    }
  }

  /// What the record ends up called. A blank name falls back to the type,
  /// and a name already taken gets the next number so two records never read
  /// the same.
  String _finalName() {
    final typed = cleanText(_nameController.text);
    if (!_isNew) return typed;

    final fallback = _kind.label;
    return uniqueName(typed.isEmpty ? fallback : typed, [
      for (final wallet in widget.wallets)
        if (!wallet.archived) wallet.name,
    ], maxLength: maxItemNameLength);
  }

  void _save() {
    // Every problem shows at once, each under its own field.
    markTriedToSave();
    final problems = _problems;
    if (problems.name != null ||
        problems.balance != null ||
        problems.rate != null ||
        problems.start != null ||
        problems.end != null) {
      return;
    }
    final name = _finalName();
    final amount = _isMovingIn
        ? _movingTotal
        : double.parse(_balanceController.text.trim().replaceAll(',', ''));
    final rate = _kind.isInterestBearing
        ? double.tryParse(_rateController.text.trim())
        : null;

    if (_isMovingIn && widget.onMoveIn != null) {
      widget.onMoveIn!(name, _from);
      Navigator.pop(context, true);
      return;
    }
    if (widget.onSave != null) {
      widget.onSave!(name, amount);
      Navigator.pop(context, true);
      return;
    }

    if (_isNew) {
      WalletService.addWallet(
        type: WalletType.other,
        name: name,
        startingBalance: amount,
        // Moved in now: the wallets it comes from give it, as transfers.
        fundedFrom: _isMovingIn ? _from : const {},
        currentWallets: widget.wallets,
        purpose: WalletPurpose.savings,
        savingsKind: _kind.name,
        annualInterestRatePercent: rate,
        depositStartDate: _depositStartDate,
        maturityDate: _kind == SavingsKind.timeDeposit ? _maturityDate : null,
        interestPayout: _kind == SavingsKind.savingsDeposit ? _payout : null,
      );
    } else {
      final wallet = widget.wallet!;
      if (name != wallet.name) {
        WalletService.updateWallet(walletId: wallet.id, name: name);
      }
      WalletService.correctDeclaredBalance(wallet: wallet, recorded: amount);
      if (_canEditSavingsMetadata) {
        WalletService.updateWallet(
          walletId: wallet.id,
          updateSavingsMetadata: true,
          savingsKind: _kind.name,
          annualInterestRatePercent: rate,
          depositStartDate: _kind.isInterestBearing ? _depositStartDate : null,
          maturityDate: _kind == SavingsKind.timeDeposit ? _maturityDate : null,
        );
        if (_kind == SavingsKind.savingsDeposit &&
            _payout != wallet.interestPayout) {
          WalletService.setInterestPayout(wallet, _payout);
        }
      }
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final asksRate = _asksRate;
    final problems = triedToSave ? _problems : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The same layout as setup's Add Savings, from the same parts.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isNew ? _addLabel : 'Edit ${widget.wallet!.name}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                !_isNew
                    ? 'Fix what you entered when you set this up.'
                    // What Savings means, in one line, where it is chosen.
                    : "Money you're keeping. It's not counted in your "
                          'Available Balance until you move it out.',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              if (_canEditSavingsMetadata)
                SavingsKindPicker(
                  kind: _kind,
                  keyPrefix: 'new-savings-',
                  onChanged: (kind) => setState(() => _kind = kind),
                  onLearnMore: _explain,
                ),
              if (!_isNew) ...[
                const FieldLabel('Name'),
                TextField(
                  key: const Key('set-aside-name'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: maxItemNameLength,
                  inputFormatters: const [SafeTextFormatter()],
                  decoration: outlinedFieldDecoration(
                    hint: 'e.g. ${_kind.label}',
                    error: problems?.name,
                  ),
                ),
              ],
              if (_asksSource) ...[
                const FieldLabel('Where is this money?'),
                _SourceChoice(
                  movingIn: _movingIn,
                  onChanged: (movingIn) => setState(() => _movingIn = movingIn),
                ),
                const SizedBox(height: 6),
                Text(
                  _movingIn
                      ? 'It leaves the wallets you pick and goes into this '
                            'savings. Your total stays the same.'
                      : 'Recorded as it is. Nothing leaves your wallets.',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
              ],
              if (_isMovingIn) ...[
                const SizedBox(height: 12),
                WalletSplitPicker(
                  key: const ValueKey('savings-from-wallets'),
                  wallets: widget.wallets,
                  goals: heldGoals,
                  purpose: SplitPurpose.giving,
                  onChanged: (amounts) => setState(() => _from = amounts),
                ),
                if (problems?.balance != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    problems!.balance!,
                    style: TextStyle(
                      fontSize: 12,
                      color: dangerColorOn(context),
                    ),
                  ),
                ],
              ] else ...[
                FieldLabel(_isNew ? 'Current balance' : 'Balance'),
                TextField(
                  key: const Key('set-aside-balance'),
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration: outlinedFieldDecoration(
                    hint: '0.00',
                    prefix: '₱ ',
                    error: problems?.balance,
                    helper: _isNew
                        ? "Check your bank app or passbook. Enter 0 if it's "
                              'empty.'
                        : widget.minimumBalance > 0
                        ? 'At least ${formatPeso(widget.minimumBalance)} is '
                              'assigned to goals, so it cannot go below that.'
                        : 'Changing this only fixes a figure you typed. It is '
                              'not money coming in or going out.',
                  ),
                ),
              ],
              if (asksRate) ...[
                const FieldLabel('Interest rate per year'),
                TextField(
                  key: const Key('set-aside-interest-rate'),
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [RateInputFormatter()],
                  decoration: outlinedFieldDecoration(
                    hint: 'e.g. 5',
                    suffix: '%',
                    helper: 'Found in your bank app or account papers.',
                    error: problems?.rate,
                  ),
                ),
                const FieldLabel('Start date'),
                PickDateField(
                  key: const Key('set-aside-deposit-start'),
                  date: _depositStartDate,
                  onTap: _pickDepositStart,
                  helper: 'When this money started earning interest.',
                  error: problems?.start,
                ),
              ],
              // A savings deposit pays now and then; a time deposit pays at
              // its end date.
              if (asksRate && _kind == SavingsKind.savingsDeposit)
                InterestPayoutPicker(
                  payout: _payout,
                  onChanged: (payout) => setState(() => _payout = payout),
                ),
              if (_canEditSavingsMetadata &&
                  _kind == SavingsKind.timeDeposit) ...[
                const FieldLabel('End date'),
                PickDateField(
                  key: const Key('new-savings-maturity'),
                  date: _maturityDate,
                  onTap: _pickMaturity,
                  helper:
                      'When you can take it out without a penalty. FinAssist '
                      'asks what you did with it then.',
                  error: problems?.end,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('set-aside-save'),
                  style: confirmButtonStyle(),
                  onPressed: _save,
                  child: Text(
                    _isNew ? _addLabel : 'Save Changes',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Already in the account, or moving in now from the user's wallets: two
/// large tiles, the chosen one solid blue, like the other choices in the app.
class _SourceChoice extends StatelessWidget {
  const _SourceChoice({required this.movingIn, required this.onChanged});

  final bool movingIn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required Key key,
      required String iconAsset,
      required String title,
      required String subtitle,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final colors = context.appColors;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: '$title. $subtitle',
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: key,
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? appPrimaryBlue : colors.card,
                  border: Border.all(
                    color: selected ? appPrimaryBlue : colors.border,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(iconAsset, width: 24, height: 24),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white70 : colors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            key: const Key('savings-source-already'),
            iconAsset: 'assets/icons/icons8-money-box-96.png',
            title: 'Already in the account',
            subtitle: 'At the bank now',
            selected: !movingIn,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 10),
          tile(
            key: const Key('savings-source-wallets'),
            iconAsset: 'assets/icons/icons8-money-transfer-96.png',
            title: 'Moving it in now',
            subtitle: 'From my cash or bank',
            selected: movingIn,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}
