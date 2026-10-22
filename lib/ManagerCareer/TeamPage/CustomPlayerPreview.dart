import 'package:flutter/material.dart';

import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/Components/PlayerAvatar.dart';

class CustomPlayerPreview extends StatelessWidget {
  const CustomPlayerPreview({
    super.key,
    required this.name,
    required this.position,
    required this.nationality,
    required this.overall,
    required this.potential,
    required this.shirt,
    required this.avatar,
    required this.fifaVersion,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  final String name, nationality, fifaVersion;
  final String? position, avatar;
  final int? overall, potential, shirt;
  final VoidCallback onPickImage;
  final VoidCallback? onRemoveImage;

  Widget _rating(BuildContext context, String label, int? value, Color accent) {
    final colors = CareerUiColors(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.panel.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: animation.drive(Tween(begin: .85, end: 1.0)),
                  child: child,
                ),
              ),
              child: Text(
                value?.toString() ?? '—',
                key: ValueKey(value),
                style: TextStyle(
                  color: accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                colors.accent.withValues(alpha: .15),
                colors.panel,
              ),
              colors.panel,
            ],
          ),
          border: Border.all(color: colors.accent.withValues(alpha: .3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: colors.accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'JOGADOR PERSONALIZADO',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 9,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (shirt != null)
                  Text(
                    '#$shirt',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: avatar == null
                      ? 'Adicionar foto do jogador'
                      : 'Alterar foto do jogador',
                  child: SizedBox(
                    width: 76,
                    height: 80,
                    child: Stack(
                      children: [
                        Material(
                          color: colors.accent.withValues(alpha: .08),
                          shape: CircleBorder(
                            side: BorderSide(
                              color: colors.accent.withValues(alpha: .3),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onPickImage,
                            child: SizedBox(
                              width: 72,
                              height: 72,
                              child: avatar == null
                                  ? Icon(
                                      Icons.person_outline_rounded,
                                      size: 40,
                                      color: colors.accent,
                                    )
                                  : PlayerAvatar(
                                      fifaVersion: fifaVersion,
                                      customAvatarFilePath: avatar,
                                      radius: 36,
                                    ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 4,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.panel,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.add_a_photo_outlined,
                                size: 13,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Seu próximo talento' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              position ?? 'Posição',
                              style: TextStyle(
                                color: colors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (nationality.isNotEmpty)
                            Text(
                              nationality,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      if (onRemoveImage != null)
                        TextButton(
                          onPressed: onRemoveImage,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Remover foto',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _rating(context, 'OVERALL', overall, colors.accent),
                const SizedBox(width: 10),
                _rating(context, 'POTENCIAL', potential, colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
