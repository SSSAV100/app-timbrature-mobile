import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/assenza_request.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../widgets/sync_status_dot.dart';
import 'assenza_form_screen.dart';

class FerieAssenzeScreen extends StatefulWidget {
  const FerieAssenzeScreen({super.key});

  @override
  State<FerieAssenzeScreen> createState() => _FerieAssenzeScreenState();
}

class _FerieAssenzeScreenState extends State<FerieAssenzeScreen> {
  double? _balanceHours;
  String? _balanceError;
  List<AssenzaRequest> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        BcApiService.instance.fetchVacationBalanceHours(),
        LocalDbService.instance.getAllAssenze(),
      ]);
      setState(() {
        _balanceHours = results[0] as double;
        _requests = results[1] as List<AssenzaRequest>;
        _balanceError = null;
      });
    } catch (_) {
      final requests = await LocalDbService.instance.getAllAssenze();
      setState(() {
        _requests = requests;
        _balanceError = 'Saldo non disponibile (verifica la connessione).';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openNewRequest() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AssenzaFormScreen()),
    );
    if (result == true) {
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ferie e assenze')),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            _buildBalanceCard(),
            const SizedBox(height: 20),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_requests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nessuna richiesta ancora inviata.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._requests.map(_buildRequestTile),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewRequest,
        icon: const Icon(Icons.add),
        label: const Text('Nuova richiesta'),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo ferie/permessi', style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          Text(
            _balanceHours != null ? '${_balanceHours!.toStringAsFixed(1)} h' : '—',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          if (_balanceError != null) ...[
            const SizedBox(height: 4),
            Text(_balanceError!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestTile(AssenzaRequest request) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final sameDay = request.startDate.year == request.endDate.year &&
        request.startDate.month == request.endDate.month &&
        request.startDate.day == request.endDate.day;
    final period = sameDay
        ? dateFormat.format(request.startDate)
        : '${dateFormat.format(request.startDate)} - ${dateFormat.format(request.endDate)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          SyncStatusDot(status: request.status),
          const SizedBox(width: 10),
          Icon(_iconFor(request.type), size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_labelFor(request.type), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(period, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text('${request.hoursPerDay.toStringAsFixed(1)} h/g', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  IconData _iconFor(AssenzaType type) => switch (type) {
        AssenzaType.ferie => Icons.beach_access_outlined,
        AssenzaType.malattia => Icons.medical_services_outlined,
        AssenzaType.infortunio => Icons.warning_amber_outlined,
      };

  String _labelFor(AssenzaType type) => switch (type) {
        AssenzaType.ferie => 'Ferie',
        AssenzaType.malattia => 'Malattia',
        AssenzaType.infortunio => 'Infortunio',
      };
}
