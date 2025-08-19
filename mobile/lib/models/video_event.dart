// ABOUTME: Video Event model for handling kind 32222 addressable short video events
// ABOUTME: Parses and structures video content data from Nostr relays (NIP-32222)

import 'dart:developer' as developer;

import 'package:nostr_sdk/event.dart';
import 'package:openvine/services/thumbnail_api_service.dart';

/// Represents an addressable video event (kind 32222 NIP-32222)
class VideoEvent {
  // approved, flagged, etc.

  const VideoEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.content,
    required this.timestamp,
    this.title,
    this.videoUrl,
    this.thumbnailUrl,
    this.duration,
    this.dimensions,
    this.mimeType,
    this.sha256,
    this.fileSize,
    this.hashtags = const [],
    this.publishedAt,
    this.rawTags = const {},
    this.vineId,
    this.group,
    this.altText,
    this.blurhash,
    this.isRepost = false,
    this.reposterId,
    this.reposterPubkey,
    this.repostedAt,
    this.isFlaggedContent = false,
    this.moderationStatus,
    this.originalLoops,
    this.originalLikes,
  });

  /// Create VideoEvent from Nostr event
  factory VideoEvent.fromNostrEvent(Event event) {
    if (event.kind != 32222) {
      throw ArgumentError('Event must be kind 32222 (addressable short video)');
    }

    developer.log(
        '🔍 DEBUG: Parsing Kind ${event.kind} event ${event.id.substring(0, 8)}...',
        name: 'VideoEvent');
    developer.log('🔍 DEBUG: Event has ${event.tags.length} tags',
        name: 'VideoEvent');
    developer.log(
        '🔍 DEBUG: Event content: ${event.content.length > 100 ? "${event.content.substring(0, 100)}..." : event.content}',
        name: 'VideoEvent');

    final tags = <String, String>{};
    final hashtags = <String>[];
    String? videoUrl;
    String? thumbnailUrl;
    String? title;
    int? duration;
    String? dimensions;
    String? mimeType;
    String? sha256;
    int? fileSize;
    String? publishedAt;
    String? vineId;
    String? group;
    String? altText;
    String? blurhash;
    int? originalLoops;
    int? originalLikes;

    // Parse event tags according to NIP-71
    // Handle both List<String> and List<dynamic> from different nostr implementations
    for (var i = 0; i < event.tags.length; i++) {
      final tagRaw = event.tags[i];
      if ((tagRaw as List).isEmpty) continue;

      // Convert List<dynamic> to List<String> safely
      final tag = tagRaw.map((e) => e.toString()).toList();

      final tagName = tag[0];
      final tagValue = (tag.length > 1) ? tag[1] : '';

      developer.log(
          '🔍 DEBUG: Tag [$i]: $tagName = "$tagValue" (${tag.length} elements)',
          name: 'VideoEvent');

      switch (tagName) {
        case 'url':
          developer.log('🔍 DEBUG: Found url tag with value: $tagValue',
              name: 'VideoEvent');
          // Check if this is a valid video URL
          if (tagValue.isNotEmpty && _isValidVideoUrl(tagValue)) {
            if (tagValue.contains('apt.openvine.co')) {
              // Fix typo: apt.openvine.co -> api.openvine.co
              final fixedUrl = tagValue.replaceAll('apt.openvine.co', 'api.openvine.co');
              developer.log(
                  '🔧 FIXED: Corrected apt.openvine.co to api.openvine.co: $fixedUrl',
                  name: 'VideoEvent');
              videoUrl = fixedUrl;
            } else {
              videoUrl = tagValue;
              developer.log('✅ Set videoUrl from url tag: $videoUrl',
                  name: 'VideoEvent');
            }
          } else {
            developer.log('⚠️ WARNING: Invalid URL in url tag: $tagValue',
                name: 'VideoEvent');
          }
        case 'imeta':
          developer.log('🔍 DEBUG: Found imeta tag with ${tag.length} elements',
              name: 'VideoEvent');
          // Parse imeta tag which contains comma-separated metadata
          // Ensure we have a List<String> for the parser
          final iMetaTag = List<String>.from(tag);
          _parseImetaTag(iMetaTag, (key, value) {
            developer.log('🔍 DEBUG: imeta key="$key" value="$value"',
                name: 'VideoEvent');
            switch (key) {
              case 'url':
                developer.log('🔍 DEBUG: imeta URL value: $value',
                    name: 'VideoEvent');
                // Check if this is a valid video URL and prefer it over existing URL if better
                if (value.isNotEmpty && _isValidVideoUrl(value)) {
                  if (value.contains('apt.openvine.co')) {
                    // Fix typo: apt.openvine.co -> api.openvine.co
                    final fixedUrl = value.replaceAll('apt.openvine.co', 'api.openvine.co');
                    developer.log(
                        '🔧 FIXED: Corrected apt.openvine.co to api.openvine.co in imeta: $fixedUrl',
                        name: 'VideoEvent');
                    videoUrl ??= fixedUrl; // Only set if not already set
                  } else {
                    videoUrl ??= value; // Only set if not already set
                    developer.log('✅ Set videoUrl from imeta: $value',
                        name: 'VideoEvent');
                  }
                } else {
                  developer.log('⚠️ WARNING: Invalid URL in imeta: $value',
                      name: 'VideoEvent');
                }
              case 'm':
                mimeType ??= value;
              case 'x':
                sha256 ??= value;
              case 'size':
                fileSize ??= int.tryParse(value);
              case 'dim':
                dimensions ??= value;
              case 'thumb':
                // Thumbnail URL
                thumbnailUrl ??= value;
              case 'image':
                // NIP-92 uses 'image' for thumbnail in imeta
                thumbnailUrl ??= value;
              case 'blurhash':
                // Blurhash for progressive loading
                blurhash ??= value;
              case 'duration':
                duration ??= double.tryParse(value)?.round();
            }
          });
        case 'title':
          title = tagValue as String?;
        case 'published_at':
          publishedAt = tagValue as String?;
        case 'duration':
          duration = int.tryParse(tagValue);
        case 'dim':
          dimensions = tagValue as String?;
        case 'm':
          mimeType = tagValue as String?;
        case 'x':
          sha256 = tagValue as String?;
        case 'size':
          fileSize = int.tryParse(tagValue);
        case 'thumb':
          // Thumbnail URL
          thumbnailUrl = tagValue as String?;
        case 'image':
          // Alternative to 'thumb' tag - some clients use 'image' instead
          thumbnailUrl ??= tagValue as String?;
        case 'd':
          // Replaceable event ID - original vine ID
          vineId = tagValue as String?;
        case 'h':
          // Group/community tag
          group = tagValue as String?;
        case 'alt':
          // Accessibility text
          altText = tagValue as String?;
        case 'blurhash':
          // Blurhash for progressive image loading
          blurhash = tagValue as String?;
        case 'loops':
          // Original loop count from classic Vine
          originalLoops = int.tryParse(tagValue);
        case 'likes':
          // Original like count from classic Vine
          originalLikes = int.tryParse(tagValue);
        case 't':
          if (tagValue.isNotEmpty) {
            hashtags.add(tagValue);
          }
        case 'r':
          // NIP-25 reference - might contain media URLs
          // Also handle "r" tags with type annotation (e.g., ["r", "url", "video"] or ["r", "url", "thumbnail"])
          if (tag.length >= 3) {
            final url = tagValue;
            final type = tag[2];
            developer.log(
                '🔍 DEBUG: Found r tag with type annotation: url="$url" type="$type"',
                name: 'VideoEvent');

            if (type == 'video' && url.isNotEmpty && _isValidVideoUrl(url)) {
              videoUrl ??= url;
              developer.log(
                  '✅ Found video URL in r tag with type annotation: $url',
                  name: 'VideoEvent');
            } else if (type == 'thumbnail' &&
                url.isNotEmpty &&
                !url.contains('picsum.photos')) {
              thumbnailUrl ??= url;
              developer.log(
                  '✅ Found thumbnail URL in r tag with type annotation: $url',
                  name: 'VideoEvent');
            }
          } else if (tagValue.isNotEmpty && _isValidVideoUrl(tagValue)) {
            // Fallback: if no type annotation, treat as video URL
            videoUrl ??= tagValue;
            developer.log('✅ Found video URL in r tag: $tagValue',
                name: 'VideoEvent');
          }
        case 'e':
          // Event reference - check if it's a media URL in disguise
          if (tagValue.isNotEmpty && _isValidVideoUrl(tagValue)) {
            videoUrl ??= tagValue;
            developer.log('✅ Found video URL in e tag: $tagValue',
                name: 'VideoEvent');
          }
        case 'i':
          // External identity - sometimes used for media
          if (tagValue.isNotEmpty && _isValidVideoUrl(tagValue)) {
            videoUrl ??= tagValue;
            developer.log('✅ Found video URL in i tag: $tagValue',
                name: 'VideoEvent');
          }
        default:
          // POSTEL'S LAW: Check if any unknown tag contains a valid video URL
          if (tagValue.isNotEmpty && _isValidVideoUrl(tagValue)) {
            videoUrl ??= tagValue;
            developer.log(
                '✅ Found video URL in unknown tag "$tagName": $tagValue',
                name: 'VideoEvent');
          }
      }

      // Store all tags for potential future use
      tags[tagName] = tagValue;
    }

    final createdAtTimestamp = event.createdAt is DateTime
        ? (event.createdAt as DateTime).millisecondsSinceEpoch ~/ 1000
        : int.tryParse(event.createdAt.toString()) ?? 0;

    developer.log('🔍 DEBUG: Final parsing results:', name: 'VideoEvent');
    developer.log('🔍 DEBUG: videoUrl = $videoUrl', name: 'VideoEvent');
    developer.log('🔍 DEBUG: thumbnailUrl = $thumbnailUrl', name: 'VideoEvent');
    developer.log('🔍 DEBUG: duration = $duration', name: 'VideoEvent');

    // POSTEL'S LAW: Be liberal in what you accept
    // Apply comprehensive fallback logic to find video URLs
    if (videoUrl == null || videoUrl!.isEmpty) {
      developer.log(
          '🔧 FALLBACK: No video URL found in tags, searching content...',
          name: 'VideoEvent');
      videoUrl = _extractVideoUrlFromContent(event.content);
      if (videoUrl != null) {
        developer.log('✅ FALLBACK: Found video URL in content: $videoUrl',
            name: 'VideoEvent');
      }
    }

    // If still no URL, try to find any URL that might be a video
    if (videoUrl == null || videoUrl!.isEmpty) {
      developer.log(
          '🔧 FALLBACK: Searching all tags for any potential video URL...',
          name: 'VideoEvent');
      videoUrl = _findAnyVideoUrlInTags(event.tags);
      if (videoUrl != null) {
        developer.log(
            '✅ FALLBACK: Found potential video URL in tags: $videoUrl',
            name: 'VideoEvent');
      }
    }

    // If we still have a broken apt.openvine.co URL (shouldn't happen now), fix it
    if (videoUrl != null && videoUrl!.contains('apt.openvine.co')) {
      final fixedUrl = videoUrl!.replaceAll('apt.openvine.co', 'api.openvine.co');
      developer.log(
          '🔧 FINAL FIX: Corrected remaining apt.openvine.co to api.openvine.co: $fixedUrl',
          name: 'VideoEvent');
      videoUrl = fixedUrl;
    }

    developer.log(
        '🔍 DEBUG: hasVideo = ${videoUrl != null && videoUrl!.isNotEmpty}',
        name: 'VideoEvent');

    // Use 'd' tag if available, otherwise fallback to event ID
    // Many relays don't include 'd' tags on Kind 32222 events
    if (vineId == null || vineId.isEmpty) {
      developer.log(
          '⚠️ WARNING: Kind 32222 event missing "d" tag, using event ID as fallback',
          name: 'VideoEvent');
      vineId = event.id; // Use event ID as unique identifier
    }

    // Generate fallback thumbnail URL if none provided
    final String? finalThumbnailUrl = thumbnailUrl ?? _generateFallbackThumbnailUrl(videoUrl, event.id);
    
    if (finalThumbnailUrl != thumbnailUrl) {
      developer.log('🔧 FALLBACK: Generated thumbnail URL: $finalThumbnailUrl', name: 'VideoEvent');
    }
    
    developer.log('🖼️ FINAL: thumbnailUrl = $finalThumbnailUrl', name: 'VideoEvent');
    developer.log('🖼️ FINAL: blurhash = $blurhash', name: 'VideoEvent');

    return VideoEvent(
      id: event.id,
      pubkey: event.pubkey,
      createdAt: createdAtTimestamp,
      content: event.content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(createdAtTimestamp * 1000),
      title: title,
      videoUrl: videoUrl,
      thumbnailUrl: finalThumbnailUrl,
      duration: duration,
      dimensions: dimensions,
      mimeType: mimeType,
      sha256: sha256,
      fileSize: fileSize,
      hashtags: hashtags,
      publishedAt: publishedAt,
      rawTags: tags,
      vineId: vineId,
      group: group,
      altText: altText,
      blurhash: blurhash,
      isRepost: false,
      reposterId: null,
      reposterPubkey: null,
      repostedAt: null,
      originalLoops: originalLoops,
      originalLikes: originalLikes,
    );
  }
  final String id;
  final String pubkey;
  final int createdAt;
  final String content;
  final String? title;
  final String? videoUrl;
  final String? thumbnailUrl;
  final int? duration; // in seconds
  final String? dimensions; // WIDTHxHEIGHT
  final String? mimeType;
  final String? sha256;
  final int? fileSize;
  final List<String> hashtags;
  final DateTime timestamp;
  final String? publishedAt;
  final Map<String, String> rawTags;

  // Vine-specific fields from NIP-32222 spec
  final String? vineId; // 'd' tag - original vine ID for replaceable events
  final String? group; // 'h' tag - group/community identification
  final String? altText; // 'alt' tag - accessibility text
  final String? blurhash; // 'blurhash' tag - for progressive image loading

  // Repost metadata fields
  final bool isRepost;
  final String? reposterId;
  final String? reposterPubkey;
  final DateTime? repostedAt;

  // Content moderation fields
  final bool
      isFlaggedContent; // Content flagged as potentially adult/inappropriate
  final String? moderationStatus;
  
  // Original Vine metrics (from imported data)
  final int? originalLoops; // Original loop count from classic Vine
  final int? originalLikes; // Original like count from classic Vine

  /// Parse imeta tag which contains space-separated key-value pairs
  /// NIP-32222 format: ["imeta", "key1 value1", "key2 value2", ...]
  static void _parseImetaTag(
      List<String> tag, void Function(String key, String value) onKeyValue) {
    // Skip the first element which is "imeta"
    for (var i = 1; i < tag.length; i++) {
      final element = tag[i];
      // Each element is "key value" separated by space
      final spaceIndex = element.indexOf(' ');
      if (spaceIndex > 0) {
        final key = element.substring(0, spaceIndex);
        final value = element.substring(spaceIndex + 1);
        onKeyValue(key, value);
      }
    }
  }

  /// Extract width from dimensions string
  int? get width {
    if (dimensions == null) return null;
    final parts = dimensions!.split('x');
    return parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  }

  /// Extract height from dimensions string
  int? get height {
    if (dimensions == null) return null;
    final parts = dimensions!.split('x');
    return parts.length > 1 ? int.tryParse(parts[1]) : null;
  }

  /// Check if video is in portrait orientation
  bool get isPortrait {
    if (width == null || height == null) return false;
    return height! > width!;
  }

  /// Get file size in MB
  double? get fileSizeMB {
    if (fileSize == null) return null;
    return fileSize! / (1024 * 1024);
  }

  /// Get formatted duration string (e.g., "0:15")
  String get formattedDuration {
    if (duration == null) return '';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get relative time string (e.g., "2 hours ago")
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${difference.inDays ~/ 7}w ago';
    }
  }

  /// Get shortened pubkey for display (first 8 characters + npub prefix)
  String get displayPubkey {
    // In a real implementation, convert to npub format
    // For now, just show first 8 chars
    return pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey;
  }

  /// Check if this event has video content
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// Get effective thumbnail URL with fallback generation
  String? get effectiveThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl;
    }

    // NO MORE FAKE PICSUM SHIT!
    // Return null so we use proper video icon placeholder
    return null;
  }

  /// Get thumbnail URL from API service with automatic generation
  /// This method provides an async fallback that generates thumbnails when missing
  Future<String?> getApiThumbnailUrl({
    double timeSeconds = 2.5,
    ThumbnailSize size = ThumbnailSize.medium,
  }) async {
    // First check if we already have a thumbnail URL
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl;
    }

    // Use the new thumbnail API service for automatic generation
    return ThumbnailApiService.getThumbnailWithFallback(
      id,
      timeSeconds: timeSeconds,
      size: size,
    );
  }

  /// Get thumbnail URL synchronously from API service (no generation)
  /// This method provides immediate URL construction without async calls
  String getApiThumbnailUrlSync({
    double timeSeconds = 2.5,
    ThumbnailSize size = ThumbnailSize.medium,
  }) {
    // First check if we already have a thumbnail URL
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl!;
    }

    // Generate API URL (may or may not exist, but provides proper fallback)
    return ThumbnailApiService.getThumbnailUrl(
      id,
      timeSeconds: timeSeconds,
      size: size,
    );
  }

  /// Check if video URL is a GIF
  bool get isGif {
    if (mimeType != null) {
      return mimeType!.toLowerCase() == 'image/gif';
    }
    if (videoUrl != null) {
      return videoUrl!.toLowerCase().endsWith('.gif');
    }
    return false;
  }

  /// Check if video URL is MP4
  bool get isMp4 {
    if (mimeType != null) {
      return mimeType!.toLowerCase() == 'video/mp4';
    }
    if (videoUrl != null) {
      return videoUrl!.toLowerCase().endsWith('.mp4');
    }
    return false;
  }

  /// Create a copy with updated fields
  VideoEvent copyWith({
    String? id,
    String? pubkey,
    int? createdAt,
    String? content,
    String? title,
    String? videoUrl,
    String? thumbnailUrl,
    int? duration,
    String? dimensions,
    String? mimeType,
    String? sha256,
    int? fileSize,
    List<String>? hashtags,
    DateTime? timestamp,
    String? publishedAt,
    Map<String, String>? rawTags,
    String? vineId,
    String? group,
    String? altText,
    String? blurhash,
    bool? isRepost,
    String? reposterId,
    String? reposterPubkey,
    DateTime? repostedAt,
  }) =>
      VideoEvent(
        id: id ?? this.id,
        pubkey: pubkey ?? this.pubkey,
        createdAt: createdAt ?? this.createdAt,
        content: content ?? this.content,
        title: title ?? this.title,
        videoUrl: videoUrl ?? this.videoUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        duration: duration ?? this.duration,
        dimensions: dimensions ?? this.dimensions,
        mimeType: mimeType ?? this.mimeType,
        sha256: sha256 ?? this.sha256,
        fileSize: fileSize ?? this.fileSize,
        hashtags: hashtags ?? this.hashtags,
        timestamp: timestamp ?? this.timestamp,
        publishedAt: publishedAt ?? this.publishedAt,
        rawTags: rawTags ?? this.rawTags,
        vineId: vineId ?? this.vineId,
        group: group ?? this.group,
        altText: altText ?? this.altText,
        blurhash: blurhash ?? this.blurhash,
        isRepost: isRepost ?? this.isRepost,
        reposterId: reposterId ?? this.reposterId,
        reposterPubkey: reposterPubkey ?? this.reposterPubkey,
        repostedAt: repostedAt ?? this.repostedAt,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoEvent && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VideoEvent('
      'id: ${id.substring(0, 8)}..., '
      'pubkey: $displayPubkey, '
      'title: $title, '
      'duration: $formattedDuration, '
      'time: $relativeTime'
      ')';

  /// Create a VideoEvent instance representing a repost
  /// Used when displaying Kind 6 repost events in the feed
  static VideoEvent createRepostEvent({
    required VideoEvent originalEvent,
    required String repostEventId,
    required String reposterPubkey,
    required DateTime repostedAt,
  }) =>
      originalEvent.copyWith(
        isRepost: true,
        reposterId: repostEventId,
        reposterPubkey: reposterPubkey,
        repostedAt: repostedAt,
      );

  /// Check if a URL is a valid video URL
  static bool _isValidVideoUrl(String url) {
    if (url.isEmpty) return false;

    // Fix common typo: apt.openvine.co -> api.openvine.co
    String correctedUrl = url;
    if (url.contains('apt.openvine.co')) {
      correctedUrl = url.replaceAll('apt.openvine.co', 'api.openvine.co');
    }

    try {
      final uri = Uri.parse(correctedUrl);

      // Must be HTTP or HTTPS
      if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
        return false;
      }

      // Must have a valid host
      if (uri.host.isEmpty) return false;

      // Check for video file extensions or known video hosting domains
      final path = uri.path.toLowerCase();
      final host = uri.host.toLowerCase();

      // Known video file extensions
      if (path.endsWith('.mp4') ||
          path.endsWith('.webm') ||
          path.endsWith('.mov') ||
          path.endsWith('.avi') ||
          path.endsWith('.gif')) {
        return true;
      }

      // Known video hosting domains
      if (host.contains('blossom.primal.net') ||
          host.contains('nostr.build') ||
          host.contains('primal.net') ||
          host.contains('void.cat') ||
          host.contains('nostpic.com') ||
          host.contains('openvine.co') ||
          host.contains('satellite.earth')) {
        return true;
      }

      return false;
    } catch (e) {
      developer.log('🔍 INVALID URL (parse error): $correctedUrl - error: $e', name: 'VideoEvent');
      return false;
    }
  }

  /// Extract video URL from event content text (fallback strategy)
  static String? _extractVideoUrlFromContent(String content) {
    // Look for URLs in the content using regex
    final urlRegex = RegExp(r'https?://[^\s]+');
    final matches = urlRegex.allMatches(content);

    for (final match in matches) {
      var url = match.group(0);
      if (url != null) {
        // Fix common typo: apt.openvine.co -> api.openvine.co
        if (url.contains('apt.openvine.co')) {
          url = url.replaceAll('apt.openvine.co', 'api.openvine.co');
        }
        if (_isValidVideoUrl(url)) {
          return url;
        }
      }
    }

    return null;
  }

  /// Find any potential video URL in all tags (aggressive fallback)
  static String? _findAnyVideoUrlInTags(List<dynamic> tags) {
    for (final tagRaw in tags) {
      if (tagRaw is! List || tagRaw.isEmpty) continue;

      final tag = tagRaw.map((e) => e.toString()).toList();

      // Check all tag values for potential URLs
      for (var i = 1; i < tag.length; i++) {
        var value = tag[i];
        if (value.isNotEmpty) {
          // Fix common typo: apt.openvine.co -> api.openvine.co
          if (value.contains('apt.openvine.co')) {
            value = value.replaceAll('apt.openvine.co', 'api.openvine.co');
          }
          if (_isValidVideoUrl(value)) {
            return value;
          }
        }
      }
    }

    return null;
  }

  /// Generate fallback thumbnail URL when none is provided
  static String? _generateFallbackThumbnailUrl(String? videoUrl, String eventId) {
    // If no video URL, can't generate thumbnail
    if (videoUrl == null || videoUrl.isEmpty) {
      return null;
    }

    // Fix common typo: apt.openvine.co -> api.openvine.co
    String correctedUrl = videoUrl;
    if (videoUrl.contains('apt.openvine.co')) {
      correctedUrl = videoUrl.replaceAll('apt.openvine.co', 'api.openvine.co');
    }

    try {
      final uri = Uri.parse(correctedUrl);
      
      // For api.openvine.co videos, use the thumbnail API service with event ID
      if (uri.host.contains('api.openvine.co') || uri.host.contains('apt.openvine.co')) {
        // Use the event ID for thumbnail generation, not the media ID
        // The thumbnail API expects event IDs
        return ThumbnailApiService.getThumbnailUrl(eventId);
      }
      
      // For other video hosts, try to generate a thumbnail URL pattern
      if (uri.host.contains('blossom.primal.net') || uri.host.contains('primal.net')) {
        // Primal uses a thumbnail service with .jpg extension
        final videoPath = uri.path;
        if (videoPath.endsWith('.mp4')) {
          final basePath = videoPath.substring(0, videoPath.length - 4);
          return 'https://${uri.host}$basePath.jpg';
        }
      }
      
      // For nostr.build, they have a thumbnail pattern
      if (uri.host.contains('nostr.build')) {
        final videoPath = uri.path;
        if (videoPath.contains('/av/')) {
          // nostr.build thumbnail pattern: replace /av/ with /i/ and change extension
          final thumbnailPath = videoPath.replaceAll('/av/', '/i/').replaceAll('.mp4', '.jpg');
          return 'https://${uri.host}$thumbnailPath';
        }
      }
      
      developer.log('🔧 FALLBACK: Could not generate thumbnail URL for video host: ${uri.host}', name: 'VideoEvent');
      return null;
    } catch (e) {
      developer.log('🔧 FALLBACK: Error generating thumbnail URL: $e', name: 'VideoEvent');
      return null;
    }
  }
}

/// Exception thrown when parsing video events
class VideoEventException implements Exception {
  const VideoEventException(this.message);
  final String message;

  @override
  String toString() => 'VideoEventException: $message';
}
