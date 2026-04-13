#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
process_json_deepseek.py  -- 2025-07-16 单文件写出版（升级版, 改字段名）
-------------------------------------------------
1) 批量读取 IN_DIR 中所有 *.json（支持列表或 NDJSON）
2) 筛选「时间区间」含 Yes 且「起诉时间」可识别为日期的记录
3) 调用 DeepSeek Chat 模型，返回三项信息：
      • 判决是否减弱原诉求          → 字段  VERDICT_FIELD（默认：判决是否减弱_v2）
      • 原告类型（四类）            → 字段  原告类型
      • 被告类型（四类）            → 字段  被告类型
   四类严格限定：金融机构 / 公司 / 政府机构 / 个人
4) 仅对满足条件且得到三项信息的记录写入输出
5) 每处理完一个输入文件，就保存一个 <原名>_judged.json
6) 全程显示 tqdm 进度条
"""

import os
import re
import json
import asyncio
from pathlib import Path
from typing import List, Dict, Any

import aiofiles
from tqdm.asyncio import tqdm                    # tqdm ≥ 4.66 支持 asyncio
from openai import AsyncOpenAI

# ———————————————— ① 路径 / 参数配置 ————————————————
IN_DIR   = Path(os.getenv("IN_DIR",  "./data/input"))    # folder of raw JSON court docs
OUT_DIR  = Path(os.getenv("OUT_DIR", "./data/output"))   # folder for processed output
PATTERN  = "*.json"

DEEPSEEK_KEY  = os.environ["DEEPSEEK_KEY"]   # set via env var, never hardcode
DEEPSEEK_URL  = "https://api.deepseek.com"
MODEL_NAME    = "deepseek-chat"
SYSTEM_PROMPT = "You are a helpful assistant"

CONCURRENCY   = 100       # 并发上限
MAX_RETRIES   = 5

# 新字段名（随便改成你喜欢的，比如 "verdict_weakened_new" / "是否削弱原诉求_新"）
VERDICT_FIELD = "判决是否减弱_new"

# ———————————————— ② DeepSeek Prompt ————————————————
PROMPT_TEMPLATE = (
    "以下是一份民事/刑事案件裁判文书的正文。请完成两件事：\n"
    "① 比较原始诉求与法院判决，判断是否【减弱】原始诉求（仅部分支持、金额减少、部分驳回等）。\n"
    "② 判断原告（起诉者）与被告（被起诉者）的主体类别，严格从以下 4 类中各选其一：\n"
    "   - 金融机构（银行、信托、证券、保险、基金、消费金融公司、小贷公司等）\n"
    "   - 公司（除金融机构以外的各类企业法人、公司、有限合伙、平台等）\n"
    "   - 政府机构（政府部门、事业单位、监管机关、法院/检察院/公安机关、村委会/居委会等）\n"
    "   - 个人（自然人、公民、个体工商户【若无法明确为公司则归为个人】）\n"
    "\n"
    "请按如下**固定格式**严格输出三行，不要添加多余解释或空行：\n"
    "VERDICT=<YES/NO>                 # YES 表示判决减弱原诉求\n"
    "PLAINTIFF_CLASS=<金融机构/公司/政府机构/个人>\n"
    "DEFENDANT_CLASS=<金融机构/公司/政府机构/个人>\n"
    "\n"
    "注意：如果文书中主体类别无法完全确定，请按照最接近的类别判定，并且仍然只能填入四选一。\n"
    "正文：\n{doc}\n"
)

# ———————————————— ③ 工具函数 ————————————————
_date_pat = re.compile(r"\d{4}[-/年]")   # 粗略判定含年份

def valid_date(text: str | None) -> bool:
    """起诉时间是否看似日期"""
    return bool(text and _date_pat.search(str(text)))

async def read_json_file(path: Path) -> List[Dict[str, Any]]:
    """更稳定的 JSON 读取器，支持回退逐行"""
    async with aiofiles.open(path, "r", encoding="utf-8") as fp:
        sample = await fp.read(4096)
        first_non_ws = next((c for c in sample if not c.isspace()), "")
        await fp.seek(0)

        # NDJSON 判断（首个非空字符是 {，且不是 [）
        if first_non_ws == "{":
            recs = []
            async for line in fp:
                line = line.strip()
                if line:
                    try:
                        recs.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            return recs

        # 尝试作为列表 JSON 读取
        text = await fp.read()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            print(f"⚠️  {path.name} JSON 解析失败，回退逐行处理")
            recs, bad = [], 0
            for line in text.splitlines():
                line = line.strip().rstrip(',')
                if not line:
                    continue
                try:
                    recs.append(json.loads(line))
                except json.JSONDecodeError:
                    bad += 1
            if bad:
                print(f"   → 跳过 {bad} 条格式错误记录")
            return recs

async def write_json_once(records: List[Dict[str, Any]], out_path: Path):
    """写出处理结果（单文件一次性）"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    async with aiofiles.open(out_path, "w", encoding="utf-8") as fp:
        await fp.write(json.dumps(records, ensure_ascii=False, indent=2))
    print(f"\n✅ 写入 {out_path} ({len(records)} 条)")

def _norm(cls: str) -> str:
    """
    可选：把模型可能输出的同义词收敛到四类标签上。
    你可以随时扩充这个映射表。
    """
    table = {
        "企业": "公司",
        "机构": "公司",
        "机构方": "公司",
        "自然人": "个人",
        "个人用户": "个人",
        "事业单位": "政府机构",
        "法院": "政府机构",
        "检察院": "政府机构",
        "公安机关": "政府机构",
        "村委会": "政府机构",
        "居委会": "政府机构",
    }
    return table.get(cls, cls)

async def ask_deepseek(client: AsyncOpenAI, doc: str,
                       sem: asyncio.Semaphore) -> Dict[str, str] | None:
    """调用 DeepSeek，解析固定格式（含 4 类主体分类）"""
    prompt = PROMPT_TEMPLATE.format(doc=doc)
    async with sem:
        for _ in range(MAX_RETRIES):
            try:
                resp = await client.chat.completions.create(
                    model=MODEL_NAME,
                    messages=[{"role": "system", "content": SYSTEM_PROMPT},
                              {"role": "user",   "content": prompt}],
                    stream=False, timeout=60,
                )
                txt = resp.choices[0].message.content
                # 统一空白，方便正则
                txt = re.sub(r"[ \t\r]+", " ", txt)

                m = re.search(
                    r"VERDICT=(YES|NO).*?"
                    r"PLAINTIFF_CLASS=(金融机构|公司|政府机构|个人).*?"
                    r"DEFENDANT_CLASS=(金融机构|公司|政府机构|个人)",
                    txt, flags=re.S | re.I
                )
                if m:
                    ver, pl, de = m.groups()
                    # 归一化（可选）
                    pl, de = _norm(pl), _norm(de)
                    return {
                        VERDICT_FIELD: ver.upper(),
                        "原告类型": pl,
                        "被告类型": de
                    }
            except Exception as e:
                print(f"[DeepSeek 异常] {e}，重试…")
                await asyncio.sleep(0.5)
    return None

async def process_file(path: Path, client: AsyncOpenAI, sem: asyncio.Semaphore):
    stem_out = f"{path.stem}_judged.json"
    out_path = OUT_DIR / stem_out

    # 如果已处理，直接跳过
    if out_path.exists():
        print(f"⏭️  跳过已处理文件：{out_path.name}")
        return

    records = await read_json_file(path)
    print(f"\n➡ 读取 {path.name}：共 {len(records)} 条")

    out_records: List[Dict[str, Any]] = []
    bar = tqdm(total=len(records), desc=path.name, unit="条")

    async def handle(rec: Dict[str, Any]) -> Dict[str, Any] | None:
        flag = str(rec.get("时间区间", "")).lower()
        sue  = rec.get("起诉时间")
        if flag.startswith("yes") and valid_date(sue):
            info = await ask_deepseek(client, rec.get("正文", ""), sem)
            if info:
                rec.update(info)
                return rec
        return None

    coros = [handle(r) for r in records]

    for coro in asyncio.as_completed(coros):
        res = await coro
        bar.update(1)
        if res:
            out_records.append(res)

    bar.close()

    # 写出结果
    await write_json_once(out_records, out_path)

# ———————————————— ⑤ 主入口 ————————————————
async def main():
    if not DEEPSEEK_KEY:
        raise RuntimeError("请先在环境变量中设置 DEEPSEEK_KEY")

    sem    = asyncio.Semaphore(CONCURRENCY)
    client = AsyncOpenAI(api_key=DEEPSEEK_KEY, base_url=DEEPSEEK_URL)

    files = sorted(IN_DIR.glob(PATTERN))
    if not files:
        print(f"❗ 在 {IN_DIR} 未找到符合 {PATTERN} 的文件")
        return

    for p in files:
        await process_file(p, client, sem)

if __name__ == "__main__":
    asyncio.run(main())
