import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'widgets.dart';

/// Edit a room on its own page, matching the member edit form. Returns true
/// when the room was updated.
class RoomFormPage extends StatefulWidget {
  const RoomFormPage({super.key, required this.api, required this.room});

  final ApiClient api;
  final Room room;

  @override
  State<RoomFormPage> createState() => _RoomFormPageState();
}

class _RoomFormPageState extends State<RoomFormPage> {
  final _number = TextEditingController();
  final _capacity = TextEditingController();
  final _notes = TextEditingController();
  late String _status;
  bool _busy = false;
  String? _error;

  /// Set once the page is being popped, so the [finally] block does not
  /// rebuild a form that is on its way out.
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    _number.text = widget.room.roomNumber;
    _capacity.text = widget.room.capacity.toString();
    _status = widget.room.status;
    _notes.text = widget.room.notes ?? '';
  }

  @override
  void dispose() {
    _number.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final capacity = int.tryParse(_capacity.text.trim()) ?? 0;
    if (_number.text.trim().isEmpty || capacity < 1) {
      setState(
        () => _error = 'Enter a room name and a capacity of at least 1.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.updateRoom(
        roomId: widget.room.id,
        roomNumber: _number.text.trim(),
        capacity: capacity,
        status: _status,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (!mounted) return;
      _popping = true;
      toastOk(context, 'Room ${_number.text.trim()} updated.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted && !_popping) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leading: PressScale(
          enabled: !_busy,
          child: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Edit Room ${widget.room.roomNumber}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (_error != null) ...[
              ShakeOnError(
                trigger: _error,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Room name'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              decoration: const InputDecoration(labelText: 'Capacity'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                'Empty',
                'Occupied',
                'Maintenance',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _status = v ?? 'Empty'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
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
                        : const Text('Save changes', key: ValueKey('idle')),
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
