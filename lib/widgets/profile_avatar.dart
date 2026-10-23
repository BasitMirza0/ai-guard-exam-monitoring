import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

String? profilePhotoUrl(User? user) {
  if (user == null) return null;
  if (user.photoURL?.trim().isNotEmpty == true) return user.photoURL;
  for (final provider in user.providerData) {
    if (provider.photoURL?.trim().isNotEmpty == true) return provider.photoURL;
  }
  return null;
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.photoUrl,
    this.name = '',
    this.size = 52,
  });
  final String? photoUrl;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final initials =
        name
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part.characters.first.toUpperCase())
            .join();
    final fallback = ColoredBox(
      color: AppColors.primarySoft,
      child: Center(
        child:
            initials.isEmpty
                ? Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primary,
                  size: size * .45,
                )
                : Text(
                  initials,
                  style: TextStyle(
                    fontSize: size * .32,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
      ),
    );
    final uri = Uri.tryParse(photoUrl ?? '');
    final valid =
        uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
    return Semantics(
      label: 'Profile picture',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child:
              valid
                  ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(1, 512),
                    gaplessPlayback: true,
                    loadingBuilder:
                        (_, child, progress) =>
                            progress == null ? child : fallback,
                    errorBuilder: (_, __, ___) => fallback,
                  )
                  : fallback,
        ),
      ),
    );
  }
}
