import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
import 'home_screen.dart';

class FinancialSetupScreen extends StatefulWidget {
  const FinancialSetupScreen({super.key});

  @override
  State<FinancialSetupScreen> createState() => _FinancialSetupScreenState();
}

class _FinancialSetupScreenState extends State<FinancialSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _incomeController = TextEditingController();
  final _budgetController = TextEditingController();

  String? _incomeSource;
  String? _incomeFrequency;
  bool _isSaving = false;

  static const _primaryBlue = Color(0xFF1976D2);
  static const _incomeSources = [
    'Allowance',
    'Salary',
    'Part-time Job',
    'Business',
    'Freelance',
    'Other',
  ];
  static const _incomeFrequencies = [
    'Weekly',
    'Bi-weekly',
    'Monthly',
    'Irregular',
  ];

  String? _positiveAmountValidator(String? value) {
    final amount = double.tryParse(value?.trim().replaceAll(',', '') ?? '');

    if (amount == null || amount <= 0) {
      return 'Enter a valid positive amount.';
    }

    return null;
  }

  Future<void> _saveSetup() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;

    if (_incomeSource == null || _incomeFrequency == null) {
      _showMessage('Please select your income source and frequency.');
      return;
    }

    final income = double.parse(
      _incomeController.text.trim().replaceAll(',', ''),
    );
    final budget = double.parse(
      _budgetController.text.trim().replaceAll(',', ''),
    );

    setState(() {
      _isSaving = true;
    });

    try {
      await UserProfileService.saveFinancialSetup(
        incomeSource: _incomeSource!,
        income: income,
        incomeFrequency: _incomeFrequency!,
        budget: budget,
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } catch (_) {
      _showMessage('We could not save your information. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _incomeController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Financial Setup'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to FinAssist! 👋',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Let's personalize your financial assistant.",
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
                const SizedBox(height: 30),
                _label('Main source of income'),
                DropdownButtonFormField<String>(
                  initialValue: _incomeSource,
                  decoration: _inputDecoration('Select your income source'),
                  items: _incomeSources
                      .map(
                        (source) => DropdownMenuItem(
                          value: source,
                          child: Text(source),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _incomeSource = value),
                  validator: (value) =>
                      value == null ? 'Select an income source.' : null,
                ),
                const SizedBox(height: 20),
                _label('Income amount'),
                TextFormField(
                  controller: _incomeController,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _positiveAmountValidator,
                  decoration: _inputDecoration('Enter your usual income'),
                ),
                const SizedBox(height: 20),
                _label('Income frequency'),
                DropdownButtonFormField<String>(
                  initialValue: _incomeFrequency,
                  decoration: _inputDecoration('Select your income frequency'),
                  items: _incomeFrequencies
                      .map(
                        (frequency) => DropdownMenuItem(
                          value: frequency,
                          child: Text(frequency),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _incomeFrequency = value),
                  validator: (value) =>
                      value == null ? 'Select an income frequency.' : null,
                ),
                const SizedBox(height: 20),
                _label('Daily spending limit'),
                TextFormField(
                  controller: _budgetController,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _positiveAmountValidator,
                  decoration: _inputDecoration(
                    'Enter your daily spending limit',
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Continue',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryBlue, width: 2),
      ),
    );
  }
}
