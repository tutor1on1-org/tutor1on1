import 'package:flutter/material.dart';

class PendingCountBadge extends StatelessWidget {
  const PendingCountBadge({
    super.key,
    required this.count,
    required this.child,
    this.badgeKey,
  });

  final int count;
  final Widget child;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return child;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -8,
          right: -8,
          child: Container(
            key: badgeKey,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.yellowAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red, width: 1.5),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AttentionIconButton extends StatelessWidget {
  const AttentionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlighted = false,
    this.highlightKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool highlighted;
  final Key? highlightKey;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: Icon(
        icon,
        color: highlighted ? Colors.red : null,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
    if (!highlighted) {
      return button;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        key: highlightKey,
        decoration: BoxDecoration(
          color: Colors.yellowAccent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.red, width: 1.5),
        ),
        child: button,
      ),
    );
  }
}
