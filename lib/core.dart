import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

const Map<String, String> kIptvHeaders = {
  'User-Agent': 'IPTVSmartersPlayer/1.0 (Linux; Android 11)',
  'Accept': '*/*',
  'Connection': 'keep-alive',
};

enum DeviceMode { mobile, tv }
enum ContentType { live, movie, series }
enum MainSection { live, movie, series, continueWatching, favorites, recents }

class StreamItem {
  final String id;
  final String streamId;
  final String tvgId;
  final String name;
  final String cleanName;
  final String seriesName;
  final int seasonNumber;
  final int episodeNumber;
  final String qualityTag;
  final String group;
  final String logo;
  final String url;
  final ContentType type;
  final bool isAdult;

  StreamItem({
    required this.id,
    required this.streamId,
    required this.tvgId,
    required this.name,
    required this.cleanName,
    required this.seriesName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.qualityTag,
    required this.group,
    required this.logo,
    required this.url,
    required this.type,
    required this.isAdult,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'streamId': streamId,
        'tvgId': tvgId,
        'name': name,
        'cleanName': cleanName,
        'seriesName': seriesName,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'qualityTag': qualityTag,
        'group': group,
        'logo': logo,
        'url': url,
        'type': type.index,
        'isAdult': isAdult,
      };

  factory StreamItem.fromJson(Map<String, dynamic> json) {
    final typeIdx = (json['type'] as int?) ?? 0;
    return StreamItem(
      id: json['id']?.toString() ?? '',
      streamId: json['streamId']?.toString() ?? '',
      tvgId: json['tvgId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Conteúdo',
      cleanName: json['cleanName']?.toString() ?? '',
      seriesName: json['seriesName']?.toString() ?? '',
      seasonNumber: (json['seasonNumber'] as int?) ?? 1,
      episodeNumber: (json['episodeNumber'] as int?) ?? 1,
      qualityTag: json['qualityTag']?.toString() ?? 'HD',
      group: json['group']?.toString() ?? 'Geral',
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: ContentType.values[typeIdx.clamp(0, ContentType.values.length - 1)],
      isAdult: json['isAdult'] == true,
    );
  }
}

// =============================================================================
// MODELO DE PROGRESSO VOD ("CONTINUAR ASSISTINDO")
// =============================================================================
class VodProgressEntry {
  final StreamItem item;
  final int positionSeconds;
  final int durationSeconds;
  final int updatedAtMs;

  VodProgressEntry({
    required this.item,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAtMs,
  });

  double get progress => durationSeconds > 0
      ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
      : 0.0;

  String get formattedRemaining {
    final rem = (durationSeconds - positionSeconds).clamp(0, 86400);
    final mins = (rem / 60).ceil();
    return 'Faltam $mins min';
  }

  String get formattedPosition {
    final m = (positionSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (positionSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'updatedAtMs': updatedAtMs,
      };

  factory VodProgressEntry.fromJson(Map<String, dynamic> json) {
    return VodProgressEntry(
      item: StreamItem.fromJson(
          (json['item'] as Map?)?.cast<String, dynamic>() ?? {}),
      positionSeconds: (json['positionSeconds'] as int?) ?? 0,
      durationSeconds: (json['durationSeconds'] as int?) ?? 1,
      updatedAtMs: (json['updatedAtMs'] as int?) ?? 0,
    );
  }
}

// =============================================================================
// MODELO E SERVIÇO DE GUIA DE PROGRAMAÇÃO ELETRÔNICA (EPG)
// =============================================================================
class EpgProgramInfo {
  final String nowTitle;
  final String nextTitle;
  final String nowTimeRange;
  final double progress;

  const EpgProgramInfo({
    required this.nowTitle,
    required this.nextTitle,
    this.nowTimeRange = 'AO VIVO',
    this.progress = 0.45,
  });
}

class EpgService {
  static final Map<String, EpgProgramInfo> _cache = {};

  static String _decodeMaybeBase64(String raw) {
    if (raw.trim().isEmpty) return '';
    try {
      final decoded = utf8.decode(base64Decode(raw.trim()));
      if (decoded.isNotEmpty && !decoded.contains('')) {
        return decoded;
      }
    } catch (_) {}
    return raw;
  }

  static Future<EpgProgramInfo> fetchEpgForChannel({
    required StreamItem item,
    required String serverDns,
    required String username,
    required String password,
  }) async {
    if (item.type != ContentType.live) {
      return const EpgProgramInfo(
        nowTitle: 'Conteúdo Sob Demanda (VOD)',
        nextTitle: 'Controle de reprodução liberado',
        nowTimeRange: 'CINEMA / SÉRIE',
        progress: 1.0,
      );
    }

    if (_cache.containsKey(item.id)) {
      return _cache[item.id]!;
    }

    if (serverDns.isNotEmpty &&
        username.isNotEmpty &&
        password.isNotEmpty &&
        item.streamId.isNotEmpty) {
      try {
        final uri = Uri.parse(
            '$serverDns/player_api.php?username=$username&password=$password&action=get_short_epg&stream_id=${item.streamId}&limit=2');
        final res = await http
            .get(uri, headers: kIptvHeaders)
            .timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final listings = data['epg_listings'] as List?;
          if (listings != null && listings.isNotEmpty) {
            final first = listings[0] as Map;
            final nowTitle =
                _decodeMaybeBase64(first['title']?.toString() ?? '');
            String nextTitle = 'Programação contínua do canal';
            if (listings.length > 1) {
              final second = listings[1] as Map;
              final decodedNext =
                  _decodeMaybeBase64(second['title']?.toString() ?? '');
              if (decodedNext.isNotEmpty) nextTitle = decodedNext;
            }

            if (nowTitle.isNotEmpty) {
              final info = EpgProgramInfo(
                nowTitle: nowTitle,
                nextTitle: nextTitle,
                nowTimeRange: 'NO AR AGORA',
                progress: 0.55,
              );
              _cache[item.id] = info;
              return info;
            }
          }
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final hourStr = '${now.hour.toString().padLeft(2, '0')}:00';
    final nextHourStr = '${((now.hour + 1) % 24).toString().padLeft(2, '0')}:00';
    final minuteProgress = (now.minute / 60.0).clamp(0.05, 0.95);

    final fallback = EpgProgramInfo(
      nowTitle: '${item.cleanName} • Programação Ao Vivo ($hourStr)',
      nextTitle: 'A Seguir ($nextHourStr): Grade ${item.group}',
      nowTimeRange: '$hourStr - $nextHourStr',
      progress: minuteProgress,
    );
    _cache[item.id] = fallback;
    return fallback;
  }
}

// =============================================================================
// MOTOR DE VÍDEO COMPARTILHADO (COM SUPORTE A "ÚLTIMO CANAL / RECALL")
// =============================================================================
class SharedStreamEngine extends ChangeNotifier {
  static final SharedStreamEngine instance = SharedStreamEngine._internal();
  SharedStreamEngine._internal();

  VideoPlayerController? controller;
  StreamItem? currentItem;
  StreamItem? previousChannelItem; // Guarda o último canal para troca rápida (Recall)
  EpgProgramInfo? currentEpg;

  bool isReady = false;
  bool hasError = false;
  bool isRecovering = false;
  bool usingHlsFallback = false;

  String serverDns = '';
  String username = '';
  String password = '';
  double measuredSpeedMbps = 18.5;

  Timer? _watchdogTimer;
  Duration _lastPosition = Duration.zero;
  int _stallCounter = 0;
  int _recoveryAttempts = 0;
  int _vodSaveTick = 0;

  void Function(VodProgressEntry entry)? onVodProgressSaved;
  VoidCallback? onVodEpisodeEnded;

  void configureCredentials({
    required String dns,
    required String user,
    required String pass,
    required double speedMbps,
  }) {
    serverDns = dns;
    username = user;
    password = pass;
    measuredSpeedMbps = speedMbps;
  }

  Future<void> openStream(
    StreamItem item, {
    Duration? startPosition,
    bool forceReload = false,
    bool tryHlsFallback = false,
  }) async {
    if (!forceReload &&
        currentItem?.url == item.url &&
        controller != null &&
        isReady &&
        !hasError) {
      if (startPosition != null && item.type != ContentType.live) {
        await controller!.seekTo(startPosition);
      }
      if (!controller!.value.isPlaying) {
        await controller!.play();
      }
      notifyListeners();
      return;
    }

    _saveCurrentVodProgressImmediately();

    // Registra o último canal ao vivo para o botão Recall
    if (currentItem != null &&
        currentItem!.id != item.id &&
        currentItem!.type == ContentType.live &&
        item.type == ContentType.live) {
      previousChannelItem = currentItem;
    }

    currentItem = item;
    isReady = false;
    hasError = false;
    isRecovering = false;
    usingHlsFallback = tryHlsFallback;
    if (!tryHlsFallback) _recoveryAttempts = 0;
    notifyListeners();

    EpgService.fetchEpgForChannel(
      item: item,
      serverDns: serverDns,
      username: username,
      password: password,
    ).then((epg) {
      if (currentItem?.id == item.id) {
        currentEpg = epg;
        notifyListeners();
      }
    });

    String targetUrl = item.url;
    if (tryHlsFallback && targetUrl.endsWith('.ts')) {
      targetUrl = '${targetUrl.substring(0, targetUrl.length - 3)}.m3u8';
    }

    final oldController = controller;
    final newController = VideoPlayerController.networkUrl(
      Uri.parse(targetUrl),
      httpHeaders: kIptvHeaders,
    );
    controller = newController;
    await oldController?.dispose();

    try {
      await newController.initialize();
      if (currentItem?.id != item.id) return;

      if (item.type != ContentType.live &&
          startPosition != null &&
          startPosition.inSeconds > 5) {
        await newController.seekTo(startPosition);
      } else if (measuredSpeedMbps < 8.0 && item.type != ContentType.live) {
        await Future.delayed(const Duration(milliseconds: 350));
      }

      isReady = true;
      isRecovering = false;
      await newController.play();
      _startWatchdog();
      notifyListeners();
    } catch (_) {
      if (currentItem?.id != item.id) return;
      if (_recoveryAttempts < 2) {
        _recoveryAttempts++;
        await openStream(
          item,
          startPosition: startPosition,
          forceReload: true,
          tryHlsFallback: !tryHlsFallback,
        );
      } else {
        hasError = true;
        notifyListeners();
      }
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _stallCounter = 0;
    _vodSaveTick = 0;

    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final ctrl = controller;
      final item = currentItem;
      if (ctrl == null || item == null || !isReady) return;

      final val = ctrl.value;

      // Detecta fim do episódio em Séries para acionar o Próximo Episódio Automático
      if (item.type == ContentType.series &&
          val.duration.inSeconds > 60 &&
          val.position.inSeconds >= val.duration.inSeconds - 2) {
        onVodEpisodeEnded?.call();
        return;
      }

      if (!val.isPlaying) return;

      if (item.type != ContentType.live) {
        _vodSaveTick++;
        if (_vodSaveTick >= 3) {
          _vodSaveTick = 0;
          _saveCurrentVodProgressImmediately();
        }
      }

      if (val.position == _lastPosition && val.isBuffering) {
        _stallCounter++;
        if (_stallCounter >= 2 && !isRecovering) {
          isRecovering = true;
          notifyListeners();

          if (item.type == ContentType.live) {
            if (val.buffered.isNotEmpty) {
              final liveEdge = val.buffered.last.end;
              if (liveEdge > val.position + const Duration(seconds: 2)) {
                await ctrl.seekTo(liveEdge);
              }
            }
            await ctrl.play();
          } else {
            await ctrl.pause();
            await Future.delayed(const Duration(milliseconds: 700));
            await ctrl.play();
          }

          isRecovering = false;
          _stallCounter = 0;
          notifyListeners();
        }
      } else {
        _stallCounter = 0;
      }
      _lastPosition = val.position;
    });
  }

  void _saveCurrentVodProgressImmediately() {
    final ctrl = controller;
    final item = currentItem;
    if (ctrl == null || item == null || !isReady) return;
    if (item.type == ContentType.live) return;

    final posSec = ctrl.value.position.inSeconds;
    final durSec = ctrl.value.duration.inSeconds;
    if (posSec >= 10 && durSec > 30) {
      final entry = VodProgressEntry(
        item: item,
        positionSeconds: posSec,
        durationSeconds: durSec,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      AppStorage.saveVodProgressEntry(entry);
      onVodProgressSaved?.call(entry);
    }
  }

  /// Pausa apenas o áudio/vídeo em segundo plano sem destruir o buffer quando vai ao catálogo de séries
  void pausePreviewSilently() {
    if (controller != null && isReady && controller!.value.isPlaying) {
      controller!.pause();
      notifyListeners();
    }
  }

  void resumePreviewSilently() {
    if (controller != null && isReady && !controller!.value.isPlaying) {
      controller!.play();
      notifyListeners();
    }
  }

  void togglePlayPause() {
    if (controller == null || !isReady) return;
    if (controller!.value.isPlaying) {
      controller!.pause();
      _saveCurrentVodProgressImmediately();
    } else {
      controller!.play();
    }
    notifyListeners();
  }

  Future<void> seekRelative(int seconds) async {
    if (controller == null || !isReady) return;
    final pos = controller!.value.position;
    final dur = controller!.value.duration;
    final target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) {
      await controller!.seekTo(Duration.zero);
    } else if (dur > Duration.zero && target > dur) {
      await controller!.seekTo(dur);
    } else {
      await controller!.seekTo(target);
    }
    _saveCurrentVodProgressImmediately();
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    _saveCurrentVodProgressImmediately();
    _watchdogTimer?.cancel();
    final old = controller;
    controller = null;
    currentItem = null;
    previousChannelItem = null;
    currentEpg = null;
    isReady = false;
    hasError = false;
    notifyListeners();
    await old?.dispose();
  }
}

// =============================================================================
// AGRUPADOR DE SÉRIES (CAPA -> TEMPORADAS -> EPISÓDIOS)
// =============================================================================
class SeriesGroup {
  final String id;
  final String title;
  final String group;
  final String logo;
  final String qualityTag;
  final bool isAdult;
  final Map<int, List<StreamItem>> seasons;

  SeriesGroup({
    required this.id,
    required this.title,
    required this.group,
    required this.logo,
    required this.qualityTag,
    required this.isAdult,
    required this.seasons,
  });

  int get totalSeasons => seasons.length;

  int get totalEpisodes =>
      seasons.values.fold(0, (sum, list) => sum + list.length);

  List<StreamItem> get allEpisodesFlat {
    final sortedKeys = seasons.keys.toList()..sort();
    final List<StreamItem> list = [];
    for (final k in sortedKeys) {
      list.addAll(seasons[k]!);
    }
    return list;
  }
}

List<SeriesGroup> groupSeriesItems(List<StreamItem> items) {
  final Map<String, Map<int, List<StreamItem>>> map = {};
  final Map<String, StreamItem> firstItemMap = {};

  for (final item in items) {
    final key = item.seriesName.trim().toLowerCase();
    if (!firstItemMap.containsKey(key)) {
      firstItemMap[key] = item;
    } else if (firstItemMap[key]!.logo.isEmpty && item.logo.isNotEmpty) {
      firstItemMap[key] = item;
    }
    map.putIfAbsent(key, () => {});
    map[key]!.putIfAbsent(item.seasonNumber, () => []);
    map[key]![item.seasonNumber]!.add(item);
  }

  final List<SeriesGroup> result = [];
  map.forEach((key, seasonsMap) {
    final ref = firstItemMap[key]!;
    final sortedSeasons = <int, List<StreamItem>>{};
    final seasonKeys = seasonsMap.keys.toList()..sort();
    for (final sKey in seasonKeys) {
      final epList = List<StreamItem>.from(seasonsMap[sKey]!);
      epList.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      sortedSeasons[sKey] = epList;
    }

    result.add(
      SeriesGroup(
        id: 'series_${key.hashCode}',
        title: ref.seriesName,
        group: ref.group,
        logo: ref.logo,
        qualityTag: ref.qualityTag,
        isAdult: ref.isAdult,
        seasons: sortedSeasons,
      ),
    );
  });

  result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return result;
}

Route<T> createSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

// =============================================================================
// ARMAZENAMENTO PERMANENTE REAL NO ANDROID + CACHE LOCAL DA LISTA M3U
// =============================================================================
class AppStorage {
  static Directory? _resolvedDir;

  /// Usa o diretório permanente interno do app Android (não apaga ao reiniciar a TV/Celular)
  static Future<Directory> _getPersistentDir() async {
    if (_resolvedDir != null) return _resolvedDir!;
    const androidPaths = [
      '/data/user/0/com.exemplo.iptv_player/files',
      '/data/data/com.exemplo.iptv_player/files',
    ];
    for (final p in androidPaths) {
      try {
        final d = Directory(p);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
        _resolvedDir = d;
        return d;
      } catch (_) {}
    }
    _resolvedDir = Directory.systemTemp;
    return _resolvedDir!;
  }

  static Future<File> _file(String name) async {
    final dir = await _getPersistentDir();
    return File('${dir.path}/$name');
  }

  static Future<DeviceMode?> loadDeviceMode() async {
    try {
      final f = await _file('unex_device_mode_v8.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        if (data['mode'] == 'tv') return DeviceMode.tv;
        if (data['mode'] == 'mobile') return DeviceMode.mobile;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveDeviceMode(DeviceMode mode) async {
    try {
      final f = await _file('unex_device_mode_v8.json');
      await f.writeAsString(
        jsonEncode({'mode': mode == DeviceMode.tv ? 'tv' : 'mobile'}),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadVerifiedSession() async {
    try {
      final f = await _file('unex_verified_session_v8.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (data['verified'] == true) return data;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveVerifiedSession(Map<String, dynamic> data) async {
    try {
      final f = await _file('unex_verified_session_v8.json');
      data['verified'] = true;
      await f.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> clearSession() async {
    try {
      final f = await _file('unex_verified_session_v8.json');
      if (await f.exists()) await f.delete();
      final cacheFile = await _file('unex_playlist_cache_v8.m3u');
      if (await cacheFile.exists()) await cacheFile.delete();
    } catch (_) {}
  }

  // Cache local da lista M3U para abertura instantânea em 1 segundo
  static Future<String?> loadPlaylistCache(String urlKey) async {
    try {
      final metaFile = await _file('unex_playlist_meta_v8.json');
      final cacheFile = await _file('unex_playlist_cache_v8.m3u');
      if (await metaFile.exists() && await cacheFile.exists()) {
        final meta = jsonDecode(await metaFile.readAsString());
        if (meta['url'] == urlKey) {
          final content = await cacheFile.readAsString();
          if (content.isNotEmpty) return content;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> savePlaylistCache(String urlKey, String rawM3u) async {
    try {
      final metaFile = await _file('unex_playlist_meta_v8.json');
      final cacheFile = await _file('unex_playlist_cache_v8.m3u');
      await metaFile.writeAsString(jsonEncode({
        'url': urlKey,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      }));
      await cacheFile.writeAsString(rawM3u);
    } catch (_) {}
  }

  // Persistência Permanente de Favoritos (Canais, Filmes e Séries)
  static Future<Set<String>> loadFavorites() async {
    try {
      final f = await _file('unex_favorites_v8.json');
      if (await f.exists()) {
        final list = (jsonDecode(await f.readAsString()) as List)
            .map((e) => e.toString())
            .toSet();
        return list;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveFavorites(Set<String> ids) async {
    try {
      final f = await _file('unex_favorites_v8.json');
      await f.writeAsString(jsonEncode(ids.toList()));
    } catch (_) {}
  }

  // Persistência Permanente de Recentes
  static Future<List<StreamItem>> loadRecents() async {
    try {
      final f = await _file('unex_recents_v8.json');
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        return list
            .map((e) => StreamItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveRecents(List<StreamItem> items) async {
    try {
      final f = await _file('unex_recents_v8.json');
      final data = items.take(40).map((e) => e.toJson()).toList();
      await f.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<Map<String, VodProgressEntry>> loadVodProgressMap() async {
    try {
      final f = await _file('unex_vod_progress_v8.json');
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final Map<String, VodProgressEntry> map = {};
        raw.forEach((key, value) {
          if (value is Map) {
            map[key] =
                VodProgressEntry.fromJson(value.cast<String, dynamic>());
          }
        });
        return map;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveVodProgressEntry(VodProgressEntry entry) async {
    try {
      final f = await _file('unex_vod_progress_v8.json');
      final map = await loadVodProgressMap();
      if (entry.progress >= 0.96) {
        map.remove(entry.item.id);
      } else {
        map[entry.item.id] = entry;
      }
      final serialized =
          map.map((key, value) => MapEntry(key, value.toJson()));
      await f.writeAsString(jsonEncode(serialized));
    } catch (_) {}
  }
}

Future<void> applyDeviceOrientation(DeviceMode mode) async {
  if (mode == DeviceMode.tv) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

Future<void> showExitAppConfirmationDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF151924),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.exit_to_app_rounded, color: Color(0xFF00E5FF)),
          SizedBox(width: 10),
          Expanded(
            child: Text('Sair do Aplicativo?', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
      content: const Text(
        'Deseja continuar assistindo ou fechar o UNEX Vision?',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TVFocusableItem(
          autofocus: true,
          autoScroll: false,
          onSelect: () => Navigator.pop(ctx),
          builder: (context, isFocused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: const Text(
              'Continuar no App',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        TVFocusableItem(
          autoScroll: false,
          onSelect: () {
            Navigator.pop(ctx);
            SystemNavigator.pop();
          },
          builder: (context, isFocused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2230),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? Colors.redAccent : Colors.white12,
                width: 2,
              ),
            ),
            child: const Text(
              'Fechar Aplicativo',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<Duration?> showVodResumePrompt({
  required BuildContext context,
  required VodProgressEntry entry,
}) async {
  return showDialog<Duration?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121622),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
      ),
      title: Row(
        children: [
          const Icon(Icons.history_toggle_off_rounded,
              color: Color(0xFF00E5FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Você parou em ${entry.formattedPosition} (${entry.formattedRemaining}).',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 6,
              backgroundColor: Colors.white12,
              color: const Color(0xFF00E5FF),
            ),
          ),
        ],
      ),
      actions: [
        TVFocusableItem(
          autofocus: true,
          autoScroll: false,
          onSelect: () =>
              Navigator.pop(ctx, Duration(seconds: entry.positionSeconds)),
          builder: (context, isFocused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: Text(
              'Continuar de ${entry.formattedPosition}',
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        TVFocusableItem(
          autoScroll: false,
          onSelect: () => Navigator.pop(ctx, Duration.zero),
          builder: (context, isFocused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2030),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? const Color(0xFF00E5FF) : Colors.white12,
                width: 1.5,
              ),
            ),
            child: const Text('Começar do Início'),
          ),
        ),
      ],
    ),
  );
}

// =============================================================================
// MODAL STREAMING DE TEMPORADAS E EPISÓDIOS DA SÉRIE (COM BOTÃO DE FAVORITAR SÉRIE)
// =============================================================================
Future<void> openSeriesDetailsModal({
  required BuildContext context,
  required SeriesGroup series,
  required Map<String, VodProgressEntry> vodProgressMap,
  required bool isSeriesFavorite,
  required VoidCallback onToggleSeriesFavorite,
  required void Function(StreamItem episode, List<StreamItem> fullSeriesPlaylist)
      onPlayEpisode,
}) async {
  final seasonKeys = series.seasons.keys.toList()..sort();
  int selectedSeason = seasonKeys.isNotEmpty ? seasonKeys.first : 1;
  final allEpisodesPlaylist = series.allEpisodesFlat;
  bool localFav = isSeriesFavorite;

  await showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final currentEpisodes = series.seasons[selectedSeason] ?? [];

          return Dialog(
            backgroundColor: const Color(0xFF0B0E17),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                  color: const Color(0xFF00E5FF).withOpacity(0.45), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860, maxHeight: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(21)),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF162642),
                          const Color(0xFF0B0E17).withOpacity(0.95),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 95,
                            height: 135,
                            color: const Color(0xFF08090E),
                            child: series.logo.isNotEmpty
                                ? Image.network(
                                    series.logo,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.video_library_rounded,
                                        color: Color(0xFF00E5FF),
                                        size: 40),
                                  )
                                : const Icon(Icons.video_library_rounded,
                                    color: Color(0xFF00E5FF), size: 40),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  buildQualityBadge(series.qualityTag),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      series.group,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF00E5FF),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                series.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${series.totalSeasons} Temporada(s) • ${series.totalEpisodes} Episódio(s) disponíveis',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  if (currentEpisodes.isNotEmpty)
                                    TVFocusableItem(
                                      autofocus: true,
                                      autoScroll: false,
                                      onSelect: () {
                                        Navigator.pop(ctx);
                                        onPlayEpisode(currentEpisodes.first,
                                            allEpisodesPlaylist);
                                      },
                                      builder: (context, isFocused) =>
                                          AnimatedScale(
                                        scale: isFocused ? 1.05 : 1.0,
                                        duration:
                                            const Duration(milliseconds: 140),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 10),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF00E5FF),
                                                Color(0xFF2979FF)
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isFocused
                                                  ? Colors.white
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Colors.black,
                                                  size: 20),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Assistir T$selectedSeason:E${currentEpisodes.first.episodeNumber}',
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  TVFocusableItem(
                                    autoScroll: false,
                                    onSelect: () {
                                      setModalState(() => localFav = !localFav);
                                      onToggleSeriesFavorite();
                                    },
                                    builder: (context, isFocused) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF151924),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isFocused
                                              ? const Color(0xFF00E5FF)
                                              : Colors.white24,
                                          width: isFocused ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            localFav
                                                ? Icons.star_rounded
                                                : Icons.star_border_rounded,
                                            color: localFav
                                                ? Colors.amber
                                                : Colors.white,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            localFav
                                                ? 'Série Favorita'
                                                : 'Favoritar Série',
                                            style:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        TVIconButton(
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 52,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF101420),
                      border: Border(
                        top: BorderSide(color: Colors.white10),
                        bottom: BorderSide(color: Colors.white10),
                      ),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: seasonKeys.length,
                      itemBuilder: (context, index) {
                        final sNum = seasonKeys[index];
                        final epCount = series.seasons[sNum]?.length ?? 0;
                        final isSelected = sNum == selectedSeason;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: () =>
                                setModalState(() => selectedSeason = sNum),
                            builder: (context, isFocused) => AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? const LinearGradient(colors: [
                                        Color(0xFF00E5FF),
                                        Color(0xFF2979FF)
                                      ])
                                    : null,
                                color: isSelected
                                    ? null
                                    : const Color(0xFF171C2B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isFocused
                                      ? Colors.white
                                      : isSelected
                                          ? Colors.transparent
                                          : Colors.white12,
                                  width: isFocused ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                'Temporada $sNum ($epCount)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      isSelected ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: ListView.builder(
                        key: ValueKey<int>(selectedSeason),
                        padding: const EdgeInsets.all(16),
                        itemCount: currentEpisodes.length,
                        itemBuilder: (context, index) {
                          final ep = currentEpisodes[index];
                          final savedEntry = vodProgressMap[ep.id];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TVFocusableItem(
                              onSelect: () {
                                Navigator.pop(ctx);
                                onPlayEpisode(ep, allEpisodesPlaylist);
                              },
                              builder: (context, isFocused) =>
                                  AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isFocused
                                      ? const Color(0xFF1A2842)
                                      : const Color(0xFF131724),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isFocused
                                        ? const Color(0xFF00E5FF)
                                        : Colors.white10,
                                    width: isFocused ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isFocused
                                                ? const Color(0xFF00E5FF)
                                                : Colors.white10,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'E${ep.episodeNumber.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              color: isFocused
                                                  ? Colors.black
                                                  : const Color(0xFF00E5FF),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ep.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                savedEntry != null
                                                    ? 'Continuar de ${savedEntry.formattedPosition} • ${savedEntry.formattedRemaining}'
                                                    : 'Temporada $selectedSeason • Episódio ${ep.episodeNumber}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: savedEntry != null
                                                      ? const Color(0xFF00E5FF)
                                                      : Colors.white54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        buildQualityBadge(ep.qualityTag),
                                        const SizedBox(width: 10),
                                        Icon(
                                          Icons.play_circle_fill_rounded,
                                          color: isFocused
                                              ? const Color(0xFF00E5FF)
                                              : Colors.white54,
                                          size: 28,
                                        ),
                                      ],
                                    ),
                                    if (savedEntry != null) ...[
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: savedEntry.progress,
                                          minHeight: 4,
                                          backgroundColor: Colors.white10,
                                          color: const Color(0xFF00E5FF),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// =============================================================================
// TECLADO VIRTUAL MINIMALISTA ESTILO YOUTUBE TV
// =============================================================================
enum _TVKeyboardView { qwerty, symbols, web }

Future<void> openTVVirtualKeyboard({
  required BuildContext context,
  required TextEditingController controller,
  required String title,
  bool isNumericOnly = false,
  bool isUrlField = false,
  ValueChanged<String>? onChanged,
  VoidCallback? onCompleted,
}) async {
  String currentText = controller.text;
  bool isUppercase = false;
  _TVKeyboardView activeView = _TVKeyboardView.qwerty;

  final List<List<String>> symbolRows = [
    ['@', '#', '\$', '%', '&', '*', '+', '=', '?', '!', '~', '^'],
    ['(', ')', '[', ']', '{', '}', '<', '>', '|', '\\', '/', ':'],
    [';', '\'', '"', ',', '.', '-', '_', 'ç', 'á', 'é', 'í', 'ó'],
  ];

  final List<List<String>> webShortcutRows = [
    ['http://', 'https://', 'www.', '.club', '.com', '.net'],
    ['.org', '.br', '.tv', '.xyz', ':80', ':8080'],
    ['/get.php?', 'username=', '&password=', '&type=m3u_plus', '&output=ts'],
  ];

  await showDialog(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void appendText(String str) {
            setModalState(() {
              currentText += str;
              controller.text = currentText;
            });
            onChanged?.call(currentText);
          }

          void backspace() {
            if (currentText.isNotEmpty) {
              setModalState(() {
                currentText = currentText.substring(0, currentText.length - 1);
                controller.text = currentText;
              });
              onChanged?.call(currentText);
            }
          }

          void clearAll() {
            setModalState(() {
              currentText = '';
              controller.text = '';
            });
            onChanged?.call('');
          }

          String c(String ch) => isUppercase ? ch.toUpperCase() : ch;

          return PopScope(
            canPop: activeView == _TVKeyboardView.qwerty,
            onPopInvoked: (didPop) {
              if (!didPop && activeView != _TVKeyboardView.qwerty) {
                setModalState(() => activeView = _TVKeyboardView.qwerty);
              }
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 12, right: 12),
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0D14).withOpacity(0.94),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF00E5FF).withOpacity(0.55),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.75),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: isNumericOnly ? 280 : 450,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF05070B),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '$title: ',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF00E5FF),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      currentText.isEmpty
                                          ? '...'
                                          : '$currentText▌',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: currentText.isEmpty
                                            ? Colors.white30
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isNumericOnly) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final d in [
                                    '1',
                                    '2',
                                    '3',
                                    '4',
                                    '5',
                                    '6',
                                    '7',
                                    '8',
                                    '9',
                                    '0'
                                  ])
                                    _buildMinimalKey(
                                      label: d,
                                      width: 34,
                                      autofocus: d == '1',
                                      onTap: () => appendText(d),
                                    ),
                                  _buildMinimalKey(
                                    label: '⌫',
                                    width: 38,
                                    color: const Color(0xFF281A22),
                                    textColor: Colors.orangeAccent,
                                    onTap: backspace,
                                  ),
                                  _buildMinimalKey(
                                    label: '✖',
                                    width: 34,
                                    color: const Color(0xFF281A22),
                                    textColor: Colors.redAccent,
                                    onTap: clearAll,
                                  ),
                                ],
                              ),
                            ] else if (activeView ==
                                _TVKeyboardView.symbols) ...[
                              for (int r = 0; r < symbolRows.length; r++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (int i = 0;
                                          i < symbolRows[r].length;
                                          i++)
                                        _buildMinimalKey(
                                          label: symbolRows[r][i],
                                          width: 35,
                                          autofocus: r == 0 && i == 0,
                                          onTap: () =>
                                              appendText(symbolRows[r][i]),
                                        ),
                                    ],
                                  ),
                                ),
                            ] else if (activeView == _TVKeyboardView.web) ...[
                              for (int r = 0; r < webShortcutRows.length; r++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (int i = 0;
                                          i < webShortcutRows[r].length;
                                          i++)
                                        _buildMinimalKey(
                                          label: webShortcutRows[r][i],
                                          autofocus: r == 0 && i == 0,
                                          color: const Color(0xFF152036),
                                          textColor: const Color(0xFF00E5FF),
                                          onTap: () =>
                                              appendText(webShortcutRows[r][i]),
                                        ),
                                    ],
                                  ),
                                ),
                            ] else ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final k in [
                                      '1',
                                      '2',
                                      '3',
                                      '4',
                                      '5',
                                      '6',
                                      '7',
                                      '8',
                                      '9',
                                      '0',
                                      '-',
                                      '.'
                                    ])
                                      _buildMinimalKey(
                                        label: k,
                                        width: 35,
                                        onTap: () => appendText(k),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final k in [
                                      'q',
                                      'w',
                                      'e',
                                      'r',
                                      't',
                                      'y',
                                      'u',
                                      'i',
                                      'o',
                                      'p'
                                    ])
                                      _buildMinimalKey(
                                        label: c(k),
                                        width: 35,
                                        autofocus: k == 'q',
                                        onTap: () => appendText(c(k)),
                                      ),
                                    _buildMinimalKey(
                                      label: '/',
                                      width: 35,
                                      onTap: () => appendText('/'),
                                    ),
                                    _buildMinimalKey(
                                      label: ':',
                                      width: 35,
                                      onTap: () => appendText(':'),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMinimalKey(
                                      label: '⇧',
                                      width: 35,
                                      color: isUppercase
                                          ? const Color(0xFF00E5FF)
                                          : const Color(0xFF1A2030),
                                      textColor: isUppercase
                                          ? Colors.black
                                          : Colors.white,
                                      onTap: () => setModalState(
                                          () => isUppercase = !isUppercase),
                                    ),
                                    for (final k in [
                                      'a',
                                      's',
                                      'd',
                                      'f',
                                      'g',
                                      'h',
                                      'j',
                                      'k',
                                      'l'
                                    ])
                                      _buildMinimalKey(
                                        label: c(k),
                                        width: 35,
                                        onTap: () => appendText(c(k)),
                                      ),
                                    _buildMinimalKey(
                                      label: '_',
                                      width: 35,
                                      onTap: () => appendText('_'),
                                    ),
                                    _buildMinimalKey(
                                      label: '⌫',
                                      width: 35,
                                      color: const Color(0xFF281A22),
                                      textColor: Colors.orangeAccent,
                                      onTap: backspace,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (!isNumericOnly)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildMinimalKey(
                                    label: activeView == _TVKeyboardView.symbols
                                        ? 'ABC'
                                        : '#+=',
                                    width: 40,
                                    color: activeView == _TVKeyboardView.symbols
                                        ? const Color(0xFF00E5FF)
                                        : const Color(0xFF172234),
                                    textColor:
                                        activeView == _TVKeyboardView.symbols
                                            ? Colors.black
                                            : const Color(0xFF00E5FF),
                                    onTap: () => setModalState(() {
                                      activeView =
                                          activeView == _TVKeyboardView.symbols
                                              ? _TVKeyboardView.qwerty
                                              : _TVKeyboardView.symbols;
                                    }),
                                  ),
                                  _buildMinimalKey(
                                    label: activeView == _TVKeyboardView.web
                                        ? 'ABC'
                                        : '🌐',
                                    width: 36,
                                    color: activeView == _TVKeyboardView.web
                                        ? const Color(0xFF00E5FF)
                                        : const Color(0xFF172234),
                                    textColor: activeView == _TVKeyboardView.web
                                        ? Colors.black
                                        : const Color(0xFF00E5FF),
                                    onTap: () => setModalState(() {
                                      activeView =
                                          activeView == _TVKeyboardView.web
                                              ? _TVKeyboardView.qwerty
                                              : _TVKeyboardView.web;
                                    }),
                                  ),
                                  for (final k in [
                                    'z',
                                    'x',
                                    'c',
                                    'v',
                                    'b',
                                    'n',
                                    'm'
                                  ])
                                    _buildMinimalKey(
                                      label: c(k),
                                      width: 35,
                                      onTap: () => appendText(c(k)),
                                    ),
                                  _buildMinimalKey(
                                    label: '␣',
                                    width: 66,
                                    color: const Color(0xFF1A2030),
                                    onTap: () => appendText(' '),
                                  ),
                                  _buildMinimalKey(
                                    label: '✖',
                                    width: 35,
                                    color: const Color(0xFF281A22),
                                    textColor: Colors.redAccent,
                                    onTap: clearAll,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () {
                          Navigator.pop(ctx);
                          onCompleted?.call();
                        },
                        builder: (context, isFocused) => AnimatedScale(
                          scale: isFocused ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isFocused
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.6),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Continuar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 16, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildMinimalKey({
  required String label,
  required VoidCallback onTap,
  double? width,
  double height = 29,
  Color color = const Color(0xFF151924),
  Color textColor = Colors.white,
  bool autofocus = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1.5),
    child: TVFocusableItem(
      autofocus: autofocus,
      autoScroll: false,
      onSelect: onTap,
      builder: (context, isFocused) => AnimatedScale(
        scale: isFocused ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 70),
        child: Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: width == null ? 8 : 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isFocused ? const Color(0xFF00E5FF) : color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isFocused ? Colors.white : Colors.white10,
              width: isFocused ? 1.5 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isFocused ? Colors.black : textColor,
            ),
          ),
        ),
      ),
    ),
  );
}

class AdaptiveInputField extends StatefulWidget {
  final DeviceMode deviceMode;
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final bool isUrlField;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const AdaptiveInputField({
    super.key,
    required this.deviceMode,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.isUrlField = false,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<AdaptiveInputField> createState() => _AdaptiveInputFieldState();
}

class _AdaptiveInputFieldState extends State<AdaptiveInputField> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deviceMode == DeviceMode.mobile) {
      return TextField(
        controller: widget.controller,
        obscureText: widget.isPassword ? _obscure : false,
        onChanged: widget.onChanged,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, color: const Color(0xFF00E5FF)),
          suffixIcon: widget.isPassword
              ? IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF08090E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );
    }

    final hasValue = widget.controller.text.isNotEmpty;
    final displayValue = !hasValue
        ? widget.hint
        : (widget.isPassword && _obscure)
            ? '•' * widget.controller.text.length
            : widget.controller.text;

    return TVFocusableItem(
      autoScroll: false,
      onSelect: () {
        openTVVirtualKeyboard(
          context: context,
          controller: widget.controller,
          title: widget.label,
          isUrlField: widget.isUrlField,
          onChanged: widget.onChanged,
        );
      },
      builder: (context, isFocused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF08090E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused ? const Color(0xFF00E5FF) : Colors.white12,
            width: isFocused ? 2.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: const Color(0xFF00E5FF), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: hasValue ? Colors.white : Colors.white38,
                      fontWeight:
                          hasValue ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isFocused ? const Color(0xFF00E5FF) : Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'OK p/ Digitar',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isFocused ? Colors.black : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpeedTestDialog extends StatefulWidget {
  final String testUrl;
  final void Function(double mbps) onSpeedMeasured;

  const SpeedTestDialog({
    super.key,
    required this.testUrl,
    required this.onSpeedMeasured,
  });

  @override
  State<SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<SpeedTestDialog> {
  bool isTesting = false;
  double speedMbps = 0.0;
  int pingMs = 0;
  String statusText = 'Selecione Iniciar para medir sua conexão atual';

  Future<void> _runTest() async {
    setState(() {
      isTesting = true;
      speedMbps = 0.0;
      statusText = 'Medindo latência e velocidade de download...';
    });

    try {
      final uri =
          Uri.parse('https://speed.cloudflare.com/__down?bytes=5000000');
      final pingWatch = Stopwatch()..start();
      final client = HttpClient();
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      final res = await req.close();
      pingWatch.stop();
      pingMs = pingWatch.elapsedMilliseconds;

      final dlWatch = Stopwatch()..start();
      int receivedBytes = 0;

      await for (final chunk in res) {
        receivedBytes += chunk.length;
        final elapsedSec = dlWatch.elapsedMilliseconds / 1000.0;
        if (elapsedSec > 0.1) {
          final currentMbps = (receivedBytes * 8) / (elapsedSec * 1000000);
          if (mounted) setState(() => speedMbps = currentMbps);
        }
      }
      dlWatch.stop();
      widget.onSpeedMeasured(speedMbps);

      if (mounted) {
        setState(() {
          isTesting = false;
          statusText = speedMbps >= 20
              ? 'Excelente para canais 4K e FHD!'
              : speedMbps >= 8
                  ? 'Recomendado para canais HD / FHD.'
                  : 'Conexão lenta. O Anti-Travamento ajustou o buffer.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isTesting = false;
          statusText = 'Não foi possível concluir a medição no momento.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF151924),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.speed_rounded, color: Color(0xFF00E5FF)),
          SizedBox(width: 10),
          Expanded(
            child: Text('Teste de Velocidade', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${speedMbps.toStringAsFixed(1)} Mbps',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Color(0xFF00E5FF),
            ),
          ),
          if (pingMs > 0)
            Text('Latência: $pingMs ms',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 14),
          if (isTesting)
            const LinearProgressIndicator(color: Color(0xFF00E5FF)),
          const SizedBox(height: 10),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TVFocusableItem(
          autoScroll: false,
          onSelect: () => Navigator.pop(context),
          builder: (context, isFocused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isFocused ? Colors.white : Colors.transparent),
            ),
            child: const Text('Fechar'),
          ),
        ),
        if (!isTesting)
          TVFocusableItem(
            autofocus: true,
            autoScroll: false,
            onSelect: _runTest,
            builder: (context, isFocused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: const Text(
                'Iniciar Teste',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// WIDGET DE FOCO COM SUPORTE A CLIQUE LONGO NO BOTÃO OK (FAVORITAR RÁPIDO NA TV)
// =============================================================================
class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final VoidCallback? onLongSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final bool autoScroll;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const TVFocusableItem({
    super.key,
    required this.onSelect,
    this.onLongSelect,
    required this.builder,
    this.autoScroll = true,
    this.autofocus = false,
    this.focusNode,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (!focused) {
          _longPressTimer?.cancel();
        }
        setState(() => _isFocused = focused);
        if (focused && widget.autoScroll && mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        final key = event.logicalKey;
        if (_isSelectKey(key)) {
          if (event is KeyDownEvent) {
            _longPressTriggered = false;
            if (widget.onLongSelect != null) {
              _longPressTimer?.cancel();
              _longPressTimer = Timer(const Duration(milliseconds: 650), () {
                _longPressTriggered = true;
                widget.onLongSelect!();
              });
            } else {
              widget.onSelect();
            }
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _longPressTimer?.cancel();
            if (widget.onLongSelect != null && !_longPressTriggered) {
              widget.onSelect();
            }
            return KeyEventResult.handled;
          }
        }

        if (event is KeyDownEvent) {
          if (widget.onMoveLeft != null &&
              key == LogicalKeyboardKey.arrowLeft) {
            widget.onMoveLeft!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveRight != null &&
              key == LogicalKeyboardKey.arrowRight) {
            widget.onMoveRight!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onLongPress: widget.onLongSelect,
        child: widget.builder(context, _isFocused),
      ),
    );
  }
}

class TVIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color color;
  final double size;
  final bool autofocus;

  const TVIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = Colors.white70,
    this.size = 20,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      autofocus: autofocus,
      autoScroll: false,
      onSelect: onPressed,
      builder: (context, isFocused) => AnimatedScale(
        scale: isFocused ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isFocused
                ? const Color(0xFF00E5FF).withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: isFocused ? Colors.white : color,
            size: size,
          ),
        ),
      ),
    );
  }
}

Widget buildStreamingPosterCard({
  required String title,
  required String subtitle,
  required String logoUrl,
  required String badgeText,
  required VoidCallback onTap,
  bool isFocused = false,
  bool isPlaying = false,
  bool isFavorite = false,
  double? progress,
  VoidCallback? onFavoriteTap,
}) {
  return AnimatedScale(
    scale: isFocused ? 1.06 : 1.0,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOutCubic,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: const Color(0xFF121622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFocused
              ? const Color(0xFF00E5FF)
              : isPlaying
                  ? const Color(0xFF2979FF)
                  : Colors.white12,
          width: isFocused ? 2.5 : 1,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            logoUrl.isNotEmpty
                ? Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF101420),
                      child: const Icon(Icons.movie_filter_rounded,
                          color: Color(0xFF00E5FF), size: 42),
                    ),
                  )
                : Container(
                    color: const Color(0xFF101420),
                    child: const Icon(Icons.movie_filter_rounded,
                        color: Color(0xFF00E5FF), size: 42),
                  ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.transparent,
                    Colors.black.withOpacity(0.94),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: buildQualityBadge(badgeText),
            ),
            if (onFavoriteTap != null)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onFavoriteTap,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: isFavorite ? Colors.amber : Colors.white70,
                      size: 16,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (progress != null && progress > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.05, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFF00E5FF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildQualityBadge(String tag) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: tag == '4K' || tag == 'FHD'
          ? const Color(0xFF00E5FF).withOpacity(0.25)
          : Colors.black87,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(
        color: tag == '4K' || tag == 'FHD'
            ? const Color(0xFF00E5FF).withOpacity(0.6)
            : Colors.white24,
        width: 0.8,
      ),
    ),
    child: Text(
      tag,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: tag == '4K' || tag == 'FHD'
            ? const Color(0xFF00E5FF)
            : Colors.white,
      ),
    ),
  );
}

Widget buildChannelLogo(String url, {double size = 44}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF08090E),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.tv_rounded, color: Color(0xFF00E5FF)),
            )
          : const Icon(Icons.tv_rounded, color: Color(0xFF00E5FF)),
    ),
  );
}

List<StreamItem> parseM3UAdvanced(String raw) {
  final List<StreamItem> result = [];
  final lines = const LineSplitter().convert(raw);

  String name = '';
  String group = 'Canais';
  String logo = '';
  String tvgId = '';
  int counter = 0;

  final groupRegex = RegExp(r'group-title="([^"]*)"', caseSensitive: false);
  final logoRegex = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);
  final tvgIdRegex = RegExp(r'tvg-id="([^"]*)"', caseSensitive: false);
  final streamIdRegex =
      RegExp(r'/(\d+)\.(?:ts|m3u8|mp4|mkv)$|/(\d+)$', caseSensitive: false);
  final qualityRegex = RegExp(
      r'\b(4K|UHD|FHD|1080P|HD|720P|SD|H265|HEVC)\b',
      caseSensitive: false);
  final sePattern1 =
      RegExp(r'[sS](\d{1,2})\s*[eE](\d{1,3})', caseSensitive: false);
  final sePattern2 =
      RegExp(r'[tT](\d{1,2})\s*[eE](\d{1,3})', caseSensitive: false);
  final sePattern3 = RegExp(r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false);

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#EXTINF:')) {
      final groupMatch = groupRegex.firstMatch(trimmed);
      final logoMatch = logoRegex.firstMatch(trimmed);
      final idMatch = tvgIdRegex.firstMatch(trimmed);

      group = groupMatch?.group(1)?.trim() ?? 'Geral';
      if (group.isEmpty) group = 'Geral';
      logo = logoMatch?.group(1)?.trim() ?? '';
      tvgId = idMatch?.group(1)?.trim() ?? '';

      final commaIndex = trimmed.lastIndexOf(',');
      if (commaIndex != -1 && commaIndex + 1 < trimmed.length) {
        name = trimmed.substring(commaIndex + 1).trim();
      } else {
        name = 'Canal ${counter + 1}';
      }
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      counter++;
      final lowerUrl = trimmed.toLowerCase();
      final lowerGroup = group.toLowerCase();
      final lowerName = name.toLowerCase();

      String extractedStreamId = '';
      final sidMatch = streamIdRegex.firstMatch(trimmed);
      if (sidMatch != null) {
        extractedStreamId = sidMatch.group(1) ?? sidMatch.group(2) ?? '';
      }

      RegExpMatch? seMatch = sePattern1.firstMatch(name) ??
          sePattern2.firstMatch(name) ??
          sePattern3.firstMatch(name);

      ContentType type = ContentType.live;
      if (lowerUrl.contains('/series/') ||
          lowerGroup.contains('série') ||
          lowerGroup.contains('serie') ||
          seMatch != null) {
        type = ContentType.series;
      } else if (lowerUrl.contains('/movie/') ||
          lowerGroup.contains('filme') ||
          lowerGroup.contains('vod') ||
          lowerGroup.contains('cinema') ||
          lowerUrl.endsWith('.mp4') ||
          lowerUrl.endsWith('.mkv')) {
        type = ContentType.movie;
      }

      String quality = 'HD';
      final qMatch = qualityRegex.firstMatch(name);
      if (qMatch != null) {
        final rawQ = qMatch.group(1)!.toUpperCase();
        if (rawQ == 'UHD') {
          quality = '4K';
        } else if (rawQ == '1080P') {
          quality = 'FHD';
        } else if (rawQ == '720P') {
          quality = 'HD';
        } else {
          quality = rawQ;
        }
      }

      final cleanName = name
          .replaceAll(qualityRegex, '')
          .replaceAll(RegExp(r'[\[\]\(\)\-\|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      int seasonNum = 1;
      int episodeNum = 1;
      String extractedSeriesName = cleanName;

      if (type == ContentType.series) {
        if (seMatch != null) {
          seasonNum = int.tryParse(seMatch.group(1) ?? '1') ?? 1;
          episodeNum = int.tryParse(seMatch.group(2) ?? '1') ?? 1;
          extractedSeriesName = name
              .substring(0, seMatch.start)
              .replaceAll(qualityRegex, '')
              .replaceAll(RegExp(r'[\[\]\(\)\-\|\:]'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
        if (extractedSeriesName.isEmpty) {
          extractedSeriesName = cleanName.isNotEmpty ? cleanName : name;
        }
      }

      final isAdult = lowerGroup.contains('adult') ||
          lowerGroup.contains('xxx') ||
          lowerGroup.contains('+18') ||
          lowerName.contains('xxx');

      result.add(
        StreamItem(
          id: '${counter}_${trimmed.hashCode}',
          streamId: extractedStreamId,
          tvgId: tvgId,
          name: name.isNotEmpty ? name : 'Canal $counter',
          cleanName: cleanName.isNotEmpty ? cleanName : name,
          seriesName: extractedSeriesName,
          seasonNumber: seasonNum,
          episodeNumber: episodeNum,
          qualityTag: quality,
          group: group,
          logo: logo,
          url: trimmed,
          type: type,
          isAdult: isAdult,
        ),
      );

      name = '';
      group = 'Geral';
      logo = '';
      tvgId = '';
    }
  }
  return result;
}
