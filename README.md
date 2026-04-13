# Code Samples

Selected code from three empirical / data-engineering projects, prepared as a writing sample for pre-doctoral applications.

All three projects use confidential or proprietary data that cannot be redistributed, so the repository contains scripts only. Each sub-folder has its own README with project background and instructions.

## Contents

| Folder | Language | What it shows |
|---|---|---|
| [`01_ckd_stability`](./01_ckd_stability) | Stata | Panel-data cleaning and regression analysis of kidney-disease progression as a function of follow-up regularity (HKUST RA project, 2026) |
| [`02_wmp_litigation`](./02_wmp_litigation) | Stata | DID / Cox hazard analysis of wealth-management-product litigation and bank risk (undergraduate thesis, Nankai University) |
| [`03_court_doc_llm`](./03_court_doc_llm) | Python | Asynchronous LLM pipeline (DeepSeek API) for structured extraction from Chinese court judgment documents, plus supporting data-engineering utilities |

## A note on paths and keys

All hard-coded local paths have been replaced with a `PROJECT_ROOT` placeholder (Stata) or environment variables (Python). API keys are read from `os.environ`. To run any script locally, set the relevant env var or edit the `global root` line at the top of the `.do` file.

## Author

Applying to pre-doc positions, 2026.
