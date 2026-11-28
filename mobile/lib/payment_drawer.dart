import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'payment_allocation.dart';
import 'payment_history_page.dart';
import 'status_colors.dart';
import 'success_page.dart';
import 'widgets.dart';

String _dateInput(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A room member already fetched by the caller, with the full balance known
/// from `/api/landlord/rooms` (current pending + overdue carry-over).
class PaymentMemberPreset {
  const PaymentMemberPreset({
    required this.id,
    required this.name,
    required this.due,
  });

  final String id;
  final String name;

  /// Full balance: this cycle plus anything carried over.
  final double due;
}

/// Global record-payment drawer. Open it from anywhere: with no presets it
/// walks room -> member; the member's outstanding rent period is picked
/// automatically. Returns true when a payment was saved.
class PaymentDrawer extends StatefulWidget {
  const PaymentDrawer({
    super.key,
    required this.api,
    this.roomId,
    this.roomNumber,
    this.memberId,
    this.memberName,
    this.periodId,
    this.initialMembers,
    this.initialDue,
    this.initialPeriods,
  });

  final ApiClient api;
  final String? roomId;
  final String? roomNumber;
  final String? memberId;
  final String? memberName;
  final String? periodId;

  /// Members and their full balances already fetched by the caller, so the
  /// drawer does not need another rooms/room-detail request to pick someone.
  final List<PaymentMemberPreset>? initialMembers;

  /// Full balance (pending + overdue) from the rooms-list snapshot. Shown at
  /// once while the individual member request runs in the background.
  final double? initialDue;

  /// Rent periods when the caller has already fetched the member endpoint;
  /// lets the form be usable immediately instead of showing a spinner.
  final List<MemberPeriod>? initialPeriods;

  @override
  State<PaymentDrawer> createState() => _PaymentDrawerState();
}

class _PaymentDrawerState extends State<PaymentDrawer> {
  List<Room> _rooms = const [];
  bool _roomsLoading = false;

  List<PaymentMemberPreset> _members = const [];
  bool _membersLoading = false;

  List<MemberPeriod> _periods = const [];
  bool _dueLoading = true;

  /// The displayed periods came from the rooms-list snapshot, not the member
  /// endpoint, so their ids are not safe to submit until the background call
  /// has replaced them.
  bool _periodsProvisional = false;

  late final TextEditingController _amount;
  final _notes = TextEditingController();

  String? _roomId;
  String? _memberId;
  String _memberName = '';
  String? _periodId;
  String? _presetPeriodId;

  String _method = paymentMethods.first;
  bool _busy = false;
  String? _error;

  /// Snapshot shown on the confirmation screen after a successful save.
  _SavedPayment? _saved;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _roomId = widget.roomId;
    _memberId = widget.memberId;
    _memberName = widget.memberName ?? '';
    _presetPeriodId = widget.periodId;

    final presets = widget.initialMembers;
    if (presets != null && presets.isNotEmpty) {
      _members = presets;
      if (_memberId == null) {
        final owed = presets.where((m) => m.due > 0);
        final first = owed.isNotEmpty ? owed.first : presets.first;
        _memberId = first.id;
        _memberName = first.name;
      }
    }

    // Paint the balance the caller already has (rooms list or member profile)
    // before the per-member request answers.
    if (widget.initialPeriods != null && widget.initialPeriods!.isNotEmpty) {
      _periods = widget.initialPeriods!;
      _periodId = _pickPeriod(_periods, _presetPeriodId);
      _presetPeriodId = null;
      _dueLoading = false;
    } else {
      final due =
          widget.initialDue ??
          presets?.where((m) => m.id == _memberId).firstOrNull?.due ??
          0.0;
      if (due > 0) _seedSnapshotPeriod(due);
    }

    if (_memberId != null) {
      _loadPeriods(soft: !_dueLoading);
    } else if (_roomId != null && presets == null) {
      _loadRoomMembers(_roomId!);
    } else {
      _loadRooms();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  MemberPeriod? get _period {
    for (final p in _periods) {
      if (p.id == _periodId) return p;
    }
    return null;
  }

  /// Picks the period the payment should be booked against: a real id supplied
  /// by the caller first, otherwise the oldest outstanding cycle.
  String? _pickPeriod(List<MemberPeriod> periods, String? wanted) {
    MemberPeriod? picked;
    if (wanted != null) {
      for (final p in periods) {
        if (p.id == wanted) {
          picked = p;
          break;
        }
      }
    }
    picked ??= periods.where((p) => p.pending > 0).firstOrNull;
    picked ??= periods.firstOrNull;
    return picked?.id;
  }

  /// One provisional cycle holding the balance already known from the rooms
  /// list. Its id is not real, so submitting is blocked until the member
  /// endpoint replaces it.
  void _seedSnapshotPeriod(double due) {
    _periods = [
      MemberPeriod(
        id: 'snapshot-${_memberId ?? ''}',
        startIso: '',
        endIso: '',
        rent: due,
        paid: 0,
        pending: due,
        status: 'Pending',
      ),
    ];
    _periodId = _periods.first.id;
    _periodsProvisional = true;
    _dueLoading = false;
  }

  List<PaymentCycle> get _cycles =>
      buildAllocationOrder(_periods, _periodId ?? '');

  double get _outstandingTotal => overdueTotal(_cycles) + currentTotal(_cycles);

  String get _roomLabel {
    for (final room in _rooms) {
      if (room.id == _roomId) return 'Room ${room.roomNumber}';
    }
    return 'Select room';
  }

  Future<void> _loadRooms() async {
    setState(() {
      _roomsLoading = true;
      _dueLoading = true;
      _error = null;
    });
    try {
      final rooms = await widget.api.rooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _roomsLoading = false;
        _dueLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _roomsLoading = false;
        _dueLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _roomsLoading = false;
        _dueLoading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  Future<void> _selectRoom(String roomId) async {
    setState(() {
      _roomId = roomId;
      _memberId = null;
      _memberName = '';
      _members = const [];
      _periodId = null;
      _periods = const [];
      _amount.clear();
      _dueLoading = true;
      _error = null;
    });
    await _loadRoomMembers(roomId);
  }

  Future<void> _loadRoomMembers(String roomId) async {
    setState(() {
      _membersLoading = true;
      _dueLoading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.roomDetail(roomId);
      if (!mounted) return;
      final members = [
        for (final row in detail.rows)
          PaymentMemberPreset(id: row.memberId, name: row.name, due: row.totalDue),
      ];
      final owed = members.where((m) => m.due > 0);
      final first = owed.isNotEmpty ? owed.first : members.firstOrNull;
      setState(() {
        _members = members;
        _membersLoading = false;
        if (first == null) {
          _error = 'No active members in this room.';
          _memberId = null;
          _memberName = '';
          _dueLoading = false;
        } else {
          _memberId = first.id;
          _memberName = first.name;
        }
      });
      if (first != null) await _loadPeriods();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _dueLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _dueLoading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  void _selectMember(String memberId) {
    PaymentMemberPreset? preset;
    for (final m in _members) {
      if (m.id == memberId) {
        preset = m;
        break;
      }
    }
    final hasSnapshot = preset != null && preset.due > 0;
    setState(() {
      _memberId = memberId;
      _memberName = preset?.name ?? '';
      _periodId = null;
      _periods = const [];
      _periodsProvisional = false;
      _amount.clear();
      _dueLoading = true;
      _error = null;
      if (hasSnapshot) _seedSnapshotPeriod(preset!.due);
    });
    _loadPeriods(soft: hasSnapshot);
  }

  Future<void> _pickRoom() async {
    if (_rooms.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHeader(sheetContext, 'Select room'),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _rooms.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (sheetContext, index) {
                    final room = _rooms[index];
                    final selected = room.id == _roomId;
                    return PressScale(
                      child: ListTile(
                        title: Text('Room ${room.roomNumber}'),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(room.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != _roomId) await _selectRoom(picked);
  }

  Widget _sheetHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: theme.dividerColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickerField({
    required ThemeData theme,
    required String value,
    required VoidCallback? onTap,
  }) {
    return PressScale(
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: const Icon(Icons.keyboard_arrow_down),
            enabled: onTap != null,
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }

  /// [soft] keeps the snapshot on screen: no spinner and no clearing of an
  /// amount the user may already have typed while the request was in flight.
  Future<void> _loadPeriods({bool soft = false}) async {
    final memberId = _memberId;
    if (memberId == null) return;
    if (!soft) {
      setState(() {
        _dueLoading = true;
        _error = null;
      });
    }
    try {
      final periods = await widget.api.memberPeriods(memberId);
      if (!mounted) return;
      final pickedId = _pickPeriod(periods, _presetPeriodId);
      _presetPeriodId = null;
      setState(() {
        _periods = periods;
        _periodId = pickedId;
        _periodsProvisional = false;
        if (!soft) _amount.clear();
        _dueLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _dueLoading = false;
        if (!soft || _periods.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dueLoading = false;
        if (!soft || _periods.isEmpty) _error = 'Could not reach the server.';
      });
    }
  }

  DateTime _stampDate(MemberPeriod? period) {
    final now = DateTime.now();
    if (period == null) return now;
    final start = DateTime.tryParse(period.startIso);
    if (start != null && now.isBefore(start)) return start;
    return now;
  }

  /// Material 3 menu surface matching the app's cards and outlines.
  MenuStyle get _menuStyle => MenuStyle(
    backgroundColor: WidgetStateProperty.all(AppColors.card),
    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
    shadowColor: WidgetStateProperty.all(
      AppColors.mainText.withValues(alpha: 0.16),
    ),
    elevation: WidgetStateProperty.all(8),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 6)),
    side: WidgetStateProperty.all(const BorderSide(color: AppColors.border)),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    maximumSize: WidgetStateProperty.all(const Size(double.infinity, 280)),
  );

  IconData _methodIcon(String method) => switch (method) {
    'Cash' => Icons.money_outlined,
    'UPI' => Icons.qr_code_rounded,
    'Bank Transfer' => Icons.account_balance_outlined,
    _ => Icons.more_horiz,
  };

  /// Select-only Material 3 dropdown for the payment method. No keyboard, just
  /// a compact menu anchored to the field.
  Widget _methodDropdown() {
    return DropdownMenu<String>(
      // Rebuild when the selection changes so the field reflects state even
      // though initialSelection is only read when the widget is created.
      key: ValueKey('method-$_method'),
      expandedInsets: EdgeInsets.zero,
      initialSelection: _method,
      label: const Text('Method'),
      hintText: 'Choose method',
      enableFilter: false,
      enableSearch: false,
      selectOnly: true,
      requestFocusOnTap: false,
      menuHeight: 240,
      menuStyle: _menuStyle,
      leadingIcon: const Icon(
        Icons.payments_outlined,
        size: 20,
        color: AppColors.secondaryText,
      ),
      dropdownMenuEntries: [
        for (final method in paymentMethods)
          DropdownMenuEntry<String>(
            value: method,
            label: method,
            leadingIcon: Icon(
              _methodIcon(method),
              size: 20,
              color: AppColors.primary,
            ),
          ),
      ],
      onSelected: (value) {
        if (value != null) setState(() => _method = value);
      },
    );
  }

  /// Searchable Material 3 dropdown for the member. Each row shows the balance
  /// already known from the rooms snapshot, so the right person is easy to
  /// pick even in a full room.
  Widget _memberDropdown() {
    if (_members.isEmpty) {
      return _pickerField(theme: Theme.of(context), value: 'No members', onTap: null);
    }
    return DropdownMenu<String>(
      key: ValueKey('member-$_memberId'),
      expandedInsets: EdgeInsets.zero,
      initialSelection: _memberId,
      hintText: 'Search or select member',
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      menuHeight: 280,
      menuStyle: _menuStyle,
      leadingIcon: const CircleAvatar(
        radius: 12,
        backgroundColor: AppColors.skySoft,
        child: Icon(Icons.person_outline, size: 16, color: AppColors.sky),
      ),
      dropdownMenuEntries: [
        for (final member in _members)
          DropdownMenuEntry<String>(
            value: member.id,
            label: member.name,
            labelWidget: Row(
              children: [
                Expanded(
                  child: Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  inr(member.due),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: member.due > 0
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                ),
              ],
            ),
          ),
      ],
      onSelected: (value) {
        if (value != null && value != _memberId) _selectMember(value);
      },
    );
  }

  Future<void> _submit() async {
    final period = _period;
    final memberId = _memberId;
    if (memberId == null) {
      setState(() => _error = 'Choose a member first.');
      return;
    }
    if (period == null) {
      setState(() => _error = 'No rent period is available for this member.');
      return;
    }
    if (_periodsProvisional) {
      // The snapshot has no real rent-period id, so wait for the member
      // endpoint before sending a payment the server could reject.
      setState(
        () => _error = 'Confirming the latest dues. Please try again shortly.',
      );
      return;
    }
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (amount > _outstandingTotal + 0.01) {
      setState(
        () => _error =
            'Amount exceeds the outstanding balance (${inr(_outstandingTotal)}).',
      );
      return;
    }
    final paymentDate = _dateInput(_stampDate(period));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.recordPayment(
        rentPeriodId: period.id,
        amount: _amount.text.trim(),
        paymentDate: paymentDate,
        paymentMethod: _method,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _saved = _SavedPayment(
          amount: amount,
          memberName: _memberName,
          method: _method,
          date: paymentDate,
          roomNumber: widget.roomNumber,
          memberId: _memberId,
          roomId: _roomId,
        );
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Clears the amount fields but keeps the selected member/period, so the
  /// same flow can record the next payment without starting over.
  void _recordAnother() {
    setState(() {
      _saved = null;
      _amount.clear();
      _notes.clear();
      _error = null;
    });
  }

  /// Shows the saved record in context, then closes the drawer on the way out
  /// so the caller refreshes its totals.
  Future<void> _viewHistory() async {
    final saved = _saved;
    if (saved == null) return;
    await Navigator.of(context).push(
      smoothRoute(
        PaymentHistoryPage(
          api: widget.api,
          isAdmin: true,
          memberId: saved.memberId,
          memberName: saved.memberName,
          roomId: saved.roomId,
          roomNumber: saved.roomNumber,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    if (saved != null) {
      return SuccessScreen(
        title: 'Payment recorded successfully',
        message: '${inr(saved.amount)} recorded for ${saved.memberName}.',
        detailsTitle: 'Payment details',
        nextStep: 'The rent balance has been updated.',
        details: [
          SuccessDetail(
            label: 'Member',
            value: saved.memberName,
            icon: Icons.person_outline,
          ),
          SuccessDetail(
            label: 'Amount',
            value: inr(saved.amount),
            icon: Icons.currency_rupee,
          ),
          SuccessDetail(
            label: 'Method',
            value: saved.method,
            icon: Icons.payments_outlined,
          ),
          SuccessDetail(
            label: 'Date',
            value: saved.date,
            icon: Icons.calendar_today_outlined,
          ),
        ],
        onBack: () => Navigator.of(context).pop(true),
        actions: [
          SuccessAction(
            label: 'View history',
            icon: Icons.history,
            style: SuccessActionStyle.outlined,
            onPressed: _viewHistory,
          ),
          SuccessAction(
            label: 'Record another',
            icon: Icons.add_task,
            style: SuccessActionStyle.filled,
            onPressed: _recordAnother,
          ),
        ],
      );
    }
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _header(theme),
          Expanded(
            child: _dueLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
                    child: _form(context, theme),
                  ),
          ),
        ],
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
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Record Payment'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: AppColors.mainText.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PressScale(
                  enabled: !_busy,
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 104),
                child: Text(
                  _memberName.isEmpty ? 'Record Payment' : _memberName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total due',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                      if (_dueLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 4, bottom: 2),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        Text(
                          inr(_outstandingTotal),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _outstandingTotal > 0
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error!),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.roomId == null && _memberId == null) ...[
          _label(theme, 'Room *'),
          const SizedBox(height: 6),
          if (_roomsLoading)
            const SkeletonBlock(height: 56)
          else if (_rooms.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No rooms found.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                PressScale(
                  child: TextButton(
                    onPressed: _loadRooms,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            )
          else
            _pickerField(theme: theme, value: _roomLabel, onTap: _pickRoom),
          const SizedBox(height: 12),
        ],
        if (widget.memberId == null) ...[
          _label(theme, 'Member *'),
          const SizedBox(height: 6),
          if (_membersLoading)
            const SkeletonBlock(height: 56)
          else
            _memberDropdown(),
          const SizedBox(height: 12),
        ],
        if (_memberId != null && _periodId != null) ...[
          _label(theme, 'Payment Amount *'),
          const SizedBox(height: 6),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(
              labelText: 'Amount (₹)',
              prefixText: '₹ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (_amount.text.trim().isNotEmpty && _outstandingTotal > 0) ...[
            _allocationPreview(
              theme,
              double.tryParse(_amount.text.trim()) ?? 0,
            ),
            const SizedBox(height: 12),
          ],
          _methodDropdown(),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ],
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );

  Widget _allocationPreview(ThemeData theme, double amount) {
    final lines = previewAllocation(_cycles, amount);
    final applied = lines.fold<double>(0, (sum, line) => sum + line.applied);
    final unallocated = amount - applied;
    final remaining = math.max(0.0, _outstandingTotal - applied);

    return Card(
      color: unallocated > 0.004 ? AppColors.dangerSoft : AppColors.successSoft,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment Allocation',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  inr(amount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.mainText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Oldest dues are cleared first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 10),
            if (lines.isEmpty)
              Text(
                'Nothing outstanding to allocate this against.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondaryText,
                ),
              )
            else
              for (final line in lines) _allocationRow(theme, line),
            if (unallocated > 0.004) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${inr(unallocated)} more than the outstanding balance - the server will reject this.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 18),
            Row(
              children: [
                Text(
                  'Remaining rent',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const Spacer(),
                Text(
                  inr(remaining),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: remaining > 0 ? AppColors.danger : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _allocationRow(ThemeData theme, AllocationLine line) {
    final tag = line.cycle.overdue
        ? 'Overdue period'
        : line.cycle.advance
        ? 'Advance period'
        : 'Current period';
    return AllocationPeriodRow(
      label: line.cycle.label,
      amount: line.applied,
      overdue: line.cycle.overdue,
      caption: line.clears ? '$tag · cleared' : '$tag · ${inr(line.left)} left',
    );
  }
}

/// Opens the global record-payment drawer and returns true when a payment was
/// saved. Safe to call from any screen.
Future<bool> showPaymentDrawer(
  BuildContext context, {
  required ApiClient api,
  String? roomId,
  String? roomNumber,
  String? memberId,
  String? memberName,
  String? periodId,
  List<PaymentMemberPreset>? initialMembers,
  double? initialDue,
  List<MemberPeriod>? initialPeriods,
}) async {
  final result = await Navigator.of(context).push<bool>(
    DrawerRoute<bool>(
      page: PaymentDrawer(
        api: api,
        roomId: roomId,
        roomNumber: roomNumber,
        memberId: memberId,
        memberName: memberName,
        periodId: periodId,
        initialMembers: initialMembers,
        initialDue: initialDue,
        initialPeriods: initialPeriods,
      ),
      barrierColor: AppColors.mainText.withValues(alpha: 0.35),
    ),
  );
  return result == true;
}

/// Values captured at save time so the confirmation shows exactly what was
/// submitted.
class _SavedPayment {
  const _SavedPayment({
    required this.amount,
    required this.memberName,
    required this.method,
    required this.date,
    required this.roomNumber,
    required this.memberId,
    required this.roomId,
  });

  final double amount;
  final String memberName;
  final String method;
  final String date;
  final String? roomNumber;
  final String? memberId;
  final String? roomId;
}
