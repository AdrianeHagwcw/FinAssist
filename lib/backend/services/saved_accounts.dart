import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An account that has signed in on this phone, kept so Switch account can
/// list it. Only what the list shows is kept, never a password.
@immutable
class SavedAccount {
  const SavedAccount({
    required this.uid,
    required this.email,
    this.name = '',
    this.usesPassword = true,
    this.usesGoogle = false,
  });

  /// The signed-in [user], or null without an email to show.
  static SavedAccount? of(User? user) {
    final email = user?.email?.trim() ?? '';
    if (user == null || email.isEmpty) return null;
    final providers = {for (final p in user.providerData) p.providerId};
    final usesGoogle = providers.contains('google.com');
    return SavedAccount(
      uid: user.uid,
      email: email,
      name: user.displayName?.trim() ?? '',
      usesPassword: providers.contains('password') || !usesGoogle,
      usesGoogle: usesGoogle,
    );
  }

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    uid: json['uid'] as String,
    email: json['email'] as String,
    name: json['name'] as String? ?? '',
    usesPassword: json['password'] as bool? ?? true,
    usesGoogle: json['google'] as bool? ?? false,
  );

  /// Firebase's id for the account, which stays the same when its email
  /// is changed.
  final String uid;
  final String email;
  final String name;

  /// Logs in with a password. An account can have both ways.
  final bool usesPassword;

  /// Can log in through Google.
  final bool usesGoogle;

  /// The name, or the email for an account without one.
  String get label => name.isNotEmpty ? name : email;

  String get initial => label.substring(0, 1).toUpperCase();

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'name': name,
    'password': usesPassword,
    'google': usesGoogle,
  };
}

/// The accounts used on this phone, the last one signed in first.
class SavedAccounts {
  static const _key = 'savedAccounts';

  /// Enough for a shared phone without the list growing forever.
  static const limit = 5;

  static Future<List<SavedAccount>> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return [
        for (final entry in preferences.getStringList(_key) ?? const [])
          SavedAccount.fromJson(jsonDecode(entry) as Map<String, dynamic>),
      ];
    } catch (error) {
      debugPrint('Could not load saved accounts: $error');
      return const [];
    }
  }

  /// Puts [account] first, replacing what was kept for it before, so a
  /// changed name or email shows the new one.
  static Future<void> remember(SavedAccount? account) async {
    if (account == null) return;
    final others = [
      for (final saved in await load())
        if (saved.uid != account.uid) saved,
    ];
    await _save([account, ...others].take(limit).toList());
  }

  static Future<void> forget(SavedAccount account) async => _save([
    for (final saved in await load())
      if (saved.uid != account.uid) saved,
  ]);

  static Future<void> _save(List<SavedAccount> accounts) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(_key, [
        for (final account in accounts) jsonEncode(account.toJson()),
      ]);
    } catch (error) {
      debugPrint('Could not save accounts: $error');
    }
  }
}
