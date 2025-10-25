// ABOUTME: Router-driven HomeScreen implementation (clean room)
// ABOUTME: Pure presentation with no lifecycle mutations - URL is source of truth

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openvine/mixins/video_prefetch_mixin.dart';
import 'package:openvine/providers/home_screen_controllers.dart';
import 'package:openvine/providers/route_feed_providers.dart';
import 'package:openvine/providers/social_providers.dart' as social;
import 'package:openvine/providers/user_profile_providers.dart';
import 'package:openvine/router/page_context_provider.dart';
import 'package:openvine/router/route_utils.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Router-driven HomeScreen - PageView syncs with URL bidirectionally
class HomeScreenRouter extends ConsumerStatefulWidget {
  const HomeScreenRouter({super.key});

  @override
  ConsumerState<HomeScreenRouter> createState() => _HomeScreenRouterState();
}

class _HomeScreenRouterState extends ConsumerState<HomeScreenRouter> with VideoPrefetchMixin {
  PageController? _controller;
  int? _lastUrlIndex;
  int? _lastPrefetchIndex;
  String? _currentVideoId; // Track the video ID we're currently viewing

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if user follows anyone - redirect to explore if not
    final socialState = ref.watch(social.socialProvider);
    if (socialState.isInitialized && socialState.followingPubkeys.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/explore');
        }
      });
    }

    // Read derived context from router
    final pageContext = ref.watch(pageContextProvider);

    return pageContext.when(
      data: (ctx) {
        // Only handle home routes
        if (ctx.type != RouteType.home) {
          return const Center(child: Text('Not a home route'));
        }

        final urlIndex = ctx.videoIndex ?? 0;

        // Get video data from home feed
        final videosAsync = ref.watch(videosForHomeRouteProvider);

        return videosAsync.when(
          data: (state) {
            final videos = state.videos;

            if (videos.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No videos available',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Follow some creators to see their videos here',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final itemCount = videos.length;

            // Initialize controller once with URL index
            if (_controller == null) {
              final safeIndex = urlIndex.clamp(0, itemCount - 1);
              _controller = PageController(initialPage: safeIndex);
              _lastUrlIndex = safeIndex;
              _currentVideoId = videos[safeIndex].id; // Remember which video we're showing
            }

            // Check if video list changed (e.g., reordered due to social provider update)
            // If current video moved to different index, update URL to maintain position
            if (_currentVideoId != null && videos.isNotEmpty) {
              final currentVideoIndex = videos.indexWhere((v) => v.id == _currentVideoId);
              if (currentVideoIndex != -1 && currentVideoIndex != urlIndex) {
                // Video we're viewing is now at a different index - update URL silently
                Log.debug(
                  '📍 Video $_currentVideoId moved from index $urlIndex → $currentVideoIndex, updating URL',
                  name: 'HomeScreenRouter',
                  category: LogCategory.video,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  context.go(buildRoute(
                    RouteContext(type: RouteType.home, videoIndex: currentVideoIndex),
                  ));
                });
                return; // Skip rest of sync logic, let rebuild handle it
              }
            }

            // Sync controller when URL changes externally (back/forward/deeplink)
            // Use post-frame to avoid calling jumpToPage during build
            if (_controller!.hasClients) {
              final safeIndex = urlIndex.clamp(0, itemCount - 1);
              final currentPage = _controller!.page?.round() ?? 0;

              // Sync if URL changed OR if controller position doesn't match URL
              if (urlIndex != _lastUrlIndex || currentPage != safeIndex) {
                _lastUrlIndex = urlIndex;
                _currentVideoId = videos[safeIndex].id; // Update tracked video
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_controller!.hasClients) return;
                  final currentPageNow = _controller!.page?.round() ?? 0;
                  if (currentPageNow != safeIndex) {
                    Log.debug('🔄 Syncing PageController: current=$currentPageNow -> target=$safeIndex',
                        name: 'HomeScreenRouter', category: LogCategory.video);
                    _controller!.jumpToPage(safeIndex);
                  }
                });
              }
            }

            // Prefetch profiles for adjacent videos (±1 index) only when URL index changes
            if (urlIndex != _lastPrefetchIndex) {
              _lastPrefetchIndex = urlIndex;
              final safeIndex = urlIndex.clamp(0, itemCount - 1);
              final pubkeysToPrefetech = <String>[];

              // Prefetch previous video's profile
              if (safeIndex > 0) {
                pubkeysToPrefetech.add(videos[safeIndex - 1].pubkey);
              }

              // Prefetch next video's profile
              if (safeIndex < itemCount - 1) {
                pubkeysToPrefetech.add(videos[safeIndex + 1].pubkey);
              }

              // Schedule prefetch for next frame to avoid doing work during build
              if (pubkeysToPrefetech.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  ref.read(userProfileProvider.notifier)
                      .prefetchProfilesImmediately(pubkeysToPrefetech);
                });
              }
            }

            return RefreshIndicator(
              onRefresh: () => ref.read(homeRefreshControllerProvider).refresh(),
              child: PageView.builder(
                key: const Key('home-video-page-view'),
                itemCount: videos.length,
                controller: _controller,
                scrollDirection: Axis.vertical,
                onPageChanged: (newIndex) {
                  // Update tracked video ID
                  _currentVideoId = videos[newIndex].id;

                  // Guard: only navigate if URL doesn't match
                  if (newIndex != urlIndex) {
                    context.go(buildRoute(
                      RouteContext(type: RouteType.home, videoIndex: newIndex),
                    ));
                  }

                  // Trigger pagination near end
                  if (newIndex >= itemCount - 2) {
                    ref.read(homePaginationControllerProvider).maybeLoadMore();
                  }

                  // Prefetch videos around current index
                  checkForPrefetch(currentIndex: newIndex, videos: videos);

                  Log.debug('📄 Page changed to index $newIndex (${videos[newIndex].id}...)',
                      name: 'HomeScreenRouter', category: LogCategory.video);
                },
                itemBuilder: (context, index) {
                  return VideoFeedItem(
                    key: ValueKey('video-${videos[index].id}'),
                    video: videos[index],
                    index: index,
                    hasBottomNavigation: true,
                    contextTitle: '', // Home feed has no context title
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text('Error: $error'),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
    );
  }
}
