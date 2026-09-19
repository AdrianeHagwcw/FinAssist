import 'package:flutter/material.dart';

import '../models/financial_preferences.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/category_icon.dart';
import 'financial_preferences_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({this.profile, this.onSave, super.key});
  final Stream<Map<String, dynamic>?>? profile;
  final void Function(Map<String, dynamic>)? onSave;
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final _profile =
      widget.profile ?? UserProfileService.watchProfile().map((s) => s.data());

  void _save(Map<String, dynamic> values) =>
      (widget.onSave ?? UserProfileService.updatePreferences)(values);

  /// Everything but Others is hidden, so the button offers to show them again.
  bool _allHidden(FinancialPreferences prefs) =>
      prefs.availableCategories.length <= 1;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Expense categories',
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
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Could not load categories. Please reopen this screen.',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final prefs = FinancialPreferences.fromMap(snapshot.data);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const PreferenceIntro(
              title: 'Keep the list to what you use',
              message:
                  'Hide the categories you never pick, so recording an '
                  'expense is quicker. Existing transactions and reports keep '
                  'their labels.',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Shown when recording expenses',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => _save({
                    'hiddenCategories': _allHidden(prefs)
                        ? <String>[]
                        : [
                            for (final category in prefs.allCategories)
                              if (category != 'Others') category,
                          ],
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: context.appColors.primaryText,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(_allHidden(prefs) ? 'Show all' : 'Hide all'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Material(
              color: context.appColors.card,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  for (final category in prefs.allCategories)
                    SwitchListTile(
                      title: Text(category),
                      subtitle: category == 'Others'
                          ? const Text(
                              'Stays on, so there is always one choice left',
                            )
                          : null,
                      secondary: CategoryIcon(category),
                      value:
                          !prefs.hiddenCategories.contains(category) ||
                          category == 'Others',
                      onChanged: category == 'Others'
                          ? null
                          : (show) {
                              final hidden = {...prefs.hiddenCategories};
                              show
                                  ? hidden.remove(category)
                                  : hidden.add(category);
                              _save({'hiddenCategories': hidden.toList()});
                            },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    ),
  );
}
