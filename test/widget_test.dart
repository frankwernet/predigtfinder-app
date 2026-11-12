import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predigtfinder/main.dart';

void main() {
  testWidgets('PredigtFinder startet', (tester) async {
    await tester.pumpWidget(const PredigtFinderApp());

    expect(find.text('PredigtFinder V0.1'), findsOneWidget);
    expect(find.text('OneDrive 1 öffnen'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
  });
}
