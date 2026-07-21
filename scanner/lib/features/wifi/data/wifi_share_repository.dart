import 'package:firebase_database/firebase_database.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiShareRepository {
  final _db = FirebaseDatabase.instance.ref('rooms');

  /// roomId: 2人で共有する部屋番号（決め打ちでOK。例:「test-room-1」）
  /// deviceName: 自分の端末名（さな/りんや）
  Future<void> uploadResults({
    required String roomId,
    required String deviceName,
    required List<WiFiAccessPoint> results,
  }) async {
    final data = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'results': results
          .map((ap) => {'ssid': ap.ssid, 'bssid': ap.bssid, 'rssi': ap.level})
          .toList(),
    };
    await _db.child(roomId).child(deviceName).set(data);
  }

  /// 相手の端末名を指定して、その結果をリアルタイムで受け取る
  Stream<Map<String, dynamic>?> watchPeerResults({
    required String roomId,
    required String peerDeviceName,
  }) {
    return _db.child(roomId).child(peerDeviceName).onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return null;
      return Map<String, dynamic>.from(value as Map);
    });
  }
}
