// ABOUTME: Explore screen showing trending content, Editor's Picks, and Popular Now sections
// ABOUTME: Displays curated content similar to original Vine's explore tab

import 'package:flutter/material.dart';
import 'package:openvine/models/curation_set.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/screens/hashtag_feed_screen.dart';
import 'package:openvine/screens/search_screen.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_explore_tile.dart';
import 'package:openvine/widgets/video_feed_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_events_providers.dart';
import 'package:openvine/providers/video_manager_providers.dart';
import 'package:openvine/providers/user_profile_providers.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => ExploreScreenState();
}

// Made public to allow access from MainNavigationScreen
class ExploreScreenState extends ConsumerState<ExploreScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  String? _selectedHashtag;
  String? _playingVideoId;
  int _currentVideoIndex = 0;
  List<VideoEvent> _currentTabVideos = [];
  bool _isInFeedMode = false; // Track if we're in full feed mode vs grid mode
  
  // Tab tap tracking for double-tap detection
  DateTime? _lastTabTap;
  int? _lastTappedIndex;
  
  // Pagination state for grid views
  int _popularNowLimit = 50;
  int _trendingLimit = 100;
  bool _isLoadingMorePopular = false;
  bool _isLoadingMoreTrending = false;
  
  // Hashtag pagination state
  int _editorsHashtagLimit = 25;
  int _trendingHashtagLimit = 25;
  bool _isLoadingMoreEditorsHashtags = false;
  bool _isLoadingMoreTrendingHashtags = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);

    // Listen for tab changes to close video and reset state
    _tabController.addListener(_onTabChanged);

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Since we're defaulting to Popular Now (index 1), no initial fetch needed
    // Popular Now gets data directly from videoEventService
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      // Pause any playing videos when switching tabs
      final exploreVideoManager = ref.read(exploreVideoManagerProvider);
      exploreVideoManager.pauseAllVideos();
      
      // Also pause all videos through the main VideoManager to ensure complete coverage
      final videoManager = ref.read(videoManagerProvider.notifier);
      videoManager.pauseAllVideos();

      // Close the currently playing video overlay if any and return to grid mode
      if (_playingVideoId != null || _isInFeedMode) {
        setState(() {
          _playingVideoId = null;
          _currentVideoIndex = 0;
          _currentTabVideos = [];
          _isInFeedMode = false; // Return to grid mode when switching tabs
        });
      }

      // Reset video index for all tabs
      setState(() {
        _currentVideoIndex = 0;
      });

      // No special fetching needed - Popular Now and Trending use videoEventService directly
    }
  }
  
  /// Handle tab tap to detect double-tap and already-selected tap
  void _handleTabTap(int index) {
    Log.debug('🔄 Tab tapped: index=$index, current=${_tabController.index}, isInFeedMode=$_isInFeedMode',
        name: 'ExploreScreen', category: LogCategory.ui);
    
    // Always pause videos when tapping any tab (whether switching or not)
    final exploreVideoManager = ref.read(exploreVideoManagerProvider);
    exploreVideoManager.pauseAllVideos();
    
    // Also pause all videos through the main VideoManager
    final videoManager = ref.read(videoManagerProvider.notifier);
    videoManager.pauseAllVideos();
    
    // Check if tapping on the already selected tab
    if (index == _tabController.index) {
      // If we're in feed mode, exit to grid mode
      if (_isInFeedMode) {
        Log.debug('🔄 Tapping current tab while in feed mode - exiting to grid',
            name: 'ExploreScreen', category: LogCategory.ui);
        _exitFeedMode();
        return;
      }
      
      // Check for double-tap
      final now = DateTime.now();
      if (_lastTappedIndex == index && 
          _lastTabTap != null && 
          now.difference(_lastTabTap!).inMilliseconds < 500) {
        // Double-tap detected on the same tab - exit feed mode if active
        Log.debug('🔄 Double-tap detected on tab $index',
            name: 'ExploreScreen', category: LogCategory.ui);
        if (_isInFeedMode) {
          _exitFeedMode();
        }
        _lastTabTap = null;
        _lastTappedIndex = null;
      } else {
        // Single tap on already selected tab
        _lastTabTap = now;
        _lastTappedIndex = index;
      }
    } else {
      // Switching to a different tab
      _lastTabTap = null;
      _lastTappedIndex = null;
      _tabController.animateTo(index);
    }
  }

  /// Handle video tap to enter feed mode
  void _enterFeedMode(List<VideoEvent> videos, int startIndex) {
    debugPrint('🎬 _enterFeedMode called for video ${videos[startIndex].id.substring(0, 8)} at index $startIndex');
    Log.debug('🎬 Entering feed mode for video ${videos[startIndex].id} at index $startIndex', 
        name: 'ExploreScreen', category: LogCategory.ui);
    
    // Preload the current video and surrounding videos in VideoManager before entering feed mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final videoManager = ref.read(videoManagerProvider.notifier);
      
      // Preload current video first (priority)
      videoManager.preloadVideo(videos[startIndex].id);
      
      // Preload surrounding videos for smooth scrolling
      for (int i = -2; i <= 2; i++) {
        final index = startIndex + i;
        if (index >= 0 && index < videos.length && index != startIndex) {
          videoManager.preloadVideo(videos[index].id);
        }
      }
      
      Log.debug('🚀 Preloaded ${videos[startIndex].id.substring(0, 8)} and surrounding videos for feed mode',
          name: 'ExploreScreen', category: LogCategory.ui);
    });
    
    // Batch fetch profiles for visible videos
    _batchFetchProfilesAroundIndex(startIndex, videos);
    
    setState(() {
      debugPrint('📱 Setting state: _isInFeedMode = true, _currentVideoIndex = $startIndex');
      _isInFeedMode = true;
      _currentTabVideos = videos;
      _currentVideoIndex = startIndex;
      _playingVideoId = videos[startIndex].id;
    });
  }

  /// Exit feed mode and return to grid view
  void _exitFeedMode() {
    // Pause any playing videos when exiting feed mode
    final exploreVideoManager = ref.read(exploreVideoManagerProvider);
    exploreVideoManager.pauseAllVideos();
    
    // Also pause all videos through the main VideoManager
    final videoManager = ref.read(videoManagerProvider.notifier);
    videoManager.pauseAllVideos();
    
    setState(() {
      _isInFeedMode = false;
      _playingVideoId = null;
      _currentVideoIndex = 0;
      _currentTabVideos = [];
      _selectedHashtag = null; // Clear hashtag when exiting
    });
  }
  
  /// Batch fetch profiles for videos around the current position
  void _batchFetchProfilesAroundIndex(int currentIndex, List<VideoEvent> videos) {
    if (videos.isEmpty) return;

    // Define window of videos to prefetch profiles for
    const preloadRadius = 5; // Preload profiles for ±5 videos in grid view
    final startIndex =
        (currentIndex - preloadRadius).clamp(0, videos.length - 1);
    final endIndex = (currentIndex + preloadRadius).clamp(0, videos.length - 1);

    // Collect unique pubkeys that need profile fetching
    final pubkeysToFetch = <String>{};
    final userProfilesNotifier = ref.read(userProfileNotifierProvider.notifier);

    for (var i = startIndex; i <= endIndex; i++) {
      final video = videos[i];

      // Only add pubkeys that don't have profiles yet
      if (!userProfilesNotifier.hasProfile(video.pubkey)) {
        pubkeysToFetch.add(video.pubkey);
      }
      
      // Also fetch reposter profiles if needed
      if (video.isRepost && video.reposterPubkey != null && 
          !userProfilesNotifier.hasProfile(video.reposterPubkey!)) {
        pubkeysToFetch.add(video.reposterPubkey!);
      }
    }

    if (pubkeysToFetch.isEmpty) return;

    Log.debug(
      '🔄 Batch fetching ${pubkeysToFetch.length} profiles for videos in explore screen',
      name: 'ExploreScreen',
      category: LogCategory.ui,
    );

    // Batch fetch profiles using Riverpod
    userProfilesNotifier.fetchMultipleProfiles(pubkeysToFetch.toList());
  }

  /// Check if currently in feed mode
  bool get isInFeedMode => _isInFeedMode;

  /// Public method to exit feed mode (called from MainNavigationScreen)
  void exitFeedMode() {
    Log.debug('🔄 ExploreScreen.exitFeedMode() called - current feed mode: $_isInFeedMode',
        name: 'ExploreScreen', category: LogCategory.ui);
    if (_isInFeedMode) {
      _exitFeedMode();
    } else {
      Log.debug('🔄 Not in feed mode, ignoring exitFeedMode() call',
          name: 'ExploreScreen', category: LogCategory.ui);
    }
  }

  /// Load more popular now videos
  void _loadMorePopularNow() {
    if (_isLoadingMorePopular) return;
    
    setState(() {
      _isLoadingMorePopular = true;
      _popularNowLimit += 25; // Load 25 more videos
    });
    
    // Brief delay to show loading state, then hide it
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoadingMorePopular = false;
        });
      }
    });
  }

  /// Load more trending videos  
  void _loadMoreTrending() {
    if (_isLoadingMoreTrending) return;
    
    setState(() {
      _isLoadingMoreTrending = true;
      _trendingLimit += 25; // Load 25 more videos
    });
    
    // Brief delay to show loading state, then hide it
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoadingMoreTrending = false;
        });
      }
    });
  }

  /// Load more editor's pick hashtags
  void _loadMoreEditorsHashtags() {
    if (_isLoadingMoreEditorsHashtags) return;
    
    setState(() {
      _isLoadingMoreEditorsHashtags = true;
      _editorsHashtagLimit += 10; // Load 10 more hashtags
    });
    
    // Brief delay to show loading state, then hide it
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isLoadingMoreEditorsHashtags = false;
        });
      }
    });
  }

  /// Load more trending hashtags
  void _loadMoreTrendingHashtags() {
    if (_isLoadingMoreTrendingHashtags) return;
    
    setState(() {
      _isLoadingMoreTrendingHashtags = true;
      _trendingHashtagLimit += 10; // Load 10 more hashtags
    });
    
    // Brief delay to show loading state, then hide it
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isLoadingMoreTrendingHashtags = false;
        });
      }
    });
  }

  /// Show videos for a specific hashtag
  Future<void> showHashtagVideos(String hashtag) async {
    Log.debug('📍 Showing hashtag videos for: #$hashtag',
        name: 'ExploreScreen', category: LogCategory.ui);

    // Switch to trending tab for hashtag display
    _tabController.animateTo(2);

    setState(() {
      _selectedHashtag = hashtag;
    });

    // Subscribe to hashtag videos and wait for them to load
    final hashtagService = ref.read(hashtagServiceProvider);
    await hashtagService.subscribeToHashtagVideos([hashtag]);

    // Force a rebuild after subscription is established
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();

    // Pause any playing videos - but only if context is still mounted
    if (mounted) {
      try {
        final exploreVideoManager = ref.read(exploreVideoManagerProvider);
        exploreVideoManager.pauseAllVideos();
        
        // Also pause through main VideoManager for complete coverage
        final videoManager = ref.read(videoManagerProvider.notifier);
        videoManager.pauseAllVideos();
      } catch (e) {
        // Ignore errors when context is no longer valid
      }
    }

    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Only handle lifecycle for Popular Now tab with PageView
    if (_tabController.index != 1) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Pause videos when app goes to background
        final exploreVideoManager = ref.read(exploreVideoManagerProvider);
        exploreVideoManager.pauseAllVideos();
      case AppLifecycleState.resumed:
        // Videos will auto-resume via VideoFeedItem when it rebuilds
        if (mounted) {
          setState(() {}); // Trigger rebuild
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: VineTheme.backgroundColor,
        appBar: _isInFeedMode
            ? AppBar(
                backgroundColor: VineTheme.vineGreen,
                elevation: 0,
                leading: IconButton(
                  icon:
                      const Icon(Icons.arrow_back, color: VineTheme.whiteText),
                  onPressed: _exitFeedMode,
                ),
                title: const Text(
                  'Explore',
                  style: TextStyle(
                    color: VineTheme.whiteText,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: VineTheme.whiteText),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SearchScreen(),
                        ),
                      );
                    },
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: VineTheme.whiteText,
                  indicatorWeight: 2,
                  labelColor: VineTheme.whiteText,
                  unselectedLabelColor:
                      VineTheme.whiteText.withValues(alpha: 0.7),
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  onTap: _handleTabTap,
                  tabs: const [
                    Tab(text: "EDITOR'S PICKS"),
                    Tab(text: 'POPULAR NOW'),
                    Tab(text: 'TRENDING'),
                  ],
                ),
              )
            : AppBar(
                backgroundColor: VineTheme.vineGreen,
                elevation: 0,
                title: const Text(
                  'Explore',
                  style: TextStyle(
                    color: VineTheme.whiteText,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: VineTheme.whiteText),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SearchScreen(),
                        ),
                      );
                    },
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: VineTheme.whiteText,
                  indicatorWeight: 2,
                  labelColor: VineTheme.whiteText,
                  unselectedLabelColor:
                      VineTheme.whiteText.withValues(alpha: 0.7),
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  onTap: _handleTabTap,
                  tabs: const [
                    Tab(text: "EDITOR'S PICKS"),
                    Tab(text: 'POPULAR NOW'),
                    Tab(text: 'TRENDING'),
                  ],
                ),
              ),
        body: Stack(
          children: [
            TabBarView(
              controller: _tabController,
              children: [
                _buildEditorsPicks(),
                _buildPopularNow(),
                _buildTrending(),
              ],
            ),
            // No overlay needed - feed mode handles video playback directly
          ],
        ),
      );

  Widget _buildEditorsPicks() {
    final curationService = ref.watch(curationServiceProvider);
    final hashtagService = ref.watch(hashtagServiceProvider);
    
    // Get editor's picks from curation service
    final editorsPicks = curationService.getVideosForSetType(CurationSetType.editorsPicks);

          // Riverpod providers handle subscription automatically

          if (curationService.isLoading && editorsPicks.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(
                color: VineTheme.vineGreen,
              ),
            );
          }

          if (editorsPicks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_outline,
                    size: 64,
                    color: VineTheme.secondaryText,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "Editor's Picks",
                    style: TextStyle(
                      color: VineTheme.primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Curated videos selected by our\ncommunity moderators.',
                    style: TextStyle(
                      color: VineTheme.secondaryText,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Get editor's pick hashtags with pagination
          final allEditorsHashtags = hashtagService.getEditorsPicks(limit: 100); // Get more from service
          final editorsHashtags = allEditorsHashtags.take(_editorsHashtagLimit).toList();

          // Batch fetch profiles for the first visible videos
          if (editorsPicks.isNotEmpty && !_isInFeedMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _batchFetchProfilesAroundIndex(0, editorsPicks);
            });
          }

          // Full-screen video feed with hashtag filter at top
          return Column(
            children: [
              // Editor's pick hashtags
              if (editorsHashtags.isNotEmpty) ...[
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: editorsHashtags.length + (editorsHashtags.length < allEditorsHashtags.length ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show load more button at the end
                      if (index >= editorsHashtags.length) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _isLoadingMoreEditorsHashtags
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: VineTheme.vineGreen,
                                    strokeWidth: 2,
                                  ),
                                )
                              : ActionChip(
                                  label: const Text('+ More'),
                                  onPressed: _loadMoreEditorsHashtags,
                                  backgroundColor: VineTheme.vineGreen,
                                  labelStyle: const TextStyle(
                                    color: VineTheme.whiteText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        );
                      }
                      
                      final hashtag = editorsHashtags[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text('#$hashtag'),
                          onPressed: () {
                            debugPrint(
                                "🔗 Navigating to hashtag feed from editor's picks: #$hashtag");
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    HashtagFeedScreen(hashtag: hashtag),
                              ),
                            );
                          },
                          backgroundColor: VineTheme.cardBackground,
                          labelStyle: const TextStyle(
                            color: VineTheme.primaryText,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(color: VineTheme.secondaryText, height: 1),
              ],

              // Video content - either grid or feed mode
              Expanded(
                child: _isInFeedMode
                    ? PageView.builder(
                        scrollDirection: Axis.vertical,
                        itemCount: _currentTabVideos.length,
                        controller:
                            PageController(initialPage: _currentVideoIndex),
                        onPageChanged: (index) {
                          setState(() {
                            _currentVideoIndex = index;
                            _playingVideoId = _currentTabVideos[index].id;
                          });

                          // Note: Preloading would be handled by VideoEventService if needed
                          // For now, rely on natural video loading
                        },
                        itemBuilder: (context, index) {
                          final video = _currentTabVideos[index];
                          final isActive = index == _currentVideoIndex;

                          return VideoFeedItem(
                            key: ValueKey(video.id),
                            video: video,
                            isActive: isActive && _tabController.index == 0, // Only active if on Editor's Picks tab
                          );
                        },
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(1),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              MediaQuery.of(context).size.width < 600
                                  ? 3
                                  : MediaQuery.of(context).size.width < 900
                                      ? 4
                                      : MediaQuery.of(context).size.width < 1200
                                          ? 5
                                          : 6,
                          crossAxisSpacing: 1,
                          mainAxisSpacing: 1,
                          childAspectRatio: 1,
                        ),
                        itemCount: editorsPicks.length,
                        itemBuilder: (context, index) {
                          final video = editorsPicks[index];
                          return VideoExploreTile(
                            video: video,
                            isActive: false,
                            onTap: () {
                              _enterFeedMode(editorsPicks, index);
                            },
                            onClose: _exitFeedMode,
                          );
                        },
                      ),
              ),
            ],
          );
  }

  Widget _buildPopularNow() {
    // Use the proper Riverpod provider that reactively updates
    final asyncVideoEvents = ref.watch(videoEventsProvider);
    
    // Handle different async states
    return asyncVideoEvents.when(
      loading: () => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: VineTheme.vineGreen,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Popular Now...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: VineTheme.vineGreen,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Popular Now...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      data: (allVideos) {
        // Sort by creation time for now (analytics will provide better sorting later)
        final popularVideos = List<VideoEvent>.from(allVideos)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // Take videos up to current limit for Popular Now
        final videos = popularVideos.take(_popularNowLimit).toList();

        Log.debug('PopularNow: ${videos.length} videos available',
            name: 'ExploreScreen', category: LogCategory.ui);

        if (videos.isEmpty) {
          return _buildPopularNowEmptyState();
        }
        
        // Batch fetch profiles for the first visible videos
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _batchFetchProfilesAroundIndex(0, videos);
        });

        return _buildPopularNowContent(videos, allVideos);
      },
    );
  }

  Widget _buildPopularNowEmptyState() {
    return RefreshIndicator(
      color: VineTheme.vineGreen,
      onRefresh: () async {
        // Invalidate the video events provider to refresh
        ref.invalidate(videoEventsProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.trending_up,
                  size: 64,
                  color: VineTheme.secondaryText,
                ),
                SizedBox(height: 16),
                Text(
                  'Looking for Popular Videos...',
                  style: TextStyle(
                    color: VineTheme.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Fetching the most popular content\\nfrom the network.\\n\\nPull down to refresh.',
                  style: TextStyle(
                    color: VineTheme.secondaryText,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopularNowContent(List<VideoEvent> videos, List<VideoEvent> allVideos) {
    debugPrint('🏗️ _buildPopularNowContent: _isInFeedMode = $_isInFeedMode, videos.length = ${videos.length}');
    // Check if we should show feed mode or grid mode
    if (_isInFeedMode) {
      debugPrint('📱 Building feed mode with ${_currentTabVideos.length} videos, currentIndex = $_currentVideoIndex');
      // Full-screen video feed mode
      return PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _currentTabVideos.length,
        controller: PageController(initialPage: _currentVideoIndex),
        onPageChanged: (index) {
          setState(() {
            _currentVideoIndex = index;
            _playingVideoId = _currentTabVideos[index].id;
          });
        },
        itemBuilder: (context, index) {
          final video = _currentTabVideos[index];
          final isActive = index == _currentVideoIndex;

          return VideoFeedItem(
            key: ValueKey(video.id),
            video: video,
            isActive: isActive && _tabController.index == 1, // Only active if on Popular Now tab
          );
        },
      );
    } else {
      debugPrint('📱 Building grid mode');
      // Grid view mode with pull-to-refresh
      final screenWidth = MediaQuery.of(context).size.width;
      final crossAxisCount = screenWidth < 600
          ? 3
          : screenWidth < 900
              ? 4
              : screenWidth < 1200
                  ? 5
                  : 6;

      return RefreshIndicator(
        color: VineTheme.vineGreen,
        onRefresh: () async {
          // Reset pagination and refresh
          setState(() {
            _popularNowLimit = 50;
          });
          ref.invalidate(videoEventsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(1),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 1,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final video = videos[index];
                    return VideoExploreTile(
                      video: video,
                      isActive: false, // Never active in grid - feed mode handles playback
                      showTextOverlay: false, // Popular Now shows clean thumbnails without text
                      onTap: () {
                        debugPrint('🎬 Tapping video ${video.id.substring(0, 8)} with URL: ${video.videoUrl}');
                        _enterFeedMode(videos, index);
                      },
                      onClose: _exitFeedMode,
                    );
                  },
                  childCount: videos.length,
                ),
              ),
            ),
            // Load more button if there are more videos available
            if (videos.length >= _popularNowLimit && _popularNowLimit < allVideos.length)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: _isLoadingMorePopular
                        ? const CircularProgressIndicator(color: VineTheme.vineGreen)
                        : ElevatedButton(
                            onPressed: _loadMorePopularNow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: VineTheme.vineGreen,
                              foregroundColor: VineTheme.whiteText,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            ),
                            child: const Text('Load More Videos'),
                          ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }

  Widget _buildTrending() {
    final hashtagService = ref.watch(hashtagServiceProvider);
    final allTrendingHashtags = hashtagService.getTrendingHashtags(limit: 100); // Get more from service
    final trendingHashtags = allTrendingHashtags.take(_trendingHashtagLimit).toList();

    // If user has selected a specific hashtag, show hashtag-filtered content
    if (_selectedHashtag != null) {
      final videos = hashtagService.getVideosByHashtags([_selectedHashtag!]);
      
      return Column(
        children: [
          // Hashtag filter chips
          if (trendingHashtags.isNotEmpty) ...[
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: trendingHashtags.length + 1 + (trendingHashtags.length < allTrendingHashtags.length ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // "All" chip
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _selectedHashtag == null,
                        onSelected: (selected) {
                          setState(() {
                            _selectedHashtag = null;
                          });
                        },
                        backgroundColor: VineTheme.cardBackground,
                        selectedColor: VineTheme.vineGreen,
                        labelStyle: TextStyle(
                          color: _selectedHashtag == null
                              ? VineTheme.whiteText
                              : VineTheme.primaryText,
                          fontWeight: _selectedHashtag == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }

                  // Show load more button at the end
                  if (index > trendingHashtags.length) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _isLoadingMoreTrendingHashtags
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: VineTheme.vineGreen,
                                strokeWidth: 2,
                              ),
                            )
                          : ActionChip(
                              label: const Text('+ More'),
                              onPressed: _loadMoreTrendingHashtags,
                              backgroundColor: VineTheme.vineGreen,
                              labelStyle: const TextStyle(
                                color: VineTheme.whiteText,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    );
                  }

                  final hashtag = trendingHashtags[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (context) => HashtagFeedScreen(hashtag: hashtag),
                          ),
                        );
                      },
                      child: FilterChip(
                        label: Text('#$hashtag'),
                        selected: _selectedHashtag == hashtag,
                        onSelected: (selected) {
                          setState(() {
                            _selectedHashtag = selected ? hashtag : null;
                          });
                        },
                        backgroundColor: VineTheme.cardBackground,
                        selectedColor: VineTheme.vineGreen,
                        labelStyle: TextStyle(
                          color: _selectedHashtag == hashtag
                              ? VineTheme.whiteText
                              : VineTheme.primaryText,
                          fontWeight: _selectedHashtag == hashtag
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: VineTheme.secondaryText, height: 1),
          ],

          // Hashtag-filtered videos in list view
          Expanded(
            child: videos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.tag,
                          size: 64,
                          color: VineTheme.secondaryText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No videos found for #$_selectedHashtag',
                          style: const TextStyle(
                            color: VineTheme.primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try a different hashtag or check back later',
                          style: TextStyle(
                            color: VineTheme.secondaryText,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: videos.length,
                    itemBuilder: (context, index) {
                      final video = videos[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          height: 250,
                          child: VideoExploreTile(
                            video: video,
                            isActive: false,
                            onTap: () {
                              _enterFeedMode(videos, index);
                            },
                            onClose: _exitFeedMode,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    // Default trending infinite scroll feed
    return Column(
      children: [
        // Hashtag filter chips
        if (trendingHashtags.isNotEmpty) ...[
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: trendingHashtags.length + 1 + (trendingHashtags.length < allTrendingHashtags.length ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  // "All" chip
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _selectedHashtag == null,
                      onSelected: (selected) {
                        setState(() {
                          _selectedHashtag = null;
                        });
                      },
                      backgroundColor: VineTheme.cardBackground,
                      selectedColor: VineTheme.vineGreen,
                      labelStyle: TextStyle(
                        color: _selectedHashtag == null
                            ? VineTheme.whiteText
                            : VineTheme.primaryText,
                        fontWeight: _selectedHashtag == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }

                // Show load more button at the end
                if (index > trendingHashtags.length) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _isLoadingMoreTrendingHashtags
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: VineTheme.vineGreen,
                              strokeWidth: 2,
                            ),
                          )
                        : ActionChip(
                            label: const Text('+ More'),
                            onPressed: _loadMoreTrendingHashtags,
                            backgroundColor: VineTheme.vineGreen,
                            labelStyle: const TextStyle(
                              color: VineTheme.whiteText,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  );
                }

                final hashtag = trendingHashtags[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onLongPress: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (context) => HashtagFeedScreen(hashtag: hashtag),
                        ),
                      );
                    },
                    child: FilterChip(
                      label: Text('#$hashtag'),
                      selected: _selectedHashtag == hashtag,
                      onSelected: (selected) {
                        setState(() {
                          _selectedHashtag = selected ? hashtag : null;
                        });
                      },
                      backgroundColor: VineTheme.cardBackground,
                      selectedColor: VineTheme.vineGreen,
                      labelStyle: TextStyle(
                        color: _selectedHashtag == hashtag
                            ? VineTheme.whiteText
                            : VineTheme.primaryText,
                        fontWeight: _selectedHashtag == hashtag
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: VineTheme.secondaryText, height: 1),
        ],

        // Trending grid view (similar to Popular Now)
        Expanded(
          child: _buildTrendingVideoGrid(),
        ),
      ],
    );
  }

  Widget _buildTrendingVideoGrid() {
    // Use the proper Riverpod provider that reactively updates
    final asyncVideoEvents = ref.watch(videoEventsProvider);
    
    return asyncVideoEvents.when(
      loading: () => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: VineTheme.vineGreen,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Trending Videos...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: VineTheme.vineGreen,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Trending Videos...',
              style: TextStyle(
                color: VineTheme.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      data: (allVideos) {
        // Sort by creation time for trending
        final trendingVideos = List<VideoEvent>.from(allVideos)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // Take videos up to current limit for trending
        final videos = trendingVideos.take(_trendingLimit).toList();

        Log.debug('Trending: ${videos.length} videos available',
            name: 'ExploreScreen', category: LogCategory.ui);

        if (videos.isEmpty) {
          return RefreshIndicator(
            color: VineTheme.vineGreen,
            onRefresh: () async {
              // Invalidate the video events provider to refresh
              ref.invalidate(videoEventsProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: 64,
                        color: VineTheme.secondaryText,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Looking for Trending Videos...',
                        style: TextStyle(
                          color: VineTheme.primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fetching the latest trending content\\nfrom the network.\\n\\nPull down to refresh.',
                        style: TextStyle(
                          color: VineTheme.secondaryText,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        
        // Batch fetch profiles for the first visible trending videos
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _batchFetchProfilesAroundIndex(0, videos);
        });

        // Check if we should show feed mode or grid mode
        if (_isInFeedMode) {
          debugPrint('📱 Building trending feed mode with ${_currentTabVideos.length} videos, currentIndex = $_currentVideoIndex');
          // Full-screen video feed mode
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: _currentTabVideos.length,
            controller: PageController(initialPage: _currentVideoIndex),
            onPageChanged: (index) {
              setState(() {
                _currentVideoIndex = index;
                _playingVideoId = _currentTabVideos[index].id;
              });
            },
            itemBuilder: (context, index) {
              final video = _currentTabVideos[index];
              final isActive = index == _currentVideoIndex;

              return VideoFeedItem(
                key: ValueKey(video.id),
                video: video,
                isActive: isActive && _tabController.index == 2, // Only active if on Trending tab
              );
            },
          );
        } else {
          debugPrint('📱 Building trending grid mode');
          // Grid view mode with pull-to-refresh
          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = screenWidth < 600
              ? 3
              : screenWidth < 900
                  ? 4
                  : screenWidth < 1200
                      ? 5
                      : 6;

          return RefreshIndicator(
            color: VineTheme.vineGreen,
            onRefresh: () async {
              // Reset pagination and refresh
              setState(() {
                _trendingLimit = 100;
              });
              ref.invalidate(videoEventsProvider);
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(1),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 1,
                      mainAxisSpacing: 1,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = videos[index];
                        return VideoExploreTile(
                          video: video,
                          isActive: false,
                          onTap: () {
                            debugPrint('🎬 Tapping trending video ${video.id.substring(0, 8)} with URL: ${video.videoUrl}');
                            _enterFeedMode(videos, index);
                          },
                          onClose: _exitFeedMode,
                        );
                      },
                      childCount: videos.length,
                    ),
                  ),
                ),
                // Load more button if there are more videos available
                if (videos.length >= _trendingLimit && _trendingLimit < allVideos.length)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: _isLoadingMoreTrending
                            ? const CircularProgressIndicator(color: VineTheme.vineGreen)
                            : ElevatedButton(
                                onPressed: _loadMoreTrending,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VineTheme.vineGreen,
                                  foregroundColor: VineTheme.whiteText,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                ),
                                child: const Text('Load More Videos'),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
      },
    );
  }
}
