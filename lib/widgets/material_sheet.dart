import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/service_assignment.dart';
import '../services/bc_api_service.dart';

/// Materiale usato: articolo cercato nell'anagrafica BC e quantità. Usato
/// dagli interventi Service e dal bollettino delle ore di progetto.
/// Restituisce {itemNo, quantity, _itemDescription}.
class MaterialSheet extends StatefulWidget {
  const MaterialSheet({super.key});

  @override
  State<MaterialSheet> createState() => _MaterialSheetState();
}

class _MaterialSheetState extends State<MaterialSheet> {
  // Errori mostrati dentro il pannello: uno SnackBar finirebbe dietro il
  // bottom sheet, invisibile.
  String? _error;
  void _showError(String message) => setState(() => _error = message);

  final _quantityController = TextEditingController(text: '1');
  List<MaterialItem> _items = [];
  MaterialItem? _item;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    BcApiService.instance.fetchMaterialItems().then((items) {
      if (mounted) setState(() => _items = items);
    }).catchError((Object e) {
      if (mounted) setState(() => _loadError = 'Articoli non disponibili: $e');
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = double.tryParse(_quantityController.text.replaceAll(',', '.'));
    if (_item == null) {
      _showError('Scegli l\'articolo.');
      return;
    }
    if (quantity == null || quantity <= 0) {
      _showError('Inserisci una quantità valida.');
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'itemNo': _item!.no,
      'quantity': quantity,
      // Solo per l'app (elenco e PDF): i campi con "_" non vanno a BC, che
      // rifiuta quelli che non conosce (vedi submitServiceAction).
      '_itemDescription': _item!.description,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Materiale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (_loadError != null)
            Text(_loadError!, style: const TextStyle(fontSize: 12, color: AppColors.danger))
          else
            Autocomplete<MaterialItem>(
              displayStringForOption: (i) => '${i.no} · ${i.description}',
              optionsBuilder: (value) {
                final q = value.text.toLowerCase().trim();
                if (q.isEmpty) return const Iterable<MaterialItem>.empty();
                return _items
                    .where((i) => i.no.toLowerCase().contains(q) || i.description.toLowerCase().contains(q))
                    .take(30);
              },
              onSelected: (i) => setState(() => _item = i),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(labelText: 'Cerca articolo (codice o descrizione)'),
                onChanged: (_) => setState(() => _item = null),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Quantità${_item != null ? ' (${_item!.unitOfMeasure})' : ''}'),
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 13, color: Colors.red)),
            ),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('Aggiungi'))),
        ],
      ),
    );
  }
}
