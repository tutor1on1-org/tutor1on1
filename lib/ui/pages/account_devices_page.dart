import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';
import '../../state/auth_controller.dart';
import '../quit_app_flow.dart';

class AccountDevicesPage extends StatefulWidget {
  const AccountDevicesPage({super.key});

  @override
  State<AccountDevicesPage> createState() => _AccountDevicesPageState();
}

class _AccountDevicesPageState extends State<AccountDevicesPage> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _error;
  List<AccountDeviceSummary> _devices = const [];

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
      final devices = await _api.listAccountDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
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

  Future<void> _deleteDevice(AccountDeviceSummary device) async {
    final deletingCurrent = device.isCurrent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete device'),
        content: Text(
          deletingCurrent
              ? 'Delete "${device.deviceName}"? This device will be signed out immediately.'
              : 'Delete "${device.deviceName}" from your registered devices?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    if (deletingCurrent) {
      final pinConfirmed =
          await AppQuitFlow.confirmTeacherPinIfRequired(context);
      if (!pinConfirmed || !mounted) {
        return;
      }
    }
    try {
      final result = await _api.deleteAccountDevice(device.deviceKey);
      if (!mounted) {
        return;
      }
      if (result.deletedCurrentDevice) {
        await context.read<AuthController>().logout();
        if (!mounted) {
          return;
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device deleted.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Devices'),
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
                    children: [
                      Text(
                        _devices.length <= 1
                            ? 'You cannot delete the last registered device.'
                            : 'Delete old devices you no longer use. Deleting this device signs it out immediately.',
                      ),
                      const SizedBox(height: 16),
                      ..._devices.map(
                        (device) => Card(
                          child: ListTile(
                            leading: Icon(
                              device.online
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              color: device.online ? Colors.green : Colors.grey,
                              size: 14,
                            ),
                            title: Text(
                              device.isCurrent
                                  ? '${device.deviceName} (Current)'
                                  : device.deviceName,
                            ),
                            subtitle: Text(_deviceSubtitle(device)),
                            trailing: IconButton(
                              tooltip: _devices.length <= 1
                                  ? 'Cannot delete last device'
                                  : 'Delete device',
                              onPressed: _devices.length <= 1
                                  ? null
                                  : () => _deleteDevice(device),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _deviceSubtitle(AccountDeviceSummary device) {
    final timezoneLabel = device.timezoneName.trim().isEmpty
        ? 'UTC${_offsetLabel(device.timezoneOffsetMinutes)}'
        : device.timezoneName.trim();
    final appVersion = device.appVersion.trim().isEmpty
        ? ''
        : ' • ${device.appVersion.trim()}';
    final lastSeen = device.lastSeenAt.trim().isEmpty
        ? 'Never seen'
        : device.lastSeenAt.trim();
    final status = device.online ? 'Online' : 'Offline';
    return '$status • $lastSeen • ${device.platform} • $timezoneLabel$appVersion';
  }

  String _offsetLabel(int minutes) {
    final sign = minutes >= 0 ? '+' : '-';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final mins = absolute % 60;
    return '$sign${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }
}
