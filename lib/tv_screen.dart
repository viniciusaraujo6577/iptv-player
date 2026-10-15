import 'package:flutter/material.dart';
import 'core.dart';

class TVDashboardView extends StatelessWidget {
  final bool isSideMenuOpen;
  final VoidCallback onOpenSideMenu;
  final VoidCallback onCloseSideMenu;
  final MainSection activeSection;
  final String sectionTitle;
  final String selectedCategory;
  final List<String> sectionCategories;
  final Map<String, int> categoryCounts;
  final int totalAllCount;
  final int liveCount;
  final int movieCount;
  final int seriesCount;
  final int favoritesCount;
  final int recentsCount;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final List<StreamItem> activeQualityVariants;
  final Widget miniVideoWidget;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<MainSection> onSelectSection;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<StreamItem> onStartPreview;
  final ValueChanged<StreamItem> onOpenFullScreen;
  final ValueChanged<SeriesGroup> onSelectSeriesGroup;
  final ValueChanged<StreamItem> onToggleFavorite;
  final VoidCallback onOpenSpeedTest;
  final VoidCallback onRefreshPlaylist;
  final VoidCallback onSwitchToMobileMode;
  final VoidCallback onLogout;

  const TVDashboardView({
    super.key,
    required this.isSideMenuOpen,
    required this.onOpenSideMenu,
    required this.onCloseSideMenu,
    required this.activeSection,
    required this.sectionTitle,
    required this.selectedCategory,
    required this.sectionCategories,
    required this.categoryCounts,
    required this.totalAllCount,
    required this.liveCount,
    required this.movieCount,
    required this.seriesCount,
    required this.favoritesCount,
    required this.recentsCount,
    required this.displayedItems,
    required this.displayedSeries,
    required this.favoriteIds,
    required this.activeItem,
    required this.activeQualityVariants,
    required this.miniVideoWidget,
    required this.searchController,
    required this.searchQuery,
    required this.onSelectSection,
    required this.onSelectCategory,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStartPreview,
    required this.onOpenFullScreen,
    required this.onSelectSeriesGroup,
    required this.onToggleFavorite,
    required this.onOpenSpeedTest,
    required this.onRefreshPlaylist,
    required this.onSwitchToMobileMode,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final isSeriesView = activeSection == MainSection.series;
    final isMovieView = activeSection == MainSection.movie;
    final countText = isSeriesView
        ? '${displayedSeries.length} séries'
        : '${displayedItems.length} itens';

    return Row(
      children: [
        // 1. MENU LATERAL COM OCULTAÇÃO AUTOMÁTICA + GATILHO DE BORDA ESQUERDA
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: isSideMenuOpen ? 215 : 18,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0C12),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: isSideMenuOpen
              ? _buildExpandedSideMenu()
              : _buildCollapsedEdgeSensor(),
        ),

        // 2. COLUNA DE GÊNEROS / CATEGORIAS (SETA ESQUERDA REABRE O MENU LATERAL)
        Container(
          width: 215,
          decoration: const BoxDecoration(
            color: Color(0xFF0D0F17),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                child: Row(
                  children: [
                    if (!isSideMenuOpen)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TVIconButton(
                          icon: Icons.menu_rounded,
                          color: const Color(0xFF00E5FF),
                          size: 18,
                          onPressed: onOpenSideMenu,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        'GÊNEROS (${sectionCategories.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: sectionCategories.length,
                  itemBuilder: (context, index) {
                    final cat = sectionCategories[index];
                    final count = categoryCounts[cat] ?? 0;
                    final isSelected = cat == selectedCategory;

                    return TVFocusableItem(
                      autofocus: !isSideMenuOpen && isSelected,
                      // Ir para a esquerda no controle remoto reabre o menu lateral!
                      onMoveLeft: onOpenSideMenu,
                      onSelect: () => onSelectCategory(cat),
                      builder: (context, isFocused) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00E5FF).withOpacity(0.18)
                              : isFocused
                                  ? Colors.white10
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF00E5FF)
                                : isSelected
                                    ? const Color(0xFF00E5FF).withOpacity(0.4)
                                    : Colors.transparent,
                            width: isFocused ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected || isFocused
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.bold,
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

        // 3. ÁREA CENTRAL DE CONTEÚDO + PRÉ-VISUALIZAÇÃO
        Expanded(
          child: Column(
            children: [
              // Barra Superior (Título da Seção + Busca com Teclado Virtual de TV)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1018),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        sectionTitle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00E5FF),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TVFocusableItem(
                        autoScroll: false,
                        onMoveLeft: onOpenSideMenu,
                        onSelect: () {
                          openTVVirtualKeyboard(
                            context: context,
                            controller: searchController,
                            title: 'Pesquisar em $sectionTitle',
                            onChanged: onSearchChanged,
                          );
                        },
                        builder: (context, isFocused) => AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12151F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFocused
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white12,
                              width: isFocused ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search,
                                  color: Color(0xFF00E5FF), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  searchQuery.isEmpty
                                      ? 'Aperte OK para pesquisar em $sectionTitle...'
                                      : 'Filtro ativo: "$searchQuery"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: searchQuery.isEmpty
                                        ? Colors.white54
                                        : const Color(0xFF00E5FF),
                                    fontWeight: searchQuery.isEmpty
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (searchQuery.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: onClearSearch,
                        builder: (context, isFocused) => Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C1D24),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFocused
                                  ? Colors.white
                                  : Colors.redAccent.withOpacity(0.4),
                            ),
                          ),
                          child: const Text(
                            'Limpar',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Text(
                      countText,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
                    // GRADE ANIMADA (SÉRIES POR CAPA, FILMES EM PÔSTER OU CANAIS AO VIVO)
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: isSeriesView
                            ? _buildTVSeriesCatalogGrid()
                            : isMovieView
                                ? _buildTVMoviesPosterGrid()
                                : _buildTVLiveChannelsGrid(),
                      ),
                    ),

                    // PAINEL DIREITO DE PRÉ-VISUALIZAÇÃO PEQUENA (OCULTO EM SÉRIES PARA DAR MAIS ESPAÇO AO CATÁLOGO)
                    if (!isSeriesView)
                      Container(
                        width: 280,
                        decoration: const BoxDecoration(
                          color: Color(0xFF0A0C12),
                          border:
                              Border(left: BorderSide(color: Colors.white10)),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.fiber_manual_record,
                                    color: Colors.redAccent, size: 12),
                                SizedBox(width: 6),
                                Text(
                                  'PRÉ-VISUALIZAÇÃO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.black,
                                  child: miniVideoWidget,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (activeItem != null) ...[
                              Text(
                                activeItem!.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                activeItem!.group,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF00E5FF)),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Dica: Selecione o canal novamente na lista para abrir direto em Tela Cheia.',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white38),
                              ),
                              const SizedBox(height: 10),
                              if (activeQualityVariants.length > 1)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: activeQualityVariants.map((v) {
                                    final selected = v.id == activeItem!.id;
                                    return TVFocusableItem(
                                      autoScroll: false,
                                      onSelect: () => onStartPreview(v),
                                      builder: (context, isFocused) =>
                                          Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? const Color(0xFF00E5FF)
                                              : const Color(0xFF151924),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isFocused
                                                ? Colors.white
                                                : Colors.white12,
                                          ),
                                        ),
                                        child: Text(
                                          v.qualityTag,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: selected
                                                ? Colors.black
                                                : Colors.white,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: TVFocusableItem(
                                  autoScroll: false,
                                  onSelect: () => onOpenFullScreen(activeItem!),
                                  builder: (context, isFocused) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 11),
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
                                    child: const Center(
                                      child: Text(
                                        'ABRIR TELA CHEIA',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: TVFocusableItem(
                                  autoScroll: false,
                                  onSelect: () => onToggleFavorite(activeItem!),
                                  builder: (context, isFocused) {
                                    final isFav =
                                        favoriteIds.contains(activeItem!.id);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 9),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF151924),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isFocused
                                              ? const Color(0xFF00E5FF)
                                              : Colors.white12,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          isFav
                                              ? '★ Remover Favorito'
                                              : '☆ Favoritar',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    );
                                  },
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
          ),
        ),
      ],
    );
  }

  // FAIXA SENSORA NA BORDA ESQUERDA QUANDO O MENU ESTÁ OCULTO
  Widget _buildCollapsedEdgeSensor() {
    return TVFocusableItem(
      autoScroll: false,
      onSelect: onOpenSideMenu,
      builder: (context, isFocused) {
        if (isFocused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onOpenSideMenu();
          });
        }
        return GestureDetector(
          onTap: onOpenSideMenu,
          child: Container(
            color: const Color(0xFF0A0C12),
            child: Center(
              child: Container(
                width: 4,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // MENU LATERAL EXPANDIDO (OCULTA AUTOMATICAMENTE AO SELECIONAR UMA OPÇÃO)
  Widget _buildExpandedSideMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 10, 12),
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
                    color: Colors.black, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'UNEX VISION',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      '$totalAllCount conteúdos',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TVIconButton(
                icon: Icons.chevron_left_rounded,
                size: 18,
                onPressed: onCloseSideMenu,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              _buildTVSideNavButton(
                label: 'TV ao Vivo',
                count: liveCount,
                icon: Icons.live_tv_rounded,
                selected: activeSection == MainSection.live,
                autofocus: activeSection == MainSection.live,
                onSelect: () => onSelectSection(MainSection.live),
              ),
              _buildTVSideNavButton(
                label: 'Filmes',
                count: movieCount,
                icon: Icons.movie_creation_outlined,
                selected: activeSection == MainSection.movie,
                autofocus: activeSection == MainSection.movie,
                onSelect: () => onSelectSection(MainSection.movie),
              ),
              _buildTVSideNavButton(
                label: 'Séries',
                count: seriesCount,
                icon: Icons.video_library_outlined,
                selected: activeSection == MainSection.series,
                autofocus: activeSection == MainSection.series,
                onSelect: () => onSelectSection(MainSection.series),
              ),
              const Divider(color: Colors.white10, height: 18),
              _buildTVSideNavButton(
                label: 'Favoritos',
                count: favoritesCount,
                icon: Icons.star_rounded,
                selected: activeSection == MainSection.favorites,
                autofocus: activeSection == MainSection.favorites,
                onSelect: () => onSelectSection(MainSection.favorites),
              ),
              _buildTVSideNavButton(
                label: 'Recentes',
                count: recentsCount,
                icon: Icons.history_rounded,
                selected: activeSection == MainSection.recents,
                autofocus: activeSection == MainSection.recents,
                onSelect: () => onSelectSection(MainSection.recents),
              ),
              const Divider(color: Colors.white10, height: 18),
              _buildTVSideActionButton(
                label: 'Velocidade',
                icon: Icons.speed_rounded,
                color: const Color(0xFF00E5FF),
                onSelect: () {
                  onCloseSideMenu();
                  onOpenSpeedTest();
                },
              ),
              _buildTVSideActionButton(
                label: 'Atualizar Lista',
                icon: Icons.refresh_rounded,
                onSelect: () {
                  onCloseSideMenu();
                  onRefreshPlaylist();
                },
              ),
              _buildTVSideActionButton(
                label: 'Modo Celular',
                icon: Icons.smartphone_rounded,
                onSelect: onSwitchToMobileMode,
              ),
              _buildTVSideActionButton(
                label: 'Trocar Conta',
                icon: Icons.logout_rounded,
                color: Colors.redAccent,
                onSelect: onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // CATÁLOGO DE SÉRIES NA TV (PÔSTERES 2:3 QUE ABREM AS TEMPORADAS E EPISÓDIOS)
  Widget _buildTVSeriesCatalogGrid() {
    if (displayedSeries.isEmpty) {
      return const Center(
        key: ValueKey('tv_empty_series'),
        child: Text('Nenhuma série encontrada neste gênero.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      key: ValueKey('tv_series_$selectedCategory'),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 175,
        mainAxisExtent: 245,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: displayedSeries.length,
      itemBuilder: (context, index) {
        final series = displayedSeries[index];
        return TVFocusableItem(
          onSelect: () => onSelectSeriesGroup(series),
          builder: (context, isFocused) => buildStreamingPosterCard(
            title: series.title,
            subtitle:
                '${series.totalSeasons} Temp • ${series.totalEpisodes} Eps',
            logoUrl: series.logo,
            badgeText: series.qualityTag,
            isFocused: isFocused,
            onTap: () => onSelectSeriesGroup(series),
          ),
        );
      },
    );
  }

  // CATÁLOGO DE FILMES NA TV (PÔSTERES 2:3 COM 1º CLIQUE PREVIEW E 2º TELA CHEIA)
  Widget _buildTVMoviesPosterGrid() {
    if (displayedItems.isEmpty) {
      return const Center(
        key: ValueKey('tv_empty_movies'),
        child: Text('Nenhum filme encontrado neste gênero.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      key: ValueKey('tv_movies_$selectedCategory'),
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 165,
        mainAxisExtent: 230,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: displayedItems.length,
      itemBuilder: (context, index) {
        final movie = displayedItems[index];
        final isPlaying = activeItem?.id == movie.id;
        final isFav = favoriteIds.contains(movie.id);

        return TVFocusableItem(
          onSelect: () => onStartPreview(movie),
          builder: (context, isFocused) => buildStreamingPosterCard(
            title: movie.name,
            subtitle: isPlaying ? '▶ OK p/ Tela Cheia' : movie.group,
            logoUrl: movie.logo,
            badgeText: movie.qualityTag,
            isFocused: isFocused,
            isPlaying: isPlaying,
            isFavorite: isFav,
            onFavoriteTap: () => onToggleFavorite(movie),
            onTap: () => onStartPreview(movie),
          ),
        );
      },
    );
  }

  // GRADE DE CANAIS AO VIVO NA TV (1º CLIQUE PREVIEW PEQUENO, 2º CLIQUE TELA CHEIA)
  Widget _buildTVLiveChannelsGrid() {
    if (displayedItems.isEmpty) {
      return const Center(
        key: ValueKey('tv_empty_live'),
        child: Text('Nenhum canal encontrado.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      key: ValueKey('tv_live_$selectedCategory'),
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 245,
        mainAxisExtent: 88,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: displayedItems.length,
      itemBuilder: (context, index) {
        final item = displayedItems[index];
        final isPlaying = activeItem?.id == item.id;
        final isFav = favoriteIds.contains(item.id);

        return TVFocusableItem(
          onSelect: () => onStartPreview(item),
          builder: (context, isFocused) => AnimatedScale(
            scale: isFocused ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 130),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFF172238)
                    : const Color(0xFF12151F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFocused
                      ? const Color(0xFF00E5FF)
                      : isPlaying
                          ? const Color(0xFF2979FF)
                          : Colors.white10,
                  width: isFocused ? 2.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  buildChannelLogo(item.logo, size: 44),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            buildQualityBadge(item.qualityTag),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                isPlaying
                                    ? '▶ OK p/ Tela Cheia'
                                    : item.group,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isPlaying
                                      ? const Color(0xFF00E5FF)
                                      : Colors.white54,
                                  fontWeight: isPlaying
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isFav)
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTVSideNavButton({
    required String label,
    required int count,
    required IconData icon,
    required bool selected,
    required VoidCallback onSelect,
    bool autofocus = false,
  }) {
    return TVFocusableItem(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, isFocused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF2979FF)])
              : null,
          color: selected
              ? null
              : isFocused
                  ? Colors.white10
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 17, color: selected ? Colors.black : Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.black : Colors.white,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.black87 : const Color(0xFF00E5FF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTVSideActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onSelect,
    Color color = Colors.white70,
  }) {
    return TVFocusableItem(
      onSelect: onSelect,
      builder: (context, isFocused) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isFocused ? Colors.white10 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
