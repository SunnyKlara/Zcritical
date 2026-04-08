import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/widgets/toast_notification.dart';

void main() {
  group('ToastNotification', () {
    group('ToastType enum', () {
      test('should have three types: success, error, warning', () {
        expect(ToastType.values.length, 3);
        expect(ToastType.values, contains(ToastType.success));
        expect(ToastType.values, contains(ToastType.error));
        expect(ToastType.values, contains(ToastType.warning));
      });
    });

    group('ToastNotification widget', () {
      testWidgets('should display message text', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.success(
                      context,
                      'Test message',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Test message'), findsOneWidget);

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('success toast should display check icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.success(
                      context,
                      'Success',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('error toast should display error icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.error(
                      context,
                      'Error',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byIcon(Icons.error), findsOneWidget);

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('warning toast should display warning icon', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.warning(
                      context,
                      'Warning',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byIcon(Icons.warning), findsOneWidget);

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('error toast with onRetry should display retry button',
          (tester) async {
        bool retryPressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.error(
                      context,
                      'Error',
                      duration: const Duration(milliseconds: 500),
                      onRetry: () {
                        retryPressed = true;
                      },
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('重试'), findsOneWidget);

        // Tap retry button
        await tester.tap(find.text('重试'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(retryPressed, true);
      });

      testWidgets('error toast without onRetry should not display retry button',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.error(
                      context,
                      'Error',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('重试'), findsNothing);

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('toast should auto-dismiss after duration', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.success(
                      context,
                      'Auto dismiss',
                      duration: const Duration(milliseconds: 200),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Auto dismiss'), findsOneWidget);

        // Wait for auto-dismiss
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 250)); // Animation

        expect(find.text('Auto dismiss'), findsNothing);
      });

      testWidgets('onDismiss callback should be called when toast is dismissed',
          (tester) async {
        bool dismissed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.success(
                      context,
                      'Dismiss test',
                      duration: const Duration(milliseconds: 200),
                      onDismiss: () {
                        dismissed = true;
                      },
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(dismissed, false);

        // Wait for auto-dismiss
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 250)); // Animation

        expect(dismissed, true);
      });

      testWidgets('show method should work with all toast types',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        ToastNotification.show(
                          context,
                          'Success via show',
                          ToastType.success,
                          duration: const Duration(milliseconds: 100),
                        );
                      },
                      child: const Text('Show Success'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Test success
        await tester.tap(find.text('Show Success'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Success via show'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        // Wait for dismiss
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('toast with showCloseButton should display close button',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.show(
                      context,
                      'With close button',
                      ToastType.success,
                      showCloseButton: true,
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byIcon(Icons.close), findsOneWidget);

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('close button should dismiss toast when tapped',
          (tester) async {
        bool dismissed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.show(
                      context,
                      'Close me',
                      ToastType.success,
                      showCloseButton: true,
                      duration: const Duration(seconds: 10),
                      onDismiss: () {
                        dismissed = true;
                      },
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Close me'), findsOneWidget);

        // Tap close button
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(dismissed, true);
      });

      testWidgets('toast should have proper styling', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.success(
                      context,
                      'Styled toast',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Find the container with decoration
        final container = tester.widget<Container>(
          find.ancestor(
            of: find.text('Styled toast'),
            matching: find.byType(Container),
          ).first,
        );

        expect(container.decoration, isA<BoxDecoration>());
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(12));

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('retry button should have minimum touch target size',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ToastNotification.error(
                      context,
                      'Error',
                      duration: const Duration(milliseconds: 100),
                      onRetry: () {},
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final retryButton = tester.widget<TextButton>(find.byType(TextButton));
        expect(retryButton.style?.minimumSize?.resolve({}),
            const Size(44, 44)); // Validates: Requirements 8.2

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });
    });

    group('ToastNotification static methods', () {
      testWidgets('success method should return OverlayEntry', (tester) async {
        late OverlayEntry entry;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    entry = ToastNotification.success(
                      context,
                      'Success',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();

        expect(entry, isA<OverlayEntry>());

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('error method should return OverlayEntry', (tester) async {
        late OverlayEntry entry;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    entry = ToastNotification.error(
                      context,
                      'Error',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();

        expect(entry, isA<OverlayEntry>());

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('warning method should return OverlayEntry', (tester) async {
        late OverlayEntry entry;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    entry = ToastNotification.warning(
                      context,
                      'Warning',
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();

        expect(entry, isA<OverlayEntry>());

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('show method should return OverlayEntry', (tester) async {
        late OverlayEntry entry;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    entry = ToastNotification.show(
                      context,
                      'Generic',
                      ToastType.success,
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();

        expect(entry, isA<OverlayEntry>());

        // Wait for auto-dismiss and animation
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
      });

      testWidgets('returned OverlayEntry can be used to manually remove toast',
          (tester) async {
        late OverlayEntry entry;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        entry = ToastNotification.success(
                          context,
                          'Manual remove',
                          duration: const Duration(seconds: 10),
                        );
                      },
                      child: const Text('Show Toast'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        entry.remove();
                      },
                      child: const Text('Remove Toast'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Manual remove'), findsOneWidget);

        // Manually remove
        await tester.tap(find.text('Remove Toast'));
        await tester.pump();

        expect(find.text('Manual remove'), findsNothing);
      });
    });
  });
}
