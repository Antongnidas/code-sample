# 02 — Wealth-management-product litigation and bank risk

**Role:** Collaborative research project during my master's studies at Nankai University.

**Research question:** How does wealth-management-product (WMP) litigation intensity — instrumented by a financial-court establishment shock — affect bank sales behaviour and risk-taking in the Chinese banking sector?

## Files

- `01_full_pipeline.do` — End-to-end empirical pipeline: policy-shock sample construction, OLS and Cox proportional-hazard models of financial-court establishment, dynamic logit event-study, and bank-month panel regressions of WMP issuance intensity with staggered DID. Produces the paper's main tables.
- `02_cross_section.do` — Cross-sectional robustness at the case level, exploiting judge-rotation variation with matched pseudo-time. Output is a judge-change cross-section dataset used for the paper's identification check.

## Data

Not included. Dataset was built from:
- Bank-level data from Wind / CSMAR
- Case-level data from Chinese court judgment documents (裁判文书网), extracted using the Python pipeline in `../03_court_doc_llm`

## How to run

```stata
global root "/path/to/your/data"
do 01_full_pipeline.do
do 02_cross_section.do
```
