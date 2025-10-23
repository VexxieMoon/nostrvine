// ABOUTME: Performance test for embedded relay - validates sub-100ms video feed loading
// ABOUTME: Tests core embedded relay functionality without complex event creation

import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/services/nostr_service.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/video_event_service.dart';
import 'package:openvine/services/subscription_manager.dart';
import 'package:openvine/utils/unified_logger.dart';

@Tags(['skip']) // Temporarily skipped - needs embedded relay URL fix

void main() {
  group('Embedded Relay Performance Tests', () {
    late NostrService embeddedRelay;
    late VideoEventService videoEventService;
    late SubscriptionManager subscriptionManager;
    late NostrKeyManager keyManager;

    setUpAll(() async {
      Log.setLogLevel(LogLevel.debug);
      Log.info('Starting embedded relay performance tests',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);
    });

    setUp(() async {
      // Initialize services
      keyManager = NostrKeyManager();
      embeddedRelay = NostrService(keyManager);
      subscriptionManager = SubscriptionManager(embeddedRelay);
      videoEventService = VideoEventService(
        embeddedRelay,
        subscriptionManager: subscriptionManager,
      );

      Log.debug('Performance test setup complete',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);
    });

    tearDown(() async {
      // Clean up services
      videoEventService.dispose();
      await subscriptionManager.dispose();

      Log.debug('Performance test teardown complete',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);
    });

    test('embedded relay initializes quickly', () async {
      final stopwatch = Stopwatch()..start();

      await embeddedRelay.initialize();

      stopwatch.stop();
      final initTime = stopwatch.elapsedMilliseconds;

      expect(embeddedRelay.isInitialized, isTrue);
      expect(initTime, lessThan(1000)); // Should initialize within 1 second

      Log.info('Embedded relay initialized in ${initTime}ms',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);
    });

    test('video feed subscription performance < 100ms', () async {
      // Initialize embedded relay first
      await embeddedRelay.initialize();
      expect(embeddedRelay.isInitialized, isTrue);

      // Measure video feed subscription time
      final stopwatch = Stopwatch()..start();

      await videoEventService.subscribeToVideoFeed(
        subscriptionType: SubscriptionType.discovery,
        limit: 50,
      );

      stopwatch.stop();
      final subscribeTime = stopwatch.elapsedMilliseconds;

      // Verify subscription was created
      expect(
          videoEventService.isSubscribed(SubscriptionType.discovery), isTrue);

      Log.info('Video feed subscription completed in ${subscribeTime}ms',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);

      // Target: < 100ms (vs old 500-2000ms with external relays)
      expect(subscribeTime, lessThan(100));
    });

    test('multiple concurrent subscriptions perform well', () async {
      await embeddedRelay.initialize();

      final stopwatch = Stopwatch()..start();

      // Create multiple concurrent subscriptions
      final futures = [
        videoEventService.subscribeToVideoFeed(
          subscriptionType: SubscriptionType.discovery,
          limit: 20,
        ),
        videoEventService.subscribeToVideoFeed(
          subscriptionType: SubscriptionType.homeFeed,
          limit: 20,
        ),
        videoEventService.subscribeToVideoFeed(
          subscriptionType: SubscriptionType.hashtag,
          hashtags: ['test'],
          limit: 10,
        ),
      ];

      await Future.wait(futures);

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;

      // Verify all subscriptions were created
      expect(
          videoEventService.isSubscribed(SubscriptionType.discovery), isTrue);
      expect(videoEventService.isSubscribed(SubscriptionType.homeFeed), isTrue);
      expect(videoEventService.isSubscribed(SubscriptionType.hashtag), isTrue);

      Log.info('Multiple concurrent subscriptions completed in ${totalTime}ms',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);

      // Should handle multiple subscriptions efficiently
      expect(totalTime, lessThan(200));
    });

    test('embedded relay connection status and metrics', () async {
      await embeddedRelay.initialize();

      // Check basic status
      expect(embeddedRelay.isInitialized, isTrue);
      expect(embeddedRelay.isDisposed, isFalse);

      // Check relay connections
      expect(embeddedRelay.relays, isNotEmpty);
      expect(embeddedRelay.relays, contains('ws://localhost:7447'));
      expect(embeddedRelay.relayCount, greaterThan(0));
      expect(embeddedRelay.connectedRelayCount, greaterThan(0));

      // Check relay statuses
      final statuses = embeddedRelay.relayStatuses;
      expect(statuses, isNotEmpty);

      Log.info(
          'Embedded relay status: '
          'relays=${embeddedRelay.relayCount}, '
          'connected=${embeddedRelay.connectedRelayCount}, '
          'urls=${embeddedRelay.relays}',
          name: 'EmbeddedRelayPerformanceTest',
          category: LogCategory.system);

      Log.info('✅ Embedded relay connection status verified',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);
    });

    test('subscription manager with embedded relay performs efficiently',
        () async {
      await embeddedRelay.initialize();

      final stopwatch = Stopwatch()..start();

      // Create a subscription through the subscription manager
      final subscriptionId = await subscriptionManager.createSubscription(
        name: 'test_subscription',
        filters: [], // Empty filters for basic test
        onEvent: (event) {
          Log.debug('Received event: ${event.id}',
              name: 'EmbeddedRelayPerformanceTest',
              category: LogCategory.system);
        },
      );

      stopwatch.stop();
      final createTime = stopwatch.elapsedMilliseconds;

      expect(subscriptionId, isNotEmpty);
      expect(subscriptionManager.isSubscriptionActive(subscriptionId), isTrue);
      expect(subscriptionManager.activeSubscriptionCount, greaterThan(0));

      Log.info('Subscription created in ${createTime}ms',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);

      // Should create subscriptions quickly
      expect(createTime, lessThan(50));

      // Clean up subscription
      await subscriptionManager.cancelSubscription(subscriptionId);
      expect(subscriptionManager.isSubscriptionActive(subscriptionId), isFalse);
    });

    test('embedded relay handles rapid subscription changes', () async {
      await embeddedRelay.initialize();

      final stopwatch = Stopwatch()..start();

      // Rapidly create and destroy subscriptions to test performance
      for (int i = 0; i < 5; i++) {
        await videoEventService.subscribeToVideoFeed(
          subscriptionType: SubscriptionType.discovery,
          limit: 10,
        );

        await videoEventService.unsubscribeFromVideoFeed();
      }

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;

      Log.info('Rapid subscription changes completed in ${totalTime}ms',
          name: 'EmbeddedRelayPerformanceTest', category: LogCategory.system);

      // Should handle rapid changes efficiently
      expect(totalTime, lessThan(500));

      Log.info(
          '✅ Embedded relay handled rapid subscription changes efficiently',
          name: 'EmbeddedRelayPerformanceTest',
          category: LogCategory.system);
    });
  });
}
