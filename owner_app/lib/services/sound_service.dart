import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SoundService extends ChangeNotifier {
  static final SoundService instance = SoundService._internal();
  factory SoundService() => instance;

  SoundService._internal() {
    _initSoundSetting();
  }

  static const _storage = FlutterSecureStorage();
  static const _kSoundEnabledKey = 'cafe_order_sound_enabled';
  static const String orderBellAsset = 'sounds/mixkit-cartoon-door-melodic-bell-110.wav';

  final AudioPlayer _player = AudioPlayer();
  bool _isSoundEnabled = true;
  DateTime? _lastPlayedTime;

  bool get isSoundEnabled => _isSoundEnabled;

  Future<void> _initSoundSetting() async {
    try {
      final saved = await _storage.read(key: _kSoundEnabledKey);
      if (saved != null) {
        _isSoundEnabled = saved == 'true';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error reading sound setting: $e');
    }
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _isSoundEnabled = enabled;
    notifyListeners();
    try {
      await _storage.write(key: _kSoundEnabledKey, value: enabled ? 'true' : 'false');
    } catch (e) {
      debugPrint('Error saving sound setting: $e');
    }
  }

  Future<void> toggleSound() async {
    await setSoundEnabled(!_isSoundEnabled);
  }

  /// Plays the melodic bell sound for new incoming orders with a 1.5s debounce.
  Future<void> playOrderAlert() async {
    if (!_isSoundEnabled) return;

    final now = DateTime.now();
    if (_lastPlayedTime != null && now.difference(_lastPlayedTime!).inMilliseconds < 1500) {
      // Debounce if multiple triggers occur at the exact same instant
      return;
    }
    _lastPlayedTime = now;

    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource(orderBellAsset));
      debugPrint('🔔 Order alert sound played successfully.');
    } catch (e) {
      debugPrint('Error playing order alert sound: $e');
      // Fallback try with alias path if needed
      try {
        await _player.play(AssetSource('sounds/order_bell.wav'));
      } catch (_) {}
    }
  }

  /// Preview sound immediately for settings testing
  Future<void> testSound() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource(orderBellAsset));
    } catch (e) {
      debugPrint('Error testing sound: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
