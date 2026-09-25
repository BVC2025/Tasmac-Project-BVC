import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/api_service.dart';
import 'generate_bottle_screen.dart';

class BottleListScreen extends StatefulWidget {
  final String token;

  const BottleListScreen({super.key, required this.token});

  @override
  State<BottleListScreen> createState() => _BottleListScreenState();
}

class _BottleListScreenState extends State<BottleListScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _bottlesFuture;

  @override
  void initState() {
    super.initState();
    _bottlesFuture = _apiService.listBottles(widget.token);
  }

  void _refresh() {
    setState(() {
      _bottlesFuture = _apiService.listBottles(widget.token);
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'returned':
        return Colors.orange;
      case 'redeemed':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _printAllLabels() async {
    try {
      final pdfBytes = await _apiService.getLabelsPdf(widget.token);
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Bottles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print all labels',
            onPressed: _printAllLabels,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => GenerateBottleScreen(token: widget.token)),
          );
          if (created == true) _refresh();
        },
        child: const Icon(Icons.qr_code_2),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _bottlesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final bottles = snapshot.data ?? [];
          if (bottles.isEmpty) {
            return const Center(child: Text('No bottles generated yet.'));
          }

          return ListView.separated(
            itemCount: bottles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final bottle = bottles[index] as Map<String, dynamic>;
              final status = bottle['status'] as String;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(status),
                  child: const Icon(Icons.qr_code, color: Colors.white),
                ),
                title: Text(bottle['refund_qr_code']),
                subtitle: Text(
                  '${bottle['brand_name'] ?? 'No brand'} • MFG: ${bottle['manufacturing_qr_code']}',
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(status),
              );
            },
          );
        },
      ),
    );
  }
}
