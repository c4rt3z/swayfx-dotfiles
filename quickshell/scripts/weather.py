#!/usr/bin/env python3
"""Погода для бара и панели календаря.

Источник: OpenWeather, если в настройках лежит ключ, иначе open-meteo — он
работает без ключа и регистрации, поэтому виджет живёт сразу после установки.
Кэш (~/.cache/quickshell/weather.json) держим 15 минут: бар перерисовывается
часто, а сеть дёргать на каждую перерисовку незачем.

    weather.py bar              — строка для waybar (иконка шрифтом + градусы)
    weather.py state            — сводка для панелей (JSON)
    weather.py set k=v [k=v ...]— настройки: city, api_key, provider, units
    weather.py search <город>   — поиск города для настроек (JSON)
    weather.py refresh          — сходить в сеть сейчас, не ждать кэш

Настройки: ~/.config/quickshell/weather.json
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import tr  # noqa: E402

HOME = os.path.expanduser("~")
SETTINGS = f"{HOME}/.config/quickshell/weather.json"
CACHE = f"{HOME}/.cache/quickshell/weather.json"
TTL = 900                      # секунд: столько годится кэш
TIMEOUT = 6                    # секунд на запрос

DEFAULTS = {"city": "Москва", "api_key": "", "provider": "auto", "units": "metric"}

# Иконки — из шрифта (Nerd Font, набор weathericons), эмодзи не используем.
ICONS = {
    "clear_day": "\ue30d", "clear_night": "\ue32b", "partly": "\ue30e",
    "cloudy": "\ue302", "overcast": "\ue32e", "fog": "\ue31d",
    "drizzle": "\ue32a", "rain": "\ue324", "heavy": "\ue325",
    "snow": "\ue31a", "sleet": "\ue31b", "thunder": "\ue315", "wind": "\ue3af",
}

# Русские подписи — ключи словаря, переводы лежат в i18n/<код>.json
DESCR = {
    "clear": "Ясно", "partly": "Малооблачно", "cloudy": "Облачно",
    "overcast": "Пасмурно", "fog": "Туман", "drizzle": "Морось",
    "rain": "Дождь", "heavy": "Ливень", "snow": "Снег", "sleet": "Мокрый снег",
    "thunder": "Гроза", "wind": "Ветрено",
}


def load_settings():
    data = dict(DEFAULTS)
    try:
        with open(SETTINGS, encoding="utf-8") as fh:
            saved = json.load(fh)
        if isinstance(saved, dict):
            for key, value in saved.items():
                if key in DEFAULTS and isinstance(value, (str, int, float)):
                    data[key] = str(value)
    except Exception:
        pass
    return data


def save_settings(data):
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, SETTINGS)


def load_cache():
    try:
        with open(CACHE, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict) and isinstance(data.get("data"), dict):
            return data
    except Exception:
        pass
    return {}


def save_cache(data):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, CACHE)


def get_json(url, tries=2):
    """Запрос с одной повторной попыткой: сервис погоды иногда отдаёт 503."""
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "swayfx-dotfiles-quickshell"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return json.loads(resp.read().decode("utf-8", "replace"))
        except Exception as exc:
            last = exc
            time.sleep(0.6)
    raise RuntimeError(tr("сервис погоды не ответил"))


def ui_lang():
    try:
        with open(f"{HOME}/.config/quickshell/language", encoding="utf-8") as fh:
            code = fh.read().strip().splitlines()[0].strip()
        return code or "ru"
    except Exception:
        return "ru"


# ── коды погоды → наши категории ────────────────────────────────────────────

WMO = {
    0: "clear", 1: "partly", 2: "cloudy", 3: "overcast", 45: "fog", 48: "fog",
    51: "drizzle", 53: "drizzle", 55: "drizzle", 56: "sleet", 57: "sleet",
    61: "rain", 63: "rain", 65: "heavy", 66: "sleet", 67: "sleet",
    71: "snow", 73: "snow", 75: "snow", 77: "snow",
    80: "rain", 81: "rain", 82: "heavy", 85: "snow", 86: "snow",
    95: "thunder", 96: "thunder", 99: "thunder",
}


def from_owm(code):
    if 200 <= code < 300:
        return "thunder"
    if 300 <= code < 400:
        return "drizzle"
    if code == 511:
        return "sleet"
    if 500 <= code < 600:
        return "heavy" if code in (502, 503, 504) else "rain"
    if 600 <= code < 700:
        return "sleet" if 611 <= code <= 616 else "snow"
    if 700 <= code < 800:
        return "thunder" if code == 781 else ("wind" if code in (751, 761, 771) else "fog")
    if code == 800:
        return "clear"
    if code == 801:
        return "partly"
    if code == 802:
        return "cloudy"
    return "overcast"


def icon_for(category, is_day):
    """Иконка из шрифта: ясно днём и ночью — разные значки."""
    if category == "clear":
        return ICONS["clear_day" if is_day else "clear_night"]
    return ICONS.get(category, ICONS["cloudy"])


def pack(category, is_day, temp, feels, humidity, wind, city, unit, source, extra=None):
    data = {
        "ok": True, "category": category, "is_day": bool(is_day),
        "icon": icon_for(category, is_day),
        "desc": tr(DESCR.get(category, "Облачно")),
        "temp": int(round(temp)), "feels": int(round(feels)),
        "humidity": int(round(humidity)), "wind": round(float(wind), 1),
        "city": city, "unit": unit, "source": source,
        "wind_unit": "mph" if unit == "°F" else "м/с",
        "updated": int(time.time()),
    }
    if extra:
        data.update(extra)
    return data


def unit_symbol(units):
    return "°F" if units == "imperial" else "°C"


def fetch_openmeteo(city, units, lang):
    geo = get_json("https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode({
        "name": city, "count": 1, "language": lang, "format": "json"}))
    results = geo.get("results") or []
    if not results:
        raise RuntimeError(tr("город не найден"))
    place = results[0]
    query = {
        "latitude": place["latitude"], "longitude": place["longitude"],
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,"
                   "weather_code,wind_speed_10m,is_day",
        "daily": "sunrise,sunset", "forecast_days": 1, "timezone": "auto",
        "temperature_unit": "fahrenheit" if units == "imperial" else "celsius",
        "wind_speed_unit": "mph" if units == "imperial" else "ms",
    }
    cur = get_json("https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(query))
    now = cur.get("current") or {}
    code = int(now.get("weather_code") or 0)
    name = place.get("name") or city
    country = place.get("country") or ""
    extra = {"country": country, "lat": place["latitude"], "lon": place["longitude"]}
    daily = (cur.get("daily") or {})
    sunrise = (daily.get("sunrise") or [""])[0]
    sunset = (daily.get("sunset") or [""])[0]
    if sunrise:
        extra["sunrise"] = sunrise[11:16]
    if sunset:
        extra["sunset"] = sunset[11:16]
    return pack(WMO.get(code, "cloudy"), now.get("is_day", 1),
                now.get("temperature_2m", 0), now.get("apparent_temperature", 0),
                now.get("relative_humidity_2m", 0), now.get("wind_speed_10m", 0),
                name, unit_symbol(units), "open-meteo", extra)


def fetch_openweather(city, units, lang, key):
    query = {"q": city, "appid": key, "lang": lang,
             "units": "imperial" if units == "imperial" else "metric"}
    data = get_json("https://api.openweathermap.org/data/2.5/weather?" + urllib.parse.urlencode(query))
    weather = (data.get("weather") or [{}])[0]
    main = data.get("main") or {}
    wind = data.get("wind") or {}
    sysinfo = data.get("sys") or {}
    is_day = 1
    now = int(time.time())
    if sysinfo.get("sunrise") and sysinfo.get("sunset"):
        is_day = 1 if sysinfo["sunrise"] <= now <= sysinfo["sunset"] else 0
        sunrise = time.strftime("%H:%M", time.localtime(sysinfo["sunrise"]))
        sunset = time.strftime("%H:%M", time.localtime(sysinfo["sunset"]))
    else:
        sunrise = sunset = ""
    extra = {"country": sysinfo.get("country") or "", "sunrise": sunrise, "sunset": sunset}
    return pack(from_owm(int(weather.get("id") or 800)), is_day,
                main.get("temp", 0), main.get("feels_like", 0),
                main.get("humidity", 0), wind.get("speed", 0),
                data.get("name") or city, unit_symbol(units), "openweather", extra)


def fetch(settings):
    """Сходить в сеть. Исключение — не смогли (сеть, ключ, город)."""
    city = (settings.get("city") or DEFAULTS["city"]).strip()
    units = settings.get("units") or "metric"
    lang = ui_lang()
    key = (settings.get("api_key") or "").strip()
    provider = settings.get("provider") or "auto"
    if provider == "auto":
        provider = "openweather" if key else "openmeteo"
    if provider == "openweather":
        if not key:
            raise RuntimeError(tr("нет ключа OpenWeather"))
        return fetch_openweather(city, units, lang, key)
    return fetch_openmeteo(city, units, lang)


def weather(force=False):
    """Текущая погода: кэш, если свежий, иначе сеть."""
    cache = load_cache()
    fresh = cache.get("fetched", 0) and time.time() - cache.get("fetched", 0) < TTL
    if fresh and not force and isinstance(cache.get("data"), dict):
        return cache["data"]
    try:
        data = fetch(load_settings())
        save_cache({"fetched": int(time.time()), "data": data})
        return data
    except Exception as exc:
        if isinstance(cache.get("data"), dict):
            stale = dict(cache["data"])
            stale["stale"] = True
            return stale
        return {"ok": False, "error": str(exc) or tr("Погода недоступна"),
                "icon": ICONS["cloudy"], "desc": tr("Погода недоступна"),
                "city": (load_settings().get("city") or ""), "temp": None,
                "unit": unit_symbol(load_settings().get("units") or "metric"),
                "category": "cloudy", "source": ""}


def cmd_bar(force=False):
    data = weather(force)
    if not data.get("ok"):
        print(json.dumps({"text": f"{ICONS['cloudy']} —", "tooltip": data.get("error") or "",
                          "class": "error"}, ensure_ascii=False))
        return 0
    text = f"{data['icon']} {data['temp']}{data['unit']}"
    tooltip = [f"{data['desc']}, {data['city']}"]
    tooltip.append(f"{tr('Ощущается')} {data['feels']}{data['unit']}, "
                   f"{tr('Влажность')} {data['humidity']}%")
    tooltip.append(f"{tr('Ветер')} {data['wind']} {data.get('wind_unit', 'м/с')}")
    if data.get("sunrise") and data.get("sunset"):
        tooltip.append(f"{tr('Восход')} {data['sunrise']} · {tr('Закат')} {data['sunset']}")
    if data.get("stale"):
        tooltip.append(tr("данные из кэша"))
    print(json.dumps({"text": text, "tooltip": "\n".join(tooltip),
                      "class": data["category"]}, ensure_ascii=False))
    return 0


def cmd_state(force=False):
    """Погода + настройки: странице настроек нужны и то и другое."""
    print(json.dumps({"data": weather(force), "settings": load_settings()},
                     ensure_ascii=False))
    return 0


def cmd_set(pairs):
    data = load_settings()
    for pair in pairs:
        if "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        key = key.strip()
        if key in DEFAULTS:
            data[key] = value.strip()
    save_settings(data)
    try:
        os.remove(CACHE)
    except Exception:
        pass
    print(json.dumps(data, ensure_ascii=False))
    return 0


def cmd_search(query):
    try:
        geo = get_json("https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode({
            "name": query, "count": 8, "language": ui_lang(), "format": "json"}))
        results = geo.get("results") or []
    except Exception:
        results = []
    items = [{"name": r.get("name", ""), "country": r.get("country", ""),
              "admin": r.get("admin1", ""), "lat": r.get("latitude"),
              "lon": r.get("longitude")} for r in results]
    print(json.dumps({"items": items}, ensure_ascii=False))
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "bar"
    if cmd == "bar":
        return cmd_bar()
    if cmd == "state":
        return cmd_state()
    if cmd == "refresh":
        return cmd_bar(force=True)
    if cmd == "set":
        return cmd_set(argv[2:])
    if cmd == "search" and len(argv) > 2:
        return cmd_search(" ".join(argv[2:]))
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
