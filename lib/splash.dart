import 'package:flutter/material.dart';

import 'auth.dart';

/// شاشة البداية: لوجو RentPal يظهر بحركة ناعمة ثم تنسحب الشاشة كلها
/// (واللوجو معها) لأعلى لتكشف شاشة الدخول.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  // 0 → 0.45 : ظهور اللوجو   |  0.45 → 0.65 : ثبات   |  0.65 → 1 : انسحاب لأعلى
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final Animation<double> _scale = Tween(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
          parent: _c, curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack)));
  late final Animation<double> _fade = CurvedAnimation(
      parent: _c, curve: const Interval(0.0, 0.3, curve: Curves.easeOut));
  late final Animation<double> _slide = CurvedAnimation(
      parent: _c, curve: const Interval(0.65, 1.0, curve: Curves.easeInOutCubic));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.of(context).size.height;
    return Stack(
      children: [
        const LoginScreen(),
        if (!_done)
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Transform.translate(
              offset: Offset(0, -h * _slide.value),
              child: Material(
                color: Colors.white,
                child: SizedBox.expand(
                  child: Center(
                    child: FadeTransition(
                      opacity: _fade,
                      child: ScaleTransition(
                        scale: _scale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [
                                  BoxShadow(
                                      color: cs.primary.withAlpha(70),
                                      blurRadius: 28,
                                      offset: const Offset(0, 12)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(32),
                                child: Image.asset('assets/logo.png',
                                    width: 140, height: 140, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text('RentPal',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                    color: cs.primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
