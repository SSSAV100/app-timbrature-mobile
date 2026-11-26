import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Materiale usato, a testo libero con la quantità (richiesta del cliente,
/// come nel vecchio NAV: niente anagrafica articoli né unità di misura).
/// Usato dagli interventi Service e dal bollettino delle ore di progetto.
/// Restituisce {description, quantity}.
class MaterialSheet extends StatefulWidget {
  const MaterialSheet({super.key});

  /// Testo per elenchi e PDF: "3 × Tubo rame 15 mm". Gestisce anche le
  /// azioni in coda create dalle versioni con l'articolo BC.
  static String label(Map<String, dynamic> material) {
    final quantity = (material['quantity'] as num?)?.toDouble() ?? 0;
    final qty = quantity == quantity.roundToDouble() ? quantity.toStringAsFixed(0) : '$quantity';
    final text = (material['description'] as String?) ??
        '${material['itemNo'] ?? ''} ${material['_itemDescription'] ?? ''}'.trim();
    return '$qty × $text';
  }

  @override
  State<MaterialSheet> createState() => _MaterialSheetState();
}

class _MaterialSheetState extends State<MaterialSheet> {
  // Errori mostrati dentro il pannello: uno SnackBar finirebbe dietro il
  // bottom sheet, invisibile.
  String? _error;
  void _showError(String message) => setState(() => _error = message);

  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _save() {
    final description = _descriptionController.text.trim();
    final quantity = double.tryParse(_quantityController.text.replaceAll(',', '.'));
    if (description.isEmpty) {
      _showError('Descrivi il materiale.');
      return;
    }
    if (quantity == null || quantity <= 0) {
      _showError('Inserisci una quantità valida.');
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      // BC: Text[100].
      'description': description.length > 100 ? description.substring(0, 100) : description,
      'quantity': quantity,
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
          TextField(
            controller: _descriptionController,
            autofocus: true,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descrizione (es. Tubo rame 15 mm)', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantità'),
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
            ),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('Aggiungi'))),
        ],
      ),
    );
  }
}
