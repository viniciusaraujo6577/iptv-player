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

  @override
  Widget build(BuildContext context) {
    final qualities = _getQualities();
    final isVod = currentItem.type != ContentType.live;

    return PopScope(
      canPop: !showQuickChannelDrawer,
      onPopInvoked: (didPop) {
        if (!didPop && showQuickChannelDrawer) {
          setState(() => showQuickChannelDrawer = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (!showQuickChannelDrawer && !showOsd) {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.channelUp) {
                  _stepChannel(-1);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.channelDown) {
                  _stepChannel(1);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                    !isVod) {
                  setState(() => showQuickChannelDrawer = true);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  setState(() => showOsd = true);
                  _resetOsdTimer();
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
              setState(() {
                if (showQuickChannelDrawer) {
                  showQuickChannelDrawer = false;
                } else {
                  showOsd = !showOsd;
                }
              });
              if (showOsd) _resetOsdTimer();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
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
                if (showOsd)
                  Container(
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        fontSize: 11, color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                            TVFocusableItem(
                              autoScroll: false,
                              onSelect: () {
                                setState(() => aspectMode =
                                    (aspectMode + 1) % aspectLabels.length);
                              },
                              builder: (context, isFocused) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isFocused
                                        ? const Color(0xFF00E5FF)
                                        : Colors.white24,
                                  ),
                                ),
                                child: Text(aspectLabels[aspectMode],
                                    style: const TextStyle(fontSize: 11)),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12151F).withOpacity(0.92),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isVod && isInitialized && _controller != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: VideoProgressIndicator(
                                    _controller!,
                                    allowScrubbing: true,
                                    colors: const VideoProgressColors(
                                      playedColor: Color(0xFF00E5FF),
                                      bufferedColor: Colors.white24,
                                      backgroundColor: Colors.white10,
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  TVIconButton(
                                    icon: Icons.skip_previous_rounded,
                                    onPressed: () => _stepChannel(-1),
                                  ),
                                  TVIconButton(
                                    icon: _controller != null &&
                                            _controller!.value.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_fill_rounded,
                                    color: const Color(0xFF00E5FF),
                                    size: 32,
                                    onPressed: () {
                                      if (_controller == null) return;
                                      setState(() {
                                        _controller!.value.isPlaying
                                            ? _controller!.pause()
                                            : _controller!.play();
                                      });
                                    },
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
                                            padding: const EdgeInsets.only(
                                                right: 6),
                                            child: TVFocusableItem(
                                              autoScroll: false,
                                              onSelect: () =>
                                                  _initSmartStream(q),
                                              builder: (context, isFocused) =>
                                                  Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isCurrent
                                                      ? const Color(0xFF00E5FF)
                                                      : Colors.white12,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isFocused
                                                        ? Colors.white
                                                        : Colors.transparent,
                                                  ),
                                                ),
                                                child: Text(
                                                  q.qualityTag,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
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
                if (showQuickChannelDrawer)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 270,
                      color: const Color(0xFF08090E).withOpacity(0.95),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'LISTA RÁPIDA',
                                  style: TextStyle(
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
                                  autofocus: selected,
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
