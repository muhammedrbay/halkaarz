import 'dart:convert';
import 'package:http/http.dart' as http;

/// Yahoo Finance'den güncel fiyat çeker (uygulama içi portföy P&L için)
class PriceService {
  /// BIST hissesinin güncel fiyatını çeker
  /// ticker: hisse kodu (örn: "THYAO")
  /// Yahoo Finance formatı: THYAO.IS
  static Future<double?> getCurrentPrice(String ticker) async {
    try {
      final symbol = '${ticker.toUpperCase()}.IS';
      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=1d&range=1d',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['chart']?['result'];
        if (result != null && result.isNotEmpty) {
          final meta = result[0]['meta'];
          final price = meta['regularMarketPrice'];
          return price?.toDouble();
        }
      }
    } catch (e) {
      print('Fiyat çekilemedi ($ticker): $e');
    }
    return null;
  }

  /// Birden fazla hissenin fiyatını çeker
  static Future<Map<String, double>> getMultiplePrices(
    List<String> tickers,
  ) async {
    final prices = <String, double>{};
    for (final ticker in tickers) {
      final price = await getCurrentPrice(ticker);
      if (price != null) {
        prices[ticker] = price;
      }
      // Rate limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return prices;
  }
}
