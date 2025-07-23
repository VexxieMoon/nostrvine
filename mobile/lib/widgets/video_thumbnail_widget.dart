// ABOUTME: Smart video thumbnail widget that automatically generates thumbnails when missing
// ABOUTME: Uses the new thumbnail API service with proper loading states and fallbacks

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openvine/models/video_event.dart';
import 'package:openvine/services/thumbnail_api_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/video_icon_placeholder.dart';

/// Smart thumbnail widget that automatically generates thumbnails from the API
class VideoThumbnailWidget extends StatefulWidget {
  const VideoThumbnailWidget({
    required this.video,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.timeSeconds = 2.5,
    this.size = ThumbnailSize.medium,
    this.showPlayIcon = false,
    this.borderRadius,
  });
  final VideoEvent video;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double timeSeconds;
  final ThumbnailSize size;
  final bool showPlayIcon;
  final BorderRadius? borderRadius;

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  String? _thumbnailUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if video ID, time, or size changed
    if (oldWidget.video.id != widget.video.id ||
        oldWidget.timeSeconds != widget.timeSeconds ||
        oldWidget.size != widget.size) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    Log.debug(
      '🖼️ VideoThumbnailWidget: Loading thumbnail for video ${widget.video.id.substring(0, 8)}...',
      name: 'VideoThumbnailWidget',
      category: LogCategory.video,
    );
    Log.debug(
      '   Video URL: ${widget.video.videoUrl}',
      name: 'VideoThumbnailWidget',
      category: LogCategory.video,
    );
    Log.debug(
      '   Existing thumbnail: ${widget.video.thumbnailUrl}',
      name: 'VideoThumbnailWidget',
      category: LogCategory.video,
    );

    // First check if we have an existing thumbnail
    if (widget.video.effectiveThumbnailUrl != null) {
      Log.info(
        '✅ Using existing thumbnail for ${widget.video.id.substring(0, 8)}: ${widget.video.effectiveThumbnailUrl}',
        name: 'VideoThumbnailWidget',
        category: LogCategory.video,
      );
      setState(() {
        _thumbnailUrl = widget.video.effectiveThumbnailUrl;
        _isLoading = false;
      });
      return;
    }

    Log.info(
      '🚀 No existing thumbnail found, requesting API generation for ${widget.video.id.substring(0, 8)}...',
      name: 'VideoThumbnailWidget',
      category: LogCategory.video,
    );
    Log.debug(
      '   timeSeconds: ${widget.timeSeconds}, size: ${widget.size}',
      name: 'VideoThumbnailWidget',
      category: LogCategory.video,
    );

    // Try to get thumbnail from API
    setState(() {
      _isLoading = true;
    });

    try {
      final apiUrl = await widget.video.getApiThumbnailUrl(
        timeSeconds: widget.timeSeconds,
        size: widget.size,
      );

      Log.info(
        '🖼️ Thumbnail API response for ${widget.video.id.substring(0, 8)}: ${apiUrl ?? "null"}',
        name: 'VideoThumbnailWidget',
        category: LogCategory.video,
      );

      // Check if the API returned a placeholder SVG
      if (apiUrl != null && await _isPlaceholderSvg(apiUrl)) {
        Log.debug(
          '⚠️ Thumbnail API returned placeholder SVG for ${widget.video.id.substring(0, 8)}, using icon placeholder instead',
          name: 'VideoThumbnailWidget',
          category: LogCategory.video,
        );
        if (mounted) {
          setState(() {
            _thumbnailUrl = null; // Use placeholder instead
            _isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _thumbnailUrl = apiUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      Log.error(
        '❌ Thumbnail API failed for ${widget.video.id.substring(0, 8)}: $e',
        name: 'VideoThumbnailWidget',
        category: LogCategory.video,
      );
      if (mounted) {
        setState(() {
          _thumbnailUrl = null;
          _isLoading = false;
        });
      }
    }
  }

  /// Check if a URL returns a placeholder SVG
  Future<bool> _isPlaceholderSvg(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      final contentType = response.headers['content-type'];
      if (contentType != null && contentType.contains('image/svg+xml')) {
        Log.debug(
          '🔍 Detected SVG content type for ${widget.video.id.substring(0, 8)}, treating as placeholder',
          name: 'VideoThumbnailWidget',
          category: LogCategory.video,
        );
        return true;
      }
      return false;
    } catch (e) {
      Log.debug(
        '🔍 Could not check content type for ${widget.video.id.substring(0, 8)}, assuming real thumbnail: $e',
        name: 'VideoThumbnailWidget',
        category: LogCategory.video,
      );
      return false;
    }
  }

  Widget _buildContent() {
    if (_isLoading) {
      return VideoIconPlaceholder(
        width: widget.width,
        height: widget.height,
        showLoading: true,
        showPlayIcon: widget.showPlayIcon,
        borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
      );
    }

    if (_thumbnailUrl != null) {
      return Image.network(
        _thumbnailUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => VideoIconPlaceholder(
          width: widget.width,
          height: widget.height,
          showPlayIcon: widget.showPlayIcon,
          borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return VideoIconPlaceholder(
            width: widget.width,
            height: widget.height,
            showLoading: true,
            showPlayIcon: widget.showPlayIcon,
            borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
          );
        },
      );
    }

    // Fallback to placeholder
    return VideoIconPlaceholder(
      width: widget.width,
      height: widget.height,
      showPlayIcon: widget.showPlayIcon,
      borderRadius: widget.borderRadius?.topLeft.x ?? 8.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    var content = _buildContent();

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }
}

