#!/usr/bin/env python3
"""
FH5 缺失规格数据补全工具

策略：
1. "Large" 后缀车辆 → 从同名非 Large 版本复制数据
2. 剩余缺失 → 用 Fandom Search API 模糊搜索 wiki 页面
3. 多种页面标题变体尝试（去年份、去特殊字符、品牌+型号组合等）

用法：
    python fill_missing_specs.py [--limit N] [--dry-run] [--skip-network]
"""

import argparse
import json
import re
import time
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path


API_BASE = "https://forza.fandom.com/api.php"
USER_AGENT = "RideWind-GarageTool/1.1 (missing specs filler)"

# 从原始脚本复制的映射表
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
    'aus': 'Australia', 'esp': 'Spain', 'cze': 'Czech Republic', 'aut': 'Austria',
    'ned': 'Netherlands', 'bel': 'Belgium', 'can': 'Canada', 'mex': 'Mexico',
    'bra': 'Brazil', 'arg': 'Argentina', 'chn': 'China', 'ind': 'India',
    'mal': 'Malaysia', 'rsa': 'South Africa', 'nzl': 'New Zealand',
}

TYPE_MAP = {
    'x': 'X class', 's2': 'S2 class', 's1': 'S1 class',
    'a': 'A class', 'b': 'B class', 'c': 'C class', 'd': 'D class', 'p': 'P class',
}


def api_request(params: dict) -> dict:
    """调用 Fandom MediaWiki API"""
    params["format"] = "json"
    url = f"{API_BASE}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
        return {}


def get_car_wikitext(page_title: str) -> str:
    """获取车辆页面的 wikitext"""
    data = api_request({
        "action": "parse",
        "page": page_title,
        "prop": "wikitext",
    })
    return data.get("parse", {}).get("wikitext", {}).get("*", "")


def search_wiki(query: str) -> list:
    """用 Search API 搜索页面"""
    data = api_request({
        "action": "query",
        "list": "search",
        "srsearch": query,
        "srnamespace": "0",
        "srlimit": "5",
    })
    results = data.get("query", {}).get("search", [])
    return [r["title"] for r in results]


def parse_car_infobox(wikitext: str) -> dict:
    """从 wikitext 中解析 CarInfobox 模板参数"""
    specs = {}
    match = re.search(r'\{\{CarInfobox(.*?)\}\}', wikitext, re.DOTALL)
    if not match:
        # 尝试其他 infobox 变体
        match = re.search(r'\{\{Infobox[_ ]?[Cc]ar(.*?)\}\}', wikitext, re.DOTALL)
    if not match:
        return specs

    infobox_text = match.group(1)
    for m in re.finditer(r'\|\s*(\w+)\s*=\s*([^\n|{}]*)', infobox_text):
        key = m.group(1).strip()
        value = m.group(2).strip()
        if value:
            specs[key] = value
    return specs


def format_specs(raw: dict) -> dict:
    """将原始 infobox 数据格式化"""
    result = {}

    if 'year' in raw:
        result['year'] = raw['year']
    if 'origin' in raw:
        code = raw['origin'].lower()
        result['origin'] = ORIGIN_MAP.get(code, raw['origin'])
    if 'engine' in raw:
        result['engine'] = raw['engine']
    if 'disp' in raw:
        try:
            disp = float(raw['disp'])
            result['displacement'] = f"{disp}L"
        except ValueError:
            result['displacement'] = raw['disp']
    if 'aspiration' in raw:
        code = raw['aspiration'].lower()
        result['aspiration'] = ASPIRATION_MAP.get(code, raw['aspiration'])
    if 'power' in raw:
        try:
            result['horsepower'] = int(raw['power'])
        except ValueError:
            pass
    if 'torque' in raw:
        try:
            result['torque_lbft'] = int(raw['torque'])
        except ValueError:
            pass
    if 'layout' in raw:
        code = raw['layout'].lower()
        result['layout'] = LAYOUT_MAP.get(code, raw['layout'])
        if 'FWD' in result.get('layout', ''):
            result['drivetrain'] = 'FWD'
        elif 'RWD' in result.get('layout', ''):
            result['drivetrain'] = 'RWD'
        elif 'AWD' in result.get('layout', ''):
            result['drivetrain'] = 'AWD'
    if 'weight' in raw:
        try:
            lbs = int(raw['weight'])
            result['weight_lbs'] = lbs
            result['weight_kg'] = round(lbs * 0.4536)
        except ValueError:
            pass
    if 'gears' in raw:
        try:
            result['gears'] = f"{int(raw['gears'])}-Speed"
        except ValueError:
            result['gears'] = raw['gears']
    if 'front' in raw:
        try:
            front = int(raw['front'])
            result['weight_dist'] = f"{front}:{100-front} F/R"
        except ValueError:
            pass
    if 'type' in raw:
        code = raw['type'].lower()
        result['class'] = TYPE_MAP.get(code, raw['type'])

    # 极速和加速
    if 'speed' in raw:
        try:
            result['top_speed_kmh'] = int(float(raw['speed']))
        except ValueError:
            pass
    if 'accel' in raw or '0-100' in raw or '0-60' in raw:
        val = raw.get('accel') or raw.get('0-100') or raw.get('0-60')
        if val:
            try:
                result['acceleration_0_100'] = round(float(val), 1)
            except ValueError:
                pass

    return result


def generate_title_variants(brand: str, model: str) -> list:
    """生成多种可能的 wiki 页面标题"""
    full = f"{brand} {model}".strip()
    variants = [full]

    # 去掉 "Large" 后缀
    no_large = re.sub(r'\s+Large$', '', full)
    if no_large != full:
        variants.append(no_large)
        full = no_large  # 后续变体基于去掉 Large 的版本

    # 去掉年份后缀
    no_year = re.sub(r'\s+\d{4}$', '', full)
    if no_year != full:
        variants.append(no_year)

    # 去掉 "FE" (Forza Edition)
    no_fe = re.sub(r'\s+FE$', '', full)
    if no_fe != full:
        variants.append(no_fe)
        no_fe_no_year = re.sub(r'\s+\d{4}$', '', no_fe)
        if no_fe_no_year != no_fe:
            variants.append(no_fe_no_year)

    # 去掉 "WP" (Welcome Pack)
    no_wp = re.sub(r'\s+WP$', '', full)
    if no_wp != full:
        variants.append(no_wp)
        no_wp_no_year = re.sub(r'\s+\d{4}$', '', no_wp)
        if no_wp_no_year != no_wp:
            variants.append(no_wp_no_year)

    # 去掉 "Traffic"
    no_traffic = re.sub(r'\s+Traffic$', '', full)
    if no_traffic != full:
        variants.append(no_traffic)

    # 特殊字符处理 — 去掉引号
    no_quote = full.replace("'", "").replace("'", "")
    if no_quote != full:
        variants.append(no_quote)

    # 去掉括号内容
    no_paren = re.sub(r'\s*\([^)]*\)', '', full)
    if no_paren != full:
        variants.append(no_paren.strip())

    return list(dict.fromkeys(variants))  # 去重保序


def try_fetch_specs(brand: str, model: str) -> dict:
    """尝试多种策略获取车辆规格"""
    variants = generate_title_variants(brand, model)

    # 策略1：直接尝试各种标题变体
    for title in variants:
        wikitext = get_car_wikitext(title)
        if wikitext:
            raw = parse_car_infobox(wikitext)
            if raw:
                return format_specs(raw)
        time.sleep(0.2)

    # 策略2：搜索 API
    search_query = f"{brand} {model}"
    # 清理搜索词
    search_query = search_query.replace(" Large", "").replace(" FE", "").replace(" WP", "").replace(" Traffic", "")
    search_query = re.sub(r'\s+\d{4}$', '', search_query).strip()
    search_query = re.sub(r"[''()]", '', search_query).strip()

    results = search_wiki(search_query)
    time.sleep(0.2)

    for title in results:
        # 只接受包含品牌名的结果
        if brand.lower() in title.lower():
            wikitext = get_car_wikitext(title)
            if wikitext:
                raw = parse_car_infobox(wikitext)
                if raw:
                    return format_specs(raw)
            time.sleep(0.2)

    return {}


def main():
    parser = argparse.ArgumentParser(description="补全 FH5 缺失车辆规格")
    parser.add_argument("--limit", type=int, default=0, help="限制处理数量（0=全部）")
    parser.add_argument("--dry-run", action="store_true", help="只打印不保存")
    parser.add_argument("--skip-network", action="store_true", help="只做 Large 复制，跳过网络请求")
    args = parser.parse_args()

    specs_path = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\car_specs.json')

    with open(specs_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"📋 加载 {len(data)} 辆车")

    # 建立已有数据索引（用于 Large 复制）
    specs_by_name = {}
    for car in data:
        if car.get('specs') and car['specs']:
            specs_by_name[car['full_name']] = car['specs']

    # Phase 1: Large 后缀车辆 → 复制同名非 Large 版本
    print("\n🔄 Phase 1: 复制 Large 变体数据...")
    large_fixed = 0
    for car in data:
        if car.get('specs') and car['specs']:
            continue
        name = car['full_name']
        if 'Large' not in name:
            continue

        # 去掉 Large 后缀寻找原版
        base_name = re.sub(r'\s+Large$', '', name)
        if base_name in specs_by_name:
            car['specs'] = specs_by_name[base_name].copy()
            large_fixed += 1
            if large_fixed <= 5:
                print(f"   ✅ {name} ← 复制自 {base_name}")

    print(f"   Large 复制完成: {large_fixed} 辆")

    # 更新索引（Large 复制后的新数据也可用于后续）
    for car in data:
        if car.get('specs') and car['specs']:
            specs_by_name[car['full_name']] = car['specs']

    # Phase 2: 网络抓取剩余缺失
    if not args.skip_network:
        still_empty = [c for c in data if not c.get('specs') or not c['specs']]
        print(f"\n🌐 Phase 2: 网络抓取剩余 {len(still_empty)} 辆...")

        if args.limit > 0:
            still_empty = still_empty[:args.limit]
            print(f"   ⚠️ 限制为 {args.limit} 辆")

        network_fixed = 0
        network_failed = 0

        for i, car in enumerate(still_empty):
            brand = car['brand']
            model = car['model']

            specs = try_fetch_specs(brand, model)
            if specs:
                car['specs'] = specs
                network_fixed += 1
                if network_fixed <= 10 or network_fixed % 20 == 0:
                    print(f"   ✅ [{i+1}/{len(still_empty)}] {car['full_name']} → {specs.get('horsepower', '?')}hp")
            else:
                network_failed += 1
                if network_failed <= 10:
                    print(f"   ❌ [{i+1}/{len(still_empty)}] {car['full_name']}")

            # 进度报告
            total_done = network_fixed + network_failed
            if total_done % 50 == 0 and total_done > 0:
                print(f"   📊 进度: {total_done}/{len(still_empty)} (✅{network_fixed} ❌{network_failed})")

            time.sleep(0.3)

        print(f"\n   网络抓取完成: ✅{network_fixed} ❌{network_failed}")

    # 最终统计
    final_empty = [c for c in data if not c.get('specs') or not c['specs']]
    final_has = [c for c in data if c.get('specs') and c['specs']]
    print(f"\n📊 最终统计:")
    print(f"   有数据: {len(final_has)} / {len(data)}")
    print(f"   仍缺失: {len(final_empty)} / {len(data)}")

    # 保存
    if not args.dry_run:
        with open(specs_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"\n💾 已保存: {specs_path}")
    else:
        print("\n⚠️ Dry-run 模式，未保存")


if __name__ == "__main__":
    main()
