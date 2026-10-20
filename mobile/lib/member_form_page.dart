import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
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
      if (_aadhaar.text.trim().isNotEmpty)
        'aadhaarNumber': _aadhaar.text.trim(),
    };
    try {
      if (widget.isEdit) {
        await widget.api.updateMember(widget.member!.id, payload);
        if (!mounted) return;
        toastOk(context, '${_name.text.trim()} updated.');
      } else {
        await widget.api.addMember(widget.roomId, payload);
        if (!mounted) return;
        toastOk(
          context,
          '${_name.text.trim()} added to Room ${widget.roomNumber}.',
        );
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
      appBar: AppBar(
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.isEdit
              ? 'Edit member · Room ${widget.roomNumber}'
              : 'Add member to Room ${widget.roomNumber}',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              decoration: const InputDecoration(
                labelText: 'Mobile (10 digits) *',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(left: 12, right: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [_IndiaFlag(), SizedBox(width: 6), Text('+91')],
                  ),
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
              ),
              keyboardType: TextInputType.number,
              maxLength: 10,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rent,
              decoration: const InputDecoration(
                labelText: 'Monthly rent (₹) *',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aadhaar,
              decoration: const InputDecoration(
                labelText: 'Aadhaar (optional, 12 digits)',
              ),
              keyboardType: TextInputType.number,
              maxLength: 12,
            ),
            const SizedBox(height: 12),
            PressScale(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.border),
                ),
                title: const Text('Rent start date'),
                subtitle: Text(_dateInput(_start)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: _pickDate,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          boxShadow: [
            BoxShadow(
              color: AppColors.mainText.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SizedBox(
              height: 50,
              child: PressScale(
                enabled: !_busy,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: AnimatedSwitcher(
                    duration: MotionDuration.quick,
                    child: _busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.isEdit ? 'Save changes' : 'Add member',
                            key: const ValueKey('idle'),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny Indian-flag mark shown ahead of the +91 prefix in the mobile field.
class _IndiaFlag extends StatelessWidget {
  const _IndiaFlag();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        width: 20,
        height: 14,
        decoration: const BoxDecoration(color: Colors.white),
        child: Column(
          children: [
            Expanded(child: Container(color: const Color(0xFFFF9933))),
            Expanded(
              child: Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF000080),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Expanded(child: Container(color: const Color(0xFF138808))),
          ],
        ),
      ),
    );
  }
}
