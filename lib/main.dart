import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PremiumIPTVApp());
}

class PremiumIPTVApp extends StatelessWidget {
  const PremiumIPTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNEX Vision',
      debugShowCheckedModeBanner: false,
      // Ativa o clique com o botão central/OK do controle remoto da TV Box
      shortcuts: <LogicalKeySet, Intent>{
        ...WidgetsApp.defaultShortcuts,
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF131620),
        ),
      ),
      home: const MainDashboard(),
    );
  }
}

class Channel {
  final String id;
  final String name;
  final String group;
  final String logo;
  final String url;

  Channel({
    required this.id,
    required this.name,
    required this.group,
    required this.logo,
    required this.url,
  });
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  String currentM3uUrl =
      'http://cdn4k.club/get.php?username=65pa7z&password=44k3io&type=m3u_plus&output=ts';

  List<Channel> allChannels = [];
  List<Channel> displayedChannels = [];
  List<String> categories = ['Todos', 'Favoritos'];
  Set<String> favoriteIds = {};

  String selectedCategory = 'Todos';
  String searchQuery = '';
  bool isLoading = true;
  String errorMessage = '';

  Channel? activeChannel;
  VideoPlayerController? _previewController;
  bool isPreviewInitialized = false;
  bool isPreviewError = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchPlaylist();
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchPlaylist() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final response = await http
          .get(Uri.parse(currentM3uUrl))
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final parsed = await compute(parseM3UContent, response.body);
        final groupSet = <String>{'Todos', 'Favoritos'};
        for (final ch in parsed) {
          if (ch.group.isNotEmpty) groupSet.add(ch.group);
        }

        setState(() {
          allChannels = parsed;
          categories = groupSet.toList();
          selectedCategory = 'Todos';
          applyFilters();
          isLoading = false;
        });

        if (parsed.isNotEmpty && activeChannel == null) {
          selectChannelForPreview(parsed.first, openFullOnMobile: false);
        }
      } else {
        setState(() {
          errorMessage =
              'Servidor respondeu com código ${response.statusCode}. Verifique a lista.';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage =
            'Não foi possível conectar ao servidor.\nVerifique sua internet ou o link da lista.';
        isLoading = false;
      });
    }
  }

  void applyFilters() {
    setState(() {
      displayedChannels = allChannels.where((ch) {
        final matchesCategory = selectedCategory == 'Todos'
            ? true
            : selectedCategory == 'Favoritos'
                ? favoriteIds.contains(ch.id)
                : ch.group == selectedCategory;

        final matchesSearch = searchQuery.isEmpty
            ? true
            : ch.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                ch.group.toLowerCase().contains(searchQuery.toLowerCase());

        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  void toggleFavorite(Channel channel) {
    setState(() {
      if (favoriteIds.contains(channel.id)) {
        favoriteIds.remove(channel.id);
      } else {
        favoriteIds.add(channel.id);
      }
      if (selectedCategory == 'Favoritos') {
        applyFilters();
      }
    });
  }

  Future<void> selectChannelForPreview(Channel channel,
      {bool openFullOnMobile = false}) async {
    final isSameChannel = activeChannel?.id == channel.id;

    if (isSameChannel && isPreviewInitialized) {
      openFullScreenPlayer(channel);
      return;
    }

    setState(() {
      activeChannel = channel;
      isPreviewInitialized = false;
      isPreviewError = false;
    });

    final oldController = _previewController;
    _previewController =
        VideoPlayerController.networkUrl(Uri.parse(channel.url));
    await oldController?.dispose();

    try {
      await _previewController!.initialize();
      if (!mounted) return;
      setState(() {
        isPreviewInitialized = true;
      });
      _previewController!.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isPreviewError = true;
      });
    }
  }

  void openFullScreenPlayer(Channel channel) {
    _previewController?.pause();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenPlayer(
          initialChannel: channel,
          playlist: displayedChannels.isNotEmpty ? displayedChannels : allChannels,
        ),
      ),
    ).then((_) {
      if (_previewController != null && isPreviewInitialized) {
        _previewController!.play();
      }
    });
  }

  void showUrlSettingsModal() {
    final controller = TextEditingController(text: currentM3uUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.settings_input_antenna, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text('Configurar Lista M3U'),
          ],
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: 'URL da Lista M3U Plus',
            filled: true,
            fillColor: const Color(0xFF090A0F),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                currentM3uUrl = controller.text.trim();
                Navigator.pop(context);
                fetchPlaylist();
              }
            },
            child: const Text('Salvar e Recarregar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTVLayout = screenWidth >= 800;

    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? _buildLoadingView()
            : errorMessage.isNotEmpty
                ? _buildErrorView()
                : isTVLayout
                    ? _buildTVInterface()
                    : _buildMobileInterface(),
      ),
    );
  }

  // ===========================================================================
  // INTERFACE DE TV / TV BOX (WIDESCREEN 3 PAINÉIS COM LIVE PREVIEW)
  // ===========================================================================
  Widget _buildTVInterface() {
    return Row(
      children: [
        // 1. MENU LATERAL DE CATEGORIAS
        Container(
          width: 240,
          decoration: const BoxDecoration(
            color: Color(0xFF0D0F17),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.black, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'UNEX VISION',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = cat == selectedCategory;
                    return TVFocusableItem(
                      onSelect: () {
                        selectedCategory = cat;
                        applyFilters();
                      },
                      builder: (context, isFocused) {
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: isSelected || isFocused
                                ? LinearGradient(
                                    colors: [
                                      const Color(0xFF00E5FF)
                                          .withOpacity(isFocused ? 0.35 : 0.18),
                                      const Color(0xFF2979FF).withOpacity(0.05),
                                    ],
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFocused
                                  ? const Color(0xFF00E5FF)
                                  : isSelected
                                      ? const Color(0xFF00E5FF).withOpacity(0.4)
                                      : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                cat == 'Favoritos'
                                    ? Icons.star_rounded
                                    : cat == 'Todos'
                                        ? Icons.grid_view_rounded
                                        : Icons.folder_open_rounded,
                                size: 18,
                                color: isSelected || isFocused
                                    ? const Color(0xFF00E5FF)
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  cat,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected || isFocused
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected || isFocused
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TVFocusableItem(
                  onSelect: showUrlSettingsModal,
                  builder: (context, isFocused) => Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: isFocused
                          ? Colors.white12
                          : const Color(0xFF151924),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isFocused
                              ? const Color(0xFF00E5FF)
                              : Colors.white10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings, size: 18, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('Trocar Lista', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. ÁREA CENTRAL: BUSCA + GRADE DE CANAIS
        Expanded(
          flex: 6,
          child: Column(
            children: [
              // Barra Superior de Pesquisa e Contagem
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF131620),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            searchQuery = val;
                            applyFilters();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Pesquisar canal ou categoria...',
                            hintStyle:
                                TextStyle(color: Colors.white38, fontSize: 14),
                            prefixIcon: Icon(Icons.search,
                                color: Color(0xFF00E5FF), size: 20),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131620),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${displayedChannels.length} canais',
                        style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white70),
                      onPressed: fetchPlaylist,
                      tooltip: 'Atualizar Lista',
                    ),
                  ],
                ),
              ),

              // Grade de Canais
              Expanded(
                child: displayedChannels.isEmpty
                    ? const Center(
                        child: Text('Nenhum canal encontrado.',
                            style: TextStyle(color: Colors.white54)))
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 92,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: displayedChannels.length,
                        itemBuilder: (context, index) {
                          final ch = displayedChannels[index];
                          final isPlaying = activeChannel?.id == ch.id;
                          final isFav = favoriteIds.contains(ch.id);

                          return TVFocusableItem(
                            onSelect: () => selectChannelForPreview(ch),
                            builder: (context, isFocused) {
                              return AnimatedScale(
                                scale: isFocused ? 1.04 : 1.0,
                                duration: const Duration(milliseconds: 140),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isPlaying
                                        ? const Color(0xFF192338)
                                        : const Color(0xFF131620),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isFocused
                                          ? const Color(0xFF00E5FF)
                                          : isPlaying
                                              ? const Color(0xFF2979FF)
                                              : Colors.white10,
                                      width: isFocused ? 2 : 1,
                                    ),
                                    boxShadow: isFocused
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF00E5FF)
                                                  .withOpacity(0.25),
                                              blurRadius: 12,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      _buildChannelLogo(ch.logo, size: 52),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              ch.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              ch.group,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => toggleFavorite(ch),
                                        child: Icon(
                                          isFav
                                              ? Icons.star_rounded
                                              : Icons.star_border_rounded,
                                          color: isFav
                                              ? Colors.amber
                                              : Colors.white24,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        // 3. PAINEL DIREITO: MINI PLAYER AO VIVO & DETALHES DO CANAL
        Container(
          width: 340,
          decoration: const BoxDecoration(
            color: Color(0xFF0D0F17),
            border: Border(left: BorderSide(color: Colors.white10)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.fiber_manual_record,
                      color: Colors.redAccent, size: 14),
                  SizedBox(width: 8),
                  Text(
                    'PRÉ-VISUALIZAÇÃO AO VIVO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Janela de Vídeo
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black,
                    child: _buildPreviewPlayerContent(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (activeChannel != null) ...[
                Row(
                  children: [
                    _buildChannelLogo(activeChannel!.logo, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeChannel!.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              activeChannel!.group,
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    onSelect: () => openFullScreenPlayer(activeChannel!),
                    builder: (context, isFocused) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fullscreen_rounded,
                              color: Colors.black, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'ASSISTIR EM TELA CHEIA',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TVFocusableItem(
                    onSelect: () => toggleFavorite(activeChannel!),
                    builder: (context, isFocused) {
                      final isFav = favoriteIds.contains(activeChannel!.id);
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151924),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF00E5FF)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: isFav ? Colors.amber : Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isFav
                                  ? 'Remover dos Favoritos'
                                  : 'Adicionar aos Favoritos',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const Spacer(),
              const Text(
                'Dica: Clique 1x no canal para pré-visualizar e 2x para abrir em tela cheia.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // INTERFACE DE CELULAR (PLAYER FIXO NO TOPO + CATEGORIAS EM CHIPS)
  // ===========================================================================
  Widget _buildMobileInterface() {
    return Column(
      children: [
        // Top Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.black, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'UNEX VISION',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 22),
                onPressed: showUrlSettingsModal,
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: fetchPlaylist,
              ),
            ],
          ),
        ),

        // Mini Player Fixo no Topo (Estilo YouTube)
        if (activeChannel != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.black,
                  child: _buildPreviewPlayerContent(),
                ),
                Positioned(
                  bottom: 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.circle,
                                color: Colors.redAccent, size: 8),
                            const SizedBox(width: 6),
                            Text(
                              activeChannel!.name,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => openFullScreenPlayer(activeChannel!),
                        icon: const Icon(Icons.fullscreen, size: 18),
                        label: const Text('Tela Cheia',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Barra de Busca Mobile
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF131620),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                searchQuery = val;
                applyFilters();
              },
              decoration: const InputDecoration(
                hintText: 'Buscar canais...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon:
                    Icon(Icons.search, color: Color(0xFF00E5FF), size: 19),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),

        // Chips Horizontais de Categorias
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = cat == selectedCategory;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) {
                    selectedCategory = cat;
                    applyFilters();
                  },
                  selectedColor: const Color(0xFF00E5FF),
                  backgroundColor: const Color(0xFF131620),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Lista de Canais Mobile
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            itemCount: displayedChannels.length,
            itemBuilder: (context, index) {
              final ch = displayedChannels[index];
              final isPlaying = activeChannel?.id == ch.id;
              final isFav = favoriteIds.contains(ch.id);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? const Color(0xFF182236)
                      : const Color(0xFF131620),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPlaying
                        ? const Color(0xFF00E5FF)
                        : Colors.white.withOpacity(0.05),
                  ),
                ),
                child: ListTile(
                  onTap: () => selectChannelForPreview(ch),
                  leading: _buildChannelLogo(ch.logo, size: 44),
                  title: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    ch.group,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.star_rounded : Icons.star_border_rounded,
                          color: isFav ? Colors.amber : Colors.white30,
                        ),
                        onPressed: () => toggleFavorite(ch),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_rounded,
                            color: Color(0xFF00E5FF)),
                        onPressed: () => openFullScreenPlayer(ch),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPlayerContent() {
    if (isPreviewError) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
            SizedBox(height: 8),
            Text('Sinal indisponível no momento',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
          ],
        ),
      );
    }
    if (!isPreviewInitialized || _previewController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
      );
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: _previewController!.value.size.width,
        height: _previewController!.value.size.height,
        child: VideoPlayer(_previewController!),
      ),
    );
  }

  Widget _buildChannelLogo(String url, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF090A0F),
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
                    const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
              )
            : const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF00E5FF)),
          SizedBox(height: 20),
          Text(
            'SINCRONIZANDO CANAIS AO VIVO...',
            style: TextStyle(
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Colors.redAccent, size: 54),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: fetchPlaylist,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Novamente'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: showUrlSettingsModal,
                  icon: const Icon(Icons.edit),
                  label: const Text('Alterar URL'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PLAYER EM TELA CHEIA COM OSD E TROCA RÁPIDA DE CANAL (ZAPPING)
// =============================================================================
class FullScreenPlayer extends StatefulWidget {
  final Channel initialChannel;
  final List<Channel> playlist;

  const FullScreenPlayer({
    super.key,
    required this.initialChannel,
    required this.playlist,
  });

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  late Channel currentChannel;
  VideoPlayerController? _controller;
  bool isInitialized = false;
  bool hasError = false;
  bool showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentChannel = widget.initialChannel;
    _startChannel(currentChannel);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _startChannel(Channel channel) async {
    setState(() {
      currentChannel = channel;
      isInitialized = false;
      hasError = false;
      showControls = true;
    });
    _resetHideTimer();

    final old = _controller;
    _controller = VideoPlayerController.networkUrl(Uri.parse(channel.url));
    await old?.dispose();

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => isInitialized = true);
      _controller!.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => hasError = true);
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => showControls = false);
    });
  }

  void _changeChannel(int delta) {
    if (widget.playlist.isEmpty) return;
    final idx = widget.playlist.indexWhere((c) => c.id == currentChannel.id);
    if (idx == -1) return;
    final nextIdx =
        (idx + delta + widget.playlist.length) % widget.playlist.length;
    _startChannel(widget.playlist[nextIdx]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            setState(() => showControls = true);
            _resetHideTimer();
            if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.channelUp) {
              _changeChannel(-1);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.channelDown) {
              _changeChannel(1);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => showControls = !showControls);
            if (showControls) _resetHideTimer();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: hasError
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          const Text('Falha ao abrir transmissão.'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _startChannel(currentChannel),
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      )
                    : isInitialized && _controller != null
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          )
                        : const CircularProgressIndicator(
                            color: Color(0xFF00E5FF)),
              ),

              // Overlay de Controles Moderno (OSD)
              if (showControls)
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Topo: Botão Voltar + Status Ao Vivo
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              currentChannel.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.circle,
                                    color: Colors.white, size: 8),
                                SizedBox(width: 6),
                                Text('AO VIVO',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Rodapé: Card de Informação e Botões de Zapping
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131620).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.live_tv_rounded,
                                color: Color(0xFF00E5FF), size: 32),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentChannel.name,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    currentChannel.group,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Canal Anterior',
                              icon: const Icon(Icons.skip_previous_rounded,
                                  size: 30),
                              onPressed: () => _changeChannel(-1),
                            ),
                            IconButton(
                              tooltip: 'Pausar / Reproduzir',
                              icon: Icon(
                                _controller != null &&
                                        _controller!.value.isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: const Color(0xFF00E5FF),
                                size: 38,
                              ),
                              onPressed: () {
                                if (_controller == null) return;
                                setState(() {
                                  _controller!.value.isPlaying
                                      ? _controller!.pause()
                                      : _controller!.play();
                                });
                              },
                            ),
                            IconButton(
                              tooltip: 'Próximo Canal',
                              icon:
                                  const Icon(Icons.skip_next_rounded, size: 30),
                              onPressed: () => _changeChannel(1),
                            ),
                          ],
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
}

// =============================================================================
// WIDGET ADAPTATIVO PARA NAVEGAÇÃO POR CONTROLE REMOTO (D-PAD) E TOQUE
// =============================================================================
class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;

  const TVFocusableItem({
    super.key,
    required this.onSelect,
    required this.builder,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (focused) => setState(() => _isFocused = focused),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: widget.builder(context, _isFocused),
      ),
    );
  }
}

// =============================================================================
// PARSER M3U EM SEGUNDO PLANO (ALTA PERFORMANCE)
// =============================================================================
List<Channel> parseM3UContent(String raw) {
  final List<Channel> result = [];
  final lines = const LineSplitter().convert(raw);

  String name = '';
  String group = 'Canais';
  String logo = '';
  int indexCounter = 0;

  final groupRegex = RegExp(r'group-title="([^"]*)"', caseSensitive: false);
  final logoRegex = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);

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
        name = 'Canal ${indexCounter + 1}';
      }
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      indexCounter++;
      result.add(
        Channel(
          id: '${indexCounter}_${trimmed.hashCode}',
          name: name.isNotEmpty ? name : 'Canal $indexCounter',
          group: group,
          logo: logo,
          url: trimmed,
        ),
      );
      name = '';
      group = 'Geral';
      logo = '';
    }
  }
  return result;
}
