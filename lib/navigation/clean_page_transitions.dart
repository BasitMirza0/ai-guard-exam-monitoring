import 'package:flutter/material.dart';

final appRouteObserver = RouteObserver<ModalRoute<dynamic>>();

/// Opaque entrances, with no outgoing fade, shadow or secondary-page motion.
/// Back removes the route on the next frame rather than compositing it on Home.
class CleanPageTransitionsBuilder extends PageTransitionsBuilder {
  const CleanPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || MediaQuery.disableAnimationsOf(context)) return child;
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }
}
