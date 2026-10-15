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
  final void Function(StreamItem item) onMinimizeToPip;

  const SmartAdaptivePlayerScreen({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.liveChannelsPool,
    required this.measuredSpeedMbps,
    required this.onMinimizeToPip,
  });

  @override
  State<SmartAdaptivePlayerScreen> createState() =>
      _SmartAdaptivePlayerScreenState();
}

class _SmartAdaptivePlayerScreenState extends State<SmartAdaptivePlayerScreen> {
  late StreamItem currentItem;
  VideoPlayerController? _controller;
  bool isInitialized = false;
  bool hasError = false;
  bool showOsd = true;
  bool showQuickChannelDrawer = false;

  int aspectMode = 0;
  final List<String> aspectLabels = ['Original', 'Esticar', '16:9', '4:3'];

  Timer? _hideTimer;
  Timer? _antiFreezeWatchdog;
  Duration _lastPosition = Duration.zero;
  int _stallCounter = 0;
  int _autoRecoveryAttempts = 0;
  bool _isRecoveringStream = false;
  bool _usingHlsFallback = false;

  final FocusNode _playPauseFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentItem = widget.initialItem;
    _initSmartStream(currentItem);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _antiFreezeWatchdog?.cancel();
    _playPauseFocusNode.dispose();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _initSmartStream(StreamItem item,
      {bool tryHlsFallback = false}) async {
    setState(() {
      currentItem = item;
      isInitialized = false;
      hasError = false;
      showOsd = true;
      _usingHlsFallback = tryHlsFallback;
    });
    _resetOsdTimer();

    String targetUrl = item.url;
    if (tryHlsFallback && targetUrl.endsWith('.ts')) {
      targetUrl = '${targetUrl.substring(0, targetUrl.length - 3)}.m3u8';
    }

    final old = _controller;
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(targetUrl),
      httpHeaders: kIptvHeaders,
    );
    await old?.dispose();

    try {
      await _controller!.initialize();
      if (!mounted) return;

      if (widget.measuredSpeedMbps < 8.0) {
        await Future.delayed(const Duration(milliseconds: 900));
      } else if (widget.measuredSpeedMbps < 15.0) {
        await Future.delayed(const Duration(milliseconds: 400));
      }

      setState(() {
        isInitialized = true;
        _isRecoveringStream = false;
      });
      _controller!.play();
      _startAntiFreezeWatchdog();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && showOsd) {
          _playPauseFocusNode.requestFocus();
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (_autoRecoveryAttempts < 2) {
        _autoRecoveryAttempts++;
        _initSmartStream(item, tryHlsFallback: !tryHlsFallback);
      } else {
        setState(() => hasError = true);
      }
    }
  }

  void _startAntiFreezeWatchdog() {
    _antiFreezeWatchdog?.cancel();
    _stallCounter = 0;

    _antiFreezeWatchdog =
        Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _controller == null || !isInitialized) return;
      final value = _controller!.value;

      if (value.isPlaying) {
        if (value.position == _lastPosition && value.isBuffering) {
          _stallCounter++;
          if (_stallCounter >= 3 && !_isRecoveringStream) {
            setState(() => _isRecoveringStream = true);
            await _controller!.pause();
            await Future.delayed(const Duration(milliseconds: 1200));
            if (mounted && _controller != null) {
              await _controller!.play();
              setState(() => _isRecoveringStream = false);
            }
            _stallCounter = 0;
          }
        } else {
          _stallCounter = 0;
        }
        _lastPosition = value.position;
      }
    });
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

  void _togglePlayPause() {
    if (_controller == null || !isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
    _resetOsdTimer();
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !isInitialized) return;
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    final target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) {
      _controller!.seekTo(Duration.zero);
    } else if (dur > Duration.zero && target > dur) {
      _controller!.seekTo(dur);
    } else {
      _controller!.seekTo(target);
    }
    _showOsdAndFocus();
  }

  void _stepChannel(int delta) {
    if (widget.playlist.isEmpty) return;
    final idx = widget.playlist.indexWhere((i) => i.id == currentItem.id);
    if (idx == -1) return;
    final next =
        (idx + delta + widget.playlist.length) % widget.playlist.length;
    _autoRecoveryAttempts = 0;
    _initSmartStream(widget.playlist[next]);
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

  @override
  Widget build(BuildContext context) {
    final qualities = _getQualities();
    final isVod = currentItem.type != ContentType.live;

    return PopScope(
      // Se a gaveta de canais ou os controles OSD estiverem abertos, o botão Voltar fecha eles primeiro
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

              // Teclas diretas de mídia do controle remoto da TV
              if (key == LogicalKeyboardKey.mediaPlayPause ||
                  key == LogicalKeyboardKey.mediaPlay ||
                  key == LogicalKeyboardKey.mediaPause) {
                _togglePlayPause();
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

              // Quando o menu OSD e a lista lateral estão ocultos:
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
                    _seekRelative(-10);
                  } else {
                    setState(() => showQuickChannelDrawer = true);
                  }
                  return KeyEventResult.handled;
                } else if (key == LogicalKeyboardKey.arrowRight) {
                  if (isVod) {
                    _seekRelative(10);
                  } else {
                    _showOsdAndFocus();
                  }
                  return KeyEventResult.handled;
                }
              } else {
                // Mantém o OSD aceso enquanto o usuário navega pelos botões com as setas
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
                // 1. VÍDEO PRINCIPAL
                Center(
                  child: hasError
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.wifi_tethering_error_rounded,
                                color: Colors.redAccent, size: 44),
                            const SizedBox(height: 12),
                            const Text('Transmissão indisponível no momento.'),
                            const SizedBox(height: 12),
                            TVFocusableItem(
                              autofocus: true,
                              autoScroll: false,
                              onSelect: () {
                                _autoRecoveryAttempts = 0;
                                _initSmartStream(currentItem,
                                    tryHlsFallback: !_usingHlsFallback);
                              },
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
                                  'Reconectar',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        )
                      : isInitialized && _controller != null
                          ? _buildAspectVideo()
                          : const CircularProgressIndicator(
                              color: Color(0xFF00E5FF)),
                ),

                // 2. INDICADOR ANTI-TRAVAMENTO
                if (_isRecoveringStream)
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
                          Text('Ajustando buffer...',
                              style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),

                // 3. CONTROLES OSD ANIMADOS
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // BARRA SUPERIOR DO PLAYER
                              Row(
                                children: [
                                  TVIconButton(
                                    icon: Icons.arrow_back_ios_new_rounded,
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  TVIconButton(
                                    icon: Icons.menu_open_rounded,
                                    color: const Color(0xFF00E5FF),
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
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          currentItem.group,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white60),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TVFocusableItem(
                                    autoScroll: false,
                                    onSelect: () {
                                      setState(() => aspectMode =
                                          (aspectMode + 1) %
                                              aspectLabels.length);
                                    },
                                    builder: (context, isFocused) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isFocused
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white12,
                                        borderRadius: BorderRadius.circular(8),
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
                                    icon: Icons.picture_in_picture_alt_rounded,
                                    color: const Color(0xFF00E5FF),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onMinimizeToPip(currentItem);
                                    },
                                  ),
                                ],
                              ),

                              // BARRA INFERIOR DO PLAYER
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF12151F).withOpacity(0.94),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isVod &&
                                        isInitialized &&
                                        _controller != null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: Column(
                                          children: [
                                            VideoProgressIndicator(
                                              _controller!,
                                              allowScrubbing: true,
                                              colors:
                                                  const VideoProgressColors(
                                                playedColor: Color(0xFF00E5FF),
                                                bufferedColor: Colors.white24,
                                                backgroundColor: Colors.white10,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  _formatDuration(_controller!
                                                      .value.position),
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white70),
                                                ),
                                                Text(
                                                  _formatDuration(_controller!
                                                      .value.duration),
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white70),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        TVIconButton(
                                          icon: Icons.skip_previous_rounded,
                                          onPressed: () => _stepChannel(-1),
                                        ),
                                        if (isVod)
                                          TVIconButton(
                                            icon: Icons.replay_10_rounded,
                                            onPressed: () => _seekRelative(-10),
                                          ),
                                        TVFocusableItem(
                                          focusNode: _playPauseFocusNode,
                                          autofocus: true,
                                          autoScroll: false,
                                          onSelect: _togglePlayPause,
                                          builder: (context, isFocused) =>
                                              AnimatedScale(
                                            scale: isFocused ? 1.15 : 1.0,
                                            duration: const Duration(
                                                milliseconds: 120),
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: isFocused
                                                    ? const Color(0xFF00E5FF)
                                                        .withOpacity(0.25)
                                                    : Colors.transparent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isFocused
                                                      ? const Color(0xFF00E5FF)
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Icon(
                                                _controller != null &&
                                                        _controller!
                                                            .value.isPlaying
                                                    ? Icons
                                                        .pause_circle_filled_rounded
                                                    : Icons
                                                        .play_circle_fill_rounded,
                                                color: const Color(0xFF00E5FF),
                                                size: 34,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (isVod)
                                          TVIconButton(
                                            icon: Icons.forward_10_rounded,
                                            onPressed: () => _seekRelative(10),
                                          ),
                                        TVIconButton(
                                          icon: Icons.skip_next_rounded,
                                          onPressed: () => _stepChannel(1),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
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
                                                        _initSmartStream(q),
                                                    builder:
                                                        (context, isFocused) =>
                                                            Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: isCurrent
                                                            ? const Color(
                                                                0xFF00E5FF)
                                                            : Colors.white12,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
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
                                                              FontWeight.bold,
                                                          color: isCurrent
                                                              ? Colors.black
                                                              : Colors.white,
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

                // 4. GAVETA RÁPIDA DE CANAIS / EPISÓDIOS NA TELA CHEIA
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  bottom: 0,
                  left: showQuickChannelDrawer ? 0 : -290,
                  width: 280,
                  child: Container(
                    color: const Color(0xFF08090E).withOpacity(0.96),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isVod ? 'EPISÓDIOS / LISTA' : 'LISTA RÁPIDA',
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
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: widget.playlist.length,
                            itemBuilder: (context, idx) {
                              final ch = widget.playlist[idx];
                              final selected = ch.id == currentItem.id;
                              return TVFocusableItem(
                                autofocus: selected && showQuickChannelDrawer,
                                onSelect: () {
                                  _initSmartStream(ch);
                                  setState(
                                      () => showQuickChannelDrawer = false);
                                },
                                builder: (context, isFocused) => Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 2),
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
                                          style: const TextStyle(fontSize: 12),
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
  }

  Widget _buildAspectVideo() {
    if (aspectMode == 1) {
      return SizedBox.expand(child: VideoPlayer(_controller!));
    } else if (aspectMode == 2) {
      return AspectRatio(aspectRatio: 16 / 9, child: VideoPlayer(_controller!));
    } else if (aspectMode == 3) {
      return AspectRatio(aspectRatio: 4 / 3, child: VideoPlayer(_controller!));
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}
