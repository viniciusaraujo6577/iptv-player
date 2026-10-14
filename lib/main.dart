import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  runApp(const IPTVApp());
}

class IPTVApp extends StatelessWidget {
  const IPTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101216),
        primaryColor: Colors.blueAccent,
      ),
      home: const HomeScreen(),
    );
  }
}

class Channel {
  final String name;
  final String group;
  final String logo;
  final String url;

  Channel({
    required this.name,
    required this.group,
    required this.logo,
    required this.url,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Sua lista M3U padrão
  final String defaultUrl =
      'http://cdn4k.club/get.php?username=65pa7z&password=44k3io&type=m3u_plus&output=ts';

  List<Channel> channels = [];
  List<Channel> filteredChannels = [];
  bool isLoading = true;
  String errorMessage = '';
  String selectedGroup = 'Todos';
  List<String> groups = ['Todos'];

  @override
  void initState() {
    super.initState();
    loadM3uData();
  }

  Future<void> loadM3uData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });

      final response = await http.get(Uri.parse(defaultUrl));

      if (response.statusCode == 200) {
        final parsed = await compute(parseM3U, response.body);
        final groupSet = <String>{'Todos'};

        for (var c in parsed) {
          if (c.group.isNotEmpty) groupSet.add(c.group);
        }

        setState(() {
          channels = parsed;
          filteredChannels = parsed;
          groups = groupSet.toList();
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Erro ao carregar lista (Código: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erro de conexão: $e';
        isLoading = false;
      });
    }
  }

  void filterByGroup(String group) {
    setState(() {
      selectedGroup = group;
      if (group == 'Todos') {
        filteredChannels = channels;
      } else {
        filteredChannels = channels.where((c) => c.group == group).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTVorTablet = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IPTV Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadM3uData,
          )
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Carregando lista de canais...'),
                ],
              ),
            )
          : errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(errorMessage, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: loadM3uData,
                        child: const Text('Tentar Novamente'),
                      )
                    ],
                  ),
                )
              : isTVorTablet
                  ? Row(
                      children: [
                        // Coluna de Categorias
                        SizedBox(
                          width: 240,
                          child: ListView.builder(
                            itemCount: groups.length,
                            itemBuilder: (context, index) {
                              final group = groups[index];
                              final isSelected = group == selectedGroup;
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: Colors.blueAccent.withOpacity(0.3),
                                title: Text(group, maxLines: 1),
                                onTap: () => filterByGroup(group),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1, color: Colors.white24),
                        // Grid de Canais para TV
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 3 / 1,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: filteredChannels.length,
                            itemBuilder: (context, index) {
                              return ChannelTile(
                                channel: filteredChannels[index],
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: filteredChannels.length,
                      itemBuilder: (context, index) {
                        return ChannelTile(channel: filteredChannels[index]);
                      },
                    ),
    );
  }
}

// Tile interativo compatível com Toque e Controle Remoto
class ChannelTile extends StatefulWidget {
  final Channel channel;

  const ChannelTile({super.key, required this.channel});

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focus) => setState(() => isFocused = focus),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                title: widget.channel.name,
                streamUrl: widget.channel.url,
              ),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isFocused ? Colors.blueAccent.withOpacity(0.4) : const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFocused ? Colors.blueAccent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.tv, color: Colors.white70, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.channel.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tela de Reprodução
class PlayerScreen extends StatefulWidget {
  final String title;
  final String streamUrl;

  const PlayerScreen({super.key, required this.title, required this.streamUrl});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
      await _videoController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        isLive: true,
        aspectRatio: _videoController.value.aspectRatio,
      );
      setState(() {});
    } catch (e) {
      setState(() => hasError = true);
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: hasError
            ? const Text('Erro ao reproduzir canal.', style: TextStyle(color: Colors.redAccent))
            : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(),
      ),
    );
  }
}

// Parser M3U isolado para não travar a tela
List<Channel> parseM3U(String content) {
  final List<Channel> list = [];
  final lines = const LineSplitter().convert(content);

  String name = '';
  String group = 'Geral';
  String logo = '';

  final regExp = RegExp(r'#EXTINF:.*?(?:group-title="([^"]*)")?.*?(?:tvg-logo="([^"]*)")?,(.*)');

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#EXTINF:')) {
      final match = regExp.firstMatch(trimmed);
      if (match != null) {
        group = match.group(1) ?? 'Geral';
        logo = match.group(2) ?? '';
        name = match.group(3)?.trim() ?? 'Canal';
      }
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      list.add(Channel(name: name, group: group, logo: logo, url: trimmed));
      name = '';
      group = 'Geral';
      logo = '';
    }
  }
  return list;
}
