import 'package:flutter/material.dart';
import '../navigation/clean_page_transitions.dart';

/// Suspends camera work while an app is backgrounded or another route covers it.
mixin CameraActivity<T extends StatefulWidget> on State<T>
    implements RouteAware {
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool _visible = true;
  ModalRoute<dynamic>? _route;
  bool get cameraActive => mounted && _foreground && _visible;

  void onCameraActivityChanged();

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route && route != null) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    onCameraActivityChanged();
  }

  @override
  void didPushNext() {
    _visible = false;
    onCameraActivityChanged();
  }

  @override
  void didPopNext() {
    _visible = true;
    onCameraActivityChanged();
  }

  @override
  void didPush() {}
  @override
  void didPop() {}

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _lifecycle?.dispose();
    super.dispose();
  }
}
