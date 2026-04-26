# Pension Fund Actuarial Analysis

**End-to-end actuarial valuation of a Brazilian BD (Defined Benefit) pension plan.**

The project uses the correct tool for each task:
- **R** for actuarial modelling (StMoMo, lifecontingencies, MortalityLaws)
- **Python** for ALM, data integration, and interactive dashboard (Streamlit)

Built to target quantitative actuarial roles at Brazilian EFPC pension funds (PreviRB, Previ, Petros, Funcef).

---

## Data Pipeline

```
R notebooks (01–03)
    ↓ export CSVs to data/processed/
Python notebook (04) + Streamlit
    ↓ read CSVs, compute ALM, serve dashboard
```

---

## Results

| Metric | Value |
|---|---|
| e65 — BR-EMS 2021 Male (2022) | ~17.5 years |
| e65 — Lee-Carter projection (2065) | ~21–23 years |
| +1 year longevity → liability | +6–8% |
| Total liability (700 participants) | ~R$ 300–500M |
| Liability Macaulay Duration | ~15–18 years |
| PREVIC discount rate (2024) | 5.75% p.a. |

---

## Project Structure

```
pension-fund-actuarial-analysis/
│
├── README.md
├── requirements_R.txt          ← R package list
├── requirements_python.txt     ← Python package list
│
├── notebooks/
│   ├── 01_mortality_tables.R   ← MortalityLaws: IBGE, BR-EMS, AT-2000
│   ├── 02_lee_carter.R         ← StMoMo: LC fit + 40yr projection
│   ├── 03_bd_plan_valuation.R  ← lifecontingencies: PMBaC, PMBC, longevity
│   └── 04_alm.ipynb            ← Python: duration, NTN-B, stress test
│
├── src/
│   ├── R/
│   │   ├── mortality.R
│   │   ├── lee_carter_utils.R
│   │   ├── bd_valuation.R
│   │   └── plan_data.R
│   └── python/
│       └── alm.py
│
├── app/
│   └── streamlit_app.py
│
└── data/
    ├── raw/                    ← source files
    └── processed/              ← R notebook exports (CSV)
```

---

## Getting Started

### Step 1 — Install R packages

```r
install.packages(c(
  "lifecontingencies", "StMoMo", "MortalityLaws",
  "demography", "tidyverse", "ggplot2", "patchwork", "scales"
))
```

### Step 2 — Run R notebooks (in order)

Open RStudio, set working directory to `notebooks/`, and run:

```r
source("01_mortality_tables.R")
source("02_lee_carter.R")
source("03_bd_plan_valuation.R")
```

This exports ~10 CSV files to `data/processed/`.

### Step 3 — Python setup

```bash
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements_python.txt
```

### Step 4 — Run Python notebook

```bash
jupyter notebook
# open notebooks/04_alm.ipynb
```

### Step 5 — Launch Streamlit dashboard

```bash
cd app
streamlit run streamlit_app.py
```

---

## Actuarial Assumptions (PREVIC 2024)

| Assumption | Value | Reference |
|---|---|---|
| Discount rate | 5.75% p.a. | PREVIC NPC 30/2024 |
| Mortality table | BR-EMS 2021 (Male) | CNseg / SUSEP |
| Salary growth | 2.0% real p.a. | Market practice |
| Max benefit | 70% projected final salary | Plan regulation |
| Retirement age | 65 | PREVIC minimum |

---

## Key Concepts

- **Commutation functions** — Dx, Nx via `lifecontingencies::axn()`
- **Projected Unit Credit (PUC)** — IFRS IAS 19 / PREVIC standard
- **PMBaC / PMBC** — Brazilian regulatory liability classification
- **Lee-Carter (1992)** — SVD estimation + RWD projection via `StMoMo`
- **Longevity risk** — sensitivity of liability to mortality improvements
- **Macaulay duration** — liability interest rate sensitivity
- **NTN-B** — Brazilian IPCA-linked sovereign bond (preferred pension asset)
- **Duration gap** — ALM risk metric (asset vs liability duration)
- **Parallel shift stress test** — Solvency II / PREVIC scenario

---

## Author

Arthur Motta — Statistics and Actuarial Science, UFRJ
[GitHub](https://github.com/arthurpmotta02) | [LinkedIn](https://linkedin.com/in/arthurpmotta)
