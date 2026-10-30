import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/reset_password_dialog.dart';

/// Admin inbox of staff "forgot password" requests sent from the login
/// screen. Resetting the password (or dismissing) closes the request.
class PasswordRequestsScreen extends StatefulWidget {
  final String token;

  const PasswordRequestsScreen({super.key, required this.token});

  @override
  State<PasswordRequestsScreen> createState() => _PasswordRequestsScreenState();
}

class _PasswordRequestsScreenState extends State<PasswordRequestsScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _requestsFuture = _apiService.listPasswordResetRequests(widget.token);

  void _refresh() {
    setState(() => _requestsFuture = _apiService.listPasswordResetRequests(widget.token));
  }

  Future<void> _reset(Map<String, dynamic> staff) async {
    final done = await showResetPasswordDialog(
      context,
      token: widget.token,
      staffId: staff['id'] as int,
      staffName: staff['full_name'] ?? '',
    );
    if (done) _refresh();
  }

  Future<void> _dismiss(Map<String, dynamic> staff) async {
    try {
      await _apiService.dismissPasswordResetRequest(widget.token, staff['id'] as int);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password Requests')),
      body: FutureBuilder<List<dynamic>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return const Center(child: Text('No pending password requests.'));
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final request = requests[index] as Map<String, dynamic>;
                final staff = request['staff'] as Map<String, dynamic>;
                final requestedAt = DateTime.tryParse(request['requested_at']?.toString() ?? '')?.toLocal();
                final message = request['message'] as String?;

                return Card(
                  elevation: 0,
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFFFFF1E0),
                              child: Icon(Icons.lock_reset, color: Color(0xFFA9672B)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    staff['full_name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                  Text(
                                    'ID: ${staff['user_id']} • ${staff['phone_number']}'
                                    '${staff['shop_name'] != null ? ' • ${staff['shop_name']}' : ''}',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (requestedAt != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Requested ${_formatWhen(requestedAt)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                        if (message != null && message.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('“$message”', style: const TextStyle(fontStyle: FontStyle.italic)),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _reset(staff),
                              icon: const Icon(Icons.key, size: 18),
                              label: const Text('Reset password'),
                            ),
                            TextButton(onPressed: () => _dismiss(staff), child: const Text('Dismiss')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatWhen(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]}, $hour:${dt.minute.toString().padLeft(2, '0')} $period';
  }
}
