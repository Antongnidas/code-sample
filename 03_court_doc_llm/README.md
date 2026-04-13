# 03 — LLM pipeline for Chinese court judgment documents

**Role:** Built as the data-engineering layer behind the WMP-litigation project (`../02_wmp_litigation`). Solo work.

**What it does:** Extracts structured research variables from hundreds of thousands of unstructured Chinese court judgment documents (裁判文书) using the DeepSeek Chat API, with asynchronous concurrency for throughput.

## Files

- `concurrent_llm.py` — Asynchronous JSON-in / JSON-out pipeline that classifies each court document (is this a bank-WMP lawsuit?) and extracts filing and closing dates with month-level precision. Uses `asyncio` + `AsyncOpenAI` with a semaphore to cap concurrent requests, with retry logic for API failures.
- `llm_structured_extraction.py` — Richer extraction step: reads the filtered corpus and asks the LLM to return three structured fields per document — (i) whether the verdict *weakened* the plaintiff's claim, and (ii) / (iii) plaintiff and defendant types classified into one of four categories (financial institution / firm / government agency / individual). Demonstrates prompt engineering for constrained-output extraction, streaming `tqdm` progress, and per-file incremental checkpointing.
- `city_distance.py` — Utility: builds a bank-to-court city-pair panel by computing Haversine great-circle distances between city centroids, used as a control variable in the main regressions.

## Running

```bash
export DEEPSEEK_API_KEY=sk-...
export IN_DIR=./data/input
export OUT_DIR=./data/output
python concurrent_llm.py
```

## Data

Raw court documents are public (裁判文书网) but bulky; not checked in.
