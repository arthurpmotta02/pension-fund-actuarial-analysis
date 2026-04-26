"""
Pension Fund Actuarial Dashboard
Reads outputs from R notebooks (data/processed/) + runs ALM in Python.
"""

import streamlit as st
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../src/python'))
from alm import (
    load_r_outputs, project_liability_cash_flows,
    macaulay_duration, modified_duration, present_value,
    NTNBBond, portfolio_duration, ALMAnalysis
)

st.set_page_config(
    page_title="Pension Fund Actuarial Dashboard",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ── Sidebar ──────────────────────────────────────────────────────────────────
st.sidebar.title("Pension Fund Dashboard")
st.sidebar.caption("Outputs from StMoMo + lifecontingencies (R)")
st.sidebar.markdown("---")

page = st.sidebar.radio("Navigation", [
    "Overview",
    "Mortality & Longevity",
    "BD Plan Valuation",
    "ALM & Duration",
    "Stress Testing"
])

st.sidebar.markdown("---")
st.sidebar.markdown("**Assumptions**")
discount_rate  = st.sidebar.slider("Discount Rate (% p.a.)", 4.0, 8.5, 5.75, 0.25) / 100
retirement_age = st.sidebar.slider("Retirement Age", 55, 70, 65)
funding_ratio  = st.sidebar.slider("Funding Ratio (assets/liabilities)", 0.80, 1.20, 1.00, 0.01)

# ── Load R outputs ────────────────────────────────────────────────────────────
DATA_DIR = os.path.join(os.path.dirname(__file__), '../data/processed')

@st.cache_data
def load_data():
    return load_r_outputs(DATA_DIR)

data = load_data()
participants = data["participants"]
e_hist       = data["e_hist"]
e_proj       = data["e_proj"]
long_sens    = data["long_sens"]
summary      = data["summary"]
ann_factors  = data.get("ann_factors")

data_ok = participants is not None

# ── Helper: check if data is available ───────────────────────────────────────
def need_r_data():
    st.warning("R notebook outputs not found in `data/processed/`. "
               "Run R notebooks 01 → 02 → 03 first.")

# ── PAGE: Overview ───────────────────────────────────────────────────────────
if page == "Overview":
    st.title("Pension Fund Actuarial Dashboard")
    st.markdown("**Data pipeline:** R (StMoMo + lifecontingencies) → CSVs → Python (ALM) → Streamlit")

    col1, col2, col3, col4 = st.columns(4)
    if data_ok:
        n_act = (participants["status"] == "active").sum()
        n_ret = (participants["status"] == "retired").sum()
        col1.metric("Active Participants",   f"{n_act:,}")
        col2.metric("Retired Participants",  f"{n_ret:,}")

        if summary is not None:
            s = summary.set_index("metric")["value"]
            col3.metric("Total Liability",  f"R$ {float(s.get('total_liability',0))/1e6:.1f}M")
            col4.metric("Discount Rate",    f"{float(s.get('discount_rate', discount_rate)):.2%}")
    else:
        need_r_data()

    st.markdown("---")
    st.markdown("""
### Methodology

| Notebook | Language | Package | Topic |
|---|---|---|---|
| 01_mortality_tables.R | R | `MortalityLaws`, `lifecontingencies` | BR-EMS 2021, IBGE 2022, AT-2000 comparison |
| 02_lee_carter.R | R | `StMoMo` | Lee-Carter fit + 40-year mortality projection |
| 03_bd_plan_valuation.R | R | `lifecontingencies` | PMBaC, PMBC, normal cost, longevity sensitivity |
| 04_alm.ipynb | Python | custom | Duration, NTN-B, interest rate stress |
| streamlit_app.py | Python | Streamlit | Interactive dashboard |

### Key Actuarial Concepts

- **PMBaC** (Provisão Matemática de Benefícios a Conceder): liability for active participants
- **PMBC** (Provisão Matemática de Benefícios Concedidos): liability for retired participants
- **Projected Unit Credit (PUC)**: IFRS IAS 19 / PREVIC standard valuation method
- **Lee-Carter**: academic standard for mortality projection (SVD + Random Walk with Drift)
- **Duration gap**: difference between liability and asset duration — main interest rate risk metric
    """)

# ── PAGE: Mortality & Longevity ───────────────────────────────────────────────
elif page == "Mortality & Longevity":
    st.title("Mortality Tables & Longevity Projection")

    if e_hist is None or e_proj is None:
        need_r_data()
    else:
        last_hist = e_hist.iloc[-1]
        last_proj = e_proj.iloc[-1]

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("e65 in 2022",  f"{last_hist['e65']:.1f} yrs")
        col2.metric("e65 in 2065",  f"{last_proj['e65_mean']:.1f} yrs",
                    delta=f"+{last_proj['e65_mean']-last_hist['e65']:.1f} yrs")
        col3.metric("e0 in 2022",   f"{last_hist['e0']:.1f} yrs")
        col4.metric("e0 in 2065",   f"{last_proj['e0_mean']:.1f} yrs",
                    delta=f"+{last_proj['e0_mean']-last_hist['e0']:.1f} yrs")

        fig, axes = plt.subplots(1, 2, figsize=(13, 5))

        # e65 projection
        axes[0].plot(e_hist["year"], e_hist["e65"], color="black", linewidth=2)
        axes[0].fill_between(e_proj["year"], e_proj["e65_low"], e_proj["e65_high"],
                             alpha=0.25, color="steelblue")
        axes[0].plot(e_proj["year"], e_proj["e65_mean"], color="steelblue", linewidth=2,
                     label="Lee-Carter projection")
        axes[0].axvline(2022, linestyle="--", color="black", linewidth=1)
        axes[0].set_xlabel("Year"); axes[0].set_ylabel("e65 (years)")
        axes[0].set_title("Life Expectancy at 65 — Lee-Carter (StMoMo)")
        axes[0].legend(); axes[0].grid(True, alpha=0.3)

        # e0 projection
        axes[1].plot(e_hist["year"], e_hist["e0"], color="black", linewidth=2)
        axes[1].fill_between(e_proj["year"], e_proj["e0_low"], e_proj["e0_high"],
                             alpha=0.25, color="coral")
        axes[1].plot(e_proj["year"], e_proj["e0_mean"], color="coral", linewidth=2,
                     label="Projected mean")
        axes[1].axvline(2022, linestyle="--", color="black", linewidth=1)
        axes[1].set_xlabel("Year"); axes[1].set_ylabel("e0 (years)")
        axes[1].set_title("Life Expectancy at Birth — Lee-Carter")
        axes[1].legend(); axes[1].grid(True, alpha=0.3)

        plt.tight_layout()
        st.pyplot(fig); plt.close()

        st.markdown("---")
        if long_sens is not None:
            st.subheader("Longevity Risk: Liability Impact")
            st.info("Computed with **lifecontingencies** in R notebook 03.")

            fig2, ax2 = plt.subplots(figsize=(9, 5))
            clrs = ["lightgray","steelblue","coral","tomato","darkred"]
            bars = ax2.bar(long_sens["shock_years"].astype(str),
                           long_sens["change_pct"],
                           color=clrs[:len(long_sens)], alpha=0.85, edgecolor="black")
            for bar, v in zip(bars, long_sens["change_pct"]):
                if v > 0:
                    ax2.text(bar.get_x()+bar.get_width()/2, v+0.1,
                             f"+{v:.1f}%", ha="center", fontsize=12, fontweight="bold")
            ax2.set_xlabel("Additional Years of Life (vs. base table)")
            ax2.set_ylabel("Change in Total Liability (%)")
            ax2.set_title("Longevity Risk — Impact on Pension Liability")
            ax2.grid(True, alpha=0.3, axis="y")
            st.pyplot(fig2); plt.close()

# ── PAGE: BD Plan Valuation ───────────────────────────────────────────────────
elif page == "BD Plan Valuation":
    st.title("BD Plan Actuarial Valuation")
    st.caption("Projected Unit Credit — computed with lifecontingencies in R")

    if not data_ok:
        need_r_data()
    else:
        valuation = data["valuation"]
        if valuation is None:
            need_r_data()
        else:
            active_v  = valuation[valuation["status"] == "active"]
            retired_v = valuation[valuation["status"] == "retired"]

            total_pmbac = active_v["pmbac"].sum()
            total_pmbc  = retired_v["pmbc"].sum()
            total_liab  = total_pmbac + total_pmbc
            total_nc    = active_v["normal_cost"].sum()

            col1, col2, col3, col4 = st.columns(4)
            col1.metric("PMBaC (Active)",    f"R$ {total_pmbac/1e6:.1f}M")
            col2.metric("PMBC (Retired)",    f"R$ {total_pmbc/1e6:.1f}M")
            col3.metric("Total Liability",   f"R$ {total_liab/1e6:.1f}M")
            col4.metric("Normal Cost",       f"R$ {total_nc/1e6:.1f}M")

            st.markdown("---")
            active_v = active_v.copy()
            active_v["age_group"] = pd.cut(
                active_v["age"], bins=[25,35,45,55,65],
                labels=["25–34","35–44","45–54","55–64"], right=False
            )
            liab_age = active_v.groupby("age_group", observed=True)["pmbac"].sum() / 1e6

            fig, axes = plt.subplots(1, 2, figsize=(13, 5))

            bars = axes[0].bar(liab_age.index, liab_age.values,
                               color="steelblue", alpha=0.85, edgecolor="black")
            for b in bars:
                axes[0].text(b.get_x()+b.get_width()/2, b.get_height()+0.05,
                             f"R${b.get_height():.1f}M",
                             ha="center", fontsize=11, fontweight="bold")
            axes[0].set_xlabel("Age Group"); axes[0].set_ylabel("PMBaC (R$ M)")
            axes[0].set_title("PMBaC by Age Group (Active)")
            axes[0].grid(True, alpha=0.3, axis="y")

            pie_vals   = [total_pmbac/1e6, total_pmbc/1e6]
            pie_labels = [f"PMBaC\n(Active)\n{total_pmbac/total_liab:.0%}",
                          f"PMBC\n(Retired)\n{total_pmbc/total_liab:.0%}"]
            axes[1].pie(pie_vals, labels=pie_labels,
                        colors=["steelblue","coral"],
                        autopct=None, startangle=90,
                        textprops={"fontsize":12,"fontweight":"bold"})
            axes[1].set_title(f"Total Liability: R$ {total_liab/1e6:.1f}M")

            plt.tight_layout()
            st.pyplot(fig); plt.close()

# ── PAGE: ALM & Duration ──────────────────────────────────────────────────────
elif page == "ALM & Duration":
    st.title("Asset-Liability Management")

    if not data_ok:
        need_r_data()
    else:
        _, cf = project_liability_cash_flows(
            participants, discount_rate=discount_rate,
            retirement_age=retirement_age, n_years=50
        )
        liab_pv    = present_value(cf, discount_rate)
        liab_D_mac = macaulay_duration(cf, discount_rate)

        st.subheader("NTN-B Portfolio")
        col1, col2, col3 = st.columns(3)
        w35 = col1.slider("NTN-B 2035 (%)", 0, 60, 25) / 100
        w45 = col2.slider("NTN-B 2045 (%)", 0, 60, 40) / 100
        w55 = col3.slider("NTN-B 2055 (%)", 0, 60, 35) / 100

        total_w = w35 + w45 + w55
        if abs(total_w - 1.0) > 0.01:
            st.warning(f"Weights sum to {total_w:.0%} — should be 100%")

        bonds = [(NTNBBond(2035), w35),(NTNBBond(2045), w45),(NTNBBond(2055), w55)]
        alm   = ALMAnalysis(cf, discount_rate, bonds)

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Liability PV",        f"R$ {liab_pv/1e6:.1f}M")
        col2.metric("Liability Duration",  f"{alm.liab_D_mac:.2f} yrs")
        col3.metric("Portfolio Duration",  f"{alm.asset_D_mac:.2f} yrs")
        col4.metric("Duration Gap",        f"{alm.duration_gap:.2f} yrs",
                    delta="Exposed to rate drops" if alm.duration_gap > 1 else "Well matched")

        years_cf = np.arange(50)
        fig, axes = plt.subplots(1, 2, figsize=(13, 5))

        axes[0].bar(2025 + years_cf, cf/1e6, color="steelblue", alpha=0.8,
                    edgecolor="black", linewidth=0.3)
        axes[0].set_xlabel("Year"); axes[0].set_ylabel("R$ millions")
        axes[0].set_title("Projected Benefit Cash Flows")
        axes[0].grid(True, alpha=0.3, axis="y")

        items = ["Liability\nDuration","Portfolio\nDuration","Gap"]
        vals  = [alm.liab_D_mac, alm.asset_D_mac, alm.duration_gap]
        clrs  = ["steelblue","coral","crimson" if alm.duration_gap>1 else "seagreen"]
        bs    = axes[1].bar(items, vals, color=clrs, alpha=0.85, edgecolor="black", width=0.4)
        axes[1].axhline(0, color="black", linewidth=1)
        for b, v in zip(bs, vals):
            axes[1].text(b.get_x()+b.get_width()/2, v+(0.2 if v>=0 else -0.7),
                         f"{v:.2f}", ha="center", fontsize=12, fontweight="bold")
        axes[1].set_ylabel("Duration (years)")
        axes[1].set_title("Duration Gap Analysis")
        axes[1].grid(True, alpha=0.3, axis="y")

        plt.tight_layout(); st.pyplot(fig); plt.close()

# ── PAGE: Stress Testing ──────────────────────────────────────────────────────
elif page == "Stress Testing":
    st.title("Interest Rate Stress Test")

    if not data_ok:
        need_r_data()
    else:
        _, cf = project_liability_cash_flows(
            participants, discount_rate=discount_rate,
            retirement_age=retirement_age, n_years=50
        )
        bonds = [(NTNBBond(2035), 0.25),(NTNBBond(2045), 0.40),(NTNBBond(2055), 0.35)]
        alm   = ALMAnalysis(cf, discount_rate, bonds)

        asset_pv = alm.asset_pv * funding_ratio / 1.0
        stress   = alm.interest_rate_stress((-200,-100,-50,50,100,200))

        st.dataframe(stress.round(0), use_container_width=True)

        fig, axes = plt.subplots(1, 2, figsize=(13, 5))

        clrs_s = ["seagreen" if v>=0 else "crimson" for v in stress["surplus"]]
        axes[0].bar([f"{s:+d}" for s in stress["shock_bp"]], stress["surplus"]/1e6,
                    color=clrs_s, alpha=0.85, edgecolor="black")
        axes[0].axhline(0, color="black", linewidth=1.5)
        axes[0].set_xlabel("Rate Shock (bp)"); axes[0].set_ylabel("Surplus (R$ M)")
        axes[0].set_title("Fund Surplus Under Rate Shocks"); axes[0].grid(True, alpha=0.3, axis="y")

        axes[1].plot([f"{s:+d}" for s in stress["shock_bp"]],
                     stress["new_liability"]/1e6, "o-", linewidth=2, label="Liability")
        axes[1].plot([f"{s:+d}" for s in stress["shock_bp"]],
                     stress["new_asset"]/1e6, "s--", linewidth=2, color="coral", label="Assets")
        axes[1].set_xlabel("Rate Shock (bp)"); axes[1].set_ylabel("Value (R$ M)")
        axes[1].set_title("Assets vs Liabilities"); axes[1].legend()
        axes[1].grid(True, alpha=0.3)

        plt.tight_layout(); st.pyplot(fig); plt.close()
