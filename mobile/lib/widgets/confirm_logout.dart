import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Asks before logging out, so a stray tap on the logout icon doesn't end
/// the session mid-shift. Returns true only when the user confirms.
Future<bool> confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.logout, color: AppColors.brandRed),
      title: const Text('Log out?'),
      content: const Text('Are you sure you want to log out? You will need your User ID and password to sign in again.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
