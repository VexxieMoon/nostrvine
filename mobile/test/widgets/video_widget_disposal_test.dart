// ABOUTME: TDD test verifying video widgets and controllers are DESTROYED on tab switch
// ABOUTME: Tests that AutomaticKeepAliveClientMixin is removed and widgets truly die

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/individual_video_providers.dart';
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/screens/video_feed_screen.dart';

// Helper widget to track disposal
class _DisposableVideoFeedWrapper extends StatefulWidget {
  final VoidCallback onDispose;

  const _DisposableVideoFeedWrapper({required this.onDispose});

  @override
  State<_DisposableVideoFeedWrapper> createState() =>
      _DisposableVideoFeedWrapperState();
}

class _DisposableVideoFeedWrapperState
    extends State<_DisposableVideoFeedWrapper> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const VideoFeedScreen();
}

void main() {
  group('Video Widget Disposal on Tab Switch', () {
    testWidgets('MUST dispose VideoFeedScreen when tab becomes inactive',
        (WidgetTester tester) async {
      // GIVEN: A VideoFeedScreen mounted in a tab container
      final container = ProviderContainer();
      addTearDown(container.dispose);

      int feedScreenDisposeCount = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: IndexedStack(
                index: container.read(tabVisibilityProvider),
                children: [
                  // Tab 0: Video feed with dispose tracking
                  _DisposableVideoFeedWrapper(
                    onDispose: () => feedScreenDisposeCount++,
                  ),
                  // Tab 1: Other content
                  const Center(child: Text('Other Tab')),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify VideoFeedScreen is mounted
      expect(find.byType(VideoFeedScreen), findsOneWidget);
      expect(feedScreenDisposeCount, equals(0));

      // WHEN: User switches to another tab
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);

      // Rebuild the IndexedStack with new index
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: IndexedStack(
                index: container.read(tabVisibilityProvider),
                children: [
                  _DisposableVideoFeedWrapper(
                    onDispose: () => feedScreenDisposeCount++,
                  ),
                  const Center(child: Text('Other Tab')),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // THEN: VideoFeedScreen MUST be disposed when IndexedStack is rebuilt without KeepAlive
      // With AutomaticKeepAliveClientMixin removed, dispose should be called
      expect(
        feedScreenDisposeCount,
        greaterThan(0),
        reason: 'VideoFeedScreen must be disposed when tab becomes inactive. '
            'If this fails, AutomaticKeepAliveClientMixin is keeping zombie widgets alive.',
      );
    });

    testWidgets('MUST dispose video controllers immediately on tab switch',
        (WidgetTester tester) async {
      // GIVEN: A video is active with a controller
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const testVideoId = 'test-video-123';
      const testVideoUrl = 'https://example.com/video.mp4';

      // Set tab 0 active and create a video controller
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);
      container.read(activeVideoProvider.notifier).setActiveVideo(testVideoId);

      // Create controller by reading the provider
      final params = VideoControllerParams(
        videoId: testVideoId,
        videoUrl: testVideoUrl,
      );

      final controller1 = container.read(individualVideoControllerProvider(params));
      expect(controller1, isNotNull);

      // WHEN: User switches to another tab (clears active video)
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);

      // Pump frames to allow state changes
      await tester.pumpAndSettle();

      // THEN: Reading the provider again should give us a DIFFERENT controller
      // because the first one was disposed immediately (not after 3 seconds)
      // This verifies no zombie controllers exist
      final controller2 = container.read(individualVideoControllerProvider(params));

      expect(
        identical(controller1, controller2),
        isFalse,
        reason: 'Controller must be disposed immediately on tab switch, creating a new instance on re-read. '
            'If this fails (same controller returned), controllers are being kept alive as zombies.',
      );
    });

    testWidgets('MUST prevent widget resurrection after disposal',
        (WidgetTester tester) async {
      // GIVEN: Video feed disposed after tab switch
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Create initial state
      container.read(tabVisibilityProvider.notifier).setActiveTab(0);
      container.read(activeVideoProvider.notifier).setActiveVideo('video-1');

      // Switch away
      container.read(tabVisibilityProvider.notifier).setActiveTab(1);
      await tester.pumpAndSettle();

      // WHEN: App goes to background and comes back
      await tester.pump(const Duration(seconds: 5));

      // THEN: Original video should NOT be resurrected
      final activeState = container.read(activeVideoProvider);
      expect(
        activeState.currentVideoId,
        isNull,
        reason: 'Video must stay dead after tab switch and app lifecycle events. '
            'If this fails, widgets are being resurrected as zombies.',
      );
    });
  });
}
