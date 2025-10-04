// ABOUTME: Tab visibility provider that manages active tab state for IndexedStack coordination
// ABOUTME: Provides reactive tab switching and visibility state management for video lifecycle

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:openvine/providers/individual_video_providers.dart';

part 'tab_visibility_provider.g.dart';

@riverpod
class TabVisibility extends _$TabVisibility {
  @override
  int build() => 0; // Current active tab index

  void setActiveTab(int index) {
    // CRITICAL: Clear active video when switching tabs to prevent background playback
    // This ensures videos are paused and controllers can be disposed when tabs become inactive
    ref.read(activeVideoProvider.notifier).clearActiveVideo();

    // CRITICAL: Clear prewarm manager to prevent zombie controllers from staying alive
    // Prewarmed videos should not persist across tab switches
    try {
      ref.read(prewarmManagerProvider.notifier).clear();
    } catch (_) {
      // Ignore if provider doesn't exist yet
    }

    state = index;
  }
}

// Tab-specific visibility providers
@riverpod
bool isFeedTabActive(Ref ref) {
  return ref.watch(tabVisibilityProvider) == 0;
}

@riverpod
bool isExploreTabActive(Ref ref) {
  return ref.watch(tabVisibilityProvider) == 2;
}

@riverpod
bool isProfileTabActive(Ref ref) {
  return ref.watch(tabVisibilityProvider) == 3;
}
