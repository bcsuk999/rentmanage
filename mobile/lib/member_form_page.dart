import 'package:flutter/material.dart';

import 'api.dart';
import 'motion.dart';
import 'widgets.dart';

String _dateInput(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Add or edit a member. Returns true when a member was created or updated.
class MemberFormPage extends StatefulWidget {
  const MemberFormPage({
    super.key,
    required this.api,
    required this.roomId,
    required this.roomNumber,
    this.member,
  });

  final ApiClient api;
  final String roomId;
  final String roomNumber;

  /// Existing member to edit; null adds a new one.
  final RoomMemberFormData? member;

  bool get isEdit => member != null;

  @override
  State<MemberFormPage> createState() => _MemberFormPageState();
}

/// Minimal member data needed to populate the edit form.
class RoomMemberFormData {
  const RoomMemberFormData({
    required this.id,
    required this.name,
    required this.mobile,
    required this.monthlyRent,
    required this.rentStartDate,
    this.aadhaarNumber,
  });

  final String id;
  final String name;
  final String mobile;
  final double monthlyRent;
  final DateTime rentStartDate;
  final String? aadhaarNumber;
}

class _MemberFormPageState extends State<MemberFormPage> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _rent = TextEditingController();
  final _aadhaar = TextEditingController();
  late DateTime _start;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _start = m?.rentStartDate ?? DateTime.now();
    if (m != null) {
      _name.text = m.name;
      _mobile.text = m.mobile;
      _rent.text = m.monthlyRent.toStringAsFixed(0);
      _aadhaar.text = m.aadhaarNumber ?? '';
    }
  }

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
    final payload = {
      'name': _name.text.trim(),
      'mobile': _mobile.text.trim(),
      'monthlyRent': _rent.text.trim(),
      'rentStartDate': _dateInput(_start),
      if (_aadhaar.text.trim().isNotEmpty) 'aadhaarNumber': _aadhaar.text.trim(),
    };
    try {
      if (widget.isEdit) {
        await widget.api.updateMember(widget.member!.id, payload);
        if (!mounted) return;
        toastOk(context, '${_name.text.trim()} updated.');
      } else {
        await widget.api.addMember(widget.roomId, payload);
        if (!mounted) return;
        toastOk(context, '${_name.text.trim()} added to Room ${widget.roomNumber}.');
      }
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
      appBar: AppBar(title: Text('${widget.isEdit ? 'Edit' : 'Add'} member · Room ${widget.roomNumber}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              ShakeOnError(
                trigger: _error,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!),
                ),
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
              child: AnimatedSwitcher(
                duration: MotionDuration.quick,
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.isEdit ? 'Save changes' : 'Add member',
                        key: const ValueKey('idle')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
