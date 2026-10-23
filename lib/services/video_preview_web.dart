import 'package:video_player/video_player.dart';

VideoPlayerController videoPreview(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));
