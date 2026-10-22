import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'status_colors.dart';
import 'widgets.dart';

String _dateInput(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class VacateMemberPage extends StatefulWidget {
  const VacateMemberPage({super.key, required this.api, required this.profile});

  final ApiClient api;
  final MemberProfile profile;

  @override
  State<VacateMemberPage> createState() => _VacateMemberPageState();
}

class _VacateMemberPageState extends State<VacateMemberPage> {
  final _note = TextEditingController();
  late DateTime _date;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = widget.profile.rentStartDate ?? DateTime(2000);
    final first = DateTime(start.year, start.month, start.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first.isAfter(today) ? today : first,
      lastDate: today,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.vacateMember(
        widget.profile.id,
        vacatingDate: _dateInput(_date),
        notes: _note.text.trim(),
      );
      if (!mounted) return;
      toastOk(context, '${widget.profile.name} vacated.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not vacate member.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final outstanding = profile.outstanding;
    return Scaffold(
      appBar: AppBar(
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text('Vacate member'),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Room ${profile.roomNumber} · ${profile.mobile}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Their payment history and any remaining dues will stay '
                    'available in Vacated Members.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
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
                title: const Text('Vacating date'),
                subtitle: Text(fmtDateMedium(_date)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: _busy ? null : _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 500,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
              ),
            ),
            if (outstanding > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Outstanding ${inr(outstanding)} will remain collectable '
                  'from Vacated Members.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.logout, size: 18),
                  label: AnimatedSwitcher(
                    duration: MotionDuration.quick,
                    child: _busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Vacate member', key: ValueKey('idle')),
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
