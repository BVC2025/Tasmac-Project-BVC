import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VoiceMessage {
  refundVerified('refund_verified'),
  manufacturingVerified('manufacturing_verified'),
  showUpi('show_upi'),
  paymentSuccess('payment_success');

  final String fileName;
  const VoiceMessage(this.fileName);
}

enum VoiceLanguage {
  english('en'),
  tamil('ta');

  final String code;
  const VoiceLanguage(this.code);
}

/// Plays pre-recorded voice announcements (generated via Sarvam AI TTS)
/// during the bottle-return flow, in the staff-selected language.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  static const _prefsKey = 'voice_language';

  final AudioPlayer _player = AudioPlayer();
  VoiceLanguage _language = VoiceLanguage.english;

  VoiceLanguage get language => _language;

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _language = VoiceLanguage.values.firstWhere(
      (l) => l.code == saved,
      orElse: () => VoiceLanguage.english,
    );
  }

  Future<void> setLanguage(VoiceLanguage language) async {
    _language = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, language.code);
  }

  Future<void> speak(VoiceMessage message) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/${_language.code}/${message.fileName}.wav'));
    } catch (_) {
      // Voice announcements are a convenience layer; a playback failure
      // (e.g. no audio output device) must never block the return flow.
    }
  }
}
