// ABOUTME: NostrService - production implementation using embedded relay DIRECTLY
// ABOUTME: Uses flutter_embedded_nostr_relay API directly, manages external relay connections

import 'dart:async';
import 'dart:convert';

import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart' as embedded;
import 'package:nostr_sdk/event.dart';
import 'package:nostr_sdk/filter.dart' as nostr;
import 'package:openvine/models/nip94_metadata.dart';
import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/p2p_discovery_service.dart';
import 'package:openvine/services/p2p_video_sync_service.dart';
import 'package:openvine/utils/unified_logger.dart';

/// Production implementation of NostrService using EmbeddedNostrRelay directly
/// Manages external relay connections and provides unified API to the app
class NostrService implements INostrService {
  NostrService(this._keyManager);
  
  final NostrKeyManager _keyManager;
  final Map<String, StreamController<Event>> _subscriptions = {};
  final Map<String, bool> _relayAuthStates = {};
  final _authStateController = StreamController<Map<String, bool>>.broadcast();
  
  // Embedded relay (handles external connections automatically)
  embedded.EmbeddedNostrRelay? _embeddedRelay;
  
  // P2P sync components
  P2PDiscoveryService? _p2pService;
  P2PVideoSyncService? _videoSyncService;
  bool _p2pEnabled = false;
  
  bool _isInitialized = false;
  bool _isDisposed = false;
  final List<String> _configuredRelays = [];
  
  @override
  Future<void> initialize({List<String>? customRelays, bool enableP2P = true}) async {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (_isInitialized) return; // Already initialized
    
    Log.info('Starting initialization with embedded relay', name: 'NostrService', category: LogCategory.relay);
    
    try {
      // Initialize embedded relay
      _embeddedRelay = embedded.EmbeddedNostrRelay();
      await _embeddedRelay!.initialize(
        enableGarbageCollection: true,
      );
      Log.info('Embedded relay initialized', name: 'NostrService', category: LogCategory.relay);
      
      // Add external relays (embedded relay will manage connections)
      final defaultRelay = 'wss://relay3.openvine.co';
      final relaysToAdd = customRelays ?? [defaultRelay];
      
      for (final relayUrl in relaysToAdd) {
        try {
          await _embeddedRelay!.addExternalRelay(relayUrl);
          _configuredRelays.add(relayUrl);
          Log.info('Added external relay: $relayUrl', name: 'NostrService', category: LogCategory.relay);
          
          // Check if the relay is actually connected
          final connectedRelays = _embeddedRelay!.connectedRelays;
          Log.debug('Connected relays after adding: $connectedRelays', name: 'NostrService', category: LogCategory.relay);
        } catch (e) {
          Log.error('Failed to add relay $relayUrl: $e', name: 'NostrService', category: LogCategory.relay);
        }
      }
      
      // Initialize P2P sync if enabled
      if (enableP2P) {
        _p2pEnabled = true;
        // P2P initialization moved to lazy loading when needed
      }
      
      _isInitialized = true;
      Log.info('Initialization complete with ${_configuredRelays.length} external relays', name: 'NostrService', category: LogCategory.relay);
      
    } catch (e) {
      Log.error('Failed to initialize: $e', name: 'NostrService', category: LogCategory.relay);
      throw StateError('Failed to initialize embedded relay: $e');
    }
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isDisposed => _isDisposed;

  @override
  List<String> get connectedRelays => _embeddedRelay?.connectedRelays ?? [];

  @override
  String? get publicKey => _keyManager.publicKey;

  @override
  bool get hasKeys => _keyManager.hasKeys;

  @override
  NostrKeyManager get keyManager => _keyManager;

  @override
  int get relayCount => _configuredRelays.length;

  @override
  int get connectedRelayCount => _embeddedRelay?.connectedRelays.length ?? 0;

  @override
  List<String> get relays => List.from(_configuredRelays);

  @override
  Map<String, dynamic> get relayStatuses {
    final statuses = <String, dynamic>{};
    
    // Get status from embedded relay for all configured external relays
    final connectedRelays = _embeddedRelay?.connectedRelays ?? [];
    for (final relayUrl in _configuredRelays) {
      final isConnected = connectedRelays.contains(relayUrl);
      statuses[relayUrl] = {
        'connected': isConnected,
        'authenticated': isConnected, // Embedded relay handles auth
      };
      // Update our auth state tracking
      _relayAuthStates[relayUrl] = isConnected;
    }
    
    return statuses;
  }

  @override
  Map<String, bool> get relayAuthStates {
    // Update auth states from embedded relay status
    final connectedRelays = _embeddedRelay?.connectedRelays ?? [];
    for (final relayUrl in _configuredRelays) {
      _relayAuthStates[relayUrl] = connectedRelays.contains(relayUrl);
    }
    return Map.from(_relayAuthStates);
  }

  @override
  Stream<Map<String, bool>> get authStateStream => _authStateController.stream;

  @override
  bool isRelayAuthenticated(String relayUrl) {
    final connectedRelays = _embeddedRelay?.connectedRelays ?? [];
    return connectedRelays.contains(relayUrl);
  }

  @override
  bool get isVineRelayAuthenticated {
    final connectedRelays = _embeddedRelay?.connectedRelays ?? [];
    return _configuredRelays.any((relay) => connectedRelays.contains(relay));
  }

  @override
  void setAuthTimeout(Duration timeout) {
    // Not applicable for embedded relay
  }

  @override
  Stream<Event> subscribeToEvents({required List<nostr.Filter> filters, bool bypassLimits = false}) {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (!_isInitialized) throw StateError('NostrService not initialized');
    if (_embeddedRelay == null) throw StateError('Embedded relay not initialized');
    
    // Generate deterministic subscription ID based on filter content
    // This prevents duplicate subscriptions with identical filters
    final filterHash = _generateFilterHash(filters);
    final id = 'sub_$filterHash';
    
    // Check if we already have this exact subscription
    if (_subscriptions.containsKey(id) && !_subscriptions[id]!.isClosed) {
      Log.info('🔄 Reusing existing subscription $id with identical filters', name: 'NostrService', category: LogCategory.relay);
      return _subscriptions[id]!.stream;
    }
    
    // Check for too many concurrent subscriptions
    if (_subscriptions.length >= 10 && !bypassLimits) {
      Log.warning('Too many concurrent subscriptions (${_subscriptions.length}). Consider cancelling old ones.', name: 'NostrService', category: LogCategory.relay);
      // Clean up any closed controllers
      _subscriptions.removeWhere((key, controller) => controller.isClosed);
      Log.debug('After cleanup, active subscriptions: ${_subscriptions.length}', name: 'NostrService', category: LogCategory.relay);
    }
    
    final controller = StreamController<Event>.broadcast();
    // Per-subscription de-duplication to avoid duplicate EVENTs from multiple relays/filters
    final seenEventIds = <String>{};
    _subscriptions[id] = controller;
    Log.debug('Total active subscriptions: ${_subscriptions.length}', name: 'NostrService', category: LogCategory.relay);
    
    // Convert nostr_sdk filters to embedded relay filters
    final embeddedFilters = filters.map(_convertToEmbeddedFilter).toList();
    
    // Debug logging for filters
    Log.debug('Creating subscription $id with ${embeddedFilters.length} filters', name: 'NostrService', category: LogCategory.relay);
    for (var i = 0; i < embeddedFilters.length; i++) {
      final filter = embeddedFilters[i];
      Log.debug('  Filter $i: kinds=${filter.kinds}, authors=${filter.authors?.length ?? 0} authors, tags=${filter.tags}', name: 'NostrService', category: LogCategory.relay);
      // Log first few authors for debugging
      if (filter.authors != null && filter.authors!.isNotEmpty) {
        final authorsPreview = filter.authors!.take(3).join(', ');
        Log.debug('    First authors: $authorsPreview', name: 'NostrService', category: LogCategory.relay);
      }
    }
    
    // Use embedded relay directly - it handles external relay subscriptions automatically
    Log.debug('Calling embedded relay subscribe with $id', name: 'NostrService', category: LogCategory.relay);
    final subscription = _embeddedRelay!.subscribe(
      subscriptionId: id,
      filters: embeddedFilters,
      onEvent: (embeddedEvent) {
        Log.debug('Embedded relay returned event for $id', name: 'NostrService', category: LogCategory.relay);
        // Convert embedded relay event to nostr_sdk event
        final event = _convertFromEmbeddedEvent(embeddedEvent);
        
        // Drop duplicates for this subscription
        if (seenEventIds.contains(event.id)) {
          Log.debug('Dropping duplicate event ${event.id.substring(0, 8)} for $id', name: 'NostrService', category: LogCategory.relay);
          return;
        }
        seenEventIds.add(event.id);
        
        if (!controller.isClosed) {
          // Debug log for home feed events
          if (id.contains('homeFeed')) {
            Log.debug('Received home feed event - kind: ${event.kind}, author: ${event.pubkey.substring(0, 8)}...', name: 'NostrService', category: LogCategory.relay);
          }
          controller.add(event);
        }
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );
    
    // Handle controller disposal
    controller.onCancel = () {
      Log.debug('Stream cancelled for subscription $id - closing embedded relay subscription', name: 'NostrService', category: LogCategory.relay);
      try {
        subscription.close();
        print('NostrService: Successfully closed embedded relay subscription $id');
      } catch (e) {
        print('NostrService: Error closing embedded relay subscription $id: $e');
      }
      _subscriptions.remove(id);
      print('NostrService: Active subscriptions after removal: ${_subscriptions.length}');
    };
    
    return controller.stream;
  }

  @override
  Future<NostrBroadcastResult> broadcastEvent(Event event) async {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (!_isInitialized) throw StateError('NostrService not initialized');
    if (_embeddedRelay == null) throw StateError('Embedded relay not initialized');
    
    final results = <String, bool>{};
    final errors = <String, String>{};
    
    try {
      // Convert nostr_sdk event to embedded relay event
      final embeddedEvent = _convertToEmbeddedEvent(event);
      
      // Publish to embedded relay - it will automatically forward to external relays
      final success = await _embeddedRelay!.publish(embeddedEvent);
      
      if (success) {
        // Mark local and connected external relays as successful
        results['local'] = true;
        
        // The embedded relay handles external relay publishing
        for (final relayUrl in _configuredRelays) {
          final isConnected = _embeddedRelay!.connectedRelays.contains(relayUrl);
          results[relayUrl] = isConnected;
          if (!isConnected) {
            errors[relayUrl] = 'Relay not connected';
          }
        }
      } else {
        results['local'] = false;
        errors['local'] = 'Event rejected by embedded relay';
        
        // Mark all external relays as failed too
        for (final relayUrl in _configuredRelays) {
          results[relayUrl] = false;
          errors[relayUrl] = 'Local relay publish failed';
        }
      }
      
    } catch (e) {
      results['local'] = false;
      errors['local'] = e.toString();
      
      // Mark all external relays as failed too
      for (final relayUrl in _configuredRelays) {
        results[relayUrl] = false;
        errors[relayUrl] = 'Embedded relay error: $e';
      }
    }
    
    final successCount = results.values.where((success) => success).length;
    
    return NostrBroadcastResult(
      event: event,
      successCount: successCount,
      totalRelays: results.length,
      results: results,
      errors: errors,
    );
  }

  @override
  Future<NostrBroadcastResult> publishFileMetadata({
    required NIP94Metadata metadata,
    required String content,
    List<String> hashtags = const [],
  }) async {
    // TODO: Implement file metadata publishing to embedded relay
    throw UnimplementedError('File metadata publishing not yet implemented');
  }

  @override
  Future<bool> addRelay(String relayUrl) async {
    if (_configuredRelays.contains(relayUrl)) {
      return false; // Already added
    }
    
    if (_embeddedRelay == null) {
      throw StateError('Embedded relay not initialized');
    }
    
    try {
      await _embeddedRelay!.addExternalRelay(relayUrl);
      _configuredRelays.add(relayUrl);
      print('NostrService: Added external relay: $relayUrl');
      return true;
    } catch (e) {
      print('NostrService: Failed to add relay $relayUrl: $e');
      return false;
    }
  }

  @override
  Future<void> removeRelay(String relayUrl) async {
    if (_embeddedRelay != null) {
      try {
        await _embeddedRelay!.removeExternalRelay(relayUrl);
      } catch (e) {
        print('NostrService: Failed to remove relay $relayUrl: $e');
      }
    }
    
    _configuredRelays.remove(relayUrl);
    _relayAuthStates.remove(relayUrl);
    print('NostrService: Removed external relay: $relayUrl');
  }

  @override
  Map<String, bool> getRelayStatus() {
    final status = <String, bool>{};
    final connectedRelays = _embeddedRelay?.connectedRelays ?? [];
    
    for (final relayUrl in _configuredRelays) {
      status[relayUrl] = connectedRelays.contains(relayUrl);
    }
    
    return status;
  }

  @override
  Future<void> reconnectAll() async {
    if (!_isInitialized) return;
    
    // Embedded relay doesn't need reconnection
    // TODO: Reconnect external relays if needed
  }

  @override
  Future<void> closeAllSubscriptions() async {
    for (final controller in _subscriptions.values) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
    _subscriptions.clear();
    
    // TODO: Close embedded relay subscriptions
  }

  @override
  Stream<Event> searchVideos(String query, {
    List<String>? authors,
    DateTime? since,
    DateTime? until,
    int? limit,
  }) {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (!_isInitialized) throw StateError('NostrService not initialized');
    if (_embeddedRelay == null) throw StateError('Embedded relay not initialized');
    
    // Create filter for video events
    final filter = embedded.Filter(
      kinds: [32222], // Video events
      authors: authors,
      since: since != null ? (since.millisecondsSinceEpoch ~/ 1000) : null,
      until: until != null ? (until.millisecondsSinceEpoch ~/ 1000) : null,
      limit: limit ?? 100,
    );
    
    // Use embedded relay to query cached events from external relays
    final controller = StreamController<Event>();
    
    () async {
      try {
        final embeddedEvents = await _embeddedRelay!.queryEvents([filter]);
        final searchQuery = query.toLowerCase();
        
        // Filter events based on search query
        for (final embeddedEvent in embeddedEvents) {
          // Search in content
          bool matches = embeddedEvent.content.toLowerCase().contains(searchQuery);
          
          // Also search in tags (title, description, etc.)
          if (!matches) {
            for (final tag in embeddedEvent.tags) {
              if (tag.any((value) => value.toLowerCase().contains(searchQuery))) {
                matches = true;
                break;
              }
            }
          }
          
          // Add matching events to the stream
          if (matches && !controller.isClosed) {
            final event = _convertFromEmbeddedEvent(embeddedEvent);
            controller.add(event);
          }
        }
        
        // Close the stream when done
        if (!controller.isClosed) {
          await controller.close();
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }();
    
    return controller.stream;
  }

  @override
  String get primaryRelay => _configuredRelays.isNotEmpty 
      ? _configuredRelays.first 
      : 'wss://relay3.openvine.co';

  /// Get embedded relay statistics for performance monitoring
  Future<Map<String, dynamic>?> getRelayStats() async {
    if (!_isInitialized || _embeddedRelay == null) return null;
    
    try {
      final stats = await _embeddedRelay!.getStats();
      final subscriptionStats = _embeddedRelay!.getSubscriptionStats();
      
      return {
        'database': stats,
        'subscriptions': subscriptionStats,
        'external_relays': _configuredRelays.length,
        'p2p_enabled': _p2pEnabled,
        'p2p_peers': _p2pService?.peers.length ?? 0,
        'p2p_connections': _p2pService?.connections.length ?? 0,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  
  // P2P Sync Methods
  
  /// Start P2P discovery for nearby OpenVine devices
  Future<bool> startP2PDiscovery() async {
    if (!_p2pEnabled) return false;
    
    await _ensureP2PInitialized();
    if (_p2pService == null) return false;
    
    try {
      await _p2pService!.startDiscovery();
      return true;
    } catch (e) {
      print('Failed to start P2P discovery: $e');
      return false;
    }
  }
  
  /// Stop P2P discovery
  Future<void> stopP2PDiscovery() async {
    if (_p2pService != null) {
      await _p2pService!.stopDiscovery();
    }
  }
  
  /// Start advertising this device for P2P connections
  Future<bool> startP2PAdvertising() async {
    if (!_p2pEnabled) return false;
    
    await _ensureP2PInitialized();
    if (_p2pService == null) return false;
    
    try {
      await _p2pService!.startAdvertising();
      return true;
    } catch (e) {
      print('Failed to start P2P advertising: $e');
      return false;
    }
  }
  
  /// Stop advertising this device
  Future<void> stopP2PAdvertising() async {
    if (_p2pService != null) {
      await _p2pService!.stopAdvertising();
    }
  }
  
  /// Get list of discovered P2P peers
  List<P2PPeer> getP2PPeers() {
    return _p2pService?.peers ?? [];
  }
  
  /// Connect to a P2P peer and start syncing video events
  Future<bool> connectToP2PPeer(P2PPeer peer) async {
    if (!_p2pEnabled) return false;
    
    await _ensureP2PInitialized();
    if (_p2pService == null) return false;
    
    try {
      final connection = await _p2pService!.connectToPeer(peer);
      if (connection != null) {
        // Setup event sync inline instead of separate method
        connection.dataStream.listen(
          (data) => _handleP2PMessage(connection.peer.id, data),
          onError: (error) => print('P2P: Data stream error from ${connection.peer.name}: $error'),
        );
        return true;
      }
    } catch (e) {
      print('Failed to connect to P2P peer ${peer.name}: $e');
    }
    
    return false;
  }
  
  /// Sync video events with all connected P2P peers
  Future<void> syncWithP2PPeers() async {
    if (!_p2pEnabled || _videoSyncService == null) return;
    
    try {
      await _videoSyncService!.syncWithAllPeers();
      print('P2P: Video sync completed with all peers');
    } catch (e) {
      print('Failed to sync with P2P peers: $e');
    }
  }
  
  /// Start automatic P2P video syncing
  Future<void> startAutoP2PSync({Duration interval = const Duration(minutes: 5)}) async {
    if (!_p2pEnabled || _videoSyncService == null) return;
    
    await _videoSyncService!.startAutoSync(interval: interval);
    print('P2P: Auto video sync started');
  }
  
  /// Stop automatic P2P video syncing
  Future<void> stopAutoP2PSync() async {
    if (_videoSyncService != null) {
      _videoSyncService!.stopAutoSync();
      print('P2P: Auto video sync stopped');
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    print('NostrService: Starting disposal...');
    
    // Close all active subscriptions
    await closeAllSubscriptions();
    await _authStateController.close();
    
    // Note: No nostr_sdk client or WebSocket server to disconnect
    // We use the embedded relay directly
    
    // Shutdown embedded relay
    if (_embeddedRelay != null) {
      await _embeddedRelay!.shutdown();
      _embeddedRelay = null;
      print('NostrService: Shutdown embedded relay');
    }
    
    // Clean up P2P services
    _p2pService?.dispose();
    _videoSyncService?.dispose();
    _p2pService = null;
    _videoSyncService = null;
    
    _isDisposed = true;
    print('NostrService: Disposal complete');
  }

  /// Get events from the embedded relay (which caches from external relays)
  @override
  Future<List<Event>> getEvents({
    required List<nostr.Filter> filters,
    int? limit,
  }) async {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (!_isInitialized) throw StateError('NostrService not initialized');
    if (_embeddedRelay == null) throw StateError('Embedded relay not initialized');
    
    // Convert to embedded relay filters
    final embeddedFilters = filters.map(_convertToEmbeddedFilter).toList();
    
    // Apply limit to first filter if provided
    if (limit != null && embeddedFilters.isNotEmpty) {
      final firstFilter = embeddedFilters[0];
      embeddedFilters[0] = embedded.Filter(
        ids: firstFilter.ids,
        authors: firstFilter.authors,
        kinds: firstFilter.kinds,
        tags: firstFilter.tags,
        since: firstFilter.since,
        until: firstFilter.until,
        limit: limit,
      );
    }
    
    // Query embedded relay directly
    final embeddedEvents = await _embeddedRelay!.queryEvents(embeddedFilters);
    
    // Convert back to nostr_sdk events
    return embeddedEvents.map(_convertFromEmbeddedEvent).toList();
  }

  // Private helper methods
  
  /// Convert nostr_sdk Filter to embedded relay Filter
  /// Generate a deterministic hash for a set of filters to prevent duplicate subscriptions
  String _generateFilterHash(List<nostr.Filter> filters) {
    // Create a deterministic string representation of the filters
    final parts = <String>[];
    
    for (final filter in filters) {
      final filterParts = <String>[];
      
      // Add kinds
      if (filter.kinds != null && filter.kinds!.isNotEmpty) {
        final sortedKinds = List<int>.from(filter.kinds!)..sort();
        filterParts.add('k:${sortedKinds.join(",")}');
      }
      
      // Add authors
      if (filter.authors != null && filter.authors!.isNotEmpty) {
        final sortedAuthors = List<String>.from(filter.authors!)..sort();
        filterParts.add('a:${sortedAuthors.join(",")}');
      }

      // Add ids
      if (filter.ids != null && filter.ids!.isNotEmpty) {
        final sortedIds = List<String>.from(filter.ids!)..sort();
        filterParts.add('i:${sortedIds.join(",")}');
      }
      
      // Add since/until
      if (filter.since != null) filterParts.add('s:${filter.since}');
      if (filter.until != null) filterParts.add('u:${filter.until}');
      
      // Add limit
      if (filter.limit != null) filterParts.add('l:${filter.limit}');
      
      // Add tags
      if (filter.t != null && filter.t!.isNotEmpty) {
        final sortedTags = List<String>.from(filter.t!)..sort();
        filterParts.add('t:${sortedTags.join(",")}');
      }
      
      // Add d tags
      if (filter.d != null && filter.d!.isNotEmpty) {
        final sortedD = List<String>.from(filter.d!)..sort();
        filterParts.add('d:${sortedD.join(",")}');
      }

      // Add p and e tags if present
      if (filter.p != null && filter.p!.isNotEmpty) {
        final sortedP = List<String>.from(filter.p!)..sort();
        filterParts.add('p:${sortedP.join(",")}');
      }
      if (filter.e != null && filter.e!.isNotEmpty) {
        final sortedE = List<String>.from(filter.e!)..sort();
        filterParts.add('e:${sortedE.join(",")}');
      }

      // Add group/h tag if used by client
      if (filter.h != null && filter.h!.isNotEmpty) {
        final sortedH = List<String>.from(filter.h!)..sort();
        filterParts.add('h:${sortedH.join(",")}');
      }
      
      parts.add(filterParts.join('|'));
    }
    
    // Create a hash from the filter string
    final filterString = parts.join('||');
    // Use a simple hash function for the subscription ID
    var hash = 0;
    for (var i = 0; i < filterString.length; i++) {
      hash = ((hash << 5) - hash) + filterString.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // Convert to 32-bit integer
    }
    return hash.abs().toString();
  }

  embedded.Filter _convertToEmbeddedFilter(nostr.Filter filter) {
    // Build tags map for embedded relay - note the # prefix for tag filters
    final Map<String, List<String>> tags = {};
    
    // Add e tags if present
    if (filter.e != null && filter.e!.isNotEmpty) {
      tags['#e'] = filter.e!;
    }
    
    // Add p tags if present
    if (filter.p != null && filter.p!.isNotEmpty) {
      tags['#p'] = filter.p!;
    }
    
    // Add t tags (hashtags) if present
    if (filter.t != null && filter.t!.isNotEmpty) {
      tags['#t'] = filter.t!;
    }

    // Add d tags (NIP-33 parameterized replaceable events) if present
    if (filter.d != null && filter.d!.isNotEmpty) {
      tags['#d'] = filter.d!;
    }

    // Add custom group tag if present (client uses 'h')
    if (filter.h != null && filter.h!.isNotEmpty) {
      tags['#h'] = filter.h!;
    }
    
    return embedded.Filter(
      ids: filter.ids,
      authors: filter.authors,
      kinds: filter.kinds,
      tags: tags.isNotEmpty ? tags : null,
      since: filter.since,
      until: filter.until,
      limit: filter.limit,
    );
  }

  /// Convert embedded relay NostrEvent to nostr_sdk Event
  Event _convertFromEmbeddedEvent(embedded.NostrEvent embeddedEvent) {
    return Event.fromJson({
      'id': embeddedEvent.id,
      'pubkey': embeddedEvent.pubkey,
      'created_at': embeddedEvent.createdAt,
      'kind': embeddedEvent.kind,
      'tags': embeddedEvent.tags,
      'content': embeddedEvent.content,
      'sig': embeddedEvent.sig,
    });
  }

  /// Convert nostr_sdk Event to embedded relay NostrEvent
  embedded.NostrEvent _convertToEmbeddedEvent(Event event) {
    return embedded.NostrEvent.fromJson({
      'id': event.id,
      'pubkey': event.pubkey,
      'created_at': event.createdAt,
      'kind': event.kind,
      'tags': event.tags,
      'content': event.content,
      'sig': event.sig,
    });
  }

  /// Initialize P2P sync functionality (lazy loaded)
  Future<void> _ensureP2PInitialized() async {
    if (_p2pService != null) return;
    
    try {
      _p2pService = P2PDiscoveryService();
      final initialized = await _p2pService!.initialize();
      
      if (initialized && _embeddedRelay != null) {
        // Initialize video sync service
        _videoSyncService = P2PVideoSyncService(_embeddedRelay!, _p2pService!);
        
        print('P2P: Sync initialized successfully');
        
        // Auto-start advertising when P2P is enabled
        await _p2pService!.startAdvertising();
      } else {
        print('P2P: Initialization failed - permissions not granted');
        _p2pService = null;
      }
    } catch (e) {
      print('P2P: Initialization error: $e');
      _p2pService = null;
    }
  }
  
  /// Handle incoming P2P messages
  Future<void> _handleP2PMessage(String peerId, List<int> data) async {
    try {
      final jsonString = utf8.decode(data);
      final message = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Delegate to video sync service
      if (_videoSyncService != null) {
        await _videoSyncService!.handleIncomingSync(peerId, message);
      } else {
        print('P2P: Video sync service not initialized');
      }
    } catch (e) {
      print('P2P: Failed to handle message from $peerId: $e');
    }
  }



  // ==========================================================================
  // NIP-65 Relay Discovery Methods
  // ==========================================================================

  /// Discover and add relays from a user's profile (kind 0 and kind 10002 events)
  /// This implements NIP-65 relay list metadata
  Future<void> discoverUserRelays(String pubkey) async {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (!_isInitialized) throw StateError('NostrService not initialized');
    
    try {
      // Query for kind 10002 (relay list metadata) - NIP-65
      final relayListFilter = embedded.Filter(
        kinds: [10002], // Relay list metadata
        authors: [pubkey],
        limit: 1,
      );
      
      final relayListEvents = await _embeddedRelay!.queryEvents([relayListFilter]);
      
      if (relayListEvents.isNotEmpty) {
        final relayListEvent = relayListEvents.first;
        // Parse relay list from tags
        for (final tag in relayListEvent.tags) {
          if (tag.isNotEmpty && tag[0] == 'r' && tag.length > 1) {
            final relayUrl = tag[1];
            if (!_configuredRelays.contains(relayUrl)) {
              // Check for read/write markers if present
              final isWrite = tag.length > 2 && tag[2] == 'write';
              final isRead = tag.length > 2 && tag[2] == 'read';
              
              await addRelay(relayUrl);
              print('NostrService: Discovered relay from NIP-65: $relayUrl (write: $isWrite, read: $isRead)');
            }
          }
        }
      }
      
      // Also check for kind 3 (contact list) which sometimes includes relay hints
      final contactListFilter = embedded.Filter(
        kinds: [3], // Contact list
        authors: [pubkey],
        limit: 1,
      );
      
      final contactListEvents = await _embeddedRelay!.queryEvents([contactListFilter]);
      
      if (contactListEvents.isNotEmpty) {
        final contactEvent = contactListEvents.first;
        // Some clients store relay URLs in the content field as JSON
        try {
          final content = contactEvent.content;
          if (content.isNotEmpty) {
            final relayPattern = RegExp(r'wss?://[^\s,"\}]+');
            final matches = relayPattern.allMatches(content);
            
            for (final match in matches) {
              final relayUrl = match.group(0);
              if (relayUrl != null && !_configuredRelays.contains(relayUrl)) {
                await addRelay(relayUrl);
                print('NostrService: Discovered relay from contact list: $relayUrl');
              }
            }
          }
        } catch (e) {
          print('NostrService: Error parsing contact list for relays: $e');
        }
      }
    } catch (e) {
      print('NostrService: Error discovering user relays: $e');
    }
  }

  /// Add relays that are commonly used by a user based on their event history
  Future<void> discoverRelaysFromEventHints(String pubkey) async {
    if (_isDisposed) throw StateError('NostrService is disposed');
    if (!_isInitialized) throw StateError('NostrService not initialized');
    
    try {
      // Get recent events from the user
      final userEventsFilter = embedded.Filter(
        authors: [pubkey],
        limit: 20, // Check last 20 events for relay hints
      );
      
      final userEvents = await _embeddedRelay!.queryEvents([userEventsFilter]);
      
      final discoveredRelays = <String>{};
      
      for (final event in userEvents) {
        // Check for relay hints in tags
        for (final tag in event.tags) {
          if (tag.length >= 3 && (tag[0] == 'e' || tag[0] == 'p')) {
            // NIP-01: ["e", <event-id>, <relay-url>] or ["p", <pubkey>, <relay-url>]
            final relayHint = tag.length > 2 ? tag[2] : null;
            if (relayHint != null && relayHint.startsWith('wss://')) {
              discoveredRelays.add(relayHint);
            }
          }
        }
      }
      
      // Add discovered relays
      for (final relayUrl in discoveredRelays) {
        if (!_configuredRelays.contains(relayUrl)) {
          await addRelay(relayUrl);
          print('NostrService: Discovered relay from event hints: $relayUrl');
        }
      }
    } catch (e) {
      print('NostrService: Error discovering relays from event hints: $e');
    }
  }
}
