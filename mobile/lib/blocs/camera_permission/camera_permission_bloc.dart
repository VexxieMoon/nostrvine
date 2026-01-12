import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

part 'camera_permission_event.dart';
part 'camera_permission_state.dart';

// TODO: Create PermissionService package.

/// BLoC for managing camera and microphone permissions.
///
/// Handles:
/// - Checking current permission status
/// - Requesting permissions via OS dialog
/// - Caching status to avoid repeated OS calls
/// - Refreshing status when app resumes from background
class CameraPermissionBloc
    extends Bloc<CameraPermissionEvent, CameraPermissionState> {
  CameraPermissionBloc() : super(const CameraPermissionInitial()) {
    on<CameraPermissionRequest>(_onRequest);
    on<CameraPermissionRefresh>(_onRefresh);
    on<CameraPermissionOpenSettings>(_onOpenSettings);
  }

  Future<void> _onRequest(
    CameraPermissionRequest event,
    Emitter<CameraPermissionState> emit,
  ) async {
    final currentState = state;

    if (currentState is! CameraPermissionLoaded) {
      return;
    }

    if (currentState.status != CameraPermissionStatus.canRequest) {
      return;
    }

    try {
      final cameraStatus = await Permission.camera.request();

      if (!cameraStatus.isGranted) {
        emit(CameraPermissionDenied());
        return;
      }

      final microphoneStatus = await Permission.microphone.request();

      if (!microphoneStatus.isGranted) {
        emit(CameraPermissionDenied());
        return;
      }

      emit(CameraPermissionLoaded(CameraPermissionStatus.authorized));
    } catch (e) {
      emit(const CameraPermissionError());
    }
  }

  Future<void> _onRefresh(
    CameraPermissionRefresh event,
    Emitter<CameraPermissionState> emit,
  ) async {
    try {
      final status = await checkPermissions();
      emit(CameraPermissionLoaded(status));
    } catch (e) {
      emit(const CameraPermissionError());
    }
  }

  Future<void> _onOpenSettings(
    CameraPermissionOpenSettings event,
    Emitter<CameraPermissionState> emit,
  ) async {
    await openAppSettings();
  }

  /// Check the status of camera and microphone permissions from OS.
  @visibleForTesting
  Future<CameraPermissionStatus> checkPermissions() async {
    final (cameraStatus, micStatus) = await (
      Permission.camera.status,
      Permission.microphone.status,
    ).wait;

    if (cameraStatus.isGranted && micStatus.isGranted) {
      return CameraPermissionStatus.authorized;
    }

    final requiresSettings =
        cameraStatus.isPermanentlyDenied ||
        micStatus.isPermanentlyDenied ||
        cameraStatus.isRestricted ||
        micStatus.isRestricted;

    if (requiresSettings) {
      return CameraPermissionStatus.requiresSettings;
    }

    return CameraPermissionStatus.canRequest;
  }
}
