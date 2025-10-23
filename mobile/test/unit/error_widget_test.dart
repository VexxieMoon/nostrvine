// ABOUTME: TDD test for custom error widget builder - tests user-friendly error display
// ABOUTME: These test the actual ErrorWidget.builder functionality

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

@Tags(['skip']) // TDD tests - intentionally failing until ErrorWidget.builder is implemented

void main() {
  group('Error Widget Builder Tests', () {
    testWidgets('ErrorWidget.builder shows user-friendly error in release mode',
        (tester) async {
      // Create a FlutterErrorDetails for testing
      final errorDetails = FlutterErrorDetails(
        exception: Exception('Test error for UI'),
        library: 'test',
        context: ErrorDescription('Test context'),
      );

      // Build the error widget using the global builder
      final errorWidget = ErrorWidget.builder(errorDetails);

      // Wrap in MaterialApp for proper context
      await tester.pumpWidget(MaterialApp(home: errorWidget));

      // Should show user-friendly error message
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Custom error widget has proper styling', (tester) async {
      final errorDetails = FlutterErrorDetails(
        exception: StateError('Custom test error'),
        library: 'test',
      );

      final errorWidget = ErrorWidget.builder(errorDetails);
      await tester.pumpWidget(MaterialApp(home: errorWidget));

      // Check for proper styling elements
      expect(find.byType(Container), findsAtLeastNWidgets(1));
      expect(find.byType(SafeArea), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);

      // Verify button can be tapped
      final button = find.byType(ElevatedButton);
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
    });

    testWidgets('Error widget displays exception message in debug mode',
        (tester) async {
      final errorDetails = FlutterErrorDetails(
        exception: ArgumentError('Debug mode test error'),
        library: 'test',
      );

      final errorWidget = ErrorWidget.builder(errorDetails);
      await tester.pumpWidget(MaterialApp(home: errorWidget));

      // In debug mode, should show detailed error
      expect(find.textContaining('Debug mode test error'), findsOneWidget);
    });
  });
}
