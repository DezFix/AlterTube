import 'package:flutter/material.dart';

// Аватар канала: фото или буква. Один виджет вместо 4 копий по экранам.
class ChannelAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final double radius;
  const ChannelAvatar({
    super.key,
    required this.name,
    this.avatarUrl = '',
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(avatarUrl),
      onBackgroundImageError: (_, __) {},
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
    );
  }
}
