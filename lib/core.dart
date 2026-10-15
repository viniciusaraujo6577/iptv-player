import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Map<String, String> kIptvHeaders = {
  'User-Agent': 'IPTVSmartersPlayer/1.0 (Linux; Android 11)',
  'Accept': '*/*',
  'Connection': 'keep-alive',
};

enum DeviceMode { mobile, tv }
enum ContentType { live, movie, series }
enum MainSection { live, movie, series, favorites, recents }

class StreamItem {
  final String id;
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
}

// =============================================================================
// MODELO AGRUPADOR DE SÉRIES (CAPA ÚNICA -> TEMPORADAS -> EPISÓDIOS)
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

// =============================================================================
// TRANSIÇÃO ANIMADA FLUIDA ENTRE TELAS
// =============================================================================
Route<T> createSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

// =============================================================================
// ARMAZENAMENTO DE PREFERÊNCIA DE DISPOSITIVO E SESSÃO
// =============================================================================
class AppStorage {
  static File get _deviceFile =>
      File('${Directory.systemTemp.path}/unex_device_mode_v6.json');
  static File get _sessionFile =>
      File('${Directory.systemTemp.path}/unex_verified_session_v6.json');

  static Future<DeviceMode?> loadDeviceMode() async {
    try {
      if (await _deviceFile.exists()) {
        final data = jsonDecode(await _deviceFile.readAsString());
        if (data['mode'] == 'tv') return DeviceMode.tv;
        if (data['mode'] == 'mobile') return DeviceMode.mobile;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveDeviceMode(DeviceMode mode) async {
    try {
      await _deviceFile.writeAsString(
        jsonEncode({'mode': mode == DeviceMode.tv ? 'tv' : 'mobile'}),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadVerifiedSession() async {
    try {
      if (await _sessionFile.exists()) {
        final data =
            jsonDecode(await _sessionFile.readAsString()) as Map<String, dynamic>;
        if (data['verified'] == true) return data;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveVerifiedSession(Map<String, dynamic> data) async {
    try {
      data['verified'] = true;
      await _sessionFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> clearSession() async {
    try {
      if (await _sessionFile.exists()) {
        await _sessionFile.delete();
      }
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

// =============================================================================
// MODAL STREAMING DE TEMPORADAS E EPISÓDIOS DA SÉRIE (CELULAR E TV)
// =============================================================================
Future<void> openSeriesDetailsModal({
  required BuildContext context,
  required SeriesGroup series,
  required void Function(StreamItem episode, List<StreamItem> fullSeriesPlaylist)
      onPlayEpisode,
}) async {
  final seasonKeys = series.seasons.keys.toList()..sort();
  int selectedSeason = seasonKeys.isNotEmpty ? seasonKeys.first : 1;
  final allEpisodesPlaylist = series.allEpisodesFlat;

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
                  // CABEÇALHO ESTILO STREAMING COM CAPA E RESUMO DA SÉRIE
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
                                    duration: const Duration(milliseconds: 140),
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
                                        borderRadius: BorderRadius.circular(10),
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
                                          const Icon(Icons.play_arrow_rounded,
                                              color: Colors.black, size: 20),
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

                  // SELETOR HORIZONTAL DE TEMPORADAS
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

                  // LISTA ANIMADA DE EPISÓDIOS DA TEMPORADA
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: ListView.builder(
                        key: ValueKey<int>(selectedSeason),
                        padding: const EdgeInsets.all(16),
                        itemCount: currentEpisodes.length,
                        itemBuilder: (context, index) {
                          final ep = currentEpisodes[index];
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
                                    horizontal: 14, vertical: 12),
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
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isFocused
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white10,
                                        borderRadius: BorderRadius.circular(10),
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
                                            'Temporada $selectedSeason • Episódio ${ep.episodeNumber}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white54,
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
// TECLADO VIRTUAL PRÓPRIO PARA TV ANDROID
// =============================================================================
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

  final List<String> alphaRows = [
    '1234567890',
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
    ':/.-_?=&@',
  ];

  final List<String> urlShortcuts = [
    'http://',
    'https://',
    '.club',
    '.com',
    '.net',
    '.org',
    ':80',
    ':8080',
  ];

  await showDialog(
    context: context,
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

          return Dialog(
            backgroundColor: const Color(0xFF10131C),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.keyboard_alt_outlined,
                                color: Color(0xFF00E5FF), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00E5FF),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Use as setas do controle e aperte OK',
                          style: TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07080C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        currentText.isEmpty
                            ? ' (Vazio - selecione as teclas abaixo)'
                            : '$currentText▌',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: currentText.isEmpty
                              ? Colors.white38
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isUrlField && !isNumericOnly) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: urlShortcuts.map((shortcut) {
                          return _buildKeyButton(
                            label: shortcut,
                            color: const Color(0xFF17243A),
                            textColor: const Color(0xFF00E5FF),
                            onTap: () => appendText(shortcut),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (isNumericOnly)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: '1234567890'.split('').map((digit) {
                          return _buildKeyButton(
                            label: digit,
                            width: 54,
                            height: 44,
                            autofocus: digit == '1',
                            onTap: () => appendText(digit),
                          );
                        }).toList(),
                      )
                    else
                      ...alphaRows.asMap().entries.map((entry) {
                        final rowIndex = entry.key;
                        final chars = entry.value.split('');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            alignment: WrapAlignment.center,
                            children: chars.asMap().entries.map((charEntry) {
                              final rawChar = charEntry.value;
                              final displayChar =
                                  isUppercase ? rawChar.toUpperCase() : rawChar;
                              return _buildKeyButton(
                                label: displayChar,
                                width: 45,
                                height: 36,
                                autofocus: rowIndex == 1 && charEntry.key == 0,
                                onTap: () => appendText(displayChar),
                              );
                            }).toList(),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (!isNumericOnly)
                          _buildKeyButton(
                            label: isUppercase ? '⇧ MAIÚSC' : '⇧ minúsc',
                            color: isUppercase
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFF1C202E),
                            textColor:
                                isUppercase ? Colors.black : Colors.white,
                            onTap: () => setModalState(
                                () => isUppercase = !isUppercase),
                          ),
                        if (!isNumericOnly)
                          _buildKeyButton(
                            label: 'ESPAÇO',
                            width: 100,
                            color: const Color(0xFF1C202E),
                            onTap: () => appendText(' '),
                          ),
                        _buildKeyButton(
                          label: '⌫ APAGAR',
                          color: const Color(0xFF2C1D24),
                          textColor: Colors.orangeAccent,
                          onTap: backspace,
                        ),
                        _buildKeyButton(
                          label: 'LIMPAR',
                          color: const Color(0xFF2C1D24),
                          textColor: Colors.redAccent,
                          onTap: clearAll,
                        ),
                        _buildKeyButton(
                          label: '✓ CONCLUIR',
                          width: 125,
                          color: const Color(0xFF00E5FF),
                          textColor: Colors.black,
                          onTap: () {
                            Navigator.pop(ctx);
                            onCompleted?.call();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildKeyButton({
  required String label,
  required VoidCallback onTap,
  double? width,
  double height = 36,
  Color color = const Color(0xFF181C28),
  Color textColor = Colors.white,
  bool autofocus = false,
}) {
  return TVFocusableItem(
    autofocus: autofocus,
    autoScroll: false,
    onSelect: onTap,
    builder: (context, isFocused) => AnimatedScale(
      scale: isFocused ? 1.1 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.symmetric(horizontal: width == null ? 12 : 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFF00E5FF) : color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.white12,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isFocused ? Colors.black : textColor,
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
          title: 'Digitar: ${widget.label}',
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
// WIDGET DE FOCO COM SUPORTE A GATILHO DE BORDA ESQUERDA (REABRIR MENU LATERAL)
// =============================================================================
class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final bool autoScroll;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveLeft;

  const TVFocusableItem({
    super.key,
    required this.onSelect,
    required this.builder,
    this.autoScroll = true,
    this.autofocus = false,
    this.focusNode,
    this.onMoveLeft,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused && widget.autoScroll && mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (widget.onMoveLeft != null &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onMoveLeft!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
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

// =============================================================================
// PÔSTER ESTILO CINEMA / STREAMING PARA FILMES E SÉRIES
// =============================================================================
Widget buildStreamingPosterCard({
  required String title,
  required String subtitle,
  required String logoUrl,
  required String badgeText,
  required VoidCallback onTap,
  bool isFocused = false,
  bool isPlaying = false,
  bool isFavorite = false,
  VoidCallback? onFavoriteTap,
}) {
  return AnimatedScale(
    scale: isFocused ? 1.06 : 1.0,
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
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
                    Colors.black.withOpacity(0.92),
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

// =============================================================================
// PARSER AVANÇADO COM EXTRAÇÃO DE TEMPORADA E EPISÓDIO PARA SÉRIES
// =============================================================================
List<StreamItem> parseM3UAdvanced(String raw) {
  final List<StreamItem> result = [];
  final lines = const LineSplitter().convert(raw);

  String name = '';
  String group = 'Canais';
  String logo = '';
  int counter = 0;

  final groupRegex = RegExp(r'group-title="([^"]*)"', caseSensitive: false);
  final logoRegex = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);
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

      group = groupMatch?.group(1)?.trim() ?? 'Geral';
      if (group.isEmpty) group = 'Geral';
      logo = logoMatch?.group(1)?.trim() ?? '';

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
    }
  }
  return result;
}
