import 'dart:async';

import 'package:flutter/material.dart';

/// انتقال سلس بين الشاشات (تلاشي + انزلاق خفيف) يعمل بنعومة على شاشات 60/90/120 هرتز.
/// كل الحركات مبنية على الزمن (وليس على عدد الإطارات) فتتكيّف تلقائياً مع معدل التحديث.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final enter = animation.drive(
      Tween<Offset>(begin: Offset(rtl ? -0.07 : 0.07, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    final fade = animation.drive(CurveTween(curve: Curves.easeOut));
    // الشاشة التي تحت تتحرك قليلاً عند فتح شاشة جديدة فوقها
    final exit = secondaryAnimation.drive(
      Tween<Offset>(begin: Offset.zero, end: Offset(rtl ? 0.03 : -0.03, 0))
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    return SlideTransition(
      position: exit,
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(position: enter, child: child),
      ),
    );
  }
}

/// تمرير ناعم بارتداد خفيف في نهاية القوائم (بدون وهج الأندرويد)
class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// ظهور تدريجي (تلاشي + صعود خفيف). مع [index] يظهر العناصر واحداً بعد الآخر.
/// العناصر ذات الترتيب 10 فأكثر تظهر مباشرة لتبقى القوائم الطويلة سريعة.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final double dy;
  final Duration duration;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.dy = 16,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.index >= 10) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 45 * widget.index);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _a.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - _a.value) * widget.dy),
            child: child,
          ),
        ),
      );
}
