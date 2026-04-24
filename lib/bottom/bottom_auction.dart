import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/auction_service.dart';
import 'mini_page/reate_auction_page.dart';

// ? Аукционы: список активных лотов, ставка продлевает окончание на 2 минуты
class BottomAuction extends StatefulWidget {
  const BottomAuction({super.key});

  @override
  State<BottomAuction> createState() => _BottomAuctionState();
}

class _BottomAuctionState extends State<BottomAuction> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _auctions = [];
  final Map<int, int> _maxBidByAuction = {};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _loadAuctions();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadAuctions() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final client = Supabase.instance.client;
      await AuctionService.instance.finalizeExpiredAuctions();

      final now = DateTime.now().toIso8601String();

      final res = await client
          .from('Auction_items')
          .select('''
            id,
            title,
            url_item,
            start_price,
            bid_count,
            ended_at,
            is_active,
            owner_id,
            User!auction_items_owner_id_fkey (
              username,
              login
            )
          ''')
          .eq('is_active', true)
          .gt('ended_at', now)
          .order('ended_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res);
      final ids = list.map((e) => (e['id'] as num).toInt()).toList();

      final Map<int, int> maxBids = {};
      if (ids.isNotEmpty) {
        final bids = await client
            .from('Bid_auction')
            .select('auction_id, new_price');
        final idSet = ids.toSet();
        for (final b in List<Map<String, dynamic>>.from(bids)) {
          final aid = (b['auction_id'] as num).toInt();
          if (!idSet.contains(aid)) continue;
          final p = (b['new_price'] as num).toInt();
          if ((maxBids[aid] ?? 0) < p) maxBids[aid] = p;
        }
      }

      if (mounted) {
        setState(() {
          _auctions = list;
          _maxBidByAuction
            ..clear()
            ..addAll(maxBids);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки: $e';
          _isLoading = false;
        });
      }
    }
  }

  int _currentPrice(int auctionId, int startPrice) {
    return _maxBidByAuction[auctionId] ?? startPrice;
  }

  String _formatPoints(int points) {
    return points.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  String _formatTimeRemaining(String endedAt) {
    try {
      final end = DateTime.parse(endedAt);
      final diff = end.difference(DateTime.now());

      if (diff.isNegative) return 'Завершён';

      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      final seconds = diff.inSeconds.remainder(60);

      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
  }

  Future<void> _onBid(
    int auctionId,
    int startPrice, {
    required String title,
  }) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final price = _currentPrice(auctionId, startPrice);
    final next = price + 50;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          'Ставка: $title',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          'Следующая цена: ${_formatPoints(next)} ⭐\n'
          'К аукциону прибавится 2 минуты.',
          style: const TextStyle(color: Colors.white70, height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
            child: const Text('Поставить'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (me == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Войдите в аккаунт')),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }

    final err = await AuctionService.instance.placeBid(auctionId: auctionId);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ставка принята, +2 мин к аукциону'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadAuctions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAuctions,
        color: const Color(0xFF7C3AED),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🔨 Аукцион игр',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Создай лот или сделай ставку (+2 мин к таймеру)',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreateAuctionPage(),
                            ),
                          ).then((_) => _loadAuctions());
                        },
                        tooltip: 'Создать аукцион',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '⚠️ $_error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadAuctions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                        ),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              else if (_auctions.isEmpty)
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.gavel, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Сейчас нет активных аукционов',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Создай аукцион — его увидят все',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreateAuctionPage(),
                            ),
                          ).then((_) => _loadAuctions());
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Создать аукцион'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Активные аукционы',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ..._auctions.map((a) {
                  final id = (a['id'] as num).toInt();
                  final start = (a['start_price'] as num).toInt();
                  final cur = _currentPrice(id, start);
                  final title = a['title'] as String? ?? 'Лот';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: _AuctionCardDb(
                      title: title,
                      seller:
                          '@${(a['User'] as Map<String, dynamic>?)?['login'] ?? 'unknown'}',
                      imageUrl: a['url_item'] as String? ?? '',
                      bidCount: (a['bid_count'] as num?)?.toInt() ?? 0,
                      timeLeft: _formatTimeRemaining('${a['ended_at']}'),
                      currentPoints: _formatPoints(cur),
                      onBid: () => _onBid(
                        id,
                        start,
                        title: title,
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateAuctionPage()),
          ).then((_) => _loadAuctions());
        },
        backgroundColor: const Color(0xFF7C3AED),
        icon: const Icon(Icons.gavel),
        label: const Text('Аукцион'),
      ),
    );
  }
}

class _AuctionCardDb extends StatelessWidget {
  final String title;
  final String seller;
  final String imageUrl;
  final int bidCount;
  final String timeLeft;
  final String currentPoints;
  final VoidCallback onBid;

  const _AuctionCardDb({
    required this.title,
    required this.seller,
    required this.imageUrl,
    required this.bidCount,
    required this.timeLeft,
    required this.currentPoints,
    required this.onBid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1212), Color(0xFF1E0A1E)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: SizedBox(
              height: 140,
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('🎮', style: TextStyle(fontSize: 64)),
                      ),
                    )
                  : const Center(
                      child: Text('🎮', style: TextStyle(fontSize: 64)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Продавец: $seller',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniStat(
                      label: 'Текущая',
                      value: '$currentPoints ⭐',
                      color: const Color(0xFF34D399),
                      icon: Icons.star,
                    ),
                    _MiniStat(
                      label: 'Ставок',
                      value: '$bidCount',
                      icon: Icons.trending_up,
                    ),
                    _MiniStat(
                      label: 'До конца',
                      value: timeLeft,
                      color: Colors.red,
                      icon: Icons.timer,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onBid,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Сделать ставку',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
