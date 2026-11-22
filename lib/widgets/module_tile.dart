import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Piastrella di un modulo nella home (Ore progetti, Interventi,
/// Ferie/assenze, Note spese, Approvazioni): stesso fondo dei riquadri del
/// riepilogo, icona colorata in un cerchio, testo scuro.
class ModuleTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final int? badgeCount;

  const ModuleTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.badgeCount,
  });

  @override
  State<ModuleTile> createState() => _ModuleTileState();
}

class _ModuleTileState extends State<ModuleTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final badge = widget.badgeCount ?? 0;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        // Stesso fondo dei riquadri del riepilogo: il colore resta solo nell'icona.
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashColor: color.withValues(alpha: 0.10),
          highlightColor: color.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: Icon(widget.icon, color: color, size: 21),
                    ),
                    const Spacer(),
                    if (badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          '$badge',
                          style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
                const Spacer(),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
