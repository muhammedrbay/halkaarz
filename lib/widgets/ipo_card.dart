import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ipo_model.dart';
import '../screens/ipo_detail_screen.dart';

/// IPO listesi kart widget'ı — gradient, glow efektleri
class IpoCard extends StatelessWidget {
  final IpoModel ipo;

  const IpoCard({super.key, required this.ipo});

  Color get _statusColor {
    switch (ipo.durum) {
      case 'taslak':
        return const Color(0xFFFFBE0B);
      case 'talep_topluyor':
        return const Color(0xFF00D4AA);
      case 'islem_goruyor':
        return const Color(0xFF00B4D8);
      default:
        return Colors.white54;
    }
  }

  String get _statusText {
    switch (ipo.durum) {
      case 'taslak':
        return 'Taslak';
      case 'talep_topluyor':
        return 'Talep Topluyor';
      case 'islem_goruyor':
        return 'İşlem Görüyor';
      default:
        return 'Bilinmiyor';
    }
  }

  IconData get _statusIcon {
    switch (ipo.durum) {
      case 'taslak':
        return Icons.edit_note_rounded;
      case 'talep_topluyor':
        return Icons.how_to_vote_rounded;
      case 'islem_goruyor':
        return Icons.show_chart_rounded;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IpoDetailScreen(ipo: ipo)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1F38),
              const Color(0xFF1A1F38).withValues(alpha: 0.8),
            ],
          ),
          border: Border.all(
            color: _statusColor.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _statusColor.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst satır: Şirket kodu + durum badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ipo.sirketKodu,
                      style: GoogleFonts.inter(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ipo.sirketAdi,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon, color: _statusColor, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _statusText,
                          style: GoogleFonts.inter(
                            color: _statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Alt satır: Fiyat, Lot, Katılım
              Row(
                children: [
                  _buildInfoChip(
                    Icons.monetization_on_outlined,
                    '₺${ipo.arzFiyati.toStringAsFixed(2)}',
                    'Arz Fiyatı',
                  ),
                  const SizedBox(width: 16),
                  _buildInfoChip(
                    Icons.inventory_2_outlined,
                    '${_formatNumber(ipo.toplamLot)} Lot',
                    'Toplam',
                  ),
                  const Spacer(),
                  if (ipo.katilimEndeksineUygun)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4AA), Color(0xFF00B4D8)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Katılım',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              if (ipo.talepBaslangic.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: Colors.white38,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ipo.talepTarihAraligi,
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white54, size: 14),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toString();
  }
}
