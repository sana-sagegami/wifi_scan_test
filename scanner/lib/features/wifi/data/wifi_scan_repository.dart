import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_scan_test/features/wifi/data/measurement_logger.dart';
import 'package:wifi_scan_test/features/wifi/data/wifi_share_repository.dart';

abstract class WifiScanRepository {
  Stream<List<WiFiAccessPoint>> get results;
  Future<bool> ensureReady();
  Future<void> start();
  Future<void> stop();
}

class InProcessWifiScanRepository implements WifiScanRepository {
  final _controller = StreamController<List<WiFiAccessPoint>>.broadcast();
  StreamSubscription? _subscription;

  @override
  Stream<List<WiFiAccessPoint>> get results => _controller.stream;

  @override
  Future<bool> ensureReady() async {
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) return false;

    final can = await WiFiScan.instance.canStartScan(askPermissions: true);
    return can == CanStartScan.yes;
  }

  @override
  Future<void> start() async {
    _subscription = WiFiScan.instance.onScannedResultsAvailable.listen((
      results,
    ) {
      _controller.add(results);
    });
    await WiFiScan.instance.startScan();
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
  }
}

final WifiScanRepositoryProvider = Provider<WifiScanRepository>((ref) {
  final repo = InProcessWifiScanRepository();
  ref.onDispose(repo.stop);
  return repo;
});

final wifiScanResultsProvider =
    StreamProvider.autoDispose<List<WiFiAccessPoint>>((ref) async* {
      final repo = ref.watch(WifiScanRepositoryProvider);
      final ready = await repo.ensureReady();
      if (!ready) {
        yield [];
        return;
      }
      await repo.start();
      yield* repo.results;
    });
final MeasurementLoggerProvider = Provider<MeasurementLogger>((ref) {
  return MeasurementLogger();
});

final wifiShareRepositoryProvider = Provider<WifiShareRepository>((ref) {
  return WifiShareRepository();
});

final peerWifiResultsProvider = StreamProvider.family
    .autoDispose<
      Map<String, dynamic>?,
      ({String roomId, String peerDeviceName})
    >((ref, args) {
      final repo = ref.watch(wifiShareRepositoryProvider);
      return repo.watchPeerResults(
        roomId: args.roomId,
        peerDeviceName: args.peerDeviceName,
      );
    });
