import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../models/project.dart';
import '../models/timesheet_entry.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../widgets/module_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _uuid = const Uuid();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<Project> _projects = [];
  Project? _selectedProject;
  PunchType? _lastPunchType;
  bool _isLoadingProjects = true;
  bool _isPunching = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadTodayStatus();

    // Ogni volta che la connessione torna disponibile, prova a sincronizzare
    // le timbrature accumulate offline (vedi SyncService).
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        SyncService.instance.syncPendingPunches();
      }
    });
    SyncService.instance.syncPendingPunches();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoadingProjects = true;
      _loadError = null;
    });
    try {
      final projects = await BcApiService.instance.fetchAssignedProjects();
      setState(() {
        _projects = projects;
        _selectedProject = projects.isNotEmpty ? projects.first : null;
      });
    } catch (_) {
      setState(() {
        _loadError =
            'Impossibile aggiornare l\'elenco cantieri (verifica la connessione).';
      });
    } finally {
      setState(() => _isLoadingProjects = false);
    }
  }

  Future<void> _loadTodayStatus() async {
    final todayPunches = await LocalDbService.instance.getTodayPunches();
    if (todayPunches.isEmpty) return;
    setState(() => _lastPunchType = todayPunches.last.type);
  }

  bool get _isCurrentlyIn =>
      _lastPunchType == PunchType.entrata || _lastPunchType == PunchType.finePausa;

  Future<void> _handlePunch() async {
    if (_selectedProject == null) return;

    final nextType = _isCurrentlyIn ? PunchType.uscita : PunchType.entrata;
    setState(() => _isPunching = true);

    final punch = TimesheetPunch(
      localId: _uuid.v4(),
      projectId: _selectedProject!.id,
      type: nextType,
      timestamp: DateTime.now(),
    );

    // Si salva sempre prima in locale: la timbratura non va persa anche se
    // la sincronizzazione con BC fallisce o il dispositivo è offline.
    await LocalDbService.instance.savePunch(punch);
    setState(() => _lastPunchType = nextType);

    await SyncService.instance.syncPendingPunches();

    if (!mounted) return;
    setState(() => _isPunching = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextType == PunchType.entrata ? 'Entrata registrata' : 'Uscita registrata',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openModulePlaceholder(String moduleName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Modulo "$moduleName": disponibile in un prossimo aggiornamento.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      body: RefreshIndicator(
        onRefresh: _loadProjects,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ciao,',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      'Marco Rossi', // TODO: nome utente reale, letto da BC
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                CircleAvatar(
                  backgroundColor: AppColors.accentBg,
                  child: Text(
                    'MR',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildPunchCard(),
            const SizedBox(height: 20),
            const Text('Moduli', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: [
                ModuleTile(
                  icon: Icons.work_outline,
                  iconColor: AppColors.primary,
                  label: 'Ore progetti',
                  onTap: () => _openModulePlaceholder('Ore progetti'),
                ),
                ModuleTile(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF0F6E56),
                  label: 'Bollettino',
                  onTap: () => _openModulePlaceholder('Bollettino'),
                ),
                ModuleTile(
                  icon: Icons.beach_access_outlined,
                  iconColor: const Color(0xFF993C1D),
                  label: 'Ferie/assenze',
                  onTap: () => _openModulePlaceholder('Ferie/assenze'),
                ),
                ModuleTile(
                  icon: Icons.receipt_long_outlined,
                  iconColor: const Color(0xFF534AB7),
                  label: 'Note spese',
                  onTap: () => _openModulePlaceholder('Note spese'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPunchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cantiere corrente',
              style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          _isLoadingProjects
              ? const SizedBox(height: 20, child: LinearProgressIndicator())
              : DropdownButton<Project>(
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: _selectedProject,
                  hint: const Text('Seleziona un cantiere'),
                  items: _projects
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.description)))
                      .toList(),
                  onChanged: (p) => setState(() => _selectedProject = p),
                ),
          if (_loadError != null) ...[
            const SizedBox(height: 4),
            Text(_loadError!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedProject == null || _isPunching) ? null : _handlePunch,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCurrentlyIn ? AppColors.danger : AppColors.success,
              ),
              icon: Icon(
                _isCurrentlyIn ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                size: 18,
              ),
              label: Text(_isCurrentlyIn ? 'Timbra uscita' : 'Timbra entrata'),
            ),
          ),
        ],
      ),
    );
  }
}
