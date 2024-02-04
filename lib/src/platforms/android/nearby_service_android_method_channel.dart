import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nearby_service/nearby_service.dart';
import 'package:nearby_service/src/utils/logger.dart';

/// An implementation of [NearbyServiceAndroidPlatform] that uses method channels.
class MethodChannelAndroidNearbyService extends NearbyServiceAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('nearby_service');

  @override
  Future<bool> initialize() async {
    return (await methodChannel.invokeMethod<bool>(
          'initialize',
          {"logLevel": Logger.level.name},
        )) ??
        false;
  }

  @override
  Future<bool> requestPermissions() async {
    return (await methodChannel.invokeMethod<bool>('requestPermissions')) ??
        false;
  }

  @override
  Future<bool> checkWifiService() async {
    return (await methodChannel.invokeMethod<bool>('checkWifiService')) ??
        false;
  }

  @override
  Future<NearbyConnectionAndroidInfo?> getConnectionInfo() async {
    return NearbyConnectionInfoMapper.mapToInfo(
      await methodChannel.invokeMethod('getConnectionInfo'),
    );
  }

  @override
  Future<bool> discover() async {
    return (await methodChannel.invokeMethod<bool>('discover')) ?? false;
  }

  @override
  Future<bool> stopDiscovery() async {
    return (await methodChannel.invokeMethod<bool>('stopDiscovery')) ?? false;
  }

  @override
  Future<bool> connect(String deviceAddress) async {
    return (await methodChannel.invokeMethod<bool?>(
          "connect",
          {"deviceAddress": deviceAddress},
        )) ??
        false;
  }

  @override
  Future<bool> disconnect() async {
    return (await methodChannel.invokeMethod<bool?>("disconnect")) ?? false;
  }

  @override
  Stream<NearbyConnectionAndroidInfo?> getConnectionInfoStream() {
    const connectedDeviceChannel = EventChannel(
      "nearby_service_connection_info",
    );
    return connectedDeviceChannel.receiveBroadcastStream().map(
          (e) => NearbyConnectionInfoMapper.mapToInfo(e),
        );
  }
}
