import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'brand_mark.dart';

/// Startup runs alongside one short reveal. Ready content is painted behind an
/// opaque cover before that cover is removed, avoiding a blank intermediate frame.
class AppLaunch extends StatefulWidget {
  const AppLaunch({super.key, required this.initialize, required this.builder});
  final Future<void> Function() initialize;
  final Widget Function(BuildContext, VoidCallback) builder;

  @override
  State<AppLaunch> createState() => _AppLaunchState();
}

class _AppLaunchState extends State<AppLaunch> with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed && mounted) setState(() {});
  });

  void _finishLaunch() {
    if (!_destinationReady ||
        !_reveal.isCompleted ||
        _exit.isAnimating ||
        _exit.isCompleted) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _exit.value = 1;
    } else {
      _exit.forward();
    }
  }

  bool _started = false, _initialized = false, _destinationReady = false;
  Object? _error;
  Widget? _content;

  @override
  void initState() {
    super.initState();
    _initialize();
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {});
        _finishLaunch();
      }
    });
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
    }
  }

  void _ready() {
    if (mounted && !_destinationReady) {
      setState(() => _destinationReady = true);
      _finishLaunch();
    }
  }

  @override
  void dispose() {
    _exit.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSplash = !_exit.isCompleted;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_initialized) _content ??= widget.builder(context, _ready),
        if (showSplash)
          FadeTransition(
            opacity: ReverseAnimation(_exit),
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _curve,
                              builder:
                                  (_, child) => Transform.translate(
                                    offset: Offset(0, 46 * (1 - _curve.value)),
                                    child: child,
                                  ),
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 1,
                                  end: 1.02,
                                ).animate(_curve),
                                child: const BrandMark(size: 96),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FadeTransition(
                              opacity: _curve,
                              child: const Column(
                                children: [
                                  Text(
                                    'AI Guard',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Confidence in every exam.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 28),
                              const Text(
                                'Unable to start. Please try again.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () {
                                  setState(() => _error = null);
                                  _initialize();
                                },
                                child: const Text('Try again'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_error == null)
                      const Positioned(
                        bottom: 32,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SizedBox(
                            width: 48,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Signals after the destination has actually rendered, rather than when its
/// asynchronous authentication/profile request merely finishes.
class LaunchDestination extends StatefulWidget {
  const LaunchDestination({
    super.key,
    required this.onReady,
    required this.child,
  });
  final VoidCallback onReady;
  final Widget child;
  @override
  State<LaunchDestination> createState() => _LaunchDestinationState();
}

class _LaunchDestinationState extends State<LaunchDestination> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
