import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  runApp(const UnexVisionApp());
}

class UnexVisionApp extends StatelessWidget {
  const UnexVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNEX Vision',
      debugShowCheckedModeBanner: false,
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08090E),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF12151F),
        ),
      ),
      home: const LoginGatewayScreen(),
    );
  }
}

// =============================================================================
// MODELOS DE DADOS E CLASSIFICADOR DE CONTEÚDO / QUALIDADE
// =============================================================================
enum ContentType { live, movie, series }

class StreamItem {
  final String id;
  final String name;
  final String cleanName; // Nome sem tags SD/HD/FHD/4K para agrupar qualidades
  final String qualityTag; // SD, HD, FHD, 4K ou AUTO
  final String group;
  final String logo;
  final String url;
  final ContentType type;
  final bool isAdult;

  StreamItem({
    required this.id,
    required this.name,
    required this.cleanName,
    required this.qualityTag,
    required this.group,
    required this.logo,
    required this.url,
    required this.type,
    required this.isAdult,
  });
}

// =============================================================================
// TELA 1: LOGIN INTELIGENTE (DNS / URL + USUÁRIO + SENHA)
// =============================================================================
class LoginGatewayScreen extends StatefulWidget {
  const LoginGatewayScreen({super.key});

  @override
  State<LoginGatewayScreen> createState() => _LoginGatewayScreenState();
}

class _LoginGatewayScreenState extends State<LoginGatewayScreen> {
  final TextEditingController _dnsController =
      TextEditingController(text: 'http://cdn4k.club');
  final TextEditingController _userController =
      TextEditingController(text: '65pa7z');
  final TextEditingController _passController =
      TextEditingController(text: '44k3io');

  bool _obscurePass = true;
  bool _autoConnect = true;

  @override
  void initState() {
    super.initState();
    // Entra direto se os dados padrão estiverem preenchidos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoConnect &&
          _dnsController.text.isNotEmpty &&
          _userController.text.isNotEmpty) {
        _connectToServer();
      }
    });
  }

  void _connectToServer() {
    String dns = _dnsController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (dns.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha a URL/DNS, Usuário e Senha.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!dns.startsWith('http://') && !dns.startsWith('https://')) {
      dns = 'http://$dns';
    }
    if (dns.endsWith('/')) {
      dns = dns.substring(0, dns.length - 1);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainDashboard(
          serverDns: dns,
          username: user,
          password: pass,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [Color(0xFF132238), Color(0xFF08090E)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF12151F).withOpacity(0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.live_tv_rounded,
                          color: Colors.black, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'UNEX VISION',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Conecte sua lista via DNS, Usuário e Senha',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 28),
                    _buildInput(
                      controller: _dnsController,
                      label: 'URL / DNS do Servidor',
                      hint: 'Ex: http://cdn4k.club',
                      icon: Icons.dns_rounded,
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _userController,
                      label: 'Usuário',
                      hint: 'Digite seu usuário',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passController,
                      obscureText: _obscurePass,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outline_rounded,
                            color: Color(0xFF00E5FF)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF08090E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: TVFocusableItem(
                        onSelect: _connectToServer,
                        builder: (context, isFocused) => Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  isFocused ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'ENTRAR E CARREGAR LISTA',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF00E5FF)),
        filled: true,
        fillColor: const Color(0xFF08090E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// =============================================================================
// TELA 2: DASHBOARD PRINCIPAL ADAPTATIVO (TV WIDESCREEN + MOBILE)
// =============================================================================
class MainDashboard extends StatefulWidget {
  final String serverDns;
  final String username;
  final String password;

  const MainDashboard({
    super.key,
    required this.serverDns,
    required this.username,
    required this.password,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  // Listas e Contadores
  List<StreamItem> allItems = [];
  List<StreamItem> filteredItems = [];
  Map<String, int> categoryCounts = {};
  List<String> currentCategories = ['Todos', 'Favoritos', 'Recentes'];

  int totalLiveCount = 0;
  int totalMoviesCount = 0;
  int totalSeriesCount = 0;

  // Estados de Filtro
  ContentType? activeContentType; // null = Todos os tipos
  String selectedCategory = 'Todos';
  String searchQuery = '';

  // Favoritos, Histórico e Controle Parental
  final Set<String> favoriteIds = {};
  final List<StreamItem> recentItems = [];
  String parentalPin = '0000';
  bool adultUnlocked = false;

  // Status da Conta e Rede
  String accountStatus = 'Ativo';
  String accountExpDate = '';
  double lastMeasuredSpeedMbps = 18.5; // Estimativa inicial para o Anti-Travamento

  bool isLoading = true;
  String errorMessage = '';

  // Mini Player / PiP Interno
  StreamItem? activeItem;
  VideoPlayerController? _previewController;
  bool isPreviewReady = false;
  bool isPreviewError = false;
  bool isMiniPipFloating = false;

  // Sleep Timer
  Timer? _sleepTimer;
  int? _sleepMinutesRemaining;

  final TextEditingController _searchController = TextEditingController();

  String get m3uUrl =>
      '${widget.serverDns}/get.php?username=${widget.username}&password=${widget.password}&type=m3u_plus&output=ts';

  @override
  void initState() {
    super.initState();
    _loadAccountInfoAndPlaylist();
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _searchController.dispose();
    _sleepTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAccountInfoAndPlaylist() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    // 1. Consulta opcional da API Xtream para pegar data de expiração da conta
    _fetchXtreamAccountStatus();

    // 2. Baixa e mede a taxa de transferência para calibrar o Anti-Travamento
    try {
      final stopwatch = Stopwatch()..start();
      final response =
          await http.get(Uri.parse(m3uUrl)).timeout(const Duration(seconds: 30));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes.length;
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        if (seconds > 0.1 && bytes > 10000) {
          lastMeasuredSpeedMbps = ((bytes * 8) / (seconds * 1000000)).clamp(1.0, 300.0);
        }

        final parsed = await compute(parseM3UAdvanced, response.body);

        int live = 0;
        int movies = 0;
        int series = 0;
        for (final item in parsed) {
          if (item.type == ContentType.live) live++;
          if (item.type == ContentType.movie) movies++;
          if (item.type == ContentType.series) series++;
        }

        if (!mounted) return;
        setState(() {
          allItems = parsed;
          totalLiveCount = live;
          totalMoviesCount = movies;
          totalSeriesCount = series;
          _rebuildCategoriesAndFilter();
          isLoading = false;
        });

        if (parsed.isNotEmpty && activeItem == null) {
          _startPreview(parsed.first);
        }
      } else {
        setState(() {
          errorMessage =
              'Servidor recusou a conexão (Código ${response.statusCode}). Verifique usuário e senha.';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage =
            'Falha ao conectar em ${widget.serverDns}.\nVerifique o DNS, sua internet ou os dados de acesso.';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchXtreamAccountStatus() async {
    try {
      final apiUrl =
          '${widget.serverDns}/player_api.php?username=${widget.username}&password=${widget.password}';
      final res =
          await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final userInfo = data['user_info'];
        if (userInfo != null) {
          final status = userInfo['status']?.toString() ?? 'Active';
          final exp = userInfo['exp_date']?.toString();
          String formattedExp = 'Ilimitado';
          if (exp != null && exp != 'null' && int.tryParse(exp) != null) {
            final dt =
                DateTime.fromMillisecondsSinceEpoch(int.parse(exp) * 1000);
            formattedExp =
                '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
          }
          if (mounted) {
            setState(() {
              accountStatus = status == 'Active' ? 'Ativo' : status;
              accountExpDate = formattedExp;
            });
          }
        }
      }
    } catch (_) {}
  }

  void _rebuildCategoriesAndFilter() {
    // Filtra pelo tipo principal (Todos, Ao Vivo, Filmes, Séries)
    final baseList = activeContentType == null
        ? allItems
        : allItems.where((i) => i.type == activeContentType).toList();

    final Map<String, int> counts = {
      'Todos': baseList.length,
      'Favoritos': baseList.where((i) => favoriteIds.contains(i.id)).length,
      'Recentes': recentItems
          .where((i) =>
              activeContentType == null || i.type == activeContentType)
          .length,
    };

    for (final item in baseList) {
      counts[item.group] = (counts[item.group] ?? 0) + 1;
    }

    final cats = <String>['Todos', 'Favoritos', 'Recentes'];
    for (final key in counts.keys) {
      if (!cats.contains(key)) cats.add(key);
    }

    if (!cats.contains(selectedCategory)) {
      selectedCategory = 'Todos';
    }

    categoryCounts = counts;
    currentCategories = cats;
    _applyItemsFilter(baseList);
  }

  void _applyItemsFilter([List<StreamItem>? sourceList]) {
    final baseList = sourceList ??
        (activeContentType == null
            ? allItems
            : allItems.where((i) => i.type == activeContentType).toList());

    List<StreamItem> result;
    if (selectedCategory == 'Todos') {
      result = baseList;
    } else if (selectedCategory == 'Favoritos') {
      result = baseList.where((i) => favoriteIds.contains(i.id)).toList();
    } else if (selectedCategory == 'Recentes') {
      result = recentItems
          .where(
              (i) => activeContentType == null || i.type == activeContentType)
          .toList();
    } else {
      result = baseList.where((i) => i.group == selectedCategory).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((i) =>
              i.name.toLowerCase().contains(q) ||
              i.group.toLowerCase().contains(q))
          .toList();
    }

    setState(() {
      filteredItems = result;
    });
  }

  void _onCategoryTap(String category) {
    final isAdultCat = category.toLowerCase().contains('adult') ||
        category.toLowerCase().contains('xxx') ||
        category.toLowerCase().contains('+18');

    if (isAdultCat && !adultUnlocked) {
      _promptParentalPin(() {
        setState(() {
          adultUnlocked = true;
          selectedCategory = category;
          _applyItemsFilter();
        });
      });
      return;
    }

    setState(() {
      selectedCategory = category;
      _applyItemsFilter();
    });
  }

  void _promptParentalPin(VoidCallback onSuccess) {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.amber),
            SizedBox(width: 10),
            Text('Controle Parental'),
          ],
        ),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'Digite o PIN (Padrão: 0000)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinCtrl.text == parentalPin) {
                Navigator.pop(context);
                onSuccess();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN incorreto!'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
  }

  void _addToRecents(StreamItem item) {
    recentItems.removeWhere((r) => r.id == item.id);
    recentItems.insert(0, item);
    if (recentItems.length > 30) {
      recentItems.removeLast();
    }
    categoryCounts['Recentes'] = recentItems.length;
  }

  void _toggleFavorite(StreamItem item) {
    setState(() {
      if (favoriteIds.contains(item.id)) {
        favoriteIds.remove(item.id);
      } else {
        favoriteIds.add(item.id);
      }
      _rebuildCategoriesAndFilter();
    });
  }

  // Busca todas as qualidades disponíveis (SD, HD, FHD, 4K) do mesmo canal
  List<StreamItem> _findQualityVariants(StreamItem item) {
    final variants = allItems
        .where((i) =>
            i.type == item.type &&
            i.cleanName.toLowerCase() == item.cleanName.toLowerCase())
        .toList();
    return variants.isEmpty ? [item] : variants;
  }

  Future<void> _startPreview(StreamItem item) async {
    if (item.isAdult && !adultUnlocked) {
      _promptParentalPin(() {
        adultUnlocked = true;
        _startPreview(item);
      });
      return;
    }

    _addToRecents(item);

    if (activeItem?.id == item.id && isPreviewReady) {
      _openFullScreen(item);
      return;
    }

    setState(() {
      activeItem = item;
      isPreviewReady = false;
      isPreviewError = false;
    });

    final old = _previewController;
    _previewController = VideoPlayerController.networkUrl(Uri.parse(item.url));
    await old?.dispose();

    try {
      await _previewController!.initialize();
      if (!mounted) return;
      setState(() => isPreviewReady = true);
      _previewController!.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => isPreviewError = true);
    }
  }

  void _openFullScreen(StreamItem item) {
    _addToRecents(item);
    _previewController?.pause();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartAdaptivePlayerScreen(
          initialItem: item,
          playlist: filteredItems.isNotEmpty ? filteredItems : allItems,
          allItems: allItems,
          measuredSpeedMbps: lastMeasuredSpeedMbps,
          onMinimizeToPip: (playingItem) {
            setState(() {
              isMiniPipFloating = true;
            });
            _startPreview(playingItem);
          },
        ),
      ),
    ).then((_) {
      if (_previewController != null && isPreviewReady && !isMiniPipFloating) {
        _previewController!.play();
      }
    });
  }

  // ===========================================================================
  // MODAL DISCRETO DE TESTE DE VELOCIDADE DA INTERNET
  // ===========================================================================
  void _showSpeedTestModal() {
    showDialog(
      context: context,
      builder: (_) => SpeedTestDialog(
        testUrl: m3uUrl,
        onSpeedMeasured: (mbps) {
          setState(() => lastMeasuredSpeedMbps = mbps);
        },
      ),
    );
  }

  // ===========================================================================
  // SLEEP TIMER (DESLIGAMENTO AUTOMÁTICO)
  // ===========================================================================
  void _showSleepTimerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bedtime_rounded, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text('Timer de Desligamento'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mins in [15, 30, 60, 90, 120])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('Desligar em $mins minutos'),
                onTap: () {
                  _setSleepTimer(mins);
                  Navigator.pop(context);
                },
              ),
            if (_sleepMinutesRemaining != null)
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                title: const Text('Cancelar Timer Ativo',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  _sleepTimer?.cancel();
                  setState(() => _sleepMinutesRemaining = null);
                  Navigator.pop(context);
                },
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
          _previewController?.pause();
          SystemNavigator.pop();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTV = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            isLoading
                ? _buildLoadingState()
                : errorMessage.isNotEmpty
                    ? _buildErrorState()
                    : isTV
                        ? _buildTVLayout()
                        : _buildMobileLayout(),

            // JANELA FLUTUANTE PIP (PICTURE-IN-PICTURE INTERNO)
            if (isMiniPipFloating && activeItem != null)
              Positioned(
                bottom: 20,
                right: 20,
                child: Material(
                  elevation: 16,
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFF12151F),
                  child: Container(
                    width: isTV ? 320 : 230,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(13)),
                            child: Container(
                              color: Colors.black,
                              child: _buildMiniVideoWidget(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  activeItem!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  setState(() => isMiniPipFloating = false);
                                  _openFullScreen(activeItem!);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.open_in_full_rounded,
                                      size: 16, color: Color(0xFF00E5FF)),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  _previewController?.pause();
                                  setState(() => isMiniPipFloating = false);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.close_rounded,
                                      size: 16, color: Colors.white70),
                                ),
                              ),
                            ],
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
    );
  }

  // ===========================================================================
  // BARRA SUPERIOR DE RESUMO DA VARIEDADE + ÍCONE DISCRETO DE SPEED TEST
  // ===========================================================================
  Widget _buildTopNavigationAndStatsBar({required bool isTV}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isTV ? 20 : 12, vertical: isTV ? 12 : 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1018),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                  ),
                  borderRadius: BorderRadius.circular(9),
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
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 14),
              // Badge de Total Geral da Lista
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.3)),
                ),
                child: Text(
                  'Total: ${allItems.length} itens',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00E5FF),
                  ),
                ),
              ),
              if (isTV && accountExpDate.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Vencimento: $accountExpDate',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
              const Spacer(),
              if (_sleepMinutesRemaining != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Chip(
                    backgroundColor: Colors.amber.withOpacity(0.2),
                    label: Text('${_sleepMinutesRemaining}m',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.amber)),
                  ),
                ),
              // BOTÃO DISCRETO DE TESTE DE VELOCIDADE COM ÍCONE CONDIZENTE
              IconButton(
                tooltip: 'Teste de Velocidade',
                icon: const Icon(Icons.speed_rounded,
                    color: Color(0xFF00E5FF), size: 22),
                onPressed: _showSpeedTestModal,
              ),
              IconButton(
                tooltip: 'Timer de Sono',
                icon: const Icon(Icons.bedtime_outlined,
                    color: Colors.white70, size: 20),
                onPressed: _showSleepTimerDialog,
              ),
              IconButton(
                tooltip: 'Atualizar Lista',
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 21),
                onPressed: _loadAccountInfoAndPlaylist,
              ),
              IconButton(
                tooltip: 'Trocar Conta / DNS',
                icon: const Icon(Icons.logout_rounded,
                    color: Colors.white70, size: 20),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LoginGatewayScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          // SELETOR DE VARIEDADE (TODOS / TV AO VIVO / FILMES / SÉRIES) COM CONTADORES
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTypeTab(
                  label: 'Tudo (${allItems.length})',
                  icon: Icons.apps_rounded,
                  selected: activeContentType == null,
                  onTap: () {
                    setState(() {
                      activeContentType = null;
                      _rebuildCategoriesAndFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildTypeTab(
                  label: 'TV ao Vivo ($totalLiveCount)',
                  icon: Icons.live_tv_rounded,
                  selected: activeContentType == ContentType.live,
                  onTap: () {
                    setState(() {
                      activeContentType = ContentType.live;
                      _rebuildCategoriesAndFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildTypeTab(
                  label: 'Filmes ($totalMoviesCount)',
                  icon: Icons.movie_creation_outlined,
                  selected: activeContentType == ContentType.movie,
                  onTap: () {
                    setState(() {
                      activeContentType = ContentType.movie;
                      _rebuildCategoriesAndFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildTypeTab(
                  label: 'Séries ($totalSeriesCount)',
                  icon: Icons.video_library_outlined,
                  selected: activeContentType == ContentType.series,
                  onTap: () {
                    setState(() {
                      activeContentType = ContentType.series;
                      _rebuildCategoriesAndFilter();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TVFocusableItem(
      onSelect: onTap,
      builder: (context, isFocused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF2979FF)])
              : null,
          color: selected ? null : const Color(0xFF151926),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused
                ? Colors.white
                : selected
                    ? Colors.transparent
                    : Colors.white10,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16, color: selected ? Colors.black : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // LAYOUT TV / TV BOX (3 COLUNAS COM CONTADORES EM CADA CATEGORIA)
  // ===========================================================================
  Widget _buildTVLayout() {
    return Column(
      children: [
        _buildTopNavigationAndStatsBar(isTV: true),
        Expanded(
          child: Row(
            children: [
              // 1. COLUNA DE CATEGORIAS COM QUANTIDADE EM CADA UMA
              Container(
                width: 260,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C0E16),
                  border: Border(right: BorderSide(color: Colors.white10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(
                        'CATEGORIAS (${currentCategories.length})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: currentCategories.length,
                        itemBuilder: (context, index) {
                          final cat = currentCategories[index];
                          final count = categoryCounts[cat] ?? 0;
                          final isSelected = cat == selectedCategory;

                          return TVFocusableItem(
                            onSelect: () => _onCategoryTap(cat),
                            builder: (context, isFocused) => Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF00E5FF).withOpacity(0.18)
                                    : isFocused
                                        ? Colors.white10
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isFocused
                                      ? const Color(0xFF00E5FF)
                                      : isSelected
                                          ? const Color(0xFF00E5FF)
                                              .withOpacity(0.4)
                                          : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    cat == 'Favoritos'
                                        ? Icons.star_rounded
                                        : cat == 'Recentes'
                                            ? Icons.history_rounded
                                            : Icons.folder_outlined,
                                    size: 17,
                                    color: isSelected || isFocused
                                        ? const Color(0xFF00E5FF)
                                        : Colors.white54,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      cat,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected || isFocused
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF00E5FF),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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

              // 2. GRADE CENTRAL DE CONTEÚDOS
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF12151F),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (v) {
                                  searchQuery = v;
                                  _applyItemsFilter();
                                },
                                decoration: const InputDecoration(
                                  hintText:
                                      'Pesquisar canal, filme ou série...',
                                  hintStyle: TextStyle(
                                      fontSize: 13, color: Colors.white38),
                                  prefixIcon: Icon(Icons.search,
                                      color: Color(0xFF00E5FF), size: 19),
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'Exibindo ${filteredItems.length} itens',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? const Center(
                              child: Text('Nenhum conteúdo nesta categoria.',
                                  style: TextStyle(color: Colors.white54)))
                          : GridView.builder(
                              padding: const EdgeInsets.all(18),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 250,
                                mainAxisExtent: 94,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final isPlaying = activeItem?.id == item.id;
                                final isFav = favoriteIds.contains(item.id);

                                return TVFocusableItem(
                                  onSelect: () => _startPreview(item),
                                  builder: (context, isFocused) =>
                                      AnimatedScale(
                                    scale: isFocused ? 1.04 : 1.0,
                                    duration: const Duration(milliseconds: 120),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isPlaying
                                            ? const Color(0xFF172238)
                                            : const Color(0xFF12151F),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isFocused
                                              ? const Color(0xFF00E5FF)
                                              : isPlaying
                                                  ? const Color(0xFF2979FF)
                                                  : Colors.white10,
                                          width: isFocused ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          _buildLogoWidget(item.logo, size: 50),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  item.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    _buildQualityBadge(
                                                        item.qualityTag),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        item.group,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.white54,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _toggleFavorite(item),
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
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // 3. PAINEL DIREITO: PRÉ-VISUALIZAÇÃO + TROCA RÁPIDA DE QUALIDADE
              Container(
                width: 330,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C0E16),
                  border: Border(left: BorderSide(color: Colors.white10)),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TRANSMISSÃO SELECIONADA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          color: Colors.black,
                          child: _buildMiniVideoWidget(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (activeItem != null) ...[
                      Text(
                        activeItem!.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeItem!.group,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF00E5FF)),
                      ),
                      const SizedBox(height: 14),
                      // Seletor Rápido de Qualidade no Painel Lateral
                      _buildQuickQualityRow(activeItem!),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: TVFocusableItem(
                          onSelect: () => _openFullScreen(activeItem!),
                          builder: (context, isFocused) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isFocused
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fullscreen_rounded,
                                    color: Colors.black),
                                SizedBox(width: 8),
                                Text(
                                  'TELA CHEIA',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // LAYOUT MOBILE (CELULAR)
  // ===========================================================================
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildTopNavigationAndStatsBar(isTV: false),
        if (activeItem != null && !isMiniPipFloating)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.black,
                  child: _buildMiniVideoWidget(),
                ),
                Positioned(
                  bottom: 8,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            activeItem!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Modo PiP Flutuante',
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black87),
                        icon: const Icon(Icons.picture_in_picture_alt_rounded,
                            color: Color(0xFF00E5FF), size: 18),
                        onPressed: () =>
                            setState(() => isMiniPipFloating = true),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                        onPressed: () => _openFullScreen(activeItem!),
                        icon: const Icon(Icons.fullscreen, size: 18),
                        label: const Text('Expandir',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF12151F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                searchQuery = v;
                _applyItemsFilter();
              },
              decoration: const InputDecoration(
                hintText: 'Buscar canais, filmes ou séries...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.white38),
                prefixIcon:
                    Icon(Icons.search, color: Color(0xFF00E5FF), size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        // Chips de Categorias Mobile com Contadores Exatos
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: currentCategories.length,
            itemBuilder: (context, index) {
              final cat = currentCategories[index];
              final count = categoryCounts[cat] ?? 0;
              final isSelected = cat == selectedCategory;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text('$cat ($count)'),
                  selected: isSelected,
                  onSelected: (_) => _onCategoryTap(cat),
                  selectedColor: const Color(0xFF00E5FF),
                  backgroundColor: const Color(0xFF12151F),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              final isPlaying = activeItem?.id == item.id;
              final isFav = favoriteIds.contains(item.id);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? const Color(0xFF172238)
                      : const Color(0xFF12151F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPlaying
                        ? const Color(0xFF00E5FF)
                        : Colors.white.withOpacity(0.05),
                  ),
                ),
                child: ListTile(
                  onTap: () => _startPreview(item),
                  leading: _buildLogoWidget(item.logo, size: 42),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Row(
                    children: [
                      _buildQualityBadge(item.qualityTag),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isFav
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: isFav ? Colors.amber : Colors.white30,
                        ),
                        onPressed: () => _toggleFavorite(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_rounded,
                            color: Color(0xFF00E5FF)),
                        onPressed: () => _openFullScreen(item),
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

  Widget _buildQuickQualityRow(StreamItem current) {
    final variants = _findQualityVariants(current);
    if (variants.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUALIDADES DISPONÍVEIS:',
          style: TextStyle(
              fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: variants.map((v) {
            final selected = v.id == current.id;
            return InkWell(
              onTap: () => _startPreview(v),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFF00E5FF) : const Color(0xFF151924),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  v.qualityTag,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildQualityBadge(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tag == '4K' || tag == 'FHD'
            ? const Color(0xFF00E5FF).withOpacity(0.2)
            : Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: tag == '4K' || tag == 'FHD'
              ? const Color(0xFF00E5FF)
              : Colors.white70,
        ),
      ),
    );
  }

  Widget _buildMiniVideoWidget() {
    if (isPreviewError) {
      return const Center(
        child: Text('Sinal indisponível',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
      );
    }
    if (!isPreviewReady || _previewController == null) {
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

  Widget _buildLogoWidget(String url, {double size = 46}) {
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

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF00E5FF)),
          SizedBox(height: 18),
          Text('CARREGANDO E CLASSIFICANDO CONTEÚDOS...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.redAccent, size: 52),
            const SizedBox(height: 12),
            Text(errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _loadAccountInfoAndPlaylist,
                  child: const Text('Tentar Novamente'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginGatewayScreen()),
                    );
                  },
                  child: const Text('Voltar ao Login'),
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
// TELA 3: SUPER PLAYER COM MOTOR ANTI-TRAVAMENTO AUTOMÁTICO + SELETOR QUALIDADE
// =============================================================================
class SmartAdaptivePlayerScreen extends StatefulWidget {
  final StreamItem initialItem;
  final List<StreamItem> playlist;
  final List<StreamItem> allItems;
  final double measuredSpeedMbps;
  final void Function(StreamItem item) onMinimizeToPip;

  const SmartAdaptivePlayerScreen({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.allItems,
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

  // Modos de Proporção de Tela: 0 = Original, 1 = Preencher (Esticar), 2 = 16:9, 3 = 4:3
  int aspectMode = 0;
  final List<String> aspectLabels = ['Original', 'Esticar', '16:9', '4:3'];

  // Motor Anti-Travamento (Monitor de Estabilidade e Buffer Dinâmico)
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

  // Motor que escolhe e ajusta a reprodução conforme a velocidade e estabilidade da rede
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
      targetUrl = targetUrl.substring(0, targetUrl.length - 3) + '.m3u8';
    }

    final old = _controller;
    _controller = VideoPlayerController.networkUrl(Uri.parse(targetUrl));
    await old?.dispose();

    try {
      await _controller!.initialize();
      if (!mounted) return;

      // Pré-aquecimento adaptativo de buffer baseado na velocidade medida da internet
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

  // Monitora travamentos de pacote em tempo real e reconstrói o buffer automaticamente
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
          // Se detectar que a rede oscilou por mais de 6s, aplica estabilização automática
          if (_stallCounter >= 3 && !_isRecoveringStream) {
            setState(() => _isRecoveringStream = true);
            await _controller!.pause();
            // Aguarda janela de recomposição de buffer proporcional à estabilidade
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
    _hideTimer = Timer(const Duration(seconds: 4), () {
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
    final list = widget.allItems
        .where((i) =>
            i.type == currentItem.type &&
            i.cleanName.toLowerCase() == currentItem.cleanName.toLowerCase())
        .toList();
    return list.isEmpty ? [currentItem] : list;
  }

  @override
  Widget build(BuildContext context) {
    final qualities = _getQualities();
    final isVod = currentItem.type != ContentType.live;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            setState(() => showOsd = true);
            _resetOsdTimer();
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
              setState(
                  () => showQuickChannelDrawer = !showQuickChannelDrawer);
              return KeyEventResult.handled;
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
              // 1. RENDERIZADOR DE VÍDEO COM PROPORÇÃO AJUSTÁVEL
              Center(
                child: hasError
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wifi_tethering_error_rounded,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          const Text('Sinal oscilou além do limite.'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              _autoRecoveryAttempts = 0;
                              _initSmartStream(currentItem,
                                  tryHlsFallback: !_usingHlsFallback);
                            },
                            child: const Text('Reconectar Fluxo'),
                          ),
                        ],
                      )
                    : isInitialized && _controller != null
                        ? _buildAspectVideo()
                        : const CircularProgressIndicator(
                            color: Color(0xFF00E5FF)),
              ),

              // Indicador discreto quando o sistema Anti-Travamento está estabilizando
              if (_isRecoveringStream)
                Positioned(
                  top: 24,
                  right: 24,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        Text('Otimizando buffer...',
                            style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),

              // 2. CONTROLES OSD EM TELA CHEIA
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // TOPO DO PLAYER
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                          IconButton(
                            tooltip: 'Lista Rápida de Canais',
                            icon: const Icon(Icons.menu_open_rounded,
                                color: Color(0xFF00E5FF)),
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
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  currentItem.group,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          // SELETOR RÁPIDO DE QUALIDADE (SD / HD / FHD / 4K) DENTRO DO PLAYER
                          if (qualities.length > 1)
                            Row(
                              children: qualities.map((q) {
                                final isCurrent = q.id == currentItem.id;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: InkWell(
                                    onTap: () => _initSmartStream(q),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white12,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        q.qualityTag,
                                        style: TextStyle(
                                          fontSize: 11,
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
                          const SizedBox(width: 8),
                          // Botão Proporção de Tela
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() => aspectMode =
                                  (aspectMode + 1) % aspectLabels.length);
                            },
                            icon: const Icon(Icons.aspect_ratio_rounded,
                                size: 16),
                            label: Text(aspectLabels[aspectMode],
                                style: const TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          // Botão Picture-in-Picture (PiP)
                          IconButton(
                            tooltip: 'Minimizar em PiP',
                            icon: const Icon(
                                Icons.picture_in_picture_alt_rounded,
                                color: Color(0xFF00E5FF)),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onMinimizeToPip(currentItem);
                            },
                          ),
                        ],
                      ),

                      // RODAPÉ DO PLAYER (COM BARRA DE PROGRESSO SE FOR FILME/SÉRIE)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF12151F).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isVod && isInitialized && _controller != null)
                              VideoProgressIndicator(
                                _controller!,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: Color(0xFF00E5FF),
                                  bufferedColor: Colors.white24,
                                  backgroundColor: Colors.white10,
                                ),
                              ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous_rounded,
                                      size: 28),
                                  onPressed: () => _stepChannel(-1),
                                ),
                                IconButton(
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
                                  icon: const Icon(Icons.skip_next_rounded,
                                      size: 28),
                                  onPressed: () => _stepChannel(1),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${currentItem.name} • ${currentItem.qualityTag}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'ANTI-TRAVAMENTO ATIVO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
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

              // 3. MENU LATERAL TRANSPARENTE DE CANAIS DENTRO DA TELA CHEIA
              if (showQuickChannelDrawer)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 290,
                    color: const Color(0xFF08090E).withOpacity(0.92),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TROCA RÁPIDA',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00E5FF)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(
                                    () => showQuickChannelDrawer = false),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: widget.playlist.length,
                            itemBuilder: (context, idx) {
                              final ch = widget.playlist[idx];
                              final selected = ch.id == currentItem.id;
                              return ListTile(
                                selected: selected,
                                selectedTileColor:
                                    const Color(0xFF00E5FF).withOpacity(0.2),
                                title: Text(ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: Text(ch.qualityTag,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF00E5FF))),
                                onTap: () {
                                  _initSmartStream(ch);
                                  setState(
                                      () => showQuickChannelDrawer = false);
                                },
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

// =============================================================================
// COMPONENTE DE TESTE DE VELOCIDADE DA INTERNET
// =============================================================================
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
  String statusText = 'Toque em Iniciar para medir sua conexão atual';

  Future<void> _runTest() async {
    setState(() {
      isTesting = true;
      speedMbps = 0.0;
      statusText = 'Medindo latência e velocidade de download...';
    });

    try {
      final uri = Uri.parse('https://speed.cloudflare.com/__down?bytes=5000000');
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
          if (mounted) {
            setState(() => speedMbps = currentMbps);
          }
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
          Text('Teste de Velocidade'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Text(
            '${speedMbps.toStringAsFixed(1)} Mbps',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Color(0xFF00E5FF),
            ),
          ),
          if (pingMs > 0)
            Text('Latência: $pingMs ms',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 16),
          if (isTesting)
            const LinearProgressIndicator(color: Color(0xFF00E5FF)),
          const SizedBox(height: 12),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
          ),
          onPressed: isTesting ? null : _runTest,
          child: const Text('Iniciar Teste',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// =============================================================================
// COMPONENTE DE FOCO PARA CONTROLE REMOTO (D-PAD) E TOQUE
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
// PARSER AVANÇADO: SEPARA CANAIS, FILMES, SÉRIES E EXTRAI QUALIDADE (SD/HD/FHD/4K)
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
  final qualityRegex =
      RegExp(r'\b(4K|UHD|FHD|1080P|HD|720P|SD|H265|HEVC)\b', caseSensitive: false);
  final seriesRegex = RegExp(r'\bS\d+\s*E\d+\b', caseSensitive: false);

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

      // Classifica entre TV ao Vivo, Filme ou Série
      ContentType type = ContentType.live;
      if (lowerUrl.contains('/series/') ||
          lowerGroup.contains('série') ||
          lowerGroup.contains('serie') ||
          seriesRegex.hasMatch(name)) {
        type = ContentType.series;
      } else if (lowerUrl.contains('/movie/') ||
          lowerGroup.contains('filme') ||
          lowerGroup.contains('vod') ||
          lowerGroup.contains('cinema') ||
          lowerUrl.endsWith('.mp4') ||
          lowerUrl.endsWith('.mkv')) {
        type = ContentType.movie;
      }

      // Extrai a tag de qualidade (4K, FHD, HD, SD) e limpa o nome para agrupar variantes
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

      final isAdult = lowerGroup.contains('adult') ||
          lowerGroup.contains('xxx') ||
          lowerGroup.contains('+18') ||
          lowerName.contains('xxx');

      result.add(
        StreamItem(
          id: '${counter}_${trimmed.hashCode}',
          name: name.isNotEmpty ? name : 'Canal $counter',
          cleanName: cleanName.isNotEmpty ? cleanName : name,
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
