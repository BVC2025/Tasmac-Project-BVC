import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'return_detail_screen.dart';

/// Rejected returns only — successful ones live in [RefundHistoryScreen].
class RejectHistoryScreen extends StatefulWidget {
  final String token;

  const RejectHistoryScreen({super.key, required this.token});

  @override
  State<RejectHistoryScreen> createState() => _RejectHistoryScreenState();
}

class _RejectHistoryScreenState extends State<RejectHistoryScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _returnsFuture;

  @override
  void initState() {
    super.initState();
    _returnsFuture = _load();
  }

  Future<List<dynamic>> _load() async {
    final all = await _apiService.listMyReturns(widget.token);
    return all.where((item) => (item as Map<String, dynamic>)['status'] == 'rejected').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reject')),
      body: FutureBuilder<List<dynamic>>(
        future: _returnsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final returns = snapshot.data ?? [];
          if (returns.isEmpty) {
            return const Center(child: Text('No rejections logged yet.'));
          }

          return ListView.separated(
            itemCount: returns.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = returns[index] as Map<String, dynamic>;
              final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();

              return ListTile(
                leading: const Icon(Icons.cancel, color: AppColors.brandRed),
                title: Text(item['qr_code'] ?? 'Unknown bottle'),
                subtitle: Text(
                  (item['rejection_reason'] ?? 'Unknown reason').toString().replaceAll('_', ' '),
                ),
                trailing: Text(
                  createdAt != null ? '${_shortDate(createdAt)}\n${_shortTime(createdAt)}' : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReturnDetailScreen(item: item, token: widget.token)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _shortDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  String _shortTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
