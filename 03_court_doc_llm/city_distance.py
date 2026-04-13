#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
city_distance_panel.py
----------------------
1. 修改 INPUT_FILE、OUTPUT_FILE 为你的文件路径
2. python city_distance_panel.py
"""

import pandas as pd
import itertools
import math
import sys
from pathlib import Path

# ======= 0. 手动设定输入 / 输出路径 =======
INPUT_FILE  = Path("./data/city_coordinates.csv")   # city name, latitude, longitude
OUTPUT_FILE = Path("./data/city_pairs.csv")

# 是否生成双向配对（A→B 与 B→A 都保留）
BIDIRECTIONAL = False     

# 地球半径（公里）
EARTH_RADIUS = 6371.0     

# ---------- 1. Haversine 距离函数 ----------
def haversine(lat1: float, lon1: float, lat2: float, lon2: float, R: float = EARTH_RADIUS) -> float:
    """根据半正矢公式计算两经纬度点的大圆距离（单位与 R 相同，默认公里）。"""
    phi1, phi2 = map(math.radians, (lat1, lat2))
    dphi, dlambda = map(math.radians, (lat2 - lat1, lon2 - lon1))
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# ---------- 2. 读取并标准化列 ----------
def load_city_data(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    expected_cols = {
        "city":     ["city", "城市", "City", "城市名称"],
        "province": ["province", "省份", "Province", "admin_name"],
        "lat":      ["lat", "latitude", "纬度"],
        "lon":      ["lon", "lng", "longitude", "经度"]
    }
    rename_map = {}
    for std, aliases in expected_cols.items():
        for alias in aliases:
            if alias in df.columns:
                rename_map[alias] = std
                break
    df = df.rename(columns=rename_map)
    missing = [c for c in expected_cols if c not in df.columns]
    if missing:
        sys.exit(f"❌ 缺少列: {missing}，请检查输入文件列名。")
    return df[["city", "province", "lat", "lon"]]

# ---------- 3. 生成两两组合并计算距离 ----------
def build_panel(df: pd.DataFrame, R: float, bidirectional: bool) -> pd.DataFrame:
    combos = itertools.permutations if bidirectional else itertools.combinations
    records = []
    for a, b in combos(df.itertuples(index=False), 2):
        if (not bidirectional) and (a.city > b.city):
            continue  # 仅保留 city_a < city_b 的唯一组合
        dist = haversine(a.lat, a.lon, b.lat, b.lon, R)
        records.append({
            "city_a":        a.city,
            "city_b":        b.city,
            "distance_km":   round(dist, 3),
            "same_province": int(a.province == b.province),
            "province_a":    a.province,
            "province_b":    b.province,
            "lon_a":         a.lon,
            "lat_a":         a.lat,
            "lon_b":         b.lon,
            "lat_b":         b.lat
        })
    return pd.DataFrame(records)

# ---------- 4. 主程序 ----------
def main():
    df = load_city_data(INPUT_FILE)
    panel_df = build_panel(df, R=EARTH_RADIUS, bidirectional=BIDIRECTIONAL)
    panel_df.to_csv(OUTPUT_FILE, index=False, encoding="utf-8-sig")
    print(f"✅ 距离面板已生成：{OUTPUT_FILE}（{len(panel_df):,} 行）")

if __name__ == "__main__":
    main()
