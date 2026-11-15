import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:kalao/models/player_state.dart';
import 'package:kalao/models/song.dart';
import 'package:kalao/utils/logger.dart';

const _log = AppLogger('MediaSession');

/// What the media session asks the player to do (notification, lock screen,
/// headset buttons, audio focus).
abstract interface class PlaybackCommands {
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
}

/// audio_service handler (IMPLEMENTATION.md §2 "Media session"): mirrors the
/// player into the system media session and forwards its buttons.
class KalaoAudioHandler extends BaseAudioHandler with SeekHandler {
  PlaybackCommands? commands;

  @override
  Future<void> play() async => commands?.play();

  @override
  Future<void> pause() async => commands?.pause();

  @override
  Future<void> seek(Duration position) async => commands?.seek(position);

  @override
  Future<void> stop() async {
    await commands?.stop();
    await super.stop();
  }

  /// Publishes [song] and [engine] to the notification and lock screen.
  void publish(Song? song, EnginePlayerState engine) {
    if (song == null) {
      playbackState.add(PlaybackState());
      mediaItem.add(null);
      return;
    }
    final current = mediaItem.value;
    if (current?.id != '${song.id}') {
      final cover = song.coverPath;
      mediaItem.add(
        MediaItem(
          id: '${song.id}',
          title: song.title,
          artist: song.artist.isEmpty ? null : song.artist,
          album: song.album.isEmpty ? null : song.album,
          duration: engine.duration ?? song.duration,
          artUri: cover == null ? null : Uri.file(cover),
        ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          engine.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [1],
        processingState: engine.buffering
            ? AudioProcessingState.buffering
            : engine.completed
            ? AudioProcessingState.completed
            : AudioProcessingState.ready,
        playing: engine.playing,
        updatePosition: engine.position,
      ),
    );
  }
}

/// Audio focus and "becoming noisy" (Mornye's audio_session handling): duck on
/// a transient loss, pause on a loss or when headphones are unplugged, and
/// resume after a transient pause ends.
class AudioFocus {
  AudioFocus(this.commands, {required this.isPlaying, required this.setDucked});

  final PlaybackCommands commands;
  final bool Function() isPlaying;
  final Future<void> Function(bool ducked) setDucked;
  final _subscriptions = <StreamSubscription<Object?>>[];
  AudioSession? _session;
  bool _resumeAfterInterruption = false;

  Future<void> start() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _session = session;
      _subscriptions
        ..add(session.becomingNoisyEventStream.listen((_) => commands.pause()))
        ..add(session.interruptionEventStream.listen(_onInterruption));
    } catch (error) {
      _log.w('Audio session unavailable', error);
    }
  }

  Future<void> activate() async {
    try {
      await _session?.setActive(true);
    } catch (error) {
      _log.w('Audio focus request failed', error);
    }
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          setDucked(true);
        case AudioInterruptionType.pause:
          _resumeAfterInterruption = isPlaying();
          commands.pause();
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = false;
          commands.pause();
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          setDucked(false);
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption) commands.play();
          _resumeAfterInterruption = false;
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = false;
      }
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
