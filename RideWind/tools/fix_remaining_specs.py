#!/usr/bin/env python3
"""
手动补全剩余 28 辆缺失数据的车辆

策略：
1. VW → 用 Volkswagen 重新搜索
2. HOR XB1 → 去掉前缀用真实车名搜索
3. Leaked → 去掉前缀搜索
4. 特殊车辆 → 手动填入已知数据
"""

import json
import re
import time
import urllib.request
import urllib.parse
from pathlib import Path

API_BASE = "https://forza.fandom.com/api.php"
USER_AGENT = "RideWind-GarageTool/1.2 (remaining specs fix)"

LAYOUT_MAP = {
    'ff': 'Front-Engine, FWD', 'fr': 'Front-Engine, RWD', 'f4': 'Front-Engine, AWD',
    'mf': 'Mid-Engine, FWD', 'mr': 'Mid-Engine, RWD', 'm4': 'Mid-Engine, AWD',
    'rf': 'Rear-Engine, FWD', 'rr': 'Rear-Engine, RWD', 'r4': 'Rear-Engine, AWD',
}
ASPIRATION_MAP = {
    'na': 'Naturally Aspirated', 'nah': 'NA + Hybrid',
    't': 'Turbocharged', 'th': 'Turbo + Hybrid',
    'tt': 'Twin-Turbo', 'tth': 'Twin-Turbo + Hybrid',
    'sc': 'Supercharged', 'sch': 'Supercharged + Hybrid',
    'ev': 'Electric', 'h': 'Hybrid',
}
ORIGIN_MAP = {
    'ita': 'Italy', 'ger': 'Germany', 'jpn': 'Japan', 'gbr': 'United Kingdom',
    'usa': 'United States', 'fra': 'France', 'swe': 'Sweden', 'kor': 'South Korea',
    'aus': 'Australia', 'esp': 'Spain', 'cze': 'Czech Republic',
}
TYPE_MAP = {
    'x': 'X class', 's2': 'S2 class', 's1': 'S1 class',
    'a': 'A class', 'b': 'B class', 'c': 'C class', 'd': 'D class', 'p': 'P class',
}


def api_request(params):
    params["format"] = "json"
    url = f"{API_BASE}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return {}


def get_car_wikitext(page_title):
    data = api_request({"action": "parse", "page": page_title, "prop": "wikitext"})
    return data.get("parse", {}).get("wikitext", {}).get("*", "")


def search_wiki(query):
    data = api_request({"action": "query", "list": "search", "srsearch": query, "srnamespace": "0", "srlimit": "5"})
    return [r["title"] for r in data.get("query", {}).get("search", [])]


def parse_car_infobox(wikitext):
    match = re.search(r'\{\{CarInfobox(.*?)\}\}', wikitext, re.DOTALL)
    if not match:
        match = re.search(r'\{\{Infobox[_ ]?[Cc]ar(.*?)\}\}', wikitext, re.DOTALL)
    if not match:
        return {}
    specs = {}
    for m in re.finditer(r'\|\s*(\w+)\s*=\s*([^\n|{}]*)', match.group(1)):
        key, value = m.group(1).strip(), m.group(2).strip()
        if value:
            specs[key] = value
    return specs


def format_specs(raw):
    result = {}
    if 'year' in raw: result['year'] = raw['year']
    if 'origin' in raw: result['origin'] = ORIGIN_MAP.get(raw['origin'].lower(), raw['origin'])
    if 'engine' in raw: result['engine'] = raw['engine']
    if 'disp' in raw:
        try: result['displacement'] = f"{float(raw['disp'])}L"
        except: result['displacement'] = raw['disp']
    if 'aspiration' in raw: result['aspiration'] = ASPIRATION_MAP.get(raw['aspiration'].lower(), raw['aspiration'])
    if 'power' in raw:
        try: result['horsepower'] = int(raw['power'])
        except: pass
    if 'torque' in raw:
        try: result['torque_lbft'] = int(raw['torque'])
        except: pass
    if 'layout' in raw:
        code = raw['layout'].lower()
        result['layout'] = LAYOUT_MAP.get(code, raw['layout'])
        if 'FWD' in result.get('layout', ''): result['drivetrain'] = 'FWD'
        elif 'RWD' in result.get('layout', ''): result['drivetrain'] = 'RWD'
        elif 'AWD' in result.get('layout', ''): result['drivetrain'] = 'AWD'
    if 'weight' in raw:
        try:
            lbs = int(raw['weight'])
            result['weight_lbs'] = lbs
            result['weight_kg'] = round(lbs * 0.4536)
        except: pass
    if 'gears' in raw:
        try: result['gears'] = f"{int(raw['gears'])}-Speed"
        except: result['gears'] = raw['gears']
    if 'front' in raw:
        try:
            front = int(raw['front'])
            result['weight_dist'] = f"{front}:{100-front} F/R"
        except: pass
    if 'type' in raw: result['class'] = TYPE_MAP.get(raw['type'].lower(), raw['type'])
    return result


def try_search_fetch(search_term):
    """搜索并获取规格"""
    wikitext = get_car_wikitext(search_term)
    if wikitext:
        raw = parse_car_infobox(wikitext)
        if raw:
            return format_specs(raw)
    time.sleep(0.3)

    results = search_wiki(search_term)
    time.sleep(0.3)
    for title in results:
        wikitext = get_car_wikitext(title)
        if wikitext:
            raw = parse_car_infobox(wikitext)
            if raw:
                return format_specs(raw)
        time.sleep(0.2)
    return {}


# 手动数据（无法从 wiki 获取的车辆）
MANUAL_SPECS = {
    "DeBerti Chevrolet Silverado 1500 DT": {
        "year": "2019", "origin": "United States", "engine": "V8",
        "displacement": "6.2L", "aspiration": "Supercharged",
        "horsepower": 1000, "torque_lbft": 850, "drivetrain": "AWD",
        "weight_kg": 2500, "weight_lbs": 5512, "gears": "10-Speed",
        "layout": "Front-Engine, AWD"
    },
    "Extreme E Odyseey 21 e-SUV 55 Acciona Sainz XE Team Large": {
        "year": "2021", "origin": "Spain", "engine": "Electric Dual Motor",
        "displacement": "N/A", "aspiration": "Electric",
        "horsepower": 544, "torque_lbft": 538, "drivetrain": "AWD",
        "weight_kg": 1780, "weight_lbs": 3924, "gears": "1-Speed",
        "layout": "Mid-Engine, AWD"
    },
    "XB1 Cadillac CT5-V": {
        "year": "2022", "origin": "United States", "engine": "V8",
        "displacement": "6.2L", "aspiration": "Supercharged",
        "horsepower": 668, "torque_lbft": 659, "drivetrain": "RWD",
        "weight_kg": 1928, "weight_lbs": 4251, "gears": "10-Speed",
        "layout": "Front-Engine, RWD"
    },
}


def get_search_name(full_name):
    """从特殊命名中提取可搜索的车名"""
    name = full_name

    # 去掉 HOR XB1 前缀 + 可能的年份缩写
    name = re.sub(r'^HOR XB1\s+\d*\s*', '', name)
    # 去掉 XB1 前缀
    name = re.sub(r'^XB1\s+', '', name)
    # 去掉 Leaked 前缀
    name = re.sub(r'^Leaked\s+', '', name)
    # 去掉 Fh5 前缀
    name = re.sub(r'^Fh5\s+', '', name)
    # 去掉 Large 后缀
    name = re.sub(r'\s+Large$', '', name)
    # VW → Volkswagen
    name = re.sub(r'^VW\b', 'Volkswagen', name)

    return name.strip()


def main():
    specs_path = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\car_specs.json')

    with open(specs_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    empty = [c for c in data if not c.get('specs') or not c['specs']]
    print(f"📋 剩余缺失: {len(empty)} 辆\n")

    fixed = 0
    still_missing = 0

    for car in empty:
        name = car['full_name']

        # 先检查手动数据
        if name in MANUAL_SPECS:
            car['specs'] = MANUAL_SPECS[name]
            fixed += 1
            print(f"  ✅ [手动] {name} → {car['specs'].get('horsepower', '?')}hp")
            continue

        # 提取可搜索名称
        search_name = get_search_name(name)
        if search_name == name:
            still_missing += 1
            print(f"  ❌ [跳过] {name}")
            continue

        print(f"  🔍 {name} → 搜索 '{search_name}'...", end=" ")
        specs = try_search_fetch(search_name)
        if specs:
            car['specs'] = specs
            fixed += 1
            print(f"✅ {specs.get('horsepower', '?')}hp")
        else:
            still_missing += 1
            print("❌")

        time.sleep(0.3)

    print(f"\n📊 结果: ✅{fixed} ❌{still_missing}")

    final_empty = [c for c in data if not c.get('specs') or not c['specs']]
    final_has = [c for c in data if c.get('specs') and c['specs']]
    print(f"   总计有数据: {len(final_has)} / {len(data)}")
    print(f"   仍缺失: {len(final_empty)} / {len(data)}")

    with open(specs_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"\n💾 已保存")


if __name__ == "__main__":
    main()
