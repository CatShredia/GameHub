# app.py
import os
import re
import time
import json
import requests
import xml.etree.ElementTree as ET
from dotenv import load_dotenv
from typing import List, Dict
from flask import Flask, jsonify, request, Response
from flask_cors import CORS
from waitress import serve

load_dotenv()

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*", "methods": ["GET", "POST", "OPTIONS"]}})

# ===== НАСТРОЙКИ =====
SELLER_ID = os.getenv('SELLER_ID')
AGENT_ID = os.getenv('AGENT_ID')
REFERRAL_ID = os.getenv('REFERRAL_ID', '')
DIGI_API = "https://api.digiseller.com/api/"

# ===== КЭШИРОВАНИЕ =====
CACHE_FILE = "products_cache.json"
CACHE_DURATION = 300  # 5 минут

ALL_GOODS: List[Dict] = []
ALL_GOODS_CACHE: Dict[str, Dict] = {}
last_load_time: float = 0
is_loading: bool = False

TRASH_WORDS = {
    'steam', 'ключ', 'key', 'steamkey', 'region', 'free', 'global', 'ru', 'рф', 'снг',
    'mir', 'весь', 'мир', 'подарок', 'бонус', 'карточки', 'картинки', 'набор', 'для',
    'на', 'от', 'и', 'с', 'в', 'по', 'из', 'оператор', 'доставка', 'мгновенная'
}


def clean_name(raw_name: str) -> str:
    if not raw_name:
        return "Без названия"
    name = re.sub(r'\s*\(?(Steam|STEAM|Region|GLOBAL|RU|РФ|СНГ|Key|ключ).*$', '', raw_name, flags=re.I)
    name = re.sub(r'[★☆✅✔♦️⚡]+', '', name)
    name = name.strip(' -|★☆')
    for sep in ['(', '[', ':', ' – ', ' - ']:
        if sep in name:
            name = name.split(sep)[0].strip()
    words = [w for w in name.split() if w.lower() not in TRASH_WORDS and len(w) > 1]
    return " ".join(words).strip() or raw_name.strip()


def _build_buy_url(product_id: str) -> str:
    base_url = "https://www.digiseller.market/asp2/pay_wm.asp"
    params = f"?id_d={product_id}"
    if REFERRAL_ID:
        params += f"&aff_id={REFERRAL_ID}"
    elif AGENT_ID:
        params += f"&aff_id={AGENT_ID}"
    return base_url + params


def _load_from_cache() -> bool:
    global ALL_GOODS, ALL_GOODS_CACHE, last_load_time
    if not os.path.exists(CACHE_FILE):
        return False
    try:
        file_mtime = os.path.getmtime(CACHE_FILE)
        if time.time() - file_mtime > CACHE_DURATION:
            return False
        with open(CACHE_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            ALL_GOODS = data.get('products', [])
            for p in ALL_GOODS:
                ALL_GOODS_CACHE[p['id']] = p
            last_load_time = data.get('loaded_at', file_mtime)
            print(f"✅ Кэш загружен: {len(ALL_GOODS)} товаров")
            return True
    except Exception as e:
        print(f"❌ Ошибка кэша: {e}")
    return False


def _save_to_cache():
    try:
        with open(CACHE_FILE, 'w', encoding='utf-8') as f:
            json.dump({'products': ALL_GOODS, 'loaded_at': time.time()}, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"❌ Не удалось сохранить кэш: {e}")


def load_all_products() -> bool:
    global ALL_GOODS, ALL_GOODS_CACHE, last_load_time, is_loading
    
    if is_loading:
        print("⏳ Загрузка уже идёт")
        return False
    is_loading = True
    start = time.time()
    print("🔄 Загрузка товаров с API...")
    
    goods = []
    temp_cache = {}
    page, rows = 1, 100
    
    try:
        while True:
            params = {
                "seller_id": SELLER_ID, "category_id": "0", "page": page, "rows": rows,
                "currency": "RUB", "lang": "ru-RU", "order": "name"
            }
            r = requests.get(f"{DIGI_API}shop/products", params=params, timeout=30)
            r.raise_for_status()
            root = ET.fromstring(r.text)
            
            retval = root.find("retval")
            if retval is None or retval.text != "0":
                retdesc = root.find("retdesc")
                print(f"❌ API: {retdesc.text if retdesc is not None else 'ошибка'}")
                break

            added = 0
            for item in root.findall(".//products/product"):
                p_id_elem = item.find("id")
                if p_id_elem is None:
                    continue
                p_id = p_id_elem.text
                full_name = item.find("name").text if item.find("name") is not None else " "
                price_text = item.find("price").text if item.find("price") is not None else "0"

                good = {
                    "id": p_id, "name": clean_name(full_name), "full_name": full_name,
                    "price": price_text,
                    "img": f"https://graph.digiseller.ru/img.ashx?id_d={p_id}&maxlength=400",
                    "buy_url": _build_buy_url(p_id),
                    "product_url": f"https://www.digiseller.market/product/{p_id}",
                    "currency": item.find("currency").text if item.find("currency") is not None else "RUB",
                    "sales": item.find("sales").text if item.find("sales") is not None else "0",
                }
                goods.append(good)
                temp_cache[p_id] = good
                added += 1

            print(f"📦 Стр. {page}: +{added} товаров")
            if added == 0 or added < rows:
                break
            page += 1

        ALL_GOODS = goods
        ALL_GOODS_CACHE = temp_cache
        last_load_time = time.time()
        _save_to_cache()
        
        elapsed = time.time() - start
        print(f"✅ Загружено {len(ALL_GOODS)} товаров за {elapsed:.1f} сек")
        return True
        
    except Exception as e:
        print(f"❌ Ошибка загрузки: {e}")
        if not ALL_GOODS:
            _load_from_cache()
        return False
    finally:
        is_loading = False


# ===== API ENDPOINTS =====

@app.route('/api/ping', methods=['GET'])
def ping():
    return jsonify({
        "status": "ok",
        "timestamp": time.time(),
        "products_loaded": len(ALL_GOODS) > 0,
        "cache_age": time.time() - last_load_time if last_load_time else None
    })


@app.route('/api/products', methods=['GET'])
def get_products_api():
    force_refresh = request.args.get('refresh', 'false').lower() == 'true'
    
    if not force_refresh and _load_from_cache() and ALL_GOODS:
        return _json_response({
            "success": True, "count": len(ALL_GOODS), "products": ALL_GOODS,
            "from_cache": True, "cache_age": time.time() - last_load_time
        })
    
    if force_refresh or not ALL_GOODS:
        print("🔄 Принудительное обновление...")
        load_all_products()
    
    return _json_response({
        "success": True, "count": len(ALL_GOODS), "products": ALL_GOODS,
        "from_cache": False
    })


@app.route('/api/product/<product_id>', methods=['GET'])
def get_product_api(product_id):
    if product_id in ALL_GOODS_CACHE:
        return _json_response({"success": True, "product": ALL_GOODS_CACHE[product_id], "from_cache": True})
    
    print(f"🔍 Товар {product_id} не в кэше")
    load_all_products()
    
    if product_id in ALL_GOODS_CACHE:
        return _json_response({"success": True, "product": ALL_GOODS_CACHE[product_id], "from_cache": False})
    
    return jsonify({"success": False, "error": "Not found"}), 404


@app.route('/api/search', methods=['GET'])
def search_products_api():
    query = request.args.get('q', '').lower().strip()
    if not query:
        return _json_response({"success": True, "products": [], "count": 0})
    
    results = [g for g in ALL_GOODS if query in g['name'].lower() or query in g['full_name'].lower()]
    return _json_response({"success": True, "count": len(results), "products": results})


def _json_response(data: dict) -> Response:
    """Создаёт JSON-ответ с безопасными заголовками для WSGI."""
    response = jsonify(data)
    # ✅ Безопасные заголовки (без hop-by-hop):
    response.headers['Content-Type'] = 'application/json; charset=utf-8'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response


# ===== ЗАПУСК СЕРВЕРА =====

if __name__ == "__main__":
    print("🚀 Запуск сервера (Waitress)...")
    print(f"📦 Seller ID: {SELLER_ID}")
    
    if not _load_from_cache():
        print("⚠️ Кэш пуст, загружаю с API...")
        load_all_products()
    
    port = int(os.getenv('PORT', 8080))
    
    print(f"\n✅ Сервер: http://0.0.0.0:{port}")
    print("📱 Android: http://10.0.2.2:" + str(port))
    print("💡 Ctrl+C для остановки")
    
    # Waitress конфигурация
    serve(
        app,
        host='0.0.0.0',
        port=port,
        threads=8,
        connection_limit=100,
        channel_timeout=300
    )