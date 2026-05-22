#!/usr/bin/env python3
"""
引擎声音映射系统 — 为 915 辆车建立声音 profile 映射

策略：
1. 从 TheDIYGuy999 声音库中提取所有可用引擎声音 profile（~20种）
2. 根据每辆车的 engine/aspiration/displacement/brand 自动映射到最佳声音 profile
3. 热门车型尽量一对一匹配（Ferrari→LaFerrari, Mustang→1965FordMustang, etc.）
4. 输出 engine_sound_map.json 供 APP 和硬件使用
"""

import json
import re
from pathlib import Path

# ═══════════════════════════════════════════════════════════════
#  声音 Profile 定义 — 从 TheDIYGuy999 车辆配置中提取
# ═══════════════════════════════════════════════════════════════

SOUND_PROFILES = [
    {
        "profile_id": "ferrari_v12",
        "display_name": "Ferrari V12 (LaFerrari)",
        "engine_type": "V12", "aspiration": "NA", "character": "high_rev_exotic",
        "files": {"idle": "LaFerrariIdle.h", "rev": "LaFerrariRev.h", "knock": "LaFerrariKnock.h", "start": "LaFerrariStart.h"},
        "config": {"cylinders": 12, "knock_interval": 12, "v_type": "V12"}
    },
    {
        "profile_id": "jaguar_v12",
        "display_name": "Jaguar V12 (XJS)",
        "engine_type": "V12", "aspiration": "NA", "character": "smooth_gt",
        "files": {"idle": "JaguarXJSidle2.h", "rev": "JaguarXJSrev2.h", "knock": "LaFerrariKnock.h", "start": "JaguarXJSstart.h"},
        "config": {"cylinders": 12, "knock_interval": 12, "v_type": "V12"}
    },
    {
        "profile_id": "muscle_v8_classic",
        "display_name": "Classic Muscle V8 (1965 Mustang)",
        "engine_type": "V8", "aspiration": "NA", "character": "muscle_rumble",
        "files": {"idle": "1965FordMustangV8idle.h", "rev": "1965FordMustangV8rev.h", "knock": "1965FordMustangV8knock.h", "start": "1965FordMustangV8start.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "muscle_v8_modern",
        "display_name": "Modern Muscle V8 (Supercharged)",
        "engine_type": "V8", "aspiration": "Supercharged", "character": "supercharged_roar",
        "files": {"idle": "JeepGrandCherokeeTrackhawkIdle.h", "rev": "JeepWranglerRubicon392V8Rev.h", "knock": "JeepGrandCherokeeTrackhawkKnock.h", "start": "JeepGrandCherokeeTrackhawkStart.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "chevy_bigblock_v8",
        "display_name": "Chevy Big Block V8 (468)",
        "engine_type": "V8", "aspiration": "NA", "character": "deep_rumble",
        "files": {"idle": "468ChevyBigBlockIdle.h", "rev": "468ChevyBigBlockRev.h", "knock": "468ChevyBigBlockKnock.h", "start": "468ChevyBigBlockStart.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "chevy_smallblock_v8",
        "display_name": "Chevy Small Block V8 (Nova)",
        "engine_type": "V8", "aspiration": "NA", "character": "sporty_v8",
        "files": {"idle": "ChevyNovaCoupeV8idle.h", "rev": "ChevyNovaCoupeV8rev.h", "knock": "ChevyNovaCoupeV8knock.h", "start": "468ChevyBigBlockStart.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "ls3_v8",
        "display_name": "LS3 V8 (6.2L Modern)",
        "engine_type": "V8", "aspiration": "NA", "character": "modern_v8",
        "files": {"idle": "62LS3Idle.h", "rev": "62LS3Rev.h", "knock": "62LS3Knock.h", "start": "62LS3Start.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "jeep_v8",
        "display_name": "Jeep Wrangler V8 (392)",
        "engine_type": "V8", "aspiration": "NA", "character": "offroad_v8",
        "files": {"idle": "JeepWranglerRubicon392V8Idle.h", "rev": "JeepWranglerRubicon392V8Rev.h", "knock": "JeepWranglerRubicon392V8Knock.h", "start": "JeepWranglerRubicon392V8Start.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "british_v8",
        "display_name": "British V8 (Defender Open Pipe)",
        "engine_type": "V8", "aspiration": "NA", "character": "british_burble",
        "files": {"idle": "DefenderV8OpenPipeIdle.h", "rev": "DefenderV8OpenPipeRev.h", "knock": "DefenderV8OpenPipeKnock.h", "start": "DefenderV8OpenPipeStart.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "mgb_v8",
        "display_name": "MGB GT V8 (Light British)",
        "engine_type": "V8", "aspiration": "NA", "character": "light_v8",
        "files": {"idle": "MGBGtV8idle.h", "rev": "MGBGtV8rev.h", "knock": "MGBGtV8knock.h", "start": "MGBGtV8start.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "dodge_v8",
        "display_name": "Dodge HEMI V8 (Challenger)",
        "engine_type": "V8", "aspiration": "NA", "character": "hemi_rumble",
        "files": {"idle": "DodgeChallenger70Idle.h", "rev": "ChevyNovaCoupeV8rev.h", "knock": "demonhawkKnock.h", "start": "1965FordMustangV8start.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "gmc_pickup_v8",
        "display_name": "GMC Sierra Pickup V8",
        "engine_type": "V8", "aspiration": "NA", "character": "truck_v8",
        "files": {"idle": "GMCSierraPickupIdle.h", "rev": "GMCSierraPickupRev.h", "knock": "GMCSierraPickupKnock.h", "start": "ChevyPickupV8SoundStart.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "chevy_pickup_v8",
        "display_name": "Chevy Pickup V8",
        "engine_type": "V8", "aspiration": "NA", "character": "pickup_rumble",
        "files": {"idle": "ChevyPickupV8SoundIdle.h", "rev": "ChevyPickupV8SoundRev.h", "knock": "ChevyPickupV8SoundKnock.h", "start": "ChevyPickupV8SoundStart.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "straightpipe_v8",
        "display_name": "Straight-Piped V8 (Race Exhaust)",
        "engine_type": "V8", "aspiration": "NA", "character": "race_exhaust",
        "files": {"idle": "ChevyNovaCoupeV8idle.h", "rev": "straightPipedCompilationRev.h", "knock": "straightPipedCompilationKnock.h", "start": "1965FordMustangV8start.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "harley_vtwin",
        "display_name": "Harley-Davidson V-Twin",
        "engine_type": "V2", "aspiration": "NA", "character": "vtwin_potato",
        "files": {"idle": "HarleyDavidsonFXSBIdle.h", "rev": "HarleyDavidsonFXSBrev.h", "knock": "HarleyDavidsonFXSBKnock.h", "start": "HarleyDavidsonFXSBStart.h"},
        "config": {"cylinders": 2, "knock_interval": 4, "v_type": "V2"}
    },
    {
        "profile_id": "vw_flat4",
        "display_name": "VW Beetle Flat-4 (Air-Cooled)",
        "engine_type": "F4", "aspiration": "NA", "character": "aircooled_buzz",
        "files": {"idle": "VWBeetleIdle.h", "rev": "VWBeetleRev.h", "knock": "VWBeetleKnock.h", "start": "VWBeetleStart.h"},
        "config": {"cylinders": 4, "knock_interval": 4, "v_type": "F4"}
    },
    {
        "profile_id": "toyota_i6",
        "display_name": "Toyota I6 (FJ40 Land Cruiser)",
        "engine_type": "I6", "aspiration": "NA", "character": "smooth_i6",
        "files": {"idle": "FJ40idle.h", "rev": "FJ40rev.h", "knock": "FJ40knock.h", "start": "LaFerrariStart.h"},
        "config": {"cylinders": 6, "knock_interval": 6, "v_type": "I6"}
    },
    {
        "profile_id": "scania_v8_turbo",
        "display_name": "Scania V8 1000HP (Twin-Turbo)",
        "engine_type": "V8", "aspiration": "Twin-Turbo", "character": "turbo_v8",
        "files": {"idle": "1000HpScaniaV8idle.h", "rev": "1000HpScaniaV8rev.h", "knock": "1000HpScaniaV8knock.h", "start": "Scania143start4.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "cummins_diesel",
        "display_name": "Cummins 6BTA Diesel I6",
        "engine_type": "I6", "aspiration": "Turbocharged", "character": "diesel_i6",
        "files": {"idle": "Cummins6BTAIdle.h", "rev": "Cummins6BTARev.h", "knock": "Cummins6BTAKnock.h", "start": "Cummins6BTAStart.h"},
        "config": {"cylinders": 6, "knock_interval": 6, "v_type": "I6"}
    },
    {
        "profile_id": "defender_td5",
        "display_name": "Land Rover Td5 Diesel I5",
        "engine_type": "I5", "aspiration": "Turbocharged", "character": "diesel_suv",
        "files": {"idle": "DefenderTd5idle.h", "rev": "DefenderTd5rev.h", "knock": "DefenderTd5knock.h", "start": "DefenderTd5start.h"},
        "config": {"cylinders": 5, "knock_interval": 5, "v_type": "I5"}
    },
    {
        "profile_id": "powerstroke_diesel",
        "display_name": "Ford Powerstroke Diesel V8",
        "engine_type": "V8", "aspiration": "Turbocharged", "character": "diesel_truck",
        "files": {"idle": "POWERSTROKEidle.h", "rev": "POWERSTROKErev2.h", "knock": "POWERSTROKEknock.h", "start": "POWERSTROKEstart2.h"},
        "config": {"cylinders": 8, "knock_interval": 8, "v_type": "V8"}
    },
    {
        "profile_id": "electric",
        "display_name": "Electric Motor (EV)",
        "engine_type": "Electric", "aspiration": "Electric", "character": "ev_whine",
        "files": {"idle": "idleDummy.h", "rev": "idleDummy.h", "knock": "DieselKnockDummy.h", "start": "idleDummy.h"},
        "config": {"cylinders": 0, "knock_interval": 1, "v_type": "EV"}
    },
]

# ═══════════════════════════════════════════════════════════════
#  品牌/车型 → 声音 Profile 优先映射
# ═══════════════════════════════════════════════════════════════

BRAND_OVERRIDES = {
    "Ferrari": "ferrari_v12", "Lamborghini": "ferrari_v12", "Pagani": "ferrari_v12",
    "Maserati": "ferrari_v12", "McLaren": "ferrari_v12",
    "Aston Martin": "jaguar_v12", "Jaguar": "jaguar_v12",
    "Shelby": "muscle_v8_classic", "Plymouth": "muscle_v8_classic",
    "Pontiac": "muscle_v8_classic", "AMC": "muscle_v8_classic",
    "Buick": "chevy_bigblock_v8", "Dodge": "dodge_v8",
    "Jeep": "jeep_v8", "Hummer": "jeep_v8",
}

MODEL_OVERRIDES = {
    "Ford Mustang": "muscle_v8_classic", "Ford GT": "ferrari_v12",
    "Ford F-150": "chevy_pickup_v8", "Ford Bronco": "jeep_v8",
    "Chevrolet Corvette": "ls3_v8", "Chevrolet Camaro": "chevy_smallblock_v8",
    "Chevrolet Silverado": "chevy_pickup_v8", "Chevrolet Chevelle": "chevy_bigblock_v8",
    "BMW M3": "straightpipe_v8", "BMW M4": "straightpipe_v8",
    "BMW M5": "straightpipe_v8", "BMW M8": "straightpipe_v8",
    "Porsche 911": "vw_flat4", "Porsche 918": "ferrari_v12", "Porsche Taycan": "electric",
    "Land Rover": "british_v8", "Range Rover": "british_v8",
    "GMC Sierra": "gmc_pickup_v8", "Ram": "cummins_diesel",
    "Toyota Land Cruiser": "toyota_i6", "Toyota FJ": "toyota_i6",
    "Volkswagen Beetle": "vw_flat4", "Volkswagen ID": "electric",
    "Rimac": "electric", "Lotus Evija": "electric",
    "Koenigsegg Gemera": "ferrari_v12", "Bugatti": "ferrari_v12",
}


def match_engine_type(engine_str, aspiration_str, displacement_str, brand, model):
    """根据引擎参数智能匹配声音 profile"""
    full_name = f"{brand} {model}"

    # 1. 具体车型覆盖
    for key, profile_id in MODEL_OVERRIDES.items():
        if key.lower() in full_name.lower():
            return profile_id

    # 2. 品牌覆盖
    if brand in BRAND_OVERRIDES:
        return BRAND_OVERRIDES[brand]

    # 3. 电动车检测
    if aspiration_str and 'electric' in aspiration_str.lower():
        return "electric"
    if engine_str and ('electric' in engine_str.lower() or 'ev' in engine_str.lower()):
        return "electric"

    # 4. 根据引擎类型匹配
    engine = (engine_str or "").upper()
    aspiration = (aspiration_str or "").lower()
    displacement = 0.0
    if displacement_str:
        m = re.search(r'([\d.]+)', displacement_str)
        if m:
            displacement = float(m.group(1))

    if 'V12' in engine or 'W12' in engine or 'W16' in engine:
        return "ferrari_v12"
    if 'V10' in engine:
        return "ferrari_v12"
    if 'V8' in engine:
        if 'turbo' in aspiration or 'twin' in aspiration:
            return "scania_v8_turbo"
        if 'supercharged' in aspiration:
            return "muscle_v8_modern"
        if displacement >= 6.0:
            return "chevy_bigblock_v8"
        if displacement >= 5.0:
            return "ls3_v8"
        return "chevy_smallblock_v8"
    if 'V6' in engine:
        if 'turbo' in aspiration:
            return "straightpipe_v8"
        return "mgb_v8"
    if 'I6' in engine or 'INLINE' in engine and '6' in engine:
        if 'turbo' in aspiration:
            return "cummins_diesel"
        return "toyota_i6"
    if 'I4' in engine or 'INLINE' in engine and '4' in engine:
        if 'turbo' in aspiration:
            return "defender_td5"
        return "vw_flat4"
    if 'I5' in engine:
        return "defender_td5"
    if 'I3' in engine or 'I2' in engine:
        return "vw_flat4"
    if 'F4' in engine or 'H4' in engine or 'FLAT' in engine or 'BOXER' in engine:
        return "vw_flat4"
    if 'F6' in engine or 'H6' in engine:
        return "vw_flat4"
    if 'ROTARY' in engine or 'WANKEL' in engine:
        return "straightpipe_v8"

    # 默认根据排量
    if displacement >= 5.0:
        return "chevy_bigblock_v8"
    if displacement >= 3.0:
        return "chevy_smallblock_v8"
    if displacement >= 1.5:
        return "mgb_v8"
    return "ls3_v8"


def main():
    specs_path = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\car_specs.json')
    output_path = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\engine_sound_map.json')

    with open(specs_path, 'r', encoding='utf-8') as f:
        cars = json.load(f)

    print(f"📋 加载 {len(cars)} 辆车")
    print(f"🔊 可用声音 Profile: {len(SOUND_PROFILES)} 种\n")

    profiles_by_id = {p["profile_id"]: p for p in SOUND_PROFILES}
    car_sound_assignments = []
    profile_usage = {}

    for car in cars:
        specs = car.get('specs', {})
        if not specs:
            profile_id = "ls3_v8"
        else:
            profile_id = match_engine_type(
                specs.get('engine', ''), specs.get('aspiration', ''),
                specs.get('displacement', ''), car.get('brand', ''), car.get('model', '')
            )

        car_sound_assignments.append({
            "full_name": car['full_name'],
            "brand": car['brand'],
            "model": car['model'],
            "sound_profile": profile_id,
        })
        profile_usage[profile_id] = profile_usage.get(profile_id, 0) + 1

    print("📊 声音 Profile 使用分布:")
    print("-" * 60)
    for pid, count in sorted(profile_usage.items(), key=lambda x: -x[1]):
        profile = profiles_by_id.get(pid, {})
        name = profile.get('display_name', pid)
        print(f"  {name:45s} | {count:3d} cars")
    print("-" * 60)
    print(f"  Total: {sum(profile_usage.values())} cars, {len(profile_usage)} profiles used")

    output = {
        "version": "1.0.0",
        "description": "RideWind Engine Sound Map - 915 cars mapped to sound profiles",
        "profiles": SOUND_PROFILES,
        "car_assignments": car_sound_assignments,
        "stats": {"total_cars": len(cars), "total_profiles": len(SOUND_PROFILES), "profile_usage": profile_usage}
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n💾 已保存: {output_path}")


if __name__ == "__main__":
    main()
