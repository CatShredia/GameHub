import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateAuctionPage extends StatefulWidget {
  const CreateAuctionPage({super.key});

  @override
  State<CreateAuctionPage> createState() => _CreateAuctionPageState();
}

class _CreateAuctionPageState extends State<CreateAuctionPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _steamKeyController = TextEditingController();
  
  int _hours = 24; // По умолчанию 24 часа
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _minPriceController.dispose();
    _imageUrlController.dispose();
    _steamKeyController.dispose();
    super.dispose();
  }

  Future<void> _createAuction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');

      final endDate = DateTime.now().add(Duration(hours: _hours));
      final imageUrl = _imageUrlController.text.trim();
      if (imageUrl.isEmpty) {
        throw Exception('Укажите URL обложки (url_item) — обязательное поле');
      }
      final steam = _steamKeyController.text.trim();
      if (steam.isEmpty) {
        throw Exception('Укажите Steam-ключ (steam_key) — обязательное поле');
      }

      // Только поля из схемы: Auction_items
      await Supabase.instance.client.from('Auction_items').insert({
        'title': _titleController.text.trim(),
        'start_price': int.parse(_minPriceController.text),
        'url_item': imageUrl,
        'steam_key': steam,
        'ended_at': endDate.toIso8601String(),
        'is_active': true,
        'owner_id': user.id,
        'bid_count': 0,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Аукцион успешно создан!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Создать аукцион',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🎮 Информация об игре
              const Text(
                '🎮 Информация об игре',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Название
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Название игры *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.title, color: Color(0xFF7C3AED)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите название';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // URL изображения
              TextFormField(
                controller: _imageUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'URL обложки (url_item) *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.image, color: Color(0xFF7C3AED)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Введите ссылку на картинку' : null,
              ),
              
              const SizedBox(height: 24),

              // 💰 Цена и длительность
              const Text(
                '💰 Условия аукциона',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Минимальная цена
              TextFormField(
                controller: _minPriceController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Минимальная цена (очки) *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.star, color: Color(0xFFF59E0B)),
                  suffixText: '⭐',
                  suffixStyle: const TextStyle(color: Color(0xFFF59E0B)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите цену';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Введите число';
                  }
                  if (int.parse(value) < 10) {
                    return 'Минимум 10 очков';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Часы (длительность)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _hours,
                    isExpanded: true,
                    icon: const Icon(Icons.access_time, color: Color(0xFF7C3AED)),
                    dropdownColor: const Color(0xFF1A1A2E),
                    items: [
                      6, 12, 24, 48, 72, 168 // 6ч, 12ч, 1 день, 2 дня, 3 дня, 7 дней
                    ].map((hours) {
                      String label;
                      if (hours < 24) {
                        label = '$hours ч.';
                      } else if (hours == 24) {
                        label = '1 день';
                      } else {
                        label = '${hours ~/ 24} дн.';
                      }
                      return DropdownMenuItem(
                        value: hours,
                        child: Row(
                          children: [
                            const Icon(Icons.timer, size: 18, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _hours = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 🔑 Steam данные
              const Text(
                '🔑 Steam ключ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Steam ключ
              TextFormField(
                controller: _steamKeyController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Steam ключ (steam_key) *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.vpn_key, color: Color(0xFF10B981)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  helperText: 'Скрыт до окончания; один или несколько, с новой строки',
                  helperStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                maxLines: 3,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Нужен Steam-ключ' : null,
              ),
              
              const SizedBox(height: 32),

              // 🔨 Кнопка создания
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createAuction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 8,
                    shadowColor: const Color(0xFF7C3AED).withOpacity(0.4),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.gavel, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              '🔨 Создать аукцион',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}