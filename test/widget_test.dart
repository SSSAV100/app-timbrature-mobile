// Smoke test: verifica che l'app si avvii senza eccezioni.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_timbrature/app.dart';

void main() {
  testWidgets('TimbratureApp si avvia senza errori', (WidgetTester tester) async {
    await tester.pumpWidget(const TimbratureApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
