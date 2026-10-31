import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Asks the admin for a new password for [staffName] and sets it — which also
/// closes any open "forgot password" request from that staff. Then offers to
/// send the new password to [staffPhone] by SMS (via the device's SMS app),
/// since that is how the staff member actually finds out what it is.
/// Returns true when the password was changed.
Future<bool> showResetPasswordDialog(
  BuildContext context, {
  required String token,
  required int staffId,
  required String staffName,
  String? staffPhone,
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
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'New password',
            helperText: 'At least 4 characters',
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setDialogState(() => obscure = !obscure),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.length < 4) return;
              Navigator.of(dialogContext).pop(controller.text);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  );

  if (newPassword == null || newPassword.isEmpty) return false;

  try {
    await ApiService().resetStaffPassword(token, staffId, newPassword);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return false;
  }

  if (!context.mounted) return true;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.check_circle, color: AppColors.primaryGreen),
      title: const Text('Password reset'),
      content: Text(
        staffPhone == null || staffPhone.isEmpty
            ? 'The new password for $staffName is set. Share it with them in person.'
            : 'The new password for $staffName is set. Send it to their phone ($staffPhone) now?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
        if (staffPhone != null && staffPhone.isNotEmpty)
          FilledButton.icon(
            icon: const Icon(Icons.sms_outlined),
            label: const Text('Send by SMS'),
            onPressed: () async {
              final message = 'TASMAC Bottle Return: your password was reset by the admin. '
                  'New password: $newPassword - please keep it private.';
              try {
                await launchUrl(Uri.parse('sms:$staffPhone?body=${Uri.encodeComponent(message)}'));
              } catch (_) {}
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
          ),
      ],
    ),
  );
  return true;
}
