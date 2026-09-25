import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/rejection_reason.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class RejectBottleScreen extends StatefulWidget {
  final String token;
  final String? refundQrCode;
  final double? latitude;
  final double? longitude;
  final String? initialReason;

  const RejectBottleScreen({
    super.key,
    required this.token,
    this.refundQrCode,
    this.latitude,
    this.longitude,
    this.initialReason,
  });

  @override
  State<RejectBottleScreen> createState() => _RejectBottleScreenState();
}

class _RejectBottleScreenState extends State<RejectBottleScreen> {
  final _remarksController = TextEditingController();
  final _apiService = ApiService();
  final _picker = ImagePicker();

  late String _selectedReason;
  Uint8List? _evidenceBytes;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedReason = widget.initialReason ?? rejectionReasons.first.value;
  }

  Future<void> _pickEvidence(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 70);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _evidenceBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not capture image: $e')));
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _apiService.rejectReturn(
        widget.token,
        reason: _selectedReason,
        refundQrCode: widget.refundQrCode,
        remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        evidenceImageBytes: _evidenceBytes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reject Bottle'),
        backgroundColor: AppColors.brandRed,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cancel_outlined, color: AppColors.brandRed, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Select a reason and, if possible, add photo evidence.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  decoration: const InputDecoration(labelText: 'Rejection Reason', border: OutlineInputBorder()),
                  items: rejectionReasons
                      .map((r) => DropdownMenuItem(value: r.value, child: Text(r.label)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedReason = value ?? _selectedReason),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _remarksController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                if (_evidenceBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_evidenceBytes!, height: 180, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickEvidence(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickEvidence(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Rejection'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
