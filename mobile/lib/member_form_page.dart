import 'package:flutter/material.dart';

import 'api.dart';

String _dateInput(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Add-member form (admin only). Returns true when a member was created.
class MemberFormPage extends StatefulWidget {
  const MemberFormPage({super.key, required this.api, required this.roomId, required this.roomNumber});

  final ApiClient api;
  final String roomId;
  final String roomNumber;

  @override
  State<MemberFormPage> createState() => _MemberFormPageState();
}

class _MemberFormPageState extends State<MemberFormPage> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _rent = TextEditingController();
  final _aadhaar = TextEditingController();
  DateTime _start = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _rent.dispose();
    _aadhaar.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.addMember(widget.roomId, {
        'name': _name.text.trim(),
        'mobile': _mobile.text.trim(),
        'monthlyRent': _rent.text.trim(),
        'rentStartDate': _dateInput(_start),
        if (_aadhaar.text.trim().isNotEmpty) 'aadhaarNumber': _aadhaar.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_name.text.trim()} added to Room ${widget.roomNumber}.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add member · Room ${widget.roomNumber}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobile,
              decoration: const InputDecoration(labelText: 'Mobile (10 digits) *', hintText: '9810010001'),
              keyboardType: TextInputType.number,
              maxLength: 10,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rent,
              decoration: const InputDecoration(labelText: 'Monthly rent (₹) *', hintText: '8000'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aadhaar,
              decoration: const InputDecoration(labelText: 'Aadhaar (optional, 12 digits)'),
              keyboardType: TextInputType.number,
              maxLength: 12,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rent start date'),
              subtitle: Text(_dateInput(_start)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add member'),
            ),
          ],
        ),
      ),
    );
  }
}
