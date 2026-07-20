import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../data/wifi_scan_repository.dart';

class WifiTestScreen extends HookConsumerWidget {
  const WifiTestScreen({super.key});

  void _logResults(List<WiFiAccessPoint> results) {
    final now = DateTime.now();
    for (final ap in results) {
      debugPrint(
        '[$now] SSID=${ap.ssid} BSSID=${ap.bssid} RSSI=${ap.level}dBm',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(wifiScanResultsProvider);
    final distanceController = useTextEditingController();
    final deviceNameController = useTextEditingController(
      text: 'さな端末',
    ); // 端末ごとに書き換え

    const roomId = 'test-room-1';
    final peerName = deviceNameController.text == 'さな端末' ? 'りんや端末' : 'さな端末';
    final peerAsync = ref.watch(
      peerWifiResultsProvider((roomId: roomId, peerDeviceName: peerName)),
    );

    Future<void> record(List<WiFiAccessPoint> results) async {
      final logger = ref.read(MeasurementLoggerProvider);
      await logger.logEntry(
        distanceLabel: distanceController.text,
        deviceName: deviceNameController.text,
        results: results,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('記録しました')));
      }
    }

    Future<void> exportCsv() async {
      final logger = ref.read(MeasurementLoggerProvider);
      final file = await logger.getFileForExport(
        deviceName: deviceNameController.text,
      );
      await Share.shareXFiles([XFile(file.path)]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Scan Test'),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share), onPressed: exportCsv),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: deviceNameController,
                    decoration: const InputDecoration(labelText: '端末名'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: distanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '距離(m)'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: peerAsync.when(
              data: (data) {
                if (data == null) return const Text('相手のデータ待ち...');
                final results = (data['results'] as List).cast<Map>();
                return Text('相手($peerName)が見てるAP数: ${results.length}');
              },
              loading: () => const Text('相手のデータ読み込み中...'),
              error: (e, st) => Text('相手データError: $e'),
            ),
          ),
          const Divider(),
          Expanded(
            child: resultsAsync.when(
              data: (results) {
                _logResults(results);
                ref
                    .read(wifiShareRepositoryProvider)
                    .uploadResults(
                      roomId: roomId,
                      deviceName: deviceNameController.text,
                      results: results,
                    );
                if (results.isEmpty) {
                  return const Center(child: Text('結果なし。右下のボタンで再スキャン'));
                }
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final ap = results[i];
                    return ListTile(
                      title: Text(ap.ssid.isEmpty ? '(hidden)' : ap.ssid),
                      subtitle: Text('BSSID: ${ap.bssid}'),
                      trailing: Text('${ap.level} dBm'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'record',
            onPressed: () async {
              final results = resultsAsync.value ?? [];
              await record(results);
            },
            child: const Icon(Icons.save),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'scan',
            onPressed: () => ref.refresh(wifiScanResultsProvider),
            child: const Icon(Icons.wifi),
          ),
        ],
      ),
    );
  }
}
