// lib/database/digiseller_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class DigisellerProduct {
  final String id;
  final String name;
  final String fullName;
  final String price;
  final String img;
  final String? seller;
  final String? currency;
  final String? sales;
  final String? buyUrl;
  final String? productUrl;

  DigisellerProduct({
    required this.id,
    required this.name,
    required this.fullName,
    required this.price,
    required this.img,
    this.seller,
    this.currency,
    this.sales,
    this.buyUrl,
    this.productUrl,
  });

  factory DigisellerProduct.fromJson(Map<String, dynamic> json) {
    return DigisellerProduct(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      fullName: json['full_name'] ?? json['fullName'] ?? '',
      price: json['price']?.toString() ?? '0',
      img: json['img'] ?? '',
      seller: json['seller'],
      currency: json['currency'],
      sales: json['sales'],
      buyUrl: json['buy_url'],
      productUrl: json['product_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'full_name': fullName,
      'price': price,
      'img': img,
      'seller': seller,
      'currency': currency,
      'sales': sales,
      'buy_url': buyUrl,
      'product_url': productUrl,
    };
  }
}

class DigisellerApiService {
  // 🔥 ВЫБЕРИТЕ НУЖНЫЙ АДРЕС ДЛЯ ВАШЕГО УСТРОЙСТВА:
  
  /// 🤖 Android эмулятор (AVD) — стандартный адрес
  static const String _baseUrl = 'http://10.0.2.2:8080/api';
  
  /// 🍎 iOS симулятор (раскомментируйте при необходимости):
  // static const String _baseUrl = 'http://localhost:8080/api';
  
  /// 📱 Физическое устройство (замените на ваш локальный IP):
  // static const String _baseUrl = 'http://192.168.1.100:8080/api';

  /// 🌐 Для ngrok (если используете туннель):
  // static const String _baseUrl = 'https://xxxx.ngrok.io/api';

  /// Получает список всех товаров с поддержкой повторных попыток
  Future<List<DigisellerProduct>> fetchProducts({
    bool refresh = false,
    int maxRetries = 2,
  }) async {
    final url = Uri.parse('$_baseUrl/products${refresh ? '?refresh=true' : ''}');
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      print('🔍 Запрос #${attempt + 1}/${maxRetries + 1}: $url');
      
      http.Client? client;
      try {
        client = http.Client();
        
        final response = await client
            .get(
              url,
              headers: {
                'Connection': 'keep-alive',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
            )
            .timeout(
              const Duration(seconds: 180), // 3 минуты — достаточно для первой загрузки
              onTimeout: () {
                throw Exception('Сервер не ответил за 180 секунд');
              },
            );
        
        print('📥 Статус: ${response.statusCode} | Размер: ${response.body.length} байт');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          if (data['success'] == true) {
            final products = (data['products'] as List)
                .map((json) => DigisellerProduct.fromJson(json))
                .toList();
            
            final fromCache = data['from_cache'] ?? false;
            final count = products.length;
            print('✅ Загружено: $count товаров ${fromCache ? '(из кэша)' : '(с сервера)'}');
            return products;
          }
          throw Exception('API вернул ошибку: ${data['error'] ?? 'неизвестно'}');
        }
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
        
      } on Exception catch (e) {
        print('⏰ Таймаут (попытка ${attempt + 1}/${maxRetries + 1}): $e');
        if (attempt == maxRetries) {
          throw Exception(
            'Таймаут подключения.\n'
            'Возможные причины:\n'
            '• Сервер Flask не запущен\n'
            '• Брандмауэр блокирует порт 8080\n'
            '• Медленная загрузка товаров с Digiseller\n'
            '• Проблемы с сетью эмулятора',
          );
        }
        await Future.delayed(const Duration(seconds: 2));
        
      } on SocketException catch (e) {
        print('🔌 Ошибка сети (попытка ${attempt + 1}/${maxRetries + 1}): $e');
        if (attempt == maxRetries) {
          throw Exception(
            'Нет соединения с сервером.\n'
            'Проверьте:\n'
            '1. Flask запущен: python app.py\n'
            '2. Адрес правильный: $_baseUrl\n'
            '3. Брандмауэр разрешает порт 8080:\n'
            '   netsh advfirewall firewall add rule name="Flask 8080" dir=in action=allow protocol=TCP localport=8080\n'
            '4. Эмулятор и ПК в одной сети',
          );
        }
        await Future.delayed(const Duration(seconds: 1));
        
      } on http.ClientException catch (e) {
        // "Connection closed while receiving data" — частая проблема с Flask dev server
        print('🔗 Разрыв соединения (попытка ${attempt + 1}/${maxRetries + 1}): $e');
        if (attempt == maxRetries) {
          throw Exception(
            'Соединение разорвано сервером.\n'
            'Решение:\n'
            '• Установите waitress: pip install waitress\n'
            '• Перезапустите сервер: python app.py',
          );
        }
        await Future.delayed(const Duration(seconds: 2));
        
      } on FormatException catch (e) {
        print('❌ Ошибка парсинга JSON: $e');
        throw Exception('Неверный формат ответа от сервера');
        
      } catch (e) {
        print('❌ Неожиданная ошибка (попытка ${attempt + 1}/${maxRetries + 1}): $e');
        if (attempt == maxRetries) {
          throw Exception('Ошибка загрузки: $e');
        }
        await Future.delayed(const Duration(seconds: 1));
      } finally {
        client?.close();
      }
    }
    
    // Должно быть недостижимо, но на всякий случай:
    throw Exception('Не удалось загрузить товары после $maxRetries попыток');
  }

  /// Получает один товар по ID
  Future<DigisellerProduct?> fetchProduct(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/product/$id'),
            headers: {'Connection': 'keep-alive'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return DigisellerProduct.fromJson(data['product']);
        }
      }
      print('⚠️ Товар $id не найден или ошибка: ${response.statusCode}');
    } on Exception {
      print('⏰ Таймаут при загрузке товара $id');
    } catch (e) {
      print('❌ Ошибка загрузки товара $id: $e');
    }
    return null;
  }

  /// Поиск товаров по запросу
  Future<List<DigisellerProduct>> searchProducts(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/search?q=${Uri.encodeComponent(query)}'),
            headers: {'Connection': 'keep-alive'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return (data['products'] as List)
              .map((json) => DigisellerProduct.fromJson(json))
              .toList();
        }
      }
    } on Exception {
      print('⏰ Таймаут при поиске: $query');
    } catch (e) {
      print('❌ Ошибка поиска "$query": $e');
    }
    return [];
  }

  /// Проверка доступности сервера (быстрый пинг)
  Future<bool> isServerAlive({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/ping'),
            headers: {'Connection': 'keep-alive'},
          )
          .timeout(timeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Принудительное обновление кэша на сервере
  Future<bool> refreshCache() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/products?refresh=true'),
            headers: {'Connection': 'keep-alive'},
          )
          .timeout(const Duration(seconds: 300)); // 5 минут для полной перезагрузки
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка обновления кэша: $e');
      return false;
    }
  }

  /// Получение базового URL (для отладки)
  String get baseUrl => _baseUrl;
}