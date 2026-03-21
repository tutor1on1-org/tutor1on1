import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';

class TeacherStudyModePage extends StatefulWidget {
  const TeacherStudyModePage({super.key});

  @override
  State<TeacherStudyModePage> createState() => _TeacherStudyModePageState();
}

class _TeacherStudyModePageState extends State<TeacherStudyModePage> {
  static const Duration _refreshInterval = Duration(seconds: 30);

  late final MarketplaceApiService _api;
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;
  List<TeacherStudentDeviceSummary> _students = const [];

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _api = MarketplaceApiService(secureStorage: services.secureStorage);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      _refreshTimer = Timer.periodic(_refreshInterval, (_) async {
        await _load(background: true);
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!mounted) {
      return;
    }
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final students = await _api.listTeacherStudentDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        _students = students;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _setManualOverride({
    required TeacherStudentDeviceSummary student,
    required bool enabled,
  }) async {
    if (!student.hasTeacherControlPin) {
      _showMessage('Set remote study control PIN in Settings first.');
      return;
    }
    final controlPin = await _promptControlPin();
    if (controlPin == null || controlPin.isEmpty) {
      return;
    }
    try {
      await _api.setStudentStudyModeOverride(
        studentUserId: student.studentUserId,
        enabled: enabled,
        controlPin: controlPin,
      );
      if (!mounted) {
        return;
      }
      _showMessage(
          enabled ? 'Study mode turned on.' : 'Study mode turned off.');
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error');
    }
  }

  Future<String?> _promptControlPin() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Teacher control PIN'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'PIN'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Study Mode'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _students.isEmpty
                        ? const [
                            Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No enrolled students found.'),
                            ),
                          ]
                        : _students
                            .map(
                              (student) => Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        student.studentUsername,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      if (student.teacherManualOverride != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Manual override: ${student.teacherManualOverride! ? 'on' : 'off'}',
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      if (!student.hasTeacherControlPin)
                                        const Text(
                                          'Remote control PIN is not configured.',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      if (student.devices.isEmpty)
                                        const Text('No registered devices.')
                                      else
                                        ...student.devices.map(
                                          (device) => ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              device.online
                                                  ? Icons.circle
                                                  : Icons.circle_outlined,
                                              color: device.online
                                                  ? Colors.green
                                                  : Colors.grey,
                                              size: 14,
                                            ),
                                            title: Text(device.deviceName),
                                            trailing: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  device.online
                                                      ? 'Online'
                                                      : 'Offline',
                                                ),
                                                Text(
                                                  _lastSeenLabel(
                                                    device.lastSeenAt,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: Text(
                                              '${device.platform} • '
                                              '${device.timezoneName.isEmpty ? 'UTC${_offsetLabel(device.timezoneOffsetMinutes)}' : device.timezoneName} • '
                                              'current=${device.currentStudyModeEnabled ? 'on' : 'off'} • '
                                              'effective=${device.effectiveStudyModeEnabled ? 'on' : 'off'}'
                                              '${device.effectiveScheduleLabel.isEmpty ? '' : ' • ${device.effectiveScheduleLabel}'}',
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ElevatedButton(
                                            onPressed: () => _setManualOverride(
                                              student: student,
                                              enabled: true,
                                            ),
                                            child: const Text('Turn On'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => _setManualOverride(
                                              student: student,
                                              enabled: false,
                                            ),
                                            child: const Text('Turn Off'),
                                          ),
                                          OutlinedButton(
                                            onPressed: () async {
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TeacherStudyModeSchedulesPage(
                                                    student: student,
                                                  ),
                                                ),
                                              );
                                              await _load(background: true);
                                            },
                                            child: const Text('Schedules'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
      ),
    );
  }

  String _offsetLabel(int minutes) {
    final sign = minutes >= 0 ? '+' : '-';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final mins = absolute % 60;
    return '$sign${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  String _lastSeenLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Never seen';
    }
    return trimmed;
  }
}

class TeacherStudyModeSchedulesPage extends StatelessWidget {
  const TeacherStudyModeSchedulesPage({
    super.key,
    required this.student,
  });

  final TeacherStudentDeviceSummary student;

  @override
  Widget build(BuildContext context) {
    return _TeacherStudyModeSchedulesBody(student: student);
  }
}

class _TeacherStudyModeSchedulesBody extends StatefulWidget {
  const _TeacherStudyModeSchedulesBody({
    required this.student,
  });

  final TeacherStudentDeviceSummary student;

  @override
  State<_TeacherStudyModeSchedulesBody> createState() =>
      _TeacherStudyModeSchedulesBodyState();
}

class _TeacherStudyModeSchedulesBodyState
    extends State<_TeacherStudyModeSchedulesBody> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _error;
  List<StudyModeScheduleSummary> _schedules = const [];

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _api = MarketplaceApiService(secureStorage: services.secureStorage);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedules = await _api
          .listStudentStudyModeSchedules(widget.student.studentUserId);
      if (!mounted) {
        return;
      }
      setState(() {
        _schedules = schedules;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Schedules: ${widget.student.studentUsername}'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => _createOneTimeSchedule(enabled: true),
                  child: const Text('Add one-time ON'),
                ),
                ElevatedButton(
                  onPressed: () => _createOneTimeSchedule(enabled: false),
                  child: const Text('Add one-time OFF'),
                ),
                ElevatedButton(
                  onPressed: () => _createWeeklySchedule(enabled: true),
                  child: const Text('Add weekly ON'),
                ),
                ElevatedButton(
                  onPressed: () => _createWeeklySchedule(enabled: false),
                  child: const Text('Add weekly OFF'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent))
            else if (_schedules.isEmpty)
              const Text('No schedules.')
            else
              ..._schedules.map(
                (schedule) => Card(
                  child: ListTile(
                    title: Text(schedule.displayLabel),
                    subtitle: Text(schedule.updatedAt),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteSchedule(schedule),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSchedule(StudyModeScheduleSummary schedule) async {
    final controlPin = await _promptControlPin();
    if (controlPin == null || controlPin.isEmpty) {
      return;
    }
    try {
      await _api.deleteStudentStudyModeSchedule(
        studentUserId: widget.student.studentUserId,
        scheduleId: schedule.scheduleId,
        controlPin: controlPin,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Schedule deleted.');
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error');
    }
  }

  Future<void> _createOneTimeSchedule({required bool enabled}) async {
    final startDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now(),
    );
    if (startDate == null || !mounted) {
      return;
    }
    final startTime =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (startTime == null || !mounted) {
      return;
    }
    final endDate = await showDatePicker(
      context: context,
      firstDate: startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: startDate,
    );
    if (endDate == null || !mounted) {
      return;
    }
    final endTime =
        await showTimePicker(context: context, initialTime: startTime);
    if (endTime == null || !mounted) {
      return;
    }
    final controlPin = await _promptControlPin();
    if (controlPin == null || controlPin.isEmpty) {
      return;
    }
    final offset = _preferredDevice?.timezoneOffsetMinutes ?? 0;
    final timezoneName = _preferredDevice?.timezoneName ?? '';
    final startUtc = _studentLocalToUtc(
      date: startDate,
      time: startTime,
      timezoneOffsetMinutes: offset,
    );
    final endUtc = _studentLocalToUtc(
      date: endDate,
      time: endTime,
      timezoneOffsetMinutes: offset,
    );
    try {
      await _api.createStudentStudyModeSchedule(
        studentUserId: widget.student.studentUserId,
        mode: 'one_time',
        enabled: enabled,
        controlPin: controlPin,
        startAtUtc: startUtc.toIso8601String(),
        endAtUtc: endUtc.toIso8601String(),
        timezoneNameSnapshot: timezoneName,
        timezoneOffsetSnapshotMinutes: offset,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Schedule created.');
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error');
    }
  }

  Future<void> _createWeeklySchedule({required bool enabled}) async {
    var weekday = DateTime.now().weekday;
    final startTime =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (startTime == null || !mounted) {
      return;
    }
    final endTime =
        await showTimePicker(context: context, initialTime: startTime);
    if (endTime == null || !mounted) {
      return;
    }
    final selectedWeekday = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select weekday'),
          content: DropdownButtonFormField<int>(
            initialValue: weekday,
            items: List.generate(
              7,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text(_weekdayLabel(index + 1)),
              ),
            ),
            onChanged: (value) {
              if (value != null) {
                setState(() => weekday = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(weekday),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (selectedWeekday == null || !mounted) {
      return;
    }
    final controlPin = await _promptControlPin();
    if (controlPin == null || controlPin.isEmpty) {
      return;
    }
    try {
      await _api.createStudentStudyModeSchedule(
        studentUserId: widget.student.studentUserId,
        mode: 'weekly',
        enabled: enabled,
        controlPin: controlPin,
        localWeekday: selectedWeekday,
        localStartMinuteOfDay: startTime.hour * 60 + startTime.minute,
        localEndMinuteOfDay: endTime.hour * 60 + endTime.minute,
        timezoneNameSnapshot: _preferredDevice?.timezoneName ?? '',
        timezoneOffsetSnapshotMinutes:
            _preferredDevice?.timezoneOffsetMinutes ?? 0,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Schedule created.');
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error');
    }
  }

  TeacherStudentDevice? get _preferredDevice {
    for (final device in widget.student.devices) {
      if (device.online) {
        return device;
      }
    }
    return widget.student.devices.isEmpty ? null : widget.student.devices.first;
  }

  DateTime _studentLocalToUtc({
    required DateTime date,
    required TimeOfDay time,
    required int timezoneOffsetMinutes,
  }) {
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)
        .subtract(Duration(minutes: timezoneOffsetMinutes));
  }

  Future<String?> _promptControlPin() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Teacher control PIN'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'PIN'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Day';
    }
  }
}
