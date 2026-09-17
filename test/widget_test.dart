import 'package:flutter_test/flutter_test.dart';

import 'package:app_timbrature/app.dart';
import 'package:app_timbrature/core/config.dart';
import 'package:app_timbrature/core/theme.dart';

void main() {
  testWidgets('L\'app si avvia e mostra la schermata di login', (tester) async {
    final config = await AppConfig.load();
    AppColors.applyBrandColor(config.primaryColorHex);

    await tester.pumpWidget(const TimbratureApp());
    await tester.pumpAndSettle();

    expect(find.text('Accedi con Microsoft'), findsOneWidget);
  });
}
