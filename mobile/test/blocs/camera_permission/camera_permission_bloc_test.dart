import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openvine/blocs/camera_permission/camera_permission_bloc.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MockPermissionHandlerPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PermissionHandlerPlatform {}

void main() {
  group('CameraPermissionBloc', () {
    late _MockPermissionHandlerPlatform mockPlatform;

    setUp(() {
      mockPlatform = _MockPermissionHandlerPlatform();
      PermissionHandlerPlatform.instance = mockPlatform;
    });

    group('initial state', () {
      test('is CameraPermissionInitial', () {
        final bloc = CameraPermissionBloc();
        expect(bloc.state, isA<CameraPermissionInitial>());
      });
    });

    group('CameraPermissionRequest', () {
      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'does nothing when state is CameraPermissionInitial',
        build: () => CameraPermissionBloc(),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => <CameraPermissionState>[],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'does nothing when state is CameraPermissionLoading',
        build: () => CameraPermissionBloc(),
        seed: () => const CameraPermissionLoading(),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => <CameraPermissionState>[],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'does nothing when status is authorized',
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.authorized),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => <CameraPermissionState>[],
        verify: (_) {
          verifyNever(() => mockPlatform.requestPermissions(any()));
        },
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'does nothing when status is requiresSettings',
        build: () => CameraPermissionBloc(),
        seed: () => const CameraPermissionLoaded(
          CameraPermissionStatus.requiresSettings,
        ),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => <CameraPermissionState>[],
        verify: (_) {
          verifyNever(() => mockPlatform.requestPermissions(any()));
        },
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Loaded(authorized)] when both permissions granted',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenAnswer(
            (_) async => {Permission.camera: PermissionStatus.granted},
          );
          when(
            () => mockPlatform.requestPermissions([Permission.microphone]),
          ).thenAnswer(
            (_) async => {Permission.microphone: PermissionStatus.granted},
          );
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [
          const CameraPermissionLoaded(CameraPermissionStatus.authorized),
        ],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Denied] when camera permission denied',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenAnswer(
            (_) async => {Permission.camera: PermissionStatus.denied},
          );
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [const CameraPermissionDenied()],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Denied] when microphone permission denied',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenAnswer(
            (_) async => {Permission.camera: PermissionStatus.granted},
          );
          when(
            () => mockPlatform.requestPermissions([Permission.microphone]),
          ).thenAnswer(
            (_) async => {Permission.microphone: PermissionStatus.denied},
          );
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [const CameraPermissionDenied()],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Denied] when camera permission permanently denied',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenAnswer(
            (_) async => {
              Permission.camera: PermissionStatus.permanentlyDenied,
            },
          );
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [const CameraPermissionDenied()],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Denied] when microphone permission permanently denied',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenAnswer(
            (_) async => {Permission.camera: PermissionStatus.granted},
          );
          when(
            () => mockPlatform.requestPermissions([Permission.microphone]),
          ).thenAnswer(
            (_) async => {
              Permission.microphone: PermissionStatus.permanentlyDenied,
            },
          );
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [const CameraPermissionDenied()],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Error] when camera request throws',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenThrow(Exception('Platform error'));
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [const CameraPermissionError()],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Error] when microphone request throws',
        setUp: () {
          when(
            () => mockPlatform.requestPermissions([Permission.camera]),
          ).thenAnswer(
            (_) async => {Permission.camera: PermissionStatus.granted},
          );
          when(
            () => mockPlatform.requestPermissions([Permission.microphone]),
          ).thenThrow(Exception('Platform error'));
        },
        build: () => CameraPermissionBloc(),
        seed: () =>
            const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        act: (bloc) => bloc.add(const CameraPermissionRequest()),
        expect: () => [const CameraPermissionError()],
      );
    });

    group('CameraPermissionRefresh', () {
      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Loaded(canRequest)] when permissions can be requested',
        setUp: () {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.denied);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.denied);
        },
        build: () => CameraPermissionBloc(),
        act: (bloc) => bloc.add(const CameraPermissionRefresh()),
        expect: () => [
          const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
        ],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Loaded(authorized)] when both permissions granted',
        setUp: () {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.granted);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.granted);
        },
        build: () => CameraPermissionBloc(),
        act: (bloc) => bloc.add(const CameraPermissionRefresh()),
        expect: () => [
          const CameraPermissionLoaded(CameraPermissionStatus.authorized),
        ],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Loaded(requiresSettings)] when permission permanently denied',
        setUp: () {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.permanentlyDenied);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.granted);
        },
        build: () => CameraPermissionBloc(),
        act: (bloc) => bloc.add(const CameraPermissionRefresh()),
        expect: () => [
          const CameraPermissionLoaded(CameraPermissionStatus.requiresSettings),
        ],
      );

      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'emits [Error] when checkPermissions throws',
        setUp: () {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenThrow(Exception('Platform error'));
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.granted);
        },
        build: () => CameraPermissionBloc(),
        act: (bloc) => bloc.add(const CameraPermissionRefresh()),
        expect: () => [const CameraPermissionError()],
      );
    });

    group('CameraPermissionOpenSettings', () {
      blocTest<CameraPermissionBloc, CameraPermissionState>(
        'calls openAppSettings',
        setUp: () {
          when(
            () => mockPlatform.openAppSettings(),
          ).thenAnswer((_) async => true);
        },
        build: () => CameraPermissionBloc(),
        act: (bloc) => bloc.add(const CameraPermissionOpenSettings()),
        expect: () => <CameraPermissionState>[],
        verify: (_) {
          verify(() => mockPlatform.openAppSettings()).called(1);
        },
      );
    });

    group('checkPermissions', () {
      test(
        'returns authorized when both camera and microphone are granted',
        () async {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.granted);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.granted);

          final bloc = CameraPermissionBloc();
          final result = await bloc.checkPermissions();

          expect(result, CameraPermissionStatus.authorized);
        },
      );

      test(
        'returns requiresSettings when camera is permanently denied',
        () async {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.permanentlyDenied);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.granted);

          final bloc = CameraPermissionBloc();
          final result = await bloc.checkPermissions();

          expect(result, CameraPermissionStatus.requiresSettings);
        },
      );

      test(
        'returns requiresSettings when microphone is permanently denied',
        () async {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.granted);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.permanentlyDenied);

          final bloc = CameraPermissionBloc();
          final result = await bloc.checkPermissions();

          expect(result, CameraPermissionStatus.requiresSettings);
        },
      );

      test('returns requiresSettings when camera is restricted', () async {
        when(
          () => mockPlatform.checkPermissionStatus(Permission.camera),
        ).thenAnswer((_) async => PermissionStatus.restricted);
        when(
          () => mockPlatform.checkPermissionStatus(Permission.microphone),
        ).thenAnswer((_) async => PermissionStatus.granted);

        final bloc = CameraPermissionBloc();
        final result = await bloc.checkPermissions();

        expect(result, CameraPermissionStatus.requiresSettings);
      });

      test('returns requiresSettings when microphone is restricted', () async {
        when(
          () => mockPlatform.checkPermissionStatus(Permission.camera),
        ).thenAnswer((_) async => PermissionStatus.granted);
        when(
          () => mockPlatform.checkPermissionStatus(Permission.microphone),
        ).thenAnswer((_) async => PermissionStatus.restricted);

        final bloc = CameraPermissionBloc();
        final result = await bloc.checkPermissions();

        expect(result, CameraPermissionStatus.requiresSettings);
      });

      test(
        'returns canRequest when permissions are denied but not permanently',
        () async {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.denied);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.denied);

          final bloc = CameraPermissionBloc();
          final result = await bloc.checkPermissions();

          expect(result, CameraPermissionStatus.canRequest);
        },
      );

      test(
        'returns canRequest when one permission granted and other denied',
        () async {
          when(
            () => mockPlatform.checkPermissionStatus(Permission.camera),
          ).thenAnswer((_) async => PermissionStatus.granted);
          when(
            () => mockPlatform.checkPermissionStatus(Permission.microphone),
          ).thenAnswer((_) async => PermissionStatus.denied);

          final bloc = CameraPermissionBloc();
          final result = await bloc.checkPermissions();

          expect(result, CameraPermissionStatus.canRequest);
        },
      );
    });
  });

  group('CameraPermissionState equality', () {
    test('CameraPermissionInitial instances are equal', () {
      expect(
        const CameraPermissionInitial(),
        equals(const CameraPermissionInitial()),
      );
    });

    test('CameraPermissionLoading instances are equal', () {
      expect(
        const CameraPermissionLoading(),
        equals(const CameraPermissionLoading()),
      );
    });

    test('CameraPermissionLoaded instances with same status are equal', () {
      expect(
        const CameraPermissionLoaded(CameraPermissionStatus.authorized),
        equals(const CameraPermissionLoaded(CameraPermissionStatus.authorized)),
      );
    });

    test(
      'CameraPermissionLoaded instances with different status are not equal',
      () {
        expect(
          const CameraPermissionLoaded(CameraPermissionStatus.authorized),
          isNot(
            equals(
              const CameraPermissionLoaded(CameraPermissionStatus.canRequest),
            ),
          ),
        );
      },
    );

    test('CameraPermissionDenied instances are equal', () {
      expect(
        const CameraPermissionDenied(),
        equals(const CameraPermissionDenied()),
      );
    });

    test('CameraPermissionError instances are equal', () {
      expect(
        const CameraPermissionError(),
        equals(const CameraPermissionError()),
      );
    });
  });

  group('CameraPermissionEvent equality', () {
    test('CameraPermissionRequest instances are equal', () {
      expect(
        const CameraPermissionRequest(),
        equals(const CameraPermissionRequest()),
      );
    });

    test('CameraPermissionRefresh instances are equal', () {
      expect(
        const CameraPermissionRefresh(),
        equals(const CameraPermissionRefresh()),
      );
    });

    test('CameraPermissionOpenSettings instances are equal', () {
      expect(
        const CameraPermissionOpenSettings(),
        equals(const CameraPermissionOpenSettings()),
      );
    });
  });
}
