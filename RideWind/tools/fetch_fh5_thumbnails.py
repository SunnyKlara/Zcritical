#!/usr/bin/env python3
"""
FH5 车辆缩略图批量下载工具

从 Forza Wiki (fandom.com) 的 Category:Thumbnails_(FH5) 批量下载
全部 ~916 张官方车辆缩略图（透明背景 PNG）。

用法：
    python fetch_fh5_thumbnails.py [--output DIR] [--dry-run] [--limit N]

输出：
    默认保存到 ../assets/car_thumbnails/
    同时生成 car_index.json（文件名→车辆信息映射）
"""

import argparse
import json
import os
import re
import time
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path


API_BASE = "https://forza.fandom.com/api.php"
CATEGORY = "Category:Thumbnails_(FH5)"
USER_AGENT = "RideWind-GarageTool/1.0 (car thumbnail fetcher)"


def api_request(params: dict) -> dict:
    """调用 Fandom MediaWiki API"""
    params["format"] = "json"
    url = f"{API_BASE}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get_category_members() -> list:
    """获取 Category:Thumbnails_(FH5) 下所有文件名"""
    titles = []
    params = {
        "action": "query",
        "list": "categorymembers",
        "cmtitle": CATEGORY,
        "cmtype": "file",
        "cmlimit": "500",
    }

    while True:
        data = api_request(params)
        members = data.get("query", {}).get("categorymembers", [])
        for m in members:
            titles.append(m["title"])
        
        # 分页
        cont = data.get("continue")
        if cont and "cmcontinue" in cont:
            params["cmcontinue"] = cont["cmcontinue"]
            print(f"  已获取 {len(titles)} 个文件名，继续翻页...")
            time.sleep(0.5)  # 礼貌延迟
        else:
            break

    return titles


def get_image_urls(titles: list) -> dict:
    """批量获取图片的真实下载 URL（每次最多 50 个）"""
    url_map = {}
    batch_size = 50

    for i in range(0, len(titles), batch_size):
        batch = titles[i:i + batch_size]
        params = {
            "action": "query",
            "titles": "|".join(batch),
            "prop": "imageinfo",
            "iiprop": "url",
        }
        data = api_request(params)
        pages = data.get("query", {}).get("pages", {})
        for page in pages.values():
            title = page.get("title", "")
            imageinfo = page.get("imageinfo", [])
            if imageinfo:
                url_map[title] = imageinfo[0]["url"]

        print(f"  已获取 {len(url_map)}/{len(titles)} 个图片 URL")
        time.sleep(0.3)

    return url_map


def parse_car_info(filename: str) -> dict:
    """从文件名解析车辆信息
    
    文件名格式示例：
      File:FH5 Ferrari LaFerrari.png
      File:FH5 BMW M3.png
      File:FH5 Porsche 911 GT3 RS.png
      File:FH5 Aston Martin DBS Superleggera.png
    """
    # 去掉 "File:" 前缀和扩展名
    name = filename.replace("File:", "")
    name = re.sub(r'\.(png|PNG|jpg|JPG)$', '', name)
    
    # 去掉 "FH5 " 前缀
    if name.startswith("FH5 "):
        name = name[4:]
    
    # 尝试分离品牌和车型
    # 已知的多词品牌
    multi_word_brands = [
        "Aston Martin", "Alfa Romeo", "Land Rover", "Range Rover",
        "Mercedes-Benz", "Mercedes-AMG", "De Tomaso", "Can-Am",
        "Radical Sportscars", "Local Motors", "Hot Wheels",
        "Forza Edition", "Barrett-Jackson", "Hoonigan", "Vuhl",
    ]
    
    brand = ""
    model = name
    
    for b in multi_word_brands:
        if name.startswith(b + " "):
            brand = b
            model = name[len(b) + 1:]
            break
    
    if not brand:
        # 单词品牌：取第一个词
        parts = name.split(" ", 1)
        brand = parts[0]
        model = parts[1] if len(parts) > 1 else ""
    
    return {
        "brand": brand,
        "model": model,
        "full_name": name,
    }


def sanitize_filename(name: str) -> str:
    """清理文件名，去掉不安全字符"""
    # 去掉 File: 前缀
    name = name.replace("File:", "")
    # 替换不安全字符
    name = re.sub(r'[<>:"/\\|?*]', '_', name)
    return name


def download_image(url: str, output_path: Path) -> bool:
    """下载单张图片"""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
            output_path.write_bytes(data)
            return True
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        print(f"    ❌ 下载失败: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="下载 FH5 车辆缩略图")
    parser.add_argument(
        "--output", "-o",
        default=None,
        help="输出目录（默认: ../assets/car_thumbnails/）"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只获取列表和 URL，不下载图片"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="限制下载数量（0=全部）"
    )
    args = parser.parse_args()

    # 确定输出目录
    if args.output:
        output_dir = Path(args.output)
    else:
        script_dir = Path(__file__).parent
        output_dir = script_dir.parent / "assets" / "car_thumbnails"

    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"📁 输出目录: {output_dir}")

    # Step 1: 获取分类下所有文件名
    print("\n🔍 Step 1: 获取 FH5 缩略图文件列表...")
    titles = get_category_members()
    print(f"   ✅ 共找到 {len(titles)} 张缩略图")

    if args.limit > 0:
        titles = titles[:args.limit]
        print(f"   ⚠️ 限制为前 {args.limit} 张")

    # Step 2: 批量获取图片 URL
    print("\n🔗 Step 2: 获取图片下载 URL...")
    url_map = get_image_urls(titles)
    print(f"   ✅ 成功获取 {len(url_map)} 个 URL")

    # Step 3: 构建索引
    print("\n📋 Step 3: 构建车辆索引...")
    car_index = []
    for title, url in url_map.items():
        info = parse_car_info(title)
        filename = sanitize_filename(title)
        info["filename"] = filename
        info["url"] = url
        car_index.append(info)

    # 按品牌排序
    car_index.sort(key=lambda x: (x["brand"], x["model"]))

    # 保存索引
    index_path = output_dir / "car_index.json"
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(car_index, f, ensure_ascii=False, indent=2)
    print(f"   ✅ 索引已保存: {index_path} ({len(car_index)} 辆车)")

    # 统计品牌
    brands = set(c["brand"] for c in car_index)
    print(f"   📊 共 {len(brands)} 个品牌")

    if args.dry_run:
        print("\n⏭️ Dry run 模式，跳过下载")
        print(f"   前 5 辆车示例:")
        for car in car_index[:5]:
            print(f"     {car['brand']} {car['model']}")
            print(f"       → {car['url'][:80]}...")
        return

    # Step 4: 下载图片
    print(f"\n⬇️ Step 4: 下载 {len(url_map)} 张图片...")
    success = 0
    failed = 0
    skipped = 0

    for i, (title, url) in enumerate(url_map.items()):
        filename = sanitize_filename(title)
        output_path = output_dir / filename

        # 跳过已存在的文件
        if output_path.exists():
            skipped += 1
            continue

        if download_image(url, output_path):
            success += 1
        else:
            failed += 1

        # 进度显示（每 50 张）
        total_done = success + failed + skipped
        if total_done % 50 == 0:
            print(f"   进度: {total_done}/{len(url_map)} "
                  f"(✅{success} ❌{failed} ⏭️{skipped})")

        # 礼貌延迟（避免被限流）
        time.sleep(0.2)

    print(f"\n🎉 完成！")
    print(f"   ✅ 成功下载: {success}")
    print(f"   ⏭️ 已跳过（已存在）: {skipped}")
    print(f"   ❌ 失败: {failed}")
    print(f"   📁 保存位置: {output_dir}")
    print(f"   📋 索引文件: {index_path}")


if __name__ == "__main__":
    main()
