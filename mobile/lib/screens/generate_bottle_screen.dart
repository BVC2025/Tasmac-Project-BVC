import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/api_service.dart';

class GenerateBottleScreen extends StatefulWidget {
  final String token;

  const GenerateBottleScreen({super.key, required this.token});

  @override
  State<GenerateBottleScreen> createState() => _GenerateBottleScreenState();
}

class _GenerateBottleScreenState extends State<GenerateBottleScreen> {
  final _brandController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _apiService = ApiService();

  bool _isGenerating = false;
  String? _errorMessage;

  // Single-bottle result (quantity == 1)
  Map<String, dynamic>? _createdBottle;
  Uint8List? _refundQrBytes;
  Uint8List? _manufacturingQrBytes;

  // Bulk result (quantity > 1)
  List<dynamic>? _createdBatch;

  Future<void> _handleGenerate() async {
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _createdBottle = null;
      _refundQrBytes = null;
      _manufacturingQrBytes = null;
      _createdBatch = null;
    });

    try {
      final brand = _brandController.text.trim();
      final brandName = brand.isEmpty ? null : brand;

      if (quantity <= 1) {
        final bottle = await _apiService.createBottle(widget.token, brandName: brandName);
        final bottleId = bottle['id'] as int;
        final refundQrBytes = await _apiService.getRefundQrImage(widget.token, bottleId);
        final mfgQrBytes = await _apiService.getManufacturingQrImage(widget.token, bottleId);
        setState(() {
          _createdBottle = bottle;
          _refundQrBytes = refundQrBytes;
          _manufacturingQrBytes = mfgQrBytes;
        });
      } else {
        final batch = await _apiService.createBottlesBulk(widget.token, count: quantity, brandName: brandName);
        setState(() {
          _createdBatch = batch;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _printBatchLabels() async {
    final ids = _createdBatch!.map((b) => b['id'] as int).toList();
    final pdfBytes = await _apiService.getLabelsPdf(widget.token, ids: ids);
    await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
  }

  @override
  void dispose() {
    _brandController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Bottle')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _brandController,
                  decoration: const InputDecoration(
                    labelText: 'Brand Name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    helperText: 'How many bottles to generate (1-500)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _handleGenerate,
                  icon: _isGenerating
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.qr_code_2),
                  label: const Text('Generate QR Code(s)'),
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null)
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                if (_createdBottle != null && _refundQrBytes != null && _manufacturingQrBytes != null) ...[
                  const Text('REFUND QR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  Text(
                    _createdBottle!['refund_qr_code'],
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                    child: Image.memory(_refundQrBytes!, width: 180, height: 180),
                  ),
                  const SizedBox(height: 20),
                  const Text('MANUFACTURING QR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  Text(
                    _createdBottle!['manufacturing_qr_code'],
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                    child: Image.memory(_manufacturingQrBytes!, width: 180, height: 180),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Done'),
                  ),
                ],
                if (_createdBatch != null) ...[
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Generated ${_createdBatch!.length} bottles',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _printBatchLabels,
                    icon: const Icon(Icons.print),
                    label: const Text('Print / Share Label Sheet'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Done'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
