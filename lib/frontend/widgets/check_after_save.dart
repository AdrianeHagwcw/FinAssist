import 'package:flutter/widgets.dart';

/// How every form shows what is wrong, so they all behave alike.
///
/// Nothing turns red while someone is still filling a form in. The first
/// tap on Save checks it; from then on it is checked again as it is typed,
/// so a message goes the moment its field is right, and comes back if the
/// field turns wrong again. A message never fades on its own, so nobody
/// misses it, and never stays once it is fixed, so nobody thinks they are
/// still wrong.
mixin CheckAfterSave<T extends StatefulWidget> on State<T> {
  bool _triedToSave = false;

  /// Whether Save has been tapped, so problems now show as they happen.
  bool get triedToSave => _triedToSave;

  /// For [Form.autovalidateMode]: off until the first Save, then on.
  AutovalidateMode get checkMode =>
      _triedToSave ? AutovalidateMode.always : AutovalidateMode.disabled;

  /// Notes that Save was tapped, so the form is checked from now on.
  void markTriedToSave() {
    if (!_triedToSave) setState(() => _triedToSave = true);
  }

  /// Checks [form] for a Save tap; true when everything in it is right.
  bool checkForm(GlobalKey<FormState> form) {
    markTriedToSave();
    return form.currentState!.validate();
  }

  /// For a form whose messages are worked out in build: builds again as
  /// [field] is typed in, once Save has been tapped, so they keep up.
  void recheckWhenChanged(Listenable field) => field.addListener(_recheck);

  void _recheck() {
    if (_triedToSave && mounted) setState(() {});
  }
}
