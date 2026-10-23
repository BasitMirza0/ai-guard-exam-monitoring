import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

bool get usesIosCamera =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get supportsMlKitFaceMesh =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

ImageFormatGroup get examCameraFormat =>
    usesIosCamera ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21;

ImageFormatGroup get liveCameraFormat =>
    usesIosCamera ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420;
