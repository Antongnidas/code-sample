# -*- coding: utf-8 -*-
"""
并发批量读取 JSON，调用 DeepSeek Chat 抽取“时间区间”并写回新文件
--------------------------------------------------
运行方法：
直接 python deepseek_concurrent.py
"""

import os
import json
import time
import asyncio
from openai import AsyncOpenAI

# ========= A. 用户自定义区 ==============

IN_DIR   = os.getenv("IN_DIR",  "./data/input")     # folder of raw JSON court docs
OUT_DIR  = os.getenv("OUT_DIR", "./data/output")    # folder for processed output
CONCURRENCY = 10                                    # concurrent request count

DEEPSEEK_API_KEY  = os.environ["DEEPSEEK_API_KEY"]  # set via env var, never hardcode
DEEPSEEK_BASE_URL = "https://api.deepseek.com"
MODEL_NAME        = "deepseek-chat"
BOT_SYSTEM_PROMPT = "You are a helpful assistant"

# ========= B. Prompt 构造 ==============

def build_prompt(text: str) -> str:
    return (
        f"'{text}' 请告诉我这篇文书是否涉及银行理财诉讼。"
        "如果是请告诉我这份文书案件的起诉时间和结案时间。"
        "回复格式：Yes/No 起诉时间：xxxx年xx月；结案时间：xxxx年xx月(至少精确到月，不确的用XX代替)"
    )

# ========= C. 异步调用 ==============

async def call_deepseek_async(client, case_text, sem, max_retries=5):
    prompt = build_prompt(case_text)
    async with sem:
        for _ in range(max_retries):
            try:
                resp = await client.chat.completions.create(
                    model=MODEL_NAME,
                    messages=[
                        {"role": "system", "content": BOT_SYSTEM_PROMPT},
                        {"role": "user", "content": prompt},
                    ],
                    stream=False
                )
                return resp.choices[0].message.content.strip()
            except Exception as e:
                print(f"[DeepSeek 调用异常] {e}，重试中…")
                await asyncio.sleep(0.5)
    return None

# ========= D. 进度统计辅助 ============

def count_items(files):
    total = 0
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            total += len(json.load(f))
    return total

# ========= E. 处理单文件 ==============

async def process_file(client, in_fp, out_fp, counter, grand_total, sem):
    with open(in_fp, "r", encoding="utf-8") as f:
        data = json.load(f)

    base = os.path.basename(in_fp)
    file_total = len(data)

    async def handle_item(item):
        text = item.get("正文", "")
        item["时间区间"] = await call_deepseek_async(client, text, sem) if text else None
        counter[0] += 1
        print(
            f"全局 {counter[0]}/{grand_total} │ "
            f"{base} {counter[0] % (file_total + 1)}/{file_total}", end="\r"
        )

    await asyncio.gather(*(handle_item(i) for i in data))

    os.makedirs(os.path.dirname(out_fp), exist_ok=True)
    with open(out_fp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print()  # 换行
    print(f"{base} → 处理完成，共 {file_total} 条")

# ========= F. 主程序 ==================

async def main():
    files = [os.path.join(IN_DIR, fn) for fn in os.listdir(IN_DIR) if fn.endswith(".json")]
    if not files:
        print("❗ 未找到需要处理的 JSON 文件")
        return

    grand_total = count_items(files)
    counter = [0]
    client = AsyncOpenAI(api_key=DEEPSEEK_API_KEY, base_url=DEEPSEEK_BASE_URL)
    sem = asyncio.Semaphore(CONCURRENCY)

    t0 = time.time()
    for fp in files:
        out_fp = os.path.join(OUT_DIR, f"processed_{os.path.basename(fp)}")
        await process_file(client, fp, out_fp, counter, grand_total, sem)
    print(f"✅ 全部完成，用时 {time.time() - t0:.1f}s")

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    asyncio.run(main())
