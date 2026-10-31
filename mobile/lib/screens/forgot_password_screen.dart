import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Staff "forgot password" request to the admins. A full page rather than a
/// dialog: on short POS screens the keyboard covered a dialog's text fields,
/// so staff couldn't see what they were typing.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialUserId;

  const ForgotPasswordScreen({super.key, this.initialUserId = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _userIdController = TextEditingController(text: widget.initialUserId);
  final _messageController = TextEditingController();
  final _apiService = ApiService();

  bool _sending = false;
  String? _sentConfirmation;
  String? _errorMessage;

  @override
  void dispose() {
    _userIdController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      final confirmation = await _apiService.requestPasswordReset(
        _userIdController.text.trim(),
        message: _messageController.text.trim(),
      );
      if (mounted) setState(() => _sentConfirmation = confirmation);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _sentConfirmation != null ? _sentView() : _formView(),
        ),
      ),
    );
  }

  Widget _formView() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_reset, size: 48, color: AppColors.primaryGreen),
          const SizedBox(height: 12),
          const Text(
            'Your admin will get a request to reset your password, and will send you the new one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _userIdController,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Your User ID',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your User ID' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _messageController,
            maxLength: 200,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Message to admin (optional)',
              hintText: 'e.g. I forgot my password after my phone was reset',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  Widget _sentView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.mark_email_read_outlined, size: 64, color: AppColors.primaryGreen),
        const SizedBox(height: 16),
        const Text(
          'Request Sent',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(_sentConfirmation!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to Login')),
      ],
    );
  }
}
