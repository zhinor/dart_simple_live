import 'dart:async';
import 'package:dart_chromecast/chromecast.dart';
import 'package:dart_chromecast/discovery.dart';
import 'package:dart_chromecast/message.dart';
import 'package:get/get.dart';

/// Chromecast设备信息
class ChromecastDevice {
  final String name;
  final String address;
  final int port;
  final String? friendlyName;

  ChromecastDevice({
    required this.name,
    required this.address,
    required this.port,
    this.friendlyName,
  });

  @override
  String toString() {
    return 'ChromecastDevice(name: $name, address: $address, port: $port)';
  }
}

/// 投屏服务类
class ChromecastService extends GetxService {
  static ChromecastService get instance => Get.find();

  // Chromecast发现器
  late CastDiscovery discovery;
  
  // 当前连接的设备
  Chromecast? _currentChromecast;
  
  // 当前连接的设备信息
  ChromecastDevice? currentDevice;
  
  // 设备列表
  final RxList<ChromecastDevice> devices = <ChromecastDevice>[].obs;
  
  // 连接状态
  final RxBool isConnected = false.obs;
  
  // 是否正在发现设备
  final RxBool isDiscovering = false.obs;
  
  // 流控制器
  final StreamController<List<ChromecastDevice>> _devicesController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  final StreamController<String> _statusController =
      StreamController.broadcast();

  // 流
  Stream<List<ChromecastDevice>> get devicesStream => _devicesController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get statusStream => _statusController.stream;

  @override
  void onInit() {
    super.onInit();
    discovery = CastDiscovery();
    // 监听设备发现
    discovery.onDeviceFound = _onDeviceFound;
    discovery.onDeviceLost = _onDeviceLost;
  }

  /// 开始发现设备
  Future<void> startDiscovery() async {
    if (isDiscovering.value) return;
    
    isDiscovering.value = true;
    try {
      await discovery.start();
      _statusController.add("开始发现设备");
    } catch (e) {
      _statusController.add("发现设备失败: $e");
      isDiscovering.value = false;
    }
  }

  /// 停止发现设备
  Future<void> stopDiscovery() async {
    isDiscovering.value = false;
    try {
      await discovery.stop();
      _statusController.add("停止发现设备");
    } catch (e) {
      _statusController.add("停止发现设备失败: $e");
    }
  }

  /// 设备发现回调
  void _onDeviceFound(CastDevice device) {
    final chromecastDevice = ChromecastDevice(
      name: device.name,
      address: device.address,
      port: device.port,
      friendlyName: device.friendlyName,
    );
    
    // 如果设备不存在则添加
    if (!devices.any((d) => d.address == device.address && d.port == device.port)) {
      devices.add(chromecastDevice);
      _devicesController.add(devices);
      _statusController.add("发现设备: ${device.friendlyName ?? device.name}");
    }
  }

  /// 设备丢失回调
  void _onDeviceLost(CastDevice device) {
    devices.removeWhere((d) => d.address == device.address && d.port == device.port);
    _devicesController.add(devices);
    _statusController.add("设备丢失: ${device.friendlyName ?? device.name}");
    
    // 如果丢失的是当前连接的设备，则断开连接
    if (currentDevice?.address == device.address && currentDevice?.port == device.port) {
      disconnect();
    }
  }

  /// 连接到指定设备
  Future<bool> connectToDevice(ChromecastDevice device) async {
    try {
      // 断开现有连接
      if (_currentChromecast != null) {
        await _currentChromecast!.disconnect();
      }
      
      // 创建新的连接
      _currentChromecast = Chromecast(
        device.address,
        device.port,
        onStatus: _onChromecastStatus,
        onMediaStatus: _onMediaStatus,
      );
      
      await _currentChromecast!.connect();
      currentDevice = device;
      isConnected.value = true;
      _connectionController.add(true);
      _statusController.add("连接到设备: ${device.friendlyName ?? device.name}");
      return true;
    } catch (e) {
      _statusController.add("连接设备失败: $e");
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    try {
      if (_currentChromecast != null) {
        await _currentChromecast!.disconnect();
        _currentChromecast = null;
      }
      currentDevice = null;
      isConnected.value = false;
      _connectionController.add(false);
      _statusController.add("断开连接");
    } catch (e) {
      _statusController.add("断开连接失败: $e");
    }
  }

  /// Chromecast状态回调
  void _onChromecastStatus(StatusMessage status) {
    _statusController.add("设备状态更新: ${status.toString()}");
  }

  /// 媒体状态回调
  void _onMediaStatus(MediaStatusMessage status) {
    _statusController.add("媒体状态更新: ${status.toString()}");
  }

  /// 播放媒体
  Future<bool> playMedia({
    required String url,
    String? title,
    String? imageUrl,
    String? contentType,
  }) async {
    if (_currentChromecast == null || !isConnected.value) {
      _statusController.add("未连接到设备");
      return false;
    }

    try {
      final media = Media(
        url: url,
        title: title ?? "直播",
        contentType: contentType ?? "video/mp4",
        images: imageUrl != null ? [imageUrl] : [],
      );
      
      await _currentChromecast!.load(media);
      _statusController.add("开始播放媒体: $title");
      return true;
    } catch (e) {
      _statusController.add("播放媒体失败: $e");
      return false;
    }
  }

  /// 暂停播放
  Future<bool> pause() async {
    if (_currentChromecast == null || !isConnected.value) {
      return false;
    }

    try {
      await _currentChromecast!.pause();
      _statusController.add("暂停播放");
      return true;
    } catch (e) {
      _statusController.add("暂停播放失败: $e");
      return false;
    }
  }

  /// 恢复播放
  Future<bool> play() async {
    if (_currentChromecast == null || !isConnected.value) {
      return false;
    }

    try {
      await _currentChromecast!.play();
      _statusController.add("恢复播放");
      return true;
    } catch (e) {
      _statusController.add("恢复播放失败: $e");
      return false;
    }
  }

  /// 停止播放
  Future<bool> stop() async {
    if (_currentChromecast == null || !isConnected.value) {
      return false;
    }

    try {
      await _currentChromecast!.stop();
      _statusController.add("停止播放");
      return true;
    } catch (e) {
      _statusController.add("停止播放失败: $e");
      return false;
    }
  }

  /// 设置音量
  Future<bool> setVolume(double volume) async {
    if (_currentChromecast == null || !isConnected.value) {
      return false;
    }

    try {
      await _currentChromecast!.setVolume(volume);
      _statusController.add("设置音量: $volume");
      return true;
    } catch (e) {
      _statusController.add("设置音量失败: $e");
      return false;
    }
  }

  /// 获取当前音量
  Future<double?> getVolume() async {
    if (_currentChromecast == null || !isConnected.value) {
      return null;
    }

    try {
      final status = await _currentChromecast!.getStatus();
      return status.volume?.level;
    } catch (e) {
      _statusController.add("获取音量失败: $e");
      return null;
    }
  }

  @override
  void onClose() {
    disconnect();
    discovery.stop();
    _devicesController.close();
    _connectionController.close();
    _statusController.close();
    super.onClose();
  }
}