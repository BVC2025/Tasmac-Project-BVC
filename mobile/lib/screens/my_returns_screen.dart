import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'return_detail_screen.dart';

class MyReturnsScreen extends StatefulWidget {
  final String token;

  const MyReturnsScreen({super.key, required this.token});

  @override
  State<MyReturnsScreen> createState() => _MyReturnsScreenState();
}

class _MyReturnsScreenState extends State<MyReturnsScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _returnsFuture;

  @override
  void initState() {
    super.initState();
    _returnsFuture = _apiService.listMyReturns(widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Returns')),
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
            return const Center(child: Text('No returns processed yet.'));
          }

          return ListView.separated(
            itemCount: returns.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = returns[index] as Map<String, dynamic>;
              final status = item['status'] as String;
              final isRejected = status == 'rejected';
              final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();

              return ListTile(
                leading: Icon(
                  isRejected ? Icons.cancel : Icons.check_circle,
                  color: isRejected ? Colors.red : Colors.green,
                ),
                title: Text(item['qr_code'] ?? 'Unknown bottle'),
                subtitle: Text(
                  isRejected
                      ? 'Rejected: ${item['rejection_reason'] ?? ''}'
                      : '${item['shop_name']} • ${item['distance_meters'] ?? '—'} m',
                ),
                trailing: Text(
                  createdAt != null ? '${_shortDate(createdAt)}\n${_shortTime(createdAt)}' : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11),
                ),
                isThreeLine: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReturnDetailScreen(item: item)),
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
