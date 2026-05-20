#!/usr/bin/env python3
"""
FH5 车辆详细规格批量抓取工具

从 Forza Wiki (fandom.com) 的每辆车页面抓取 CarInfobox 数据，
包括马力、扭矩、排量、引擎类型、驱动方式、重量、变速箱等。

用法：
    python fetch_fh5_car_specs.py [--limit N] [--dry-run]

输入：
    assets/car_thumbnails/car_index.json（已有的车辆列表）

输出：
    assets/car_thumbnails/car_specs.json（扩充后的完整数据）
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
USER_AGENT = "RideWind-GarageTool/1.0 (car specs fetcher)"

# 布局代码映射
LAYOUT_MAP = {
    'ff': 'Front-Engine, FWD',
    'fr': 'Front-Engine, RWD',
    'f4': 'Front-Engine, AWD',
    'mf': 'Mid-Engine, FWD',
    'mr': 'Mid-Engine, RWD',
    'm4': 'Mid-Engine, AWD',
    'rf': 'Rear-Engine, FWD',
    'rr': 'Rear-Engine, RWD',
    'r4': 'Rear-Engine, AWD',
}

# 进气方式映射
ASPIRATION_MAP = {
    'na': 'Naturally Aspirated',
    'nah': 'NA + Hybrid',
    't': 'Turbocharged',
    'th': 'Turbo + Hybrid',
    'tt': 'Twin-Turbo',
    'tth': 'Twin-Turbo + Hybrid',
    'sc': 'Supercharged',
    'sch': 'Supercharged + Hybrid',
    'ev': 'Electric',
    'h': 'Hybrid',
}

# 产地代码映射
ORIGIN_MAP = {
    'ita': 'Italy', 'ger': 'Germany', 'jpn': 'Japan', 'gbr': 'United Kingdom',
    'usa': 'United States', 'fra': 'France', 'swe': 'Sweden', 'kor': 'South Korea',
    'aus': 'Australia', 'esp': 'Spain', 'cze': 'Czech Republic', 'aut': 'Austria',
    'ned': 'Netherlands', 'bel': 'Belgium', 'can': 'Canada', 'mex': 'Mexico',
    'bra': 'Brazil', 'arg': 'Argentina', 'chn': 'China', 'ind': 'India',
    'mal': 'Malaysia', 'rsa': 'South Africa', 'nzl': 'New Zealand',
}

# 车辆类型映射
TYPE_MAP = {
    'x': 'X class', 's2': 'S2 class', 's1': 'S1 class',
    'a': 'A class', 'b': 'B class', 'c': 'C class', 'd': 'D class',
    'p': 'P class',
}


def api_request(params: dict) -> dict:
    """调用 Fandom MediaWiki API"""
    params["format"] = "json"
    url = f"{API_BASE}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get_car_wikitext(page_title: str) -> str:
    """获取车辆页面的 wikitext"""
    try:
        data = api_request({
            "action": "parse",
            "page": page_title,
            "prop": "wikitext",
        })
        return data.get("parse", {}).get("wikitext", {}).get("*", "")
    except (urllib.error.HTTPError, urllib.error.URLError, KeyError) as e:
        return ""


def parse_car_infobox(wikitext: str) -> dict:
    """从 wikitext 中解析 CarInfobox 模板参数"""
    specs = {}

    # 找到 {{CarInfobox ... }} 块
    match = re.search(r'\{\{CarInfobox(.*?)\}\}', wikitext, re.DOTALL)
    if not match:
        return specs

    infobox_text = match.group(1)

    # 解析 |key = value 对
    for m in re.finditer(r'\|\s*(\w+)\s*=\s*([^\n|{}]*)', infobox_text):
        key = m.group(1).strip()
        value = m.group(2).strip()
        if value:
            specs[key] = value

    return specs


def build_car_page_title(brand: str, model: str) -> str:
    """构建 wiki 页面标题（品牌_车型）"""
    full_name = f"{brand} {model}".strip()
    return full_name


def format_specs(raw: dict) -> dict:
    """将原始 infobox 数据格式化为可读格式"""
    result = {}

    # 年份
    if 'year' in raw:
        result['year'] = raw['year']

    # 产地
    if 'origin' in raw:
        code = raw['origin'].lower()
        result['origin'] = ORIGIN_MAP.get(code, raw['origin'])

    # 引擎
    if 'engine' in raw:
        result['engine'] = raw['engine']

    # 排量
    if 'disp' in raw:
        try:
            disp = float(raw['disp'])
            result['displacement'] = f"{disp}L"
        except ValueError:
            result['displacement'] = raw['disp']

    # 进气方式
    if 'aspiration' in raw:
        code = raw['aspiration'].lower()
        result['aspiration'] = ASPIRATION_MAP.get(code, raw['aspiration'])

    # 马力
    if 'power' in raw:
        try:
            hp = int(raw['power'])
            result['horsepower'] = hp
        except ValueError:
            result['horsepower_str'] = raw['power']

    # 扭矩
    if 'torque' in raw:
        try:
            tq = int(raw['torque'])
            result['torque_lbft'] = tq
        except ValueError:
            result['torque_str'] = raw['torque']

    # 布局/驱动方式
    if 'layout' in raw:
        code = raw['layout'].lower()
        result['layout'] = LAYOUT_MAP.get(code, raw['layout'])
        # 简化驱动方式
        if 'FWD' in result.get('layout', ''):
            result['drivetrain'] = 'FWD'
        elif 'RWD' in result.get('layout', ''):
            result['drivetrain'] = 'RWD'
        elif 'AWD' in result.get('layout', ''):
            result['drivetrain'] = 'AWD'

    # 重量
    if 'weight' in raw:
        try:
            lbs = int(raw['weight'])
            kg = round(lbs * 0.4536)
            result['weight_lbs'] = lbs
            result['weight_kg'] = kg
        except ValueError:
            result['weight_str'] = raw['weight']

    # 变速箱
    if 'gears' in raw:
        try:
            gears = int(raw['gears'])
            result['gears'] = f"{gears}-Speed"
        except ValueError:
            result['gears'] = raw['gears']

    # 前重量分配
    if 'front' in raw:
        try:
            front = int(raw['front'])
            result['weight_dist'] = f"{front}:{100-front} F/R"
        except ValueError:
            pass

    # PI 等级
    if 'type' in raw:
        code = raw['type'].lower()
        result['class'] = TYPE_MAP.get(code, raw['type'])

    return result


def main():
    parser = argparse.ArgumentParser(description="抓取 FH5 车辆详细规格")
    parser.add_argument("--limit", type=int, default=0, help="限制数量（0=全部）")
    parser.add_argument("--dry-run", action="store_true", help="只测试前几辆")
    args = parser.parse_args()

    # 读取现有索引
    script_dir = Path(__file__).parent
    index_path = script_dir.parent / "assets" / "car_thumbnails" / "car_index.json"
    output_path = script_dir.parent / "assets" / "car_thumbnails" / "car_specs.json"

    with open(index_path, "r", encoding="utf-8") as f:
        cars = json.load(f)

    print(f"📋 加载 {len(cars)} 辆车")

    if args.limit > 0:
        cars = cars[:args.limit]
        print(f"   ⚠️ 限制为前 {args.limit} 辆")

    # 逐辆抓取
    results = []
    success = 0
    failed = 0

    for i, car in enumerate(cars):
        brand = car['brand']
        model = car['model']
        page_title = build_car_page_title(brand, model)

        # 获取 wikitext
        wikitext = get_car_wikitext(page_title)

        if wikitext:
            raw_specs = parse_car_infobox(wikitext)
            if raw_specs:
                specs = format_specs(raw_specs)
                car_entry = {**car, "specs": specs}
                results.append(car_entry)
                success += 1

                if args.dry_run and success <= 3:
                    print(f"   ✅ {brand} {model}")
                    for k, v in specs.items():
                        print(f"      {k}: {v}")
            else:
                car_entry = {**car, "specs": {}}
                results.append(car_entry)
                failed += 1
        else:
            # 页面不存在，尝试去掉年份
            model_no_year = re.sub(r'\s+\d{4}$', '', model)
            if model_no_year != model:
                page_title2 = build_car_page_title(brand, model_no_year)
                wikitext = get_car_wikitext(page_title2)
                if wikitext:
                    raw_specs = parse_car_infobox(wikitext)
                    specs = format_specs(raw_specs) if raw_specs else {}
                    car_entry = {**car, "specs": specs}
                    results.append(car_entry)
                    if specs:
                        success += 1
                    else:
                        failed += 1
                else:
                    car_entry = {**car, "specs": {}}
                    results.append(car_entry)
                    failed += 1
            else:
                car_entry = {**car, "specs": {}}
                results.append(car_entry)
                failed += 1

        # 进度
        total = success + failed
        if total % 50 == 0 and total > 0:
            print(f"   进度: {total}/{len(cars)} (✅{success} ❌{failed})")

        # 礼貌延迟
        time.sleep(0.3)

    # 保存结果
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\n🎉 完成！")
    print(f"   ✅ 有规格数据: {success}")
    print(f"   ❌ 无规格数据: {failed}")
    print(f"   📁 保存: {output_path}")


if __name__ == "__main__":
    main()
