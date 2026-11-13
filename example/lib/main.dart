import 'package:flutter/material.dart';
import 'package:morphicons/morphicons.dart';

void main() => runApp(const MorphiconsApp());

const _ink = Color(0xFF101A19);
const _muted = Color(0xFF9AA7A1);
const _acid = Color(0xFFD2F578);
const _panel = Color(0xFF182320);
const _menu = 'M4 6h16M4 12h16M4 18h16';
const _close = 'M18 6 6 18M6 6l12 12';
const _plus = 'M12 4v16M4 12h16';
const _check = 'M20 6 9 17l-5-5';
const _arrow = 'M4 12h16M12 4l8 8-8 8';
const _down = 'M12 4v16M4 12l8 8 8-8';
const _circle = 'M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z';
const _square = 'M4 4H20V20H4Z';
const _diamond = 'M12 4 20 12 12 20 4 12Z';
const _sun =
    'M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0Z M12 2v2M12 20v2M2 12h2M20 12h2M4.93 4.93l1.42 1.42M17.65 17.65l1.42 1.42M4.93 19.07l1.42-1.42M17.65 6.35l1.42-1.42';
const _moon = 'M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z';
const _ring = [
  IconNode('path', {'d': 'M2 2H22V22H2Z M7 7V17H17V7Z', 'fill': 'currentColor'})
];
const _disc = [
  IconNode('circle', {'cx': 12, 'cy': 12, 'r': 9, 'fill': 'currentColor'})
];

class _Pair {
  const _Pair(this.title, this.detail, this.a, this.b);
  final String title;
  final String detail;
  final IconInput a;
  final IconInput b;
}

const _pairs = [
  _Pair('Menu / Close', 'Minimal rotation', _menu, _close),
  _Pair('Right / Down', 'Rigid block · 90°', _arrow, _down),
  _Pair('Plus / Close', 'Emergent 45° turn', _plus, _close),
  _Pair('Close / Check', 'Unequal subpaths', _close, _check),
  _Pair('Circle / Square', 'Curves meet corners', _circle, _square),
  _Pair('Square / Diamond', 'Closed correspondence', _square, _diamond),
  _Pair('Sun / Moon', 'Surjective matching', _sun, _moon),
  _Pair('Ring / Disc', 'Filled topology', _ring, _disc),
];

class MorphiconsApp extends StatelessWidget {
  const MorphiconsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'morphicons — Native motion lab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _ink,
          colorScheme: const ColorScheme.dark(
              primary: _acid,
              secondary: _acid,
              onSecondary: _ink,
              surface: _panel),
          useMaterial3: true,
        ),
        home: const _MotionLab(),
      );
}

class _MotionLab extends StatefulWidget {
  const _MotionLab();
  @override
  State<_MotionLab> createState() => _MotionLabState();
}

class _MotionLabState extends State<_MotionLab> {
  final _controller = MorphController(icon: _menu);
  var _selected = 0;
  var _atEnd = false;
  double? _scrub;
  var _preset = 'Snappy';
  var _reduce = false;

  SpringConfig get _spring => switch (_preset) {
        'Smooth' => SpringConfig.smooth,
        'Bouncy' => SpringConfig.bouncy,
        _ => SpringConfig.snappy,
      };

  void _play() {
    setState(() {
      _scrub = null;
      _atEnd = !_atEnd;
    });
    _controller.morphTo(_atEnd ? _pairs[_selected].b : _pairs[_selected].a);
  }

  void _select(int index) {
    setState(() {
      _selected = index;
      _atEnd = false;
      _scrub = null;
    });
    _controller.set(_pairs[index].a);
  }

  @override
  Widget build(BuildContext context) {
    final pair = _pairs[_selected];
    return Scaffold(
        body: SafeArea(
            child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  MorphIcon(icon: _plus, color: _acid, size: 22),
                  SizedBox(width: 12),
                  Text('morphicons',
                      style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1)),
                ]),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF435044)),
                        borderRadius: BorderRadius.circular(30)),
                    child: const Text('FLUTTER / DART',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 1.4,
                            color: _acid))),
              ]),
          const SizedBox(height: 58),
          const Text('NATIVE MOTION LAB   /   01',
              style: TextStyle(
                  color: _acid,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 2)),
          const SizedBox(height: 16),
          const Text('Different shapes.\nOne continuous gesture.',
              style: TextStyle(
                  fontSize: 46,
                  height: 1.08,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 18),
          const Text(
              'Real geometry. Emergent rotation. Interruptible spring physics.\nNo JavaScript bridge, no hand-drawn transition frames.',
              style: TextStyle(color: _muted, height: 1.6, fontSize: 14)),
          const SizedBox(height: 36),
          LayoutBuilder(builder: (context, constraints) {
            final stage = _stage(pair);
            final controls = _controls();
            return constraints.maxWidth >= 760
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: stage),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: controls),
                  ])
                : Column(
                    children: [stage, const SizedBox(height: 20), controls]);
          }),
          const SizedBox(height: 44),
          const Wrap(spacing: 24, runSpacing: 8, children: [
            Text('THE PAIR LIBRARY',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 2,
                    color: _muted)),
            Text('08 experiments',
                style: TextStyle(fontSize: 11, color: _muted))
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 4
                : constraints.maxWidth >= 510
                    ? 2
                    : 1;
            return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                    _pairs.length,
                    (i) => SizedBox(
                        width: (constraints.maxWidth - 12 * (columns - 1)) /
                            columns,
                        child: _pairCard(i))));
          }),
          const SizedBox(height: 42),
          const Divider(color: Color(0xFF2C3831)),
          const SizedBox(height: 16),
          const Text(
              '24 × 24 grid  /  Native Canvas  /  Zero third-party runtime dependencies',
              style: TextStyle(
                  color: _muted,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.8)),
        ]),
      )),
    )));
  }

  Widget _stage(_Pair pair) => Container(
        height: 350,
        decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2C3831))),
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned(
              top: 22,
              left: 24,
              child: Text(pair.title.toUpperCase(),
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1.3,
                      color: _muted))),
          Center(
              child: MorphIcon(
                  controller: _controller,
                  size: 126,
                  color: _acid,
                  strokeWidth: 1.7,
                  spring: _spring,
                  reducedMotion:
                      _reduce ? ReducedMotion.always : ReducedMotion.never,
                  label: '${pair.title} animated icon')),
          Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Row(children: [
                Expanded(
                    child: Text(pair.detail,
                        style: const TextStyle(color: _muted, fontSize: 12))),
                const SizedBox(width: 12),
                ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => Text(
                        't ${_controller.progress.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: _acid,
                            fontFamily: 'monospace',
                            fontSize: 12))),
              ])),
        ]),
      );

  Widget _controls() => Material(
        color: _panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF2C3831))),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('MAKE IT MOVE',
                  style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontFamily: 'monospace')),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: _play,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label:
                          Text(_atEnd ? 'Morph backward' : 'Morph forward'))),
              const SizedBox(height: 24),
              const Text('Spring character', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                  spacing: 6,
                  children: ['Smooth', 'Snappy', 'Bouncy']
                      .map((preset) => ChoiceChip(
                          label: Text(preset,
                              style: const TextStyle(fontSize: 12)),
                          selected: _preset == preset,
                          onSelected: (_) => setState(() => _preset = preset),
                          showCheckmark: false))
                      .toList()),
              const SizedBox(height: 20),
              const Text('Scrub the geometry', style: TextStyle(fontSize: 13)),
              Slider(
                  value: _scrub ?? (_atEnd ? 1 : 0),
                  label: (_scrub ?? (_atEnd ? 1 : 0)).toStringAsFixed(2),
                  onChanged: (value) {
                    setState(() => _scrub = value);
                    _controller.seek(_pairs[_selected].b, value,
                        from: _pairs[_selected].a);
                  }),
              const Text('Try 0.25 · 0.50 · 0.75 — every frame matters.',
                  style: TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 12),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Jump to target',
                      style: TextStyle(fontSize: 12)),
                  subtitle: const Text('Reduced motion: always',
                      style: TextStyle(color: _muted, fontSize: 10)),
                  value: _reduce,
                  onChanged: (value) => setState(() => _reduce = value)),
            ])),
      );

  Widget _pairCard(int index) {
    final pair = _pairs[index];
    final selected = index == _selected;
    return Material(
        color: selected ? const Color(0xFF263222) : _panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side:
                BorderSide(color: selected ? _acid : const Color(0xFF2C3831))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _select(index),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      MorphIcon(
                          icon: pair.a,
                          color: selected ? _acid : Colors.white70,
                          size: 26),
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Text('→', style: TextStyle(color: _muted))),
                      MorphIcon(
                          icon: pair.b,
                          color: selected ? _acid : Colors.white70,
                          size: 26),
                      const Spacer(),
                      Text('0${index + 1}',
                          style: const TextStyle(
                              color: _muted,
                              fontFamily: 'monospace',
                              fontSize: 10))
                    ]),
                    const SizedBox(height: 24),
                    Text(pair.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(pair.detail,
                        style: const TextStyle(color: _muted, fontSize: 11)),
                  ])),
        ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF26312B)
      ..strokeWidth = 0.5;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
