import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wifi_scan/wifi_scan.dart';

class MeasurementLogger {
  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/wifi_measurements.csv');

    // 初回はヘッダー行書き込み
    if (!await file.exists()) {
      await file.writeAsString(
        'timestamp, distance_m, device, ssid, bssid, rssi_dbm\n',
      );
    }
    _file = file;
    return file;
  }

  // distanceLabel: 計測してる距離(m)
  // deviceName: 端末名

  Future<void> logEntry({
    required String distanceLabel,
    required String deviceName,
    required List<WiFiAccessPoint> results,
  }) async {
    final file = await _getFile();
    final now = DateTime.now().toIso8601String();

    final buffer = StringBuffer();
    for (final ap in results) {
      final ssid = ap.ssid.isEmpty ? '(hidden)' : ap.ssid;
      buffer.writeln(
        '$now, $distanceLabel, $deviceName, $ssid, ${ap.bssid}, ${ap.level}',
      );
    }
    await file.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  // エクスポート時にファイル名へ日時と端末名を入れたコピーを作る
  Future<File> getFileForExport({required String deviceName}) async {
    final file = await _getFile();
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)}'
        '_${_pad(now.hour)}-${_pad(now.minute)}-${_pad(now.second)}';
    final safeDeviceName = deviceName.trim().isEmpty
        ? 'unknown'
        : deviceName.replaceAll(RegExp(r'[^A-Za-z0-9_\-ぁ-んァ-ヶ一-龠]'), '_');
    final exportPath =
        '${file.parent.path}/wifi_measurements_${timestamp}_$safeDeviceName.csv';
    return file.copy(exportPath);
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}
