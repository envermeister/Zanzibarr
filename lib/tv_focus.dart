import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV (D-pad) gezintisi için metin alanı odak düğümü üretir.
///
/// Tek satırlı metin alanlarında yukarı/aşağı oklar varsayılan olarak alanın
/// kendi kısayolları tarafından tüketilir (imleç başa/sona gider) ve odak
/// alandan çıkamaz — Android TV kumandasında kullanıcı ilk alanda takılı
/// kalır (GitHub issue #4). Bu düğüm:
///
/// - yukarı/aşağı oku her zaman yön gezintisine çevirir,
/// - sol/sağ oku yalnızca imleç metnin kenarındaysa (veya seçim yoksa)
///   gezintiye bırakır; metin ortasında imleç hareketi korunur.
///
/// [focusOnRightEdge]: imleç metin sonundayken sağ oka basılınca doğrudan
/// odaklanacak düğüm (ör. alanın yanındaki "parolayı göster" simgesi). Bu
/// simgeler `dpadFieldActionFocusNode` ile gezinti adaylığından çıkarıldığı
/// için geometrik yön gezintisi onlara asla ulaşamaz; odak buradan açıkça
/// verilir.
///
/// IME (ekran klavyesi) açıkken tuşlar zaten sistemin klavyesine gider, bu
/// işleyici yalnızca "alan odaklı, klavye kapalı" durumunda devrededir.
FocusNode dpadTraversalFocusNode(
  TextEditingController controller, {
  FocusNode Function()? focusOnRightEdge,
}) => FocusNode(
  onKeyEvent: (node, event) => _handleDpadArrow(
    node,
    event,
    controller,
    focusOnRightEdge: focusOnRightEdge,
  ),
);

/// Metin alanına bitişik eylem simgesi (ör. parola gözü) için odak düğümü.
///
/// `skipTraversal: true` düğümü sekme ve yön gezintisinin aday listesinden
/// çıkarır: simge alanla aynı yatay bantta ama dikeyde alanın metin
/// bölgesinden daha yüksekte durduğu için geometrik gezinti bir üst
/// satırdan inerken alanı atlayıp simgeyi seçiyordu (issue #4). Simgeye tek
/// geçiş yolu alandayken imleç metin sonunda sağ oka basmaktır
/// (`dpadTraversalFocusNode(focusOnRightEdge: ...)`). Simgedeyken sol ok
/// alana geri döner (imleç sona alınır), yukarı/aşağı ok gezintiyi sürdürür.
FocusNode dpadFieldActionFocusNode({
  required TextEditingController controller,
  required FocusNode fieldNode,
}) => FocusNode(
  skipTraversal: true,
  onKeyEvent: (node, event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction != null) {
      return node.focusInDirection(direction)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      fieldNode.requestFocus();
      // İmleç sona alınır: tekrar sağ ok kenardan simgeye çıkabilir.
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },
);

KeyEventResult _handleDpadArrow(
  FocusNode node,
  KeyEvent event,
  TextEditingController controller, {
  FocusNode Function()? focusOnRightEdge,
}) {
  // Kumandada basılı tutma tekrar (repeat) olayları da gezintiyi sürdürür.
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final direction = switch (event.logicalKey) {
    LogicalKeyboardKey.arrowUp => TraversalDirection.up,
    LogicalKeyboardKey.arrowDown => TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft when _caretAtStart(controller) =>
      TraversalDirection.left,
    LogicalKeyboardKey.arrowRight when _caretAtEnd(controller) =>
      TraversalDirection.right,
    _ => null,
  };
  if (direction == null) return KeyEventResult.ignored;
  // Sağ kenarda açıkça bağlanmış bir komşu varsa (ör. parola gözü) geometriye
  // güvenmeden doğrudan ona geç.
  if (direction == TraversalDirection.right && focusOnRightEdge != null) {
    final target = focusOnRightEdge();
    if (target.canRequestFocus) {
      target.requestFocus();
      return KeyEventResult.handled;
    }
  }
  // Kenardaysa (gidilecek kontrol yoksa) tuşu serbest bırak; imleç
  // davranışı veya üst katman kısayolları devralır.
  return node.focusInDirection(direction)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

/// Gezintiyle odaklanılan alanda seçim henüz yoktur (-1); kenar kabul edilir.
bool _caretAtStart(TextEditingController controller) {
  final selection = controller.selection;
  return !selection.isValid ||
      (selection.isCollapsed && selection.start <= 0);
}

bool _caretAtEnd(TextEditingController controller) {
  final selection = controller.selection;
  return !selection.isValid ||
      (selection.isCollapsed && selection.end >= controller.text.length);
}

/// Directional (TV) modunda metin alanını yalnız OK ile düzenlemeye açar.
///
/// Flutter, Android TV'de `Semantics.onFocus` sırasında ekran klavyesini
/// kendiliğinden açabilir. Alan salt-okunur başlar; D-pad OK veya dokunma
/// düzenlemeyi ve klavyeyi açar. Odaktan ayrılınca alan yeniden salt-okunur
/// olur, böylece sonraki D-pad gezintisinde klavye kendiliğinden açılmaz.
/// Telefon/masaüstü davranışı değiştirilmez.
class TvDpadTextField extends StatefulWidget {
  const TvDpadTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.decoration,
    this.textInputAction,
    this.keyboardType,
    this.autocorrect = true,
    this.validator,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autofillHints,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final InputDecoration? decoration;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final bool enableSuggestions;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final bool autofocus;

  @override
  State<TvDpadTextField> createState() => _TvDpadTextFieldState();
}

class _TvDpadTextFieldState extends State<TvDpadTextField> {
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant TvDpadTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  bool get _directionalNavigation {
    if (MediaQuery.navigationModeOf(context) == NavigationMode.directional) {
      return true;
    }
    // Android TV does not consistently publish NavigationMode.directional.
    // A D-pad key switches Flutter to traditional highlights before dispatch;
    // screens and lazily-built fields then start in read-only navigation mode.
    return defaultTargetPlatform == TargetPlatform.android &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.focusNode.hasFocus) _editing = false;
    });
  }

  void _stopEditing() {
    if (_editing) setState(() => _editing = false);
  }

  void _startEditing() {
    if (!widget.enabled || !_directionalNavigation) return;
    if (_editing) {
      widget.focusNode.context
          ?.findAncestorStateOfType<EditableTextState>()
          ?.requestKeyboard();
      return;
    }
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.requestFocus();
      widget.focusNode.context
          ?.findAncestorStateOfType<EditableTextState>()
          ?.requestKeyboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final directional = _directionalNavigation;
    final field = TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      textInputAction: widget.textInputAction,
      keyboardType: widget.keyboardType,
      autocorrect: widget.autocorrect,
      validator: widget.validator,
      obscureText: widget.obscureText,
      enableSuggestions: widget.enableSuggestions,
      autofillHints: widget.autofillHints,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      readOnly: directional && !_editing,
      onTap: directional ? _startEditing : null,
      onFieldSubmitted: (value) {
        widget.onFieldSubmitted?.call(value);
        if (directional) _stopEditing();
      },
    );
    if (!directional) return field;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _startEditing();
            return null;
          },
        ),
      },
      child: field,
    );
  }
}
