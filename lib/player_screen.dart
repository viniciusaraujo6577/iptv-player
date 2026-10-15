import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';

class SmartAdaptivePlayerScreen extends StatefulWidget {
  final StreamItem initialItem;
  final List<StreamItem> playlist;
  final List<StreamItem> liveChannelsPool;
  final double measuredSpeedMbps;
  final Duration? initialStartPosition;
  final void Function(StreamItem item) onMinimizeToPip;

  const SmartAdaptivePlayerScreen({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.liveChannelsPool,
    required this.measuredSpeedMbps,
    this.initialStartPosition,
    required this.onMinimizeToPip,
  });

  @override
  State<SmartAdaptivePlayerScreen> createState() =>
      _SmartAdaptivePlayerScreenState();
}

class _SmartAdaptivePlayerScreenState extends State<SmartAdaptivePlayerScreen> {
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  late StreamItem currentItem;

  bool showOsd = true;
  bool showQuickChannelDrawer = false;

  int aspectMode = 0;
  final List<String> aspectLabels = ['Original', 'Esticar', '16:9', '4:3'];

  Timer? _hideTimer;
  Timer? _sleepTimer;
  int? _sleepMinutesRemaining;

  final FocusNode _playPauseFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentItem = widget.initialItem;

    // Usa o motor compartilhado: se o canal já está rodando na pré-visualização, NÃO REINICIA!
    _engine.openStream(
      currentItem,
      startPosition: widget.initialStartPosition,
    );

    _resetOsdTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && showOsd) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sleepTimer?.cancel();
    _playPauseFocusNode.dispose();
    // NÃO damos dispose no _engine.controller para que o vídeo continue rodando
    // sem reiniciar ao voltar para o menu principal de canais!
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _switchStream(StreamItem item, {bool forceReload = false}) {
    setState(() {
      currentItem = item;
      showOsd = true;
    });
    _engine.openStream(item, forceReload: forceReload);
    _resetOsdTimer();
  }

  void _showOsdAndFocus() {
    setState(() => showOsd = true);
    _resetOsdTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playPauseFocusNode.requestFocus();
    });
  }

  void _resetOsdTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !showQuickChannelDrawer) {
        setState(() => showOsd = false);
      }
    });
  }

  void _stepChannel(int delta) {
    if (widget.playlist.isEmpty) return;
    final idx = widget.playlist.indexWhere((i) => i.id == currentItem.id);
    if (idx == -1) return;
    final next =
        (idx + delta + widget.playlist.length) % widget.playlist.length;
    _switchStream(widget.playlist[next]);
  }

  List<StreamItem> _getQualities() {
    if (currentItem.type != ContentType.live) return [currentItem];
    final target = currentItem.cleanName.toLowerCase();
    final list = widget.liveChannelsPool
        .where((i) => i.cleanName.toLowerCase() == target)
        .take(5)
        .toList();
    return list.isEmpty ? [currentItem] : list;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _openSleepTimerModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bedtime_rounded, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text('Timer de Sono (Sleep)', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mins in [15, 30, 60, 90, 120])
              TVFocusableItem(
                autofocus: mins == 30,
                autoScroll: false,
                onSelect: () {
                  _setSleepTimer(mins);
                  Navigator.pop(ctx);
                },
                builder: (context, isFocused) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isFocused ? Colors.white10 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused
                          ? const Color(0xFF00E5FF)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 18, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 10),
                      Text('Desligar em $mins minutos'),
                    ],
                  ),
                ),
              ),
            if (_sleepMinutesRemaining != null)
              TVFocusableItem(
                autoScroll: false,
                onSelect: () {
                  _sleepTimer?.cancel();
                  setState(() => _sleepMinutesRemaining = null);
                  Navigator.pop(ctx);
                },
                builder: (context, isFocused) => Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused ? Colors.redAccent : Colors.transparent,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text('Cancelar Timer',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepMinutesRemaining = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sleepMinutesRemaining != null && _sleepMinutesRemaining! > 1) {
          _sleepMinutesRemaining = _sleepMinutesRemaining! - 1;
        } else {
          timer.cancel();
          _sleepMinutesRemaining = null;
          _engine.stopAndClear();
          SystemNavigator.pop();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final ctrl = _engine.controller;
        final isReady = _engine.isReady && ctrl != null;
        final hasError = _engine.hasError;
        final isRecovering = _engine.isRecovering;
        final epg = _engine.currentEpg;
        final qualities = _getQualities();
        final isVod = currentItem.type != ContentType.live;

        return PopScope(
          canPop: !showQuickChannelDrawer && !showOsd,
          onPopInvoked: (didPop) {
            if (!didPop) {
              if (showQuickChannelDrawer) {
                setState(() => showQuickChannelDrawer = false);
              } else if (showOsd) {
                setState(() => showOsd = false);
              }
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  final key = event.logicalKey;

                  if (key == LogicalKeyboardKey.mediaPlayPause ||
                      key == LogicalKeyboardKey.mediaPlay ||
                      key == LogicalKeyboardKey.mediaPause) {
                    _engine.togglePlayPause();
                    _resetOsdTimer();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.channelUp) {
                    _stepChannel(-1);
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.channelDown) {
                    _stepChannel(1);
                    return KeyEventResult.handled;
                  }

                  if (!showQuickChannelDrawer && !showOsd) {
                    if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.numpadEnter ||
                        key == LogicalKeyboardKey.gameButtonA) {
                      _showOsdAndFocus();
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.arrowUp) {
                      if (!isVod) {
                        _stepChannel(-1);
                      } else {
                        _showOsdAndFocus();
                      }
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.arrowDown) {
                      if (!isVod) {
                        _stepChannel(1);
                      } else {
                        _showOsdAndFocus();
                      }
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isVod) {
                        _engine.seekRelative(-10);
                        _showOsdAndFocus();
                      } else {
                        setState(() => showQuickChannelDrawer = true);
                      }
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.arrowRight) {
                      if (isVod) {
                        _engine.seekRelative(10);
                        _showOsdAndFocus();
                      } else {
                        _showOsdAndFocus();
                      }
                      return KeyEventResult.handled;
                    }
                  } else {
                    _resetOsdTimer();
                  }
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (showQuickChannelDrawer) {
                    setState(() => showQuickChannelDrawer = false);
                  } else if (showOsd) {
                    setState(() => showOsd = false);
                  } else {
                    _showOsdAndFocus();
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. VÍDEO PRINCIPAL CONTÍNUO
                    Center(
                      child: hasError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.wifi_tethering_error_rounded,
                                    color: Colors.redAccent, size: 44),
                                const SizedBox(height: 12),
                                const Text(
                                    'Transmissão indisponível no momento.'),
                                const SizedBox(height: 12),
                                TVFocusableItem(
                                  autofocus: true,
                                  autoScroll: false,
                                  onSelect: () => _engine.openStream(
                                    currentItem,
                                    forceReload: true,
                                    tryHlsFallback: !_engine.usingHlsFallback,
                                  ),
                                  builder: (context, isFocused) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00E5FF),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isFocused
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Text(
                                      'Reconectar Fluxo',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : isReady
                              ? _buildAspectVideo(ctrl)
                              : const CircularProgressIndicator(
                                  color: Color(0xFF00E5FF)),
                    ),

                    // 2. INDICADOR DE SINCRONIZAÇÃO DE BAIXA LATÊNCIA
                    if (isRecovering)
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF00E5FF)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF00E5FF)),
                              ),
                              SizedBox(width: 8),
                              Text('Sincronizando transmissão ao vivo...',
                                  style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),

                    // 3. CONTROLES OSD COMPLETOS + GUIA EPG AO VIVO
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: !showOsd
                          ? const SizedBox.shrink()
                          : Container(
                              key: const ValueKey('osd_controls'),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black87,
                                    Colors.transparent,
                                    Colors.transparent,
                                    Colors.black87,
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // TOPO: VOLTAR AO CATÁLOGO (SEM PARAR O VÍDEO!), GAVETA, SLEEP E PIP
                                  Row(
                                    children: [
                                      TVIconButton(
                                        icon: Icons.arrow_back_ios_new_rounded,
                                        tooltip:
                                            'Voltar aos canais mantendo o vídeo',
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                      TVIconButton(
                                        icon: Icons.menu_open_rounded,
                                        color: const Color(0xFF00E5FF),
                                        tooltip: 'Gaveta Rápida de Canais',
                                        onPressed: () => setState(() =>
                                            showQuickChannelDrawer =
                                                !showQuickChannelDrawer),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              currentItem.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              currentItem.group,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF00E5FF)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_sleepMinutesRemaining != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.amber.withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Sleep: ${_sleepMinutesRemaining}m',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      TVIconButton(
                                        icon: Icons.bedtime_outlined,
                                        tooltip: 'Timer de Sono',
                                        onPressed: _openSleepTimerModal,
                                      ),
                                      const SizedBox(width: 4),
                                      TVFocusableItem(
                                        autoScroll: false,
                                        onSelect: () {
                                          setState(() => aspectMode =
                                              (aspectMode + 1) %
                                                  aspectLabels.length);
                                        },
                                        builder: (context, isFocused) =>
                                            Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isFocused
                                                ? const Color(0xFF00E5FF)
                                                : Colors.white12,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isFocused
                                                  ? Colors.white
                                                  : Colors.white24,
                                            ),
                                          ),
                                          child: Text(
                                            aspectLabels[aspectMode],
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isFocused
                                                  ? Colors.black
                                                  : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      TVIconButton(
                                        icon: Icons
                                            .picture_in_picture_alt_rounded,
                                        color: const Color(0xFF00E5FF),
                                        tooltip: 'Minimizar em PiP',
                                        onPressed: () {
                                          Navigator.pop(context);
                                          widget.onMinimizeToPip(currentItem);
                                        },
                                      ),
                                    ],
                                  ),

                                  // RODAPÉ: BARRA DE PROGRAMAÇÃO EPG + CONTROLES E SELETOR DE QUALIDADE
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10131D)
                                          .withOpacity(0.94),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // GUIA EPG (PARA CANAIS AO VIVO)
                                        if (!isVod && epg != null) ...[
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'AGORA',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  epg.nowTitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Flexible(
                                                child: Text(
                                                  'A Seguir: ${epg.nextTitle}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF00E5FF),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                        ],

                                        // BARRA DE TEMPO (PARA FILMES E SÉRIES)
                                        if (isVod && isReady)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8.0),
                                            child: Column(
                                              children: [
                                                VideoProgressIndicator(
                                                  ctrl,
                                                  allowScrubbing: true,
                                                  colors:
                                                      const VideoProgressColors(
                                                    playedColor:
                                                        Color(0xFF00E5FF),
                                                    bufferedColor:
                                                        Colors.white24,
                                                    backgroundColor:
                                                        Colors.white10,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      _formatDuration(ctrl
                                                          .value.position),
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Colors.white70),
                                                    ),
                                                    Text(
                                                      _formatDuration(ctrl
                                                          .value.duration),
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Colors.white70),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                        // BOTÕES DE CONTROLE E QUALIDADES
                                        Row(
                                          children: [
                                            TVIconButton(
                                              icon: Icons.skip_previous_rounded,
                                              onPressed: () => _stepChannel(-1),
                                            ),
                                            if (isVod)
                                              TVIconButton(
                                                icon: Icons.replay_10_rounded,
                                                onPressed: () =>
                                                    _engine.seekRelative(-10),
                                              ),
                                            TVFocusableItem(
                                              focusNode: _playPauseFocusNode,
                                              autofocus: true,
                                              autoScroll: false,
                                              onSelect: () {
                                                _engine.togglePlayPause();
                                                _resetOsdTimer();
                                              },
                                              builder: (context, isFocused) =>
                                                  AnimatedScale(
                                                scale: isFocused ? 1.15 : 1.0,
                                                duration: const Duration(
                                                    milliseconds: 120),
                                                child: Container(
                                                  margin: const EdgeInsets
                                                      .symmetric(horizontal: 4),
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: isFocused
                                                        ? const Color(
                                                                0xFF00E5FF)
                                                            .withOpacity(0.25)
                                                        : Colors.transparent,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: isFocused
                                                          ? const Color(
                                                              0xFF00E5FF)
                                                          : Colors.transparent,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    isReady &&
                                                            ctrl.value.isPlaying
                                                        ? Icons
                                                            .pause_circle_filled_rounded
                                                        : Icons
                                                            .play_circle_fill_rounded,
                                                    color:
                                                        const Color(0xFF00E5FF),
                                                    size: 34,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (isVod)
                                              TVIconButton(
                                                icon: Icons.forward_10_rounded,
                                                onPressed: () =>
                                                    _engine.seekRelative(10),
                                              ),
                                            TVIconButton(
                                              icon: Icons.skip_next_rounded,
                                              onPressed: () => _stepChannel(1),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Row(
                                                  children: qualities.map((q) {
                                                    final isCurrent =
                                                        q.id == currentItem.id;
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 6),
                                                      child: TVFocusableItem(
                                                        autoScroll: false,
                                                        onSelect: () =>
                                                            _switchStream(q),
                                                        builder: (context,
                                                                isFocused) =>
                                                            Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 5),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isCurrent
                                                                ? const Color(
                                                                    0xFF00E5FF)
                                                                : Colors
                                                                    .white12,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                            border: Border.all(
                                                              color: isFocused
                                                                  ? Colors.white
                                                                  : Colors
                                                                      .transparent,
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            q.qualityTag,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: isCurrent
                                                                  ? Colors.black
                                                                  : Colors
                                                                      .white,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    // 4. GAVETA TRANSPARENTE DE CANAIS (NAVEGAÇÃO SEM REINICIAR O VÍDEO ATUAL)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      top: 0,
                      bottom: 0,
                      left: showQuickChannelDrawer ? 0 : -290,
                      width: 280,
                      child: Container(
                        color: const Color(0xFF08090E).withOpacity(0.94),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isVod ? 'EPISÓDIOS / LISTA' : 'CANAIS',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00E5FF)),
                                  ),
                                  TVIconButton(
                                    icon: Icons.close,
                                    onPressed: () => setState(
                                        () => showQuickChannelDrawer = false),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: widget.playlist.length,
                                itemBuilder: (context, idx) {
                                  final ch = widget.playlist[idx];
                                  final selected = ch.id == currentItem.id;
                                  return TVFocusableItem(
                                    autofocus:
                                        selected && showQuickChannelDrawer,
                                    onSelect: () {
                                      setState(
                                          () => showQuickChannelDrawer = false);
                                      if (ch.id != currentItem.id) {
                                        _switchStream(ch);
                                      }
                                    },
                                    builder: (context, isFocused) => Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? const Color(0xFF00E5FF)
                                                .withOpacity(0.2)
                                            : isFocused
                                                ? Colors.white10
                                                : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isFocused
                                              ? const Color(0xFF00E5FF)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              ch.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ch.qualityTag,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF00E5FF),
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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
  }

  Widget _buildAspectVideo(VideoPlayerController ctrl) {
    if (aspectMode == 1) {
      return SizedBox.expand(child: VideoPlayer(ctrl));
    } else if (aspectMode == 2) {
      return AspectRatio(aspectRatio: 16 / 9, child: VideoPlayer(ctrl));
    } else if (aspectMode == 3) {
      return AspectRatio(aspectRatio: 4 / 3, child: VideoPlayer(ctrl));
    }
    return AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: VideoPlayer(ctrl),
    );
  }
}
