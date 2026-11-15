import 'package:flutter/material.dart';

/// Piastrella di un modulo nella home (Ore progetti, Interventi,
/// Ferie/assenze, Note spese, Approvazioni): fondo pieno sfumato nel colore
/// del modulo, icona in un cerchio, nome e una riga di descrizione, e la
/// stessa icona grande in trasparenza nell'angolo.
class ModuleTile extends StatefulWidget {
  final IconData icon;
  final List<Color> colors;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final int? badgeCount;

  const ModuleTile({
    super.key,
    required this.icon,
    required this.colors,
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

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.colors.last;
    final badge = widget.badgeCount ?? 0;
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: base.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.colors,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _setPressed,
              splashColor: Colors.white.withValues(alpha: 0.15),
              highlightColor: Colors.white.withValues(alpha: 0.05),
              child: Stack(
                children: [
                  Positioned(
                    right: -14,
                    bottom: -18,
                    child: Icon(widget.icon, size: 96, color: Colors.white.withValues(alpha: 0.13)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(widget.icon, color: Colors.white, size: 22),
                            ),
                            const Spacer(),
                            if (badge > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$badge',
                                  style: TextStyle(fontSize: 12, color: base, fontWeight: FontWeight.w700),
                                ),
                              )
                            else
                              Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white.withValues(alpha: 0.7)),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
