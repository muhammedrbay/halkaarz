import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Büyük, belirgin Katılım Endeksi filtre toggle switch'i
class KatilimToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const KatilimToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: value
              ? [
                  const Color(0xFF00D4AA).withValues(alpha: 0.15),
                  const Color(0xFF00B4D8).withValues(alpha: 0.1),
                ]
              : [
                  const Color(0xFF1A1F38),
                  const Color(0xFF1A1F38).withValues(alpha: 0.8),
                ],
        ),
        border: Border.all(
          color: value
              ? const Color(0xFF00D4AA).withValues(alpha: 0.3)
              : const Color(0xFF2A2F4A),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value
                  ? const Color(0xFF00D4AA).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            child: Icon(
              Icons.verified_rounded,
              color: value ? const Color(0xFF00D4AA) : Colors.white38,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Katılım Endeksine Uygun',
                  style: GoogleFonts.inter(
                    color: value ? const Color(0xFF00D4AA) : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Sadece uygun olanlar gösteriliyor'
                      : 'Tüm halka arzlar gösteriliyor',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 1.1,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF00D4AA),
              activeTrackColor: const Color(0xFF00D4AA).withValues(alpha: 0.3),
              inactiveThumbColor: Colors.white54,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
