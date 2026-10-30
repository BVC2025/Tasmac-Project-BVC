import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Asks the admin for a new password for [staffName] and sets it. Shows the
/// outcome as a snackbar and returns true when the password was changed —
/// which also closes any open "forgot password" request from that staff.
Future<bool> showResetPasswordDialog(
  BuildContext context, {
  required String token,
  required int staffId,
  required String staffName,
}) async {
  final controller = TextEditingController();
  bool obscure = true;

  final newPassword = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('Reset password — $staffName'),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: 'New password',
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setDialogState(() => obscure = !obscure),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  );

  if (newPassword == null || newPassword.isEmpty) return false;

  try {
    await ApiService().resetStaffPassword(token, staffId, newPassword);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset for $staffName. Share the new password with them securely.')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return false;
  }
}
