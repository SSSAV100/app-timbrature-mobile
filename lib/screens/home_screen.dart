import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../models/app_user.dart';
import '../models/project.dart';
import '../models/timesheet_entry.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../widgets/module_tile.dart';
import 'approvals_screen.dart';
import 'bollettino_screen.dart';
import 'ferie_assenze_screen.dart';
import 'note_spese_screen.dart';
import 'ore_progetti_screen.dart';

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

  AppUser? _currentUser;
  int? _pendingApprovalsCount;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadTodayStatus();
    _loadCurrentUser();

    // Ogni volta che la connessione torna disponibile, prova a sincronizzare
    // le timbrature accumulate offline (vedi SyncService).
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        SyncService.instance.syncAll();
      }
    });
    SyncService.instance.syncAll();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Legge l'utente corrente e i suoi ruoli da Business Central. Se l'utente
  /// ha un ruolo di approvatore, legge anche il numero di richieste in
  /// sospeso, per mostrare il badge sulla piastrella Approvazioni. Se la
  /// richiesta fallisce (es. offline al primo avvio), la piastrella
  /// Approvazioni resta semplicemente nascosta: non è un errore bloccante,
  /// e i ruoli vengono ricontrollati ad ogni apertura dell'app.
  Future<void> _loadCurrentUser() async {
    try {
      final user = await BcApiService.instance.fetchCurrentUser();
      setState(() => _currentUser = user);
      if (user.canApprove) {
        final approvals = await BcApiService.instance.fetchPendingApprovals();
        setState(() => _pendingApprovalsCount = approvals.length);
      }
    } catch (e, stackTrace) {
      developer.log('fetchCurrentUser fallita', name: 'HomeScreen', error: e, stackTrace: stackTrace);
      // Nessun ruolo rilevato: la piastrella Approvazioni resta nascosta.
    }
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
    } catch (e, stackTrace) {
      developer.log('fetchAssignedProjects fallita', name: 'HomeScreen', error: e, stackTrace: stackTrace);
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

    // Cattura un solo punto GPS (non un tracciamento continuo), usato da
    // Business Central per calcolare la zona di trasferta. Se il permesso
    // è negato o il GPS non è disponibile, la timbratura procede comunque
    // senza coordinate: non deve mai essere bloccata da questo.
    final position = await LocationService.getCurrentPositionOrNull();

    final punch = TimesheetPunch(
      localId: _uuid.v4(),
      projectId: _selectedProject!.id,
      type: nextType,
      timestamp: DateTime.now(),
      latitude: position?.latitude,
      longitude: position?.longitude,
    );

    // Si salva sempre prima in locale: la timbratura non va persa anche se
    // la sincronizzazione con BC fallisce o il dispositivo è offline.
    await LocalDbService.instance.savePunch(punch);
    setState(() => _lastPunchType = nextType);

    await SyncService.instance.syncAll();

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ciao,',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      _currentUser?.fullName ?? '...',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                CircleAvatar(
                  backgroundColor: AppColors.accentBg,
                  child: Text(
                    _initials(_currentUser?.fullName),
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OreProgettiScreen()),
                  ),
                ),
                ModuleTile(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF0F6E56),
                  label: 'Bollettino',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BollettinoScreen()),
                  ),
                ),
                ModuleTile(
                  icon: Icons.beach_access_outlined,
                  iconColor: const Color(0xFF993C1D),
                  label: 'Ferie/assenze',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FerieAssenzeScreen()),
                  ),
                ),
                ModuleTile(
                  icon: Icons.receipt_long_outlined,
                  iconColor: const Color(0xFF534AB7),
                  label: 'Note spese',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NoteSpeseScreen()),
                  ),
                ),
                if (_currentUser?.canApprove == true)
                  ModuleTile(
                    icon: Icons.fact_check_outlined,
                    iconColor: const Color(0xFFB8860B),
                    label: 'Approvazioni',
                    badgeCount: _pendingApprovalsCount,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ApprovalsScreen()),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return '?';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
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
