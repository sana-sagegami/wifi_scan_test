import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_scan_test/features/wifi/data/wifi_scan_repository.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Scan Test')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.refresh(wifiScanResultsProvider),
        child: const Icon(Icons.refresh),
      ),
      body: resultsAsync.when(
        data: (results) {
          _logResults(results);
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
                trailing: Text('${ap.level} dBM'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
