import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

const Map<String, String> kIptvHeaders = {
  'User-Agent': 'IPTVSmartersPlayer/1.0 (Linux; Android 11)',
  'Accept': '*/*',
  'Connection': 'keep-alive',
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const SizedBox.shrink();
  };

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
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
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
      home: const StartupRouterScreen(),
    );
  }
}

// =============================================================================
// ARMAZENAMENTO DE PREFERÊNCIA DE DISPOSITIVO (CELULAR OU TV) E SESSÃO
// =============================================================================
enum DeviceMode { mobile, tv }

class AppStorage {
  static File get _deviceFile =>
      File('${Directory.systemTemp.path}/unex_device_mode_v5.json');
  static File get _sessionFile =>
      File('${Directory.systemTemp.path}/unex_verified_session_v5.json');

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

// =============================================================================
// DIÁLOGO PADRÃO PARA CONFIRMAR SAÍDA DO APLICATIVO (IMPEDE FECHAMENTO ACIDENTAL)
// =============================================================================
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
// TECLADO VIRTUAL PRÓPRIO PARA TV ANDROID (NUNCA TRAVA O CONTROLE REMOTO)
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
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Cabeçalho + Visor do Texto Digitado
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
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07080C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Expanded(
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Atalhos rápidos para URLs / DNS
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
                      const SizedBox(height: 10),
                    ],

                    // Grade de Teclas (Numérico ou Completo)
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
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: chars.asMap().entries.map((charEntry) {
                              final rawChar = charEntry.value;
                              final displayChar = isUppercase
                                  ? rawChar.toUpperCase()
                                  : rawChar;
                              final isFirstKey =
                                  rowIndex == 1 && charEntry.key == 0;
                              return _buildKeyButton(
                                label: displayChar,
                                width: 46,
                                height: 38,
                                autofocus: isFirstKey,
                                onTap: () => appendText(displayChar),
                              );
                            }).toList(),
                          ),
                        );
                      }),

                    const SizedBox(height: 10),

                    // Barra Inferior de Ações do Teclado (Maiúsculas, Espaço, Apagar, Limpar, Concluir)
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
                            width: 110,
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
                          label: 'LIMPAR TUDO',
                          color: const Color(0xFF2C1D24),
                          textColor: Colors.redAccent,
                          onTap: clearAll,
                        ),
                        _buildKeyButton(
                          label: '✓ CONCLUIR',
                          width: 130,
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
  double height = 38,
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
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.45),
                    blurRadius: 10,
                  )
                ]
              : null,
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

// =============================================================================
// CAMPO DE ENTRADA ADAPTATIVO (TOUCH NO CELULAR / TECLADO VIRTUAL NA TV)
// =============================================================================
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
    // NO CELULAR: Usa o TextField tradicional que funcionou perfeitamente
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

    // NA TV ANDROID: Botão focado por controle remoto que abre o Teclado Virtual sem travar
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
      builder: (context, isFocused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF08090E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused ? const Color(0xFF00E5FF) : Colors.white12,
            width: isFocused ? 2.2 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.25),
                    blurRadius: 12,
                  )
                ]
              : null,
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

// =============================================================================
// MODELOS DE DADOS
// =============================================================================
enum ContentType { live, movie, series }

enum MainSection { live, movie, series, favorites, recents }

class StreamItem {
  final String id;
  final String name;
  final String cleanName;
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
    required this.qualityTag,
    required this.group,
    required this.logo,
    required this.url,
    required this.type,
    required this.isAdult,
  });
}

// =============================================================================
// ROTEADOR INICIAL
// =============================================================================
class StartupRouterScreen extends StatefulWidget {
  const StartupRouterScreen({super.key});

  @override
  State<StartupRouterScreen> createState() => _StartupRouterScreenState();
}

class _StartupRouterScreenState extends State<StartupRouterScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final savedMode = await AppStorage.loadDeviceMode();
    if (!mounted) return;

    if (savedMode == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DeviceSelectionScreen()),
      );
    } else {
      await applyDeviceOrientation(savedMode);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginGatewayScreen(
            deviceMode: savedMode,
            allowAutoLogin: true,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
      ),
    );
  }
}

// =============================================================================
// TELA 0: ESCOLHA DO DISPOSITIVO (CELULAR ANDROID OU TV ANDROID)
// =============================================================================
class DeviceSelectionScreen extends StatelessWidget {
  const DeviceSelectionScreen({super.key});

  Future<void> _selectMode(BuildContext context, DeviceMode mode) async {
    await AppStorage.saveDeviceMode(mode);
    await applyDeviceOrientation(mode);
    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoginGatewayScreen(
          deviceMode: mode,
          allowAutoLogin: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) showExitAppConfirmationDialog(context);
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.5,
              colors: [Color(0xFF132238), Color(0xFF08090E)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.devices_rounded,
                            color: Colors.black, size: 38),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'BEM-VINDO AO UNEX VISION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Em qual dispositivo você está usando o aplicativo?\nAjustaremos toda a interface e os comandos para a sua escolha.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildDeviceOptionCard(
                            context: context,
                            title: 'Celular Android',
                            subtitle:
                                'Interface vertical para tela de toque com menu lateral deslizante.',
                            icon: Icons.smartphone_rounded,
                            autofocus: false,
                            onTap: () =>
                                _selectMode(context, DeviceMode.mobile),
                          ),
                          _buildDeviceOptionCard(
                            context: context,
                            title: 'TV Android / TV Box',
                            subtitle:
                                'Interface Widescreen 100% controlada por controle remoto e teclado de TV próprio.',
                            icon: Icons.tv_rounded,
                            autofocus: true,
                            onTap: () => _selectMode(context, DeviceMode.tv),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool autofocus,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 290,
      child: TVFocusableItem(
        autofocus: autofocus,
        autoScroll: false,
        onSelect: onTap,
        builder: (context, isFocused) => AnimatedScale(
          scale: isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF12151F),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isFocused ? const Color(0xFF00E5FF) : Colors.white12,
                width: isFocused ? 2.5 : 1,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.3),
                        blurRadius: 20,
                      )
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFF00E5FF), size: 42),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'SELECIONAR',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
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
  }
}

// =============================================================================
// TELA 1: LOGIN LIMPO (COMPATÍVEL COM CONTROLE REMOTO E CELULAR)
// =============================================================================
class LoginGatewayScreen extends StatefulWidget {
  final DeviceMode deviceMode;
  final bool allowAutoLogin;
  final String initialDns;
  final String initialUser;
  final String initialPass;
  final String initialM3u;
  final bool initialDirectM3uMode;
  final String? errorBannerMessage;

  const LoginGatewayScreen({
    super.key,
    required this.deviceMode,
    this.allowAutoLogin = false,
    this.initialDns = '',
    this.initialUser = '',
    this.initialPass = '',
    this.initialM3u = '',
    this.initialDirectM3uMode = false,
    this.errorBannerMessage,
  });

  @override
  State<LoginGatewayScreen> createState() => _LoginGatewayScreenState();
}

class _LoginGatewayScreenState extends State<LoginGatewayScreen> {
  late final TextEditingController _dnsController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _m3uController;

  late bool _useDirectM3uMode;
  bool _rememberMe = true;
  bool _checkingSavedSession = false;

  @override
  void initState() {
    super.initState();
    _dnsController = TextEditingController(text: widget.initialDns);
    _userController = TextEditingController(text: widget.initialUser);
    _passController = TextEditingController(text: widget.initialPass);
    _m3uController = TextEditingController(text: widget.initialM3u);
    _useDirectM3uMode = widget.initialDirectM3uMode;

    if (widget.allowAutoLogin) {
      _checkingSavedSession = true;
      _checkAndRestoreVerifiedSession();
    }
  }

  @override
  void dispose() {
    _dnsController.dispose();
    _userController.dispose();
    _passController.dispose();
    _m3uController.dispose();
    super.dispose();
  }

  Future<void> _checkAndRestoreVerifiedSession() async {
    final saved = await AppStorage.loadVerifiedSession();
    if (!mounted) return;

    if (saved != null) {
      final mode = saved['mode']?.toString() ?? 'xtream';
      if (mode == 'm3u') {
        final directUrl = saved['m3uUrl']?.toString() ?? '';
        if (directUrl.isNotEmpty) {
          _openDashboard(directM3uUrl: directUrl, rememberSession: true);
          return;
        }
      } else {
        final dns = saved['dns']?.toString() ?? '';
        final user = saved['user']?.toString() ?? '';
        final pass = saved['pass']?.toString() ?? '';
        if (dns.isNotEmpty && user.isNotEmpty && pass.isNotEmpty) {
          _openDashboard(
            dns: dns,
            user: user,
            pass: pass,
            rememberSession: true,
          );
          return;
        }
      }
    }

    setState(() => _checkingSavedSession = false);
  }

  void _handleLoginSubmit() {
    FocusScope.of(context).unfocus();

    if (_useDirectM3uMode) {
      String rawM3u = _m3uController.text.trim();
      if (rawM3u.isEmpty) {
        _showErrorSnackBar('Informe o link M3U completo.');
        return;
      }
      if (!rawM3u.startsWith('http://') && !rawM3u.startsWith('https://')) {
        rawM3u = 'http://$rawM3u';
      }
      _openDashboard(directM3uUrl: rawM3u, rememberSession: _rememberMe);
    } else {
      String dns = _dnsController.text.trim();
      final user = _userController.text.trim();
      final pass = _passController.text.trim();

      if (dns.isEmpty || user.isEmpty || pass.isEmpty) {
        _showErrorSnackBar('Preencha a URL (DNS), o Usuário e a Senha.');
        return;
      }

      if (!dns.startsWith('http://') && !dns.startsWith('https://')) {
        dns = 'http://$dns';
      }
      while (dns.endsWith('/')) {
        dns = dns.substring(0, dns.length - 1);
      }

      _openDashboard(
        dns: dns,
        user: user,
        pass: pass,
        rememberSession: _rememberMe,
      );
    }
  }

  void _openDashboard({
    String dns = '',
    String user = '',
    String pass = '',
    String? directM3uUrl,
    required bool rememberSession,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainDashboard(
          deviceMode: widget.deviceMode,
          serverDns: dns,
          username: user,
          password: pass,
          directM3uUrl: directM3uUrl,
          rememberSession: rememberSession,
        ),
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSavedSession) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) showExitAppConfirmationDialog(context);
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.4,
              colors: [Color(0xFF132238), Color(0xFF08090E)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12151F).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.deviceMode == DeviceMode.tv
                                        ? Icons.tv_rounded
                                        : Icons.smartphone_rounded,
                                    size: 14,
                                    color: const Color(0xFF00E5FF),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.deviceMode == DeviceMode.tv
                                        ? 'Modo TV Android'
                                        : 'Modo Celular',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            TVFocusableItem(
                              autoScroll: false,
                              onSelect: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const DeviceSelectionScreen()),
                                );
                              },
                              builder: (context, isFocused) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isFocused
                                        ? const Color(0xFF00E5FF)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: const Text(
                                  'Trocar Dispositivo',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF00E5FF)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.live_tv_rounded,
                              color: Colors.black, size: 32),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'UNEX VISION',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _useDirectM3uMode
                              ? 'Informe o link M3U completo da sua lista'
                              : 'Selecione cada campo abaixo para preencher',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        if (widget.errorBannerMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.redAccent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.errorBannerMessage!,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (!_useDirectM3uMode) ...[
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _dnsController,
                            label: 'URL / DNS do Servidor',
                            hint: 'Ex: http://cdn4k.club',
                            icon: Icons.dns_rounded,
                            isUrlField: true,
                          ),
                          const SizedBox(height: 10),
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _userController,
                            label: 'Usuário',
                            hint: 'Digite seu usuário',
                            icon: Icons.person_outline_rounded,
                          ),
                          const SizedBox(height: 10),
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _passController,
                            label: 'Senha',
                            hint: 'Digite sua senha',
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                            onSubmitted: _handleLoginSubmit,
                          ),
                        ] else ...[
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _m3uController,
                            label: 'Link M3U Completo',
                            hint: 'http://.../get.php?username=...&password=...',
                            icon: Icons.link_rounded,
                            isUrlField: true,
                            onSubmitted: _handleLoginSubmit,
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: _handleLoginSubmit,
                            builder: (context, isFocused) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00E5FF),
                                    Color(0xFF2979FF)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isFocused
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: isFocused
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF00E5FF)
                                              .withOpacity(0.4),
                                          blurRadius: 14,
                                        )
                                      ]
                                    : null,
                              ),
                              child: const Center(
                                child: Text(
                                  'CONECTAR AGORA',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TVFocusableItem(
                          autoScroll: false,
                          onSelect: () => setState(
                              () => _useDirectM3uMode = !_useDirectM3uMode),
                          builder: (context, isFocused) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isFocused
                                    ? const Color(0xFF00E5FF)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _useDirectM3uMode
                                      ? Icons.vpn_key_outlined
                                      : Icons.link_rounded,
                                  size: 15,
                                  color: Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _useDirectM3uMode
                                      ? 'Usar acesso com URL, Usuário e Senha'
                                      : 'Inserir código / link M3U diretamente',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white54),
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
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA 2: DASHBOARD COM MENU LATERAL (CELULAR) E PAINEL WIDESCREEN (TV)
// =============================================================================
class MainDashboard extends StatefulWidget {
  final DeviceMode deviceMode;
  final String serverDns;
  final String username;
  final String password;
  final String? directM3uUrl;
  final bool rememberSession;

  const MainDashboard({
    super.key,
    required this.deviceMode,
    required this.serverDns,
    required this.username,
    required this.password,
    this.directM3uUrl,
    this.rememberSession = true,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late DeviceMode currentDeviceMode;

  List<StreamItem> allItems = [];
  List<StreamItem> liveItems = [];
  List<StreamItem> movieItems = [];
  List<StreamItem> seriesItems = [];

  List<StreamItem> displayedItems = [];
  Map<String, int> categoryCounts = {};
  List<String> sectionCategories = ['Todas'];

  MainSection activeSection = MainSection.live;
  String selectedCategory = 'Todas';
  String searchQuery = '';

  final Set<String> favoriteIds = {};
  final List<StreamItem> recentItems = [];
  String parentalPin = '0000';
  bool adultUnlocked = false;

  String accountExpDate = '';
  double lastMeasuredSpeedMbps = 18.5;

  bool isLoading = true;
  String errorMessage = '';

  StreamItem? activeItem;
  VideoPlayerController? _previewController;
  bool isPreviewReady = false;
  bool isPreviewError = false;
  bool isMiniPipFloating = false;

  final TextEditingController _searchController = TextEditingController();

  bool get isDirectM3u =>
      widget.directM3uUrl != null && widget.directM3uUrl!.trim().isNotEmpty;

  String get m3uUrl {
    if (isDirectM3u) return widget.directM3uUrl!.trim();
    return '${widget.serverDns}/get.php?username=${widget.username}&password=${widget.password}&type=m3u_plus&output=ts';
  }

  @override
  void initState() {
    super.initState();
    currentDeviceMode = widget.deviceMode;
    applyDeviceOrientation(currentDeviceMode);
    _loadAccountInfoAndPlaylist();
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _switchDeviceMode() async {
    final nextMode = currentDeviceMode == DeviceMode.mobile
        ? DeviceMode.tv
        : DeviceMode.mobile;
    await AppStorage.saveDeviceMode(nextMode);
    await applyDeviceOrientation(nextMode);
    if (!mounted) return;
    setState(() {
      currentDeviceMode = nextMode;
    });
  }

  Future<void> _returnToLoginForEditing({String? errorBanner}) async {
    _previewController?.pause();
    await AppStorage.clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoginGatewayScreen(
          deviceMode: currentDeviceMode,
          allowAutoLogin: false,
          initialDns: widget.serverDns,
          initialUser: widget.username,
          initialPass: widget.password,
          initialM3u: widget.directM3uUrl ?? '',
          initialDirectM3uMode: isDirectM3u,
          errorBannerMessage: errorBanner,
        ),
      ),
    );
  }

  Future<void> _loadAccountInfoAndPlaylist() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    if (!isDirectM3u) {
      _fetchXtreamAccountStatus();
    }

    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse(m3uUrl), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 35));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
        final parsed = await compute(parseM3UAdvanced, bodyText);

        if (parsed.isEmpty) {
          await AppStorage.clearSession();
          if (!mounted) return;
          setState(() {
            errorMessage =
                'Nenhum canal encontrado na lista. Verifique se o Usuário e a Senha estão corretos.';
            isLoading = false;
          });
          return;
        }

        if (widget.rememberSession) {
          if (isDirectM3u) {
            await AppStorage.saveVerifiedSession({
              'mode': 'm3u',
              'm3uUrl': widget.directM3uUrl,
            });
          } else {
            await AppStorage.saveVerifiedSession({
              'mode': 'xtream',
              'dns': widget.serverDns,
              'user': widget.username,
              'pass': widget.password,
            });
          }
        }

        final bytes = response.bodyBytes.length;
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        if (seconds > 0.1 && bytes > 10000) {
          lastMeasuredSpeedMbps =
              ((bytes * 8) / (seconds * 1000000)).clamp(1.0, 300.0);
        }

        final live = <StreamItem>[];
        final movies = <StreamItem>[];
        final series = <StreamItem>[];

        for (final item in parsed) {
          if (item.type == ContentType.live) {
            live.add(item);
          } else if (item.type == ContentType.movie) {
            movies.add(item);
          } else {
            series.add(item);
          }
        }

        if (!mounted) return;
        setState(() {
          allItems = parsed;
          liveItems = live;
          movieItems = movies;
          seriesItems = series;
          activeSection = live.isNotEmpty
              ? MainSection.live
              : movies.isNotEmpty
                  ? MainSection.movie
                  : MainSection.series;
          _rebuildSectionCategories();
          isLoading = false;
        });

        if (live.isNotEmpty && activeItem == null) {
          _startPreview(live.first);
        } else if (parsed.isNotEmpty && activeItem == null) {
          _startPreview(parsed.first);
        }
      } else {
        await AppStorage.clearSession();
        if (!mounted) return;
        setState(() {
          errorMessage =
              'O servidor recusou a conexão (Erro ${response.statusCode}). Verifique seus dados.';
          isLoading = false;
        });
      }
    } catch (_) {
      await AppStorage.clearSession();
      if (!mounted) return;
      setState(() {
        errorMessage =
            'Falha de conexão com o servidor.\nVerifique o endereço DNS/URL e sua internet.';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchXtreamAccountStatus() async {
    try {
      final apiUrl =
          '${widget.serverDns}/player_api.php?username=${widget.username}&password=${widget.password}';
      final res = await http
          .get(Uri.parse(apiUrl), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final userInfo = data['user_info'];
        if (userInfo != null) {
          final exp = userInfo['exp_date']?.toString();
          if (exp != null && exp != 'null' && int.tryParse(exp) != null) {
            final dt =
                DateTime.fromMillisecondsSinceEpoch(int.parse(exp) * 1000);
            if (mounted) {
              setState(() {
                accountExpDate =
                    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  List<StreamItem> _getBaseListForSection(MainSection section) {
    switch (section) {
      case MainSection.live:
        return liveItems;
      case MainSection.movie:
        return movieItems;
      case MainSection.series:
        return seriesItems;
      case MainSection.favorites:
        return allItems.where((i) => favoriteIds.contains(i.id)).toList();
      case MainSection.recents:
        return recentItems;
    }
  }

  String _getSectionTitle(MainSection section) {
    switch (section) {
      case MainSection.live:
        return 'TV ao Vivo';
      case MainSection.movie:
        return 'Filmes';
      case MainSection.series:
        return 'Séries';
      case MainSection.favorites:
        return 'Meus Favoritos';
      case MainSection.recents:
        return 'Assistidos Recentemente';
    }
  }

  void _selectSection(MainSection section) {
    setState(() {
      activeSection = section;
      selectedCategory = 'Todas';
      searchQuery = '';
      _searchController.clear();
      _rebuildSectionCategories();
    });
  }

  void _rebuildSectionCategories() {
    final baseList = _getBaseListForSection(activeSection);
    final Map<String, int> counts = {'Todas': baseList.length};

    for (final item in baseList) {
      counts[item.group] = (counts[item.group] ?? 0) + 1;
    }

    final cats = <String>['Todas'];
    for (final key in counts.keys) {
      if (key != 'Todas') cats.add(key);
    }

    if (!cats.contains(selectedCategory)) {
      selectedCategory = 'Todas';
    }

    categoryCounts = counts;
    sectionCategories = cats;
    _applyCategoryAndSearchFilter(baseList);
  }

  void _applyCategoryAndSearchFilter([List<StreamItem>? sourceList]) {
    final baseList = sourceList ?? _getBaseListForSection(activeSection);

    List<StreamItem> result;
    if (selectedCategory == 'Todas') {
      result = baseList;
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
      displayedItems = result;
    });
  }

  void _onCategoryTap(String category) {
    final lower = category.toLowerCase();
    final isAdultCat =
        lower.contains('adult') || lower.contains('xxx') || lower.contains('+18');

    if (isAdultCat && !adultUnlocked) {
      _promptParentalPin(() {
        setState(() {
          adultUnlocked = true;
          selectedCategory = category;
          _applyCategoryAndSearchFilter();
        });
      });
      return;
    }

    setState(() {
      selectedCategory = category;
      _applyCategoryAndSearchFilter();
    });
  }

  void _promptParentalPin(VoidCallback onSuccess) {
    final pinCtrl = TextEditingController();

    if (currentDeviceMode == DeviceMode.tv) {
      openTVVirtualKeyboard(
        context: context,
        controller: pinCtrl,
        title: 'PIN Controle Parental (Padrão: 0000)',
        isNumericOnly: true,
        onCompleted: () {
          if (pinCtrl.text == parentalPin) {
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
      );
      return;
    }

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
          autofocus: true,
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
    if (recentItems.length > 40) {
      recentItems.removeLast();
    }
  }

  void _toggleFavorite(StreamItem item) {
    setState(() {
      if (favoriteIds.contains(item.id)) {
        favoriteIds.remove(item.id);
      } else {
        favoriteIds.add(item.id);
      }
      if (activeSection == MainSection.favorites) {
        _rebuildSectionCategories();
      }
    });
  }

  List<StreamItem> _findQualityVariants(StreamItem item) {
    if (item.type != ContentType.live) return [item];
    final target = item.cleanName.toLowerCase();
    final variants = liveItems
        .where((i) => i.cleanName.toLowerCase() == target)
        .take(6)
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
    _previewController = VideoPlayerController.networkUrl(
      Uri.parse(item.url),
      httpHeaders: kIptvHeaders,
    );
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
          playlist: displayedItems.isNotEmpty ? displayedItems : liveItems,
          liveChannelsPool: liveItems,
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

  void _showMobileCategoryPickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Categorias de ${_getSectionTitle(activeSection)} (${sectionCategories.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: sectionCategories.length,
                  itemBuilder: (context, index) {
                    final cat = sectionCategories[index];
                    final count = categoryCounts[cat] ?? 0;
                    final isSelected = cat == selectedCategory;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      selected: isSelected,
                      selectedTileColor:
                          const Color(0xFF00E5FF).withOpacity(0.18),
                      leading: Icon(
                        Icons.folder_outlined,
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white54,
                      ),
                      title: Text(
                        cat,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _onCategoryTap(cat);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleDashboardBackButton() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
      return;
    }
    if (searchQuery.isNotEmpty) {
      setState(() {
        searchQuery = '';
        _searchController.clear();
        _applyCategoryAndSearchFilter();
      });
      return;
    }
    if (selectedCategory != 'Todas') {
      setState(() {
        selectedCategory = 'Todas';
        _applyCategoryAndSearchFilter();
      });
      return;
    }
    showExitAppConfirmationDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final isTVMode = currentDeviceMode == DeviceMode.tv;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleDashboardBackButton();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: isTVMode ? null : _buildMobileSideDrawer(),
        body: SafeArea(
          child: Stack(
            children: [
              isLoading
                  ? _buildLoadingState()
                  : errorMessage.isNotEmpty
                      ? _buildErrorState()
                      : isTVMode
                          ? _buildTVDedicatedInterface()
                          : _buildMobileDedicatedInterface(),
              if (isMiniPipFloating && activeItem != null)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Material(
                    elevation: 16,
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF12151F),
                    child: Container(
                      width: isTVMode ? 300 : 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFF00E5FF), width: 1.5),
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
                                horizontal: 8, vertical: 4),
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
                                TVIconButton(
                                  icon: Icons.open_in_full_rounded,
                                  size: 16,
                                  color: const Color(0xFF00E5FF),
                                  onPressed: () {
                                    setState(() => isMiniPipFloating = false);
                                    _openFullScreen(activeItem!);
                                  },
                                ),
                                TVIconButton(
                                  icon: Icons.close_rounded,
                                  size: 16,
                                  onPressed: () {
                                    _previewController?.pause();
                                    setState(() => isMiniPipFloating = false);
                                  },
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
      ),
    );
  }

  // ===========================================================================
  // MENU LATERAL (DRAWER) DO CELULAR (MANTIDO INTACTO)
  // ===========================================================================
  Widget _buildMobileSideDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0C0E16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF14243B), Color(0xFF0C0E16)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF00E5FF).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.analytics_outlined,
                            size: 15, color: Color(0xFF00E5FF)),
                        const SizedBox(width: 6),
                        Text(
                          'Total da Lista: ${allItems.length} conteúdos',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (accountExpDate.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Assinatura válida até: $accountExpDate',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                'ESCOLHA O TIPO DE CONTEÚDO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white38,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _buildDrawerItem(
                    title: 'TV ao Vivo',
                    count: liveItems.length,
                    icon: Icons.live_tv_rounded,
                    selected: activeSection == MainSection.live,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSection(MainSection.live);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Filmes',
                    count: movieItems.length,
                    icon: Icons.movie_creation_outlined,
                    selected: activeSection == MainSection.movie,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSection(MainSection.movie);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Séries',
                    count: seriesItems.length,
                    icon: Icons.video_library_outlined,
                    selected: activeSection == MainSection.series,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSection(MainSection.series);
                    },
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  _buildDrawerItem(
                    title: 'Meus Favoritos',
                    count: favoriteIds.length,
                    icon: Icons.star_rounded,
                    selected: activeSection == MainSection.favorites,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSection(MainSection.favorites);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Assistidos Recentemente',
                    count: recentItems.length,
                    icon: Icons.history_rounded,
                    selected: activeSection == MainSection.recents,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSection(MainSection.recents);
                    },
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  ListTile(
                    leading: const Icon(Icons.speed_rounded,
                        color: Color(0xFF00E5FF)),
                    title: const Text('Teste de Velocidade',
                        style: TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _showSpeedTestModal();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.tv_rounded, color: Colors.white70),
                    title: const Text('Mudar para Modo TV Android',
                        style: TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _switchDeviceMode();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent),
                    title: const Text('Trocar Lista / Sair',
                        style:
                            TextStyle(fontSize: 14, color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(context);
                      _returnToLoginForEditing();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required String title,
    required int count,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  const Color(0xFF00E5FF).withOpacity(0.22),
                  const Color(0xFF2979FF).withOpacity(0.08),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? const Color(0xFF00E5FF).withOpacity(0.5)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? const Color(0xFF00E5FF) : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E5FF) : Colors.black45,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.black : const Color(0xFF00E5FF),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // INTERFACE DEDICADA PARA CELULAR ANDROID (MANTIDA INTACTA)
  // ===========================================================================
  Widget _buildMobileDedicatedInterface() {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final sectionTitle = _getSectionTitle(activeSection);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1018),
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Abrir Menu Lateral',
                icon: const Icon(Icons.menu_rounded,
                    color: Color(0xFF00E5FF), size: 26),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$selectedCategory • ${displayedItems.length} conteúdos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Teste de Velocidade',
                icon: const Icon(Icons.speed_rounded,
                    color: Color(0xFF00E5FF), size: 22),
                onPressed: _showSpeedTestModal,
              ),
              IconButton(
                tooltip: 'Atualizar Lista',
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 21),
                onPressed: _loadAccountInfoAndPlaylist,
              ),
            ],
          ),
        ),
        if (activeItem != null && !isMiniPipFloating && !isKeyboardOpen)
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
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.circle,
                            color: Colors.redAccent, size: 8),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            activeItem!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () =>
                              setState(() => isMiniPipFloating = true),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                                Icons.picture_in_picture_alt_rounded,
                                color: Color(0xFF00E5FF),
                                size: 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _openFullScreen(activeItem!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen_rounded,
                                    color: Colors.black, size: 18),
                                SizedBox(width: 4),
                                Text(
                                  'Tela Cheia',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
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
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
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
                      _applyCategoryAndSearchFilter();
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar em $sectionTitle...',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: Colors.white38),
                      prefixIcon: const Icon(Icons.search,
                          color: Color(0xFF00E5FF), size: 18),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                searchQuery = '';
                                _applyCategoryAndSearchFilter();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _showMobileCategoryPickerModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12151F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_list_rounded,
                          color: Color(0xFF00E5FF), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Categorias (${sectionCategories.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: sectionCategories.length,
            itemBuilder: (context, index) {
              final cat = sectionCategories[index];
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
                    fontSize: 11,
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
          child: displayedItems.isEmpty
              ? const Center(
                  child: Text('Nenhum conteúdo encontrado nesta categoria.',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: displayedItems.length,
                  itemBuilder: (context, index) {
                    final item = displayedItems[index];
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        onTap: () => _startPreview(item),
                        leading: _buildLogoWidget(item.logo, size: 44),
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
                                size: 20,
                              ),
                              onPressed: () => _toggleFavorite(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.fullscreen_rounded,
                                  color: Color(0xFF00E5FF), size: 22),
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

  // ===========================================================================
  // INTERFACE DEDICADA PARA TV ANDROID / TV BOX (100% CONTROLE REMOTO)
  // ===========================================================================
  Widget _buildTVDedicatedInterface() {
    return Row(
      children: [
        // 1. MENU LATERAL PRINCIPAL DA TV
        Container(
          width: 210,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0C12),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        const Expanded(
                          child: Text(
                            'UNEX VISION',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lista: ${allItems.length} itens',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  children: [
                    _buildTVSideNavButton(
                      label: 'TV ao Vivo',
                      count: liveItems.length,
                      icon: Icons.live_tv_rounded,
                      selected: activeSection == MainSection.live,
                      autofocus: true,
                      onSelect: () => _selectSection(MainSection.live),
                    ),
                    _buildTVSideNavButton(
                      label: 'Filmes',
                      count: movieItems.length,
                      icon: Icons.movie_creation_outlined,
                      selected: activeSection == MainSection.movie,
                      onSelect: () => _selectSection(MainSection.movie),
                    ),
                    _buildTVSideNavButton(
                      label: 'Séries',
                      count: seriesItems.length,
                      icon: Icons.video_library_outlined,
                      selected: activeSection == MainSection.series,
                      onSelect: () => _selectSection(MainSection.series),
                    ),
                    const Divider(color: Colors.white10, height: 18),
                    _buildTVSideNavButton(
                      label: 'Favoritos',
                      count: favoriteIds.length,
                      icon: Icons.star_rounded,
                      selected: activeSection == MainSection.favorites,
                      onSelect: () => _selectSection(MainSection.favorites),
                    ),
                    _buildTVSideNavButton(
                      label: 'Recentes',
                      count: recentItems.length,
                      icon: Icons.history_rounded,
                      selected: activeSection == MainSection.recents,
                      onSelect: () => _selectSection(MainSection.recents),
                    ),
                    const Divider(color: Colors.white10, height: 18),
                    _buildTVSideActionButton(
                      label: 'Velocidade',
                      icon: Icons.speed_rounded,
                      color: const Color(0xFF00E5FF),
                      onSelect: _showSpeedTestModal,
                    ),
                    _buildTVSideActionButton(
                      label: 'Atualizar Lista',
                      icon: Icons.refresh_rounded,
                      onSelect: _loadAccountInfoAndPlaylist,
                    ),
                    _buildTVSideActionButton(
                      label: 'Modo Celular',
                      icon: Icons.smartphone_rounded,
                      onSelect: _switchDeviceMode,
                    ),
                    _buildTVSideActionButton(
                      label: 'Trocar Conta',
                      icon: Icons.logout_rounded,
                      color: Colors.redAccent,
                      onSelect: () => _returnToLoginForEditing(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. COLUNA DE CATEGORIAS DO TIPO SELECIONADO
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: Color(0xFF0D0F17),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                child: Text(
                  'CATEGORIAS (${sectionCategories.length})',
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
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: sectionCategories.length,
                  itemBuilder: (context, index) {
                    final cat = sectionCategories[index];
                    final count = categoryCounts[cat] ?? 0;
                    final isSelected = cat == selectedCategory;

                    return TVFocusableItem(
                      onSelect: () => _onCategoryTap(cat),
                      builder: (context, isFocused) => Container(
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

        // 3. GRADE DE CONTEÚDOS + BUSCA POR TECLADO VIRTUAL DE TV + PREVIEW
        Expanded(
          child: Column(
            children: [
              // Barra Superior da TV (Botão de Busca com Teclado Virtual de TV)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1018),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TVFocusableItem(
                        autoScroll: false,
                        onSelect: () {
                          openTVVirtualKeyboard(
                            context: context,
                            controller: _searchController,
                            title:
                                'Pesquisar em ${_getSectionTitle(activeSection)}',
                            onChanged: (val) {
                              searchQuery = val;
                              _applyCategoryAndSearchFilter();
                            },
                          );
                        },
                        builder: (context, isFocused) => Container(
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
                                      ? 'Aperte OK para pesquisar em ${_getSectionTitle(activeSection)}...'
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
                              if (searchQuery.isNotEmpty)
                                const Text(
                                  '(OK p/ alterar)',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.white54),
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
                        onSelect: () {
                          setState(() {
                            searchQuery = '';
                            _searchController.clear();
                            _applyCategoryAndSearchFilter();
                          });
                        },
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
                            'Limpar Busca',
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
                      '${displayedItems.length} itens',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
                    // Grade de Canais / Filmes / Séries
                    Expanded(
                      child: displayedItems.isEmpty
                          ? const Center(
                              child: Text('Nenhum conteúdo encontrado.',
                                  style: TextStyle(color: Colors.white54)),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(14),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisExtent: 86,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: displayedItems.length,
                              itemBuilder: (context, index) {
                                final item = displayedItems[index];
                                final isPlaying = activeItem?.id == item.id;
                                final isFav = favoriteIds.contains(item.id);

                                return TVFocusableItem(
                                  onSelect: () => _startPreview(item),
                                  builder: (context, isFocused) =>
                                      AnimatedScale(
                                    scale: isFocused ? 1.04 : 1.0,
                                    duration: const Duration(milliseconds: 120),
                                    child: Container(
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
                                          _buildLogoWidget(item.logo, size: 44),
                                          const SizedBox(width: 8),
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
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    _buildQualityBadge(
                                                        item.qualityTag),
                                                    const SizedBox(width: 4),
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
                                          if (isFav)
                                            const Icon(Icons.star_rounded,
                                                color: Colors.amber, size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    // Painel Direito de Preview da TV
                    Container(
                      width: 280,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0A0C12),
                        border: Border(left: BorderSide(color: Colors.white10)),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: Colors.black,
                                child: _buildMiniVideoWidget(),
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
                            const SizedBox(height: 10),
                            _buildQuickQualityRow(activeItem!),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TVFocusableItem(
                                autoScroll: false,
                                onSelect: () => _openFullScreen(activeItem!),
                                builder: (context, isFocused) => Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
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
                                onSelect: () => _toggleFavorite(activeItem!),
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
      builder: (context, isFocused) => Container(
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

  Widget _buildQuickQualityRow(StreamItem current) {
    final variants = _findQualityVariants(current);
    if (variants.length <= 1) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: variants.map((v) {
        final selected = v.id == current.id;
        return TVFocusableItem(
          autoScroll: false,
          onSelect: () => _startPreview(v),
          builder: (context, isFocused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:
                  selected ? const Color(0xFF00E5FF) : const Color(0xFF151924),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isFocused ? Colors.white : Colors.white12,
              ),
            ),
            child: Text(
              v.qualityTag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
          ),
        );
      }).toList(),
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
            style: TextStyle(fontSize: 11, color: Colors.white54)),
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

  Widget _buildLogoWidget(String url, {double size = 44}) {
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00E5FF)),
          const SizedBox(height: 18),
          const Text('CARREGANDO CONTEÚDOS DA LISTA...'),
          const SizedBox(height: 20),
          TVFocusableItem(
            autofocus: true,
            autoScroll: false,
            onSelect: () => _returnToLoginForEditing(),
            builder: (context, isFocused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF151924),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFocused ? const Color(0xFF00E5FF) : Colors.white24,
                ),
              ),
              child: const Text('Cancelar e Voltar ao Login',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.redAccent, size: 50),
              const SizedBox(height: 14),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  TVFocusableItem(
                    autofocus: true,
                    autoScroll: false,
                    onSelect: () => _returnToLoginForEditing(
                      errorBanner:
                          'Corrija os dados de acesso abaixo e tente novamente.',
                    ),
                    builder: (context, isFocused) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
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
                      child: const Text(
                        'CORRIGIR DADOS DE LOGIN',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  TVFocusableItem(
                    autoScroll: false,
                    onSelect: _loadAccountInfoAndPlaylist,
                    builder: (context, isFocused) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151924),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused
                              ? const Color(0xFF00E5FF)
                              : Colors.white24,
                        ),
                      ),
                      child: const Text('Tentar Novamente',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA 3: PLAYER EM TELA CHEIA COM CONTROLE REMOTO E PROTEÇÃO DO BOTÃO VOLTAR
// =============================================================================
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
// WIDGETS NAVEGÁVEIS POR CONTROLE REMOTO E TOQUE
// =============================================================================
class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final bool autoScroll;
  final bool autofocus;

  const TVFocusableItem({
    super.key,
    required this.onSelect,
    required this.builder,
    this.autoScroll = true,
    this.autofocus = false,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (focused) {
        setState(() => _isFocused = focused);
        if (focused && widget.autoScroll && mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
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

  const TVIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = Colors.white70,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      autoScroll: false,
      onSelect: onPressed,
      builder: (context, isFocused) => Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: isFocused
              ? const Color(0xFF00E5FF).withOpacity(0.2)
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
    );
  }
}

// =============================================================================
// PARSER AVANÇADO DE LISTAS M3U PLUS
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
