import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/app_user.dart';
import '../services/bc_api_service.dart';
import '../services/sync_service.dart';
import '../widgets/module_tile.dart';
import 'approvals_screen.dart';
import 'ferie_assenze_screen.dart';
import 'note_spese_screen.dart';
import 'ore_progetti_screen.dart';
import 'service_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Stato della lettura dei cantieri: offline o errore di BC.
  String? _loadError;

  /// Errore nella lettura del profilo (GET /me): senza profilo mancano nome,
  /// Approvazioni e Interventi, quindi va detto invece di mostrare solo "...".
  String? _userError;

  AppUser? _currentUser;
  int? _pendingApprovalsCount;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadCurrentUser();

    // Ogni volta che la connessione torna disponibile, invia quanto
    // registrato offline (vedi SyncService).
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
      setState(() {
        _currentUser = user;
        _userError = null;
      });
      if (user.canApprove) {
        final approvals = await BcApiService.instance.fetchPendingApprovals();
        setState(() => _pendingApprovalsCount = approvals.length);
      }
    } catch (e, stackTrace) {
      developer.log('fetchCurrentUser fallita', name: 'HomeScreen', error: e, stackTrace: stackTrace);
      // Senza profilo le piastrelle Approvazioni e Interventi restano nascoste.
      if (mounted) {
        setState(() => _userError = e is BcApiException
            ? 'Profilo non letto da Business Central: $e'
            : 'Profilo non disponibile: verifica la connessione o rifai il login.');
      }
    }
  }

  /// Aggiorna la copia locale dei cantieri (per lavorare offline in Ore su
  /// progetti e Note spese) e segnala se BC non è raggiungibile.
  Future<void> _loadProjects() async {
    try {
      await BcApiService.instance.fetchAssignedProjects();
      final fromCache = BcApiService.instance.projectsFromCache;
      if (mounted) {
        setState(() => _loadError = fromCache
            ? 'Offline: quanto registrato viene inviato al ritorno della rete.'
            : null);
      }
    } catch (e, stackTrace) {
      developer.log('fetchAssignedProjects fallita', name: 'HomeScreen', error: e, stackTrace: stackTrace);
      if (mounted) {
        // Errore restituito da BC: lo si mostra per intero, altrimenti non si
        // distingue da un problema di rete.
        setState(() => _loadError = e is BcApiException
            ? 'Impossibile aggiornare l\'elenco cantieri. $e'
            : 'Impossibile aggiornare l\'elenco cantieri (verifica la connessione).');
      }
    }
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
            if (_userError != null) ...[
              const SizedBox(height: 8),
              Text(_userError!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: 8),
              Text(_loadError!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
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
                // Sezione Service: interventi assegnati dalla Dispatch Board,
                // solo per chi ha il modulo (flag "Tecnico Service" in BC). Il
                // vecchio Bollettino su commesse Job è stato sostituito.
                if (_currentUser?.hasServiceModule == true)
                  ModuleTile(
                    icon: Icons.build_outlined,
                    iconColor: const Color(0xFF0F6E56),
                    label: 'Interventi',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServiceListScreen()),
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
}
