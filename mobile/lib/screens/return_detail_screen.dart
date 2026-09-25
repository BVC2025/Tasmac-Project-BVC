import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

class ReturnDetailScreen extends StatelessWidget {
  final Map<String, dynamic> item;
  final String token;

  const ReturnDetailScreen({super.key, required this.item, required this.token});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String;
    final isRejected = status == 'rejected';
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();

    return Scaffold(
      appBar: AppBar(title: const Text('Return Details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Icon(
                  isRejected ? Icons.cancel : Icons.check_circle,
                  color: isRejected ? AppColors.brandRed : Colors.green,
                  size: 56,
                ),
                const SizedBox(height: 8),
                Text(
                  isRejected ? 'Rejected' : 'Returned',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isRejected ? AppColors.brandRed : Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _section('Bottle', [
            _row('QR Code', item['qr_code'] ?? '—'),
          ]),
          _section('When & Where', [
            _row('Date', createdAt != null ? _formatDate(createdAt) : '—'),
            _row('Time', createdAt != null ? _formatTime(createdAt) : '—'),
            _row('Shop', item['shop_name'] ?? '—'),
            if (item['distance_meters'] != null) _row('Distance', '${item['distance_meters']} m'),
          ]),
          if (isRejected)
            _section('Rejection', [
              _row('Reason', (item['rejection_reason'] ?? '—').toString().replaceAll('_', ' ')),
              if ((item['remarks'] ?? '').toString().isNotEmpty) _row('Remarks', item['remarks']),
              if (item['has_evidence_image'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _viewEvidenceImage(context),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('View Evidence Photo'),
                  ),
                )
              else
                _row('Evidence Photo', 'Not attached'),
            ])
          else
            _section('Payment', [
              _row('Method', (item['payment_method'] ?? '—').toString().toUpperCase()),
              _row('Amount', item['payment_amount'] != null ? '₹${item['payment_amount']}' : '—'),
              _row('Reference', item['payment_reference'] ?? '—'),
              _row('Payment Status', (item['payment_status'] ?? '—').toString().toUpperCase()),
            ]),
        ],
      ),
    );
  }

  void _viewEvidenceImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Evidence Photo'), backgroundColor: Colors.black, foregroundColor: Colors.white),
          backgroundColor: Colors.black,
          body: Center(
            child: FutureBuilder(
              future: ApiService().getEvidenceImage(token, item['id'] as int),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator(color: Colors.white);
                }
                if (snapshot.hasError) {
                  return Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  );
                }
                return InteractiveViewer(child: Image.memory(snapshot.data!));
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
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
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryGreen),
              ),
              const SizedBox(height: 10),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
