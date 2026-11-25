import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/tv_focus.dart';

void main() {
  testWidgets('TV text field opens editing only with OK and closes on exit', (
    tester,
  ) async {
    final firstController = TextEditingController(text: 'news.example.com');
    final secondController = TextEditingController();
    final firstNode = dpadTraversalFocusNode(firstController);
    final secondNode = dpadTraversalFocusNode(secondController);
    addTearDown(() {
      firstController.dispose();
      secondController.dispose();
      firstNode.dispose();
      secondNode.dispose();
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(navigationMode: NavigationMode.directional),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TvDpadTextField(
                  controller: firstController,
                  focusNode: firstNode,
                ),
                TvDpadTextField(
                  controller: secondController,
                  focusNode: secondNode,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    TextField field() => tester.widget<TextField>(find.byType(TextField).first);

    expect(field().readOnly, isTrue);
    firstNode.requestFocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(field().readOnly, isFalse);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(find.byType(TextField).first, 'secure.example.com');
    expect(firstController.text, 'secure.example.com');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(field().readOnly, isTrue);
    expect(secondNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'Android D-pad mode defers IME until OK without directional MediaQuery',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
      });
      final controller = TextEditingController();
      final node = dpadTraversalFocusNode(controller);
      addTearDown(() {
        controller.dispose();
        node.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvDpadTextField(controller: controller, focusNode: node),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();

      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().readOnly, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(field().readOnly, isFalse);
      expect(tester.testTextInput.isVisible, isTrue);
      debugDefaultTargetPlatformOverride = null;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    },
  );

  testWidgets('Android touch mode keeps tap-to-open keyboard behavior', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });
    final controller = TextEditingController();
    final node = dpadTraversalFocusNode(controller);
    addTearDown(() {
      controller.dispose();
      node.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvDpadTextField(controller: controller, focusNode: node),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    debugDefaultTargetPlatformOverride = null;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('non-TV text field keeps normal editing behavior', (
    tester,
  ) async {
    final controller = TextEditingController();
    final node = dpadTraversalFocusNode(controller);
    addTearDown(() {
      controller.dispose();
      node.dispose();
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(navigationMode: NavigationMode.traditional),
        child: MaterialApp(
          home: Scaffold(
            body: TvDpadTextField(controller: controller, focusNode: node),
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
  });
}
