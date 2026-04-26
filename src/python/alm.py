"""
alm.py  —  Asset-Liability Management for pension funds
Reads outputs from R notebooks. Vectorized for performance.
"""

import numpy as np
import pandas as pd


def load_r_outputs(data_dir="../data/processed"):
    out = {}
    files = {
        "e_hist":       "e_historical.csv",
        "e_proj":       "e_projected.csv",
        "kt_hist":      "kt_historical.csv",
        "kt_proj":      "kt_projected.csv",
        "valuation":    "valuation_results.csv",
        "participants": "participants.csv",
        "long_sens":    "longevity_sensitivity.csv",
        "summary":      "valuation_summary.csv",
        "brems_m":      "brems_male.csv",
    }
    for key, fname in files.items():
        path = f"{data_dir}/{fname}"
        try:
            out[key] = pd.read_csv(path)
        except FileNotFoundError:
            out[key] = None
    return out


def _survival_curve(n_years, q65_base=0.030, gompertz_b=0.095):
    """
    Pre-compute survival probability vector from age 65.
    surv[t] = P(alive at 65+t | alive at 65)
    Vectorized — called once, reused for all participants.
    """
    t   = np.arange(n_years)
    qx  = np.minimum(q65_base * np.exp(gompertz_b * t), 1.0)
    # Cumulative survival: prod(1 - qx[0:t])
    surv = np.cumprod(1 - qx)
    surv = np.concatenate([[1.0], surv[:-1]])  # surv[0]=1 (alive at 65)
    return surv


def project_liability_cash_flows(participants,
                                  discount_rate   = 0.0575,
                                  retirement_age  = 65,
                                  n_years         = 50,
                                  benefit_rate    = 0.02,
                                  salary_growth   = 0.02,
                                  max_benefit_pct = 0.70):
    """
    Vectorized projection of annual benefit cash flows.
    """
    surv = _survival_curve(n_years + 20)   # extra buffer for older retirees
    cash_flows = np.zeros(n_years)

    active  = participants[participants["status"] == "active"].copy()
    retired = participants[participants["status"] == "retired"].copy()

    # ── Active participants ──────────────────────────────────────────────────
    for _, row in active.iterrows():
        age     = int(row["age"])
        service = int(row["years_service"])
        salary  = float(row["salary"])
        ytr     = max(retirement_age - age, 0)

        if ytr >= n_years:
            continue

        total_svc   = service + ytr
        proj_salary = salary * (1 + salary_growth) ** ytr
        benefit_pa  = min(benefit_rate * total_svc * proj_salary,
                          max_benefit_pct * proj_salary) * 13

        # Survival from retirement: years t = ytr to n_years-1
        t_range    = np.arange(n_years - ytr)
        surv_slice = surv[t_range]
        cash_flows[ytr:] += benefit_pa * surv_slice

    # ── Retired participants ─────────────────────────────────────────────────
    for _, row in retired.iterrows():
        age      = int(row["age"])
        benefit  = float(row.get("monthly_benefit", 5000)) * 13
        age_off  = max(age - retirement_age, 0)

        t_range    = np.arange(n_years)
        surv_idx   = np.minimum(age_off + t_range, len(surv) - 1)
        surv_slice = surv[surv_idx]
        cash_flows += benefit * surv_slice

    return np.arange(n_years), cash_flows


def macaulay_duration(cash_flows, discount_rate):
    t  = np.arange(1, len(cash_flows) + 1)
    v  = 1 / (1 + discount_rate)
    pv = cash_flows * v ** t
    return (t * pv).sum() / pv.sum() if pv.sum() > 0 else 0.0

def modified_duration(cash_flows, discount_rate):
    return macaulay_duration(cash_flows, discount_rate) / (1 + discount_rate)

def convexity(cash_flows, discount_rate):
    t  = np.arange(1, len(cash_flows) + 1)
    v  = 1 / (1 + discount_rate)
    pv = cash_flows * v ** t
    if pv.sum() == 0:
        return 0.0
    return (t * (t + 1) * pv).sum() / ((1 + discount_rate)**2 * pv.sum())

def present_value(cash_flows, discount_rate):
    t = np.arange(1, len(cash_flows) + 1)
    v = 1 / (1 + discount_rate)
    return (cash_flows * v ** t).sum()


class NTNBBond:
    """NTN-B (Tesouro IPCA+) — annual coupon model."""
    def __init__(self, maturity_year, face_value=1000,
                 coupon_rate=0.06, real_yield=0.06, current_year=2025):
        self.maturity_year = maturity_year
        self.face_value    = face_value
        self.coupon_rate   = coupon_rate
        self.real_yield    = real_yield
        self.years_to_mat  = max(maturity_year - current_year, 1)

    def cash_flows_per_unit(self):
        n  = self.years_to_mat
        cf = np.full(n, self.face_value * self.coupon_rate)
        cf[-1] += self.face_value
        return np.arange(1, n + 1), cf

    def price_per_unit(self):
        t, cf = self.cash_flows_per_unit()
        return (cf / (1 + self.real_yield)**t).sum()

    def macaulay_duration(self):
        t, cf = self.cash_flows_per_unit()
        pv = cf / (1 + self.real_yield)**t
        return (t * pv).sum() / pv.sum()

    def modified_duration(self):
        return self.macaulay_duration() / (1 + self.real_yield)

    def convexity(self):
        t, cf = self.cash_flows_per_unit()
        pv = cf / (1 + self.real_yield)**t
        return (t * (t + 1) * pv).sum() / ((1 + self.real_yield)**2 * pv.sum())


def portfolio_duration(bonds_weights):
    total_pv = sum(b.price_per_unit() * w for b, w in bonds_weights)
    if total_pv == 0:
        return 0.0
    return sum(b.macaulay_duration() * b.price_per_unit() * w
               for b, w in bonds_weights) / total_pv


class ALMAnalysis:
    def __init__(self, cash_flows, discount_rate, bonds_weights,
                 funding_ratio=1.0):
        self.cf            = cash_flows
        self.dr            = discount_rate
        self.bonds         = bonds_weights
        self.funding_ratio = funding_ratio

        self.liab_pv     = present_value(cash_flows, discount_rate)
        self.liab_D_mac  = macaulay_duration(cash_flows, discount_rate)
        self.liab_D_mod  = modified_duration(cash_flows, discount_rate)
        self.liab_convex = convexity(cash_flows, discount_rate)

        # Asset value scaled to liability x funding ratio
        self.asset_pv    = self.liab_pv * funding_ratio
        self.asset_D_mac = portfolio_duration(bonds_weights)
        self.duration_gap = self.liab_D_mac - self.asset_D_mac

    def summary(self):
        surplus = self.asset_pv - self.liab_pv
        fr      = self.funding_ratio
        print("=" * 60)
        print("ALM SUMMARY")
        print("=" * 60)
        print(f"\nLIABILITIES")
        print(f"  Present Value:      R$ {self.liab_pv/1e6:>10,.1f}M")
        print(f"  Macaulay Duration:  {self.liab_D_mac:>10.2f} years")
        print(f"  Modified Duration:  {self.liab_D_mod:>10.2f}")
        print(f"\nASSETS (NTN-B Portfolio, FR={fr:.0%})")
        print(f"  Value:              R$ {self.asset_pv/1e6:>10,.1f}M")
        print(f"  Macaulay Duration:  {self.asset_D_mac:>10.2f} years")
        print(f"\nSURPLUS")
        print(f"  Surplus:            R$ {surplus/1e6:>10,.1f}M")
        print(f"  Funding Ratio:      {fr:>10.1%}")
        print(f"\nDURATION GAP:         {self.duration_gap:>10.2f} years")
        assessment = (
            "Well-matched" if abs(self.duration_gap) < 1
            else "Liabilities longer → exposed to rate DROPS" if self.duration_gap > 0
            else "Assets longer → exposed to rate RISES"
        )
        print(f"  Assessment: {assessment}")
        print("=" * 60)

    def interest_rate_stress(self, shocks_bp=(-200,-100,-50,50,100,200)):
        asset_D_mod = self.asset_D_mac / (1 + self.dr)
        asset_cvx   = sum(
            b.convexity() * b.price_per_unit() * w
            for b, w in self.bonds
        ) / sum(b.price_per_unit() * w for b, w in self.bonds)

        rows = []
        for bp in shocks_bp:
            dy = bp / 10000

            dL    = self.liab_pv * (-self.liab_D_mod * dy +
                                     0.5 * self.liab_convex * dy**2)
            dA    = self.asset_pv * (-asset_D_mod * dy +
                                      0.5 * asset_cvx * dy**2)
            new_L = self.liab_pv + dL
            new_A = self.asset_pv + dA
            surplus = new_A - new_L

            rows.append({
                "shock_bp":      bp,
                "new_liability": new_L,
                "new_asset":     new_A,
                "surplus":       surplus,
                "surplus_pct":   surplus / new_L * 100
            })
        return pd.DataFrame(rows)

    def immunization_suggestion(self):
        target    = self.liab_D_mac
        available = [2030, 2035, 2040, 2045, 2050, 2055]
        durations = {yr: NTNBBond(yr).macaulay_duration() for yr in available}

        shorter = [yr for yr, d in durations.items() if d <= target]
        longer  = [yr for yr, d in durations.items() if d >  target]

        if not shorter or not longer:
            yr_max = max(durations, key=lambda yr: durations[yr])
            return {
                "note":            f"Target ({target:.1f} yrs) exceeds longest "
                                   f"available bond ({durations[yr_max]:.1f} yrs). "
                                   f"Consider NTN-B {yr_max} + interest rate swaps.",
                "target_duration": target,
                "suggested_bond":  f"NTN-B {yr_max}",
                "bond_duration":   durations[yr_max],
                "residual_gap":    target - durations[yr_max]
            }

        yr_s = max(shorter, key=lambda yr: durations[yr])
        yr_l = min(longer,  key=lambda yr: durations[yr])
        d_s  = durations[yr_s]
        d_l  = durations[yr_l]
        w_l  = float(np.clip((target - d_s) / (d_l - d_s), 0, 1))
        w_s  = 1 - w_l

        return {
            "target_duration":   target,
            "short_bond":        f"NTN-B {yr_s}",
            "short_duration":    d_s,
            "short_weight":      w_s,
            "long_bond":         f"NTN-B {yr_l}",
            "long_duration":     d_l,
            "long_weight":       w_l,
            "achieved_duration": w_s * d_s + w_l * d_l
        }