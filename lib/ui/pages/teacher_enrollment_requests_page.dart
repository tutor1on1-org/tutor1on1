import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/marketplace_api_service.dart';

class TeacherEnrollmentRequestsPage extends StatefulWidget {
  const TeacherEnrollmentRequestsPage({super.key});

  @override
  State<TeacherEnrollmentRequestsPage> createState() =>
      _TeacherEnrollmentRequestsPageState();
}

class _TeacherEnrollmentRequestsPageState
    extends State<TeacherEnrollmentRequestsPage> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _error;
  List<TeacherRequestSummary> _requests = [];
  List<TeacherQuitRequestSummary> _quitRequests = [];

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _api = MarketplaceApiService(secureStorage: services.secureStorage);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await _api.listTeacherRequests();
      final quitRequests = await _api.listTeacherQuitRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = requests;
        _quitRequests = quitRequests;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.enrollmentRequestsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context, l10n)
              : (_requests.isEmpty && _quitRequests.isEmpty)
                  ? Center(child: Text(l10n.enrollmentRequestsEmpty))
                  : ListView(
                      children: [
                        if (_requests.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Enrollment requests',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ..._requests.map(
                          (request) =>
                              _buildRequestTile(context, l10n, request),
                        ),
                        if (_quitRequests.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Quit course requests',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ..._quitRequests.map(
                          (request) =>
                              _buildQuitRequestTile(context, l10n, request),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildError(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.marketplaceLoadFailed(_error ?? '')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _load,
            child: Text(l10n.retryButton),
          ),
        ],
      ),
    );
  }

  Widget _buildQuitRequestTile(
    BuildContext context,
    AppLocalizations l10n,
    TeacherQuitRequestSummary request,
  ) {
    final detail = request.reason.trim().isEmpty
        ? 'No reason provided.'
        : request.reason.trim();
    return Card(
      child: ListTile(
        title: Text(
          '${request.studentUsername} requests to quit ${request.courseSubject}',
        ),
        subtitle: Text(detail),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _resolveQuitRequest(context, request, true),
              child: Text(l10n.enrollmentApproveButton),
            ),
            TextButton(
              onPressed: () => _resolveQuitRequest(context, request, false),
              child: Text(l10n.enrollmentRejectButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestTile(
    BuildContext context,
    AppLocalizations l10n,
    TeacherRequestSummary request,
  ) {
    return Card(
      child: ListTile(
        title: Text(
          l10n.enrollmentRequestTitle(
            request.studentUsername,
            request.courseSubject,
          ),
        ),
        subtitle: request.message.isNotEmpty
            ? Text(request.message)
            : Text(l10n.enrollmentRequestNoMessage),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _resolveRequest(context, request, true),
              child: Text(l10n.enrollmentApproveButton),
            ),
            TextButton(
              onPressed: () => _resolveRequest(context, request, false),
              child: Text(l10n.enrollmentRejectButton),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveRequest(
    BuildContext context,
    TeacherRequestSummary request,
    bool approve,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      if (approve) {
        await _api.approveRequest(request.requestId);
      } else {
        await _api.rejectRequest(request.requestId);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enrollmentRequestUpdated)),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceRequestFailed('$error'))),
      );
    }
  }

  Future<void> _resolveQuitRequest(
    BuildContext context,
    TeacherQuitRequestSummary request,
    bool approve,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      if (approve) {
        await _api.approveQuitRequest(request.requestId);
      } else {
        await _api.rejectQuitRequest(request.requestId);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enrollmentRequestUpdated)),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.marketplaceRequestFailed('$error'))),
      );
    }
  }
}
