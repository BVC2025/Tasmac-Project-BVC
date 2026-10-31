import 'package:flutter/material.dart';

import '../models/bottle_label.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/list_search.dart';
import 'return_detail_screen.dart';

/// Rejected returns only — successful ones live in [RefundHistoryScreen].
class RejectHistoryScreen extends StatefulWidget {
  final String token;

  /// Admin view: every shop's returns instead of only this user's.
  final bool allShops;

  const RejectHistoryScreen({super.key, required this.token, this.allShops = false});

  @override
  State<RejectHistoryScreen> createState() => _RejectHistoryScreenState();
}

class _RejectHistoryScreenState extends State<RejectHistoryScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _returnsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _returnsFuture = _load();
  }

  Future<List<dynamic>> _load() async {
    final all = widget.allShops
        ? await _apiService.listAllReturns(widget.token)
        : await _apiService.listMyReturns(widget.token);
    return all.where((item) => (item as Map<String, dynamic>)['status'] == 'rejected').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reject'),
        bottom: ListSearchBar(
          hint: 'Search QR, brand, size, reason…',
          onChanged: (query) => setState(() => _query = query),
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _returnsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return const Center(child: Text('No rejections logged yet.'));
          }
          final returns = all.where((item) => matchesSearch(_query, _searchFields(item as Map<String, dynamic>))).toList();
          if (returns.isEmpty) {
            return const Center(child: Text('No results for this search.'));
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
                  [
                    ?bottleLabel(item),
                    (item['rejection_reason'] ?? 'Unknown reason').toString().replaceAll('_', ' '),
                  ].join('\n'),
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

/// Every field a staff member might search a return by.
List<Object?> _searchFields(Map<String, dynamic> item) => [
      item['qr_code'],
      item['refund_qr_code'],
      item['manufacturing_qr_code'],
      item['brand_name'],
      item['bottle_size'],
      item['shop_name'],
      item['rejection_reason']?.toString().replaceAll('_', ' '),
      item['remarks'],
      item['payment_reference'],
      item['payment_customer_identifier'],
      item['created_at'],
    ];
