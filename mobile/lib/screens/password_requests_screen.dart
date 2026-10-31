import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/list_search.dart';
import '../widgets/reset_password_dialog.dart';

/// Admin inbox of staff "forgot password" requests sent from the login
/// screen. A request stays here until the admin resets that staff member's
/// password (there is deliberately no "dismiss", so none get lost); the reset
/// dialog then offers to SMS the new password to the staff member.
class PasswordRequestsScreen extends StatefulWidget {
  final String token;

  const PasswordRequestsScreen({super.key, required this.token});

  @override
  State<PasswordRequestsScreen> createState() => _PasswordRequestsScreenState();
}

class _PasswordRequestsScreenState extends State<PasswordRequestsScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _requestsFuture = _apiService.listPasswordResetRequests(widget.token);
  String _query = '';

  void _refresh() {
    setState(() => _requestsFuture = _apiService.listPasswordResetRequests(widget.token));
  }

  Future<void> _reset(Map<String, dynamic> staff) async {
    final done = await showResetPasswordDialog(
      context,
      token: widget.token,
      staffId: staff['id'] as int,
      staffName: staff['full_name'] ?? '',
      staffPhone: staff['phone_number'] as String?,
    );
    if (done) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Requests'),
        bottom: ListSearchBar(
          hint: 'Search name, User ID, phone…',
          onChanged: (query) => setState(() => _query = query),
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return const Center(child: Text('No pending password requests.'));
          }
          final requests = all.where((item) {
            final request = item as Map<String, dynamic>;
            final staff = request['staff'] as Map<String, dynamic>;
            return matchesSearch(_query, [
              staff['full_name'],
              staff['user_id'],
              staff['phone_number'],
              staff['shop_name'],
              request['message'],
            ]);
          }).toList();
          if (requests.isEmpty) {
            return const Center(child: Text('No results for this search.'));
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
                final message = (request['message'] as String?)?.trim();

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
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Message from staff',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                message == null || message.isEmpty ? 'No message was added.' : message,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontStyle: message == null || message.isEmpty ? FontStyle.italic : FontStyle.normal,
                                  color: message == null || message.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _reset(staff),
                            icon: const Icon(Icons.key, size: 18),
                            label: const Text('Reset password'),
                          ),
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
