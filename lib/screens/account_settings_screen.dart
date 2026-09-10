import 'package:flutter/material.dart';

const Color _accountBlue = Color(0xFF1976D2);
const Color _accountBackground = Color(0xFFF6F8FC);

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Adriane Aranda');
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Personal information updated.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Personal Information',
      formKey: _formKey,
      children: [
        _formLabel('Full Name'),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(Icons.person_outline, 'Enter your name'),
          validator: (value) => value == null || value.trim().length < 2
              ? 'Please enter your name.'
              : null,
        ),
        const SizedBox(height: 18),
        _formLabel('Phone Number'),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: _inputDecoration(Icons.phone_outlined, 'Optional'),
        ),
        const SizedBox(height: 28),
        _saveButton('Save Changes', _save),
      ],
    );
  }
}

class EmailAddressScreen extends StatefulWidget {
  const EmailAddressScreen({super.key});

  @override
  State<EmailAddressScreen> createState() => _EmailAddressScreenState();
}

class _EmailAddressScreenState extends State<EmailAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(
    text: 'adrianearanda@email.com',
  );

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email address updated.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Email Address',
      formKey: _formKey,
      children: [
        _formLabel('Email Address'),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration(
            Icons.email_outlined,
            'Enter your email',
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Please enter a valid email.';
            }
            return null;
          },
        ),
        const SizedBox(height: 28),
        _saveButton('Update Email', _save),
      ],
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password updated successfully.'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Change Password',
      formKey: _formKey,
      children: [
        _formLabel('Current Password'),
        _passwordField(_currentPasswordController, 'Enter current password'),
        const SizedBox(height: 18),
        _formLabel('New Password'),
        _passwordField(_newPasswordController, 'At least 8 characters'),
        const SizedBox(height: 18),
        _formLabel('Confirm New Password'),
        _passwordField(
          _confirmPasswordController,
          'Re-enter new password',
          validator: (value) => value != _newPasswordController.text
              ? 'Passwords do not match.'
              : null,
        ),
        const SizedBox(height: 28),
        _saveButton('Update Password', _save),
      ],
    );
  }
}

class _AccountFormScaffold extends StatelessWidget {
  const _AccountFormScaffold({
    required this.title,
    required this.formKey,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _accountBackground,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _accountBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(children: children),
        ),
      ),
    );
  }
}

Widget _formLabel(String text) {
  return Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

InputDecoration _inputDecoration(IconData icon, String hint) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: _accountBlue),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );
}

Widget _passwordField(
  TextEditingController controller,
  String hint, {
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    obscureText: true,
    decoration: _inputDecoration(Icons.lock_outline, hint),
    validator:
        validator ??
        (value) {
          if (value == null || value.isEmpty) {
            return 'This field is required.';
          }
          if (value.length < 8) {
            return 'Password must be at least 8 characters.';
          }
          return null;
        },
  );
}

Widget _saveButton(String label, VoidCallback onPressed) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _accountBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    ),
  );
}
