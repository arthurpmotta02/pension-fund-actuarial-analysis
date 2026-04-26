# ============================================================
# Notebook 03: BD Plan Actuarial Valuation
# ============================================================
# Projected Unit Credit valuation using lifecontingencies.
# Outputs: PMBaC, PMBC, normal cost, longevity sensitivity.

source("../src/R/mortality.R")
source("../src/R/bd_valuation.R")
source("../src/R/plan_data.R")

library(tidyverse)
library(ggplot2)
library(lifecontingencies)
library(scales)

# ── 1. Setup ─────────────────────────────────────────────────────────────────
i    <- 0.0575
plan <- default_plan

# Use BR-EMS 2021 Male (conservative — standard for EFPC)
brems_m  <- build_brems_2021("M")
act_main <- build_act_table(brems_m, i, "BR-EMS 2021 M")

cat("Setup complete.\n")
cat(sprintf("  Discount rate:   %.2f%%\n", i * 100))
cat(sprintf("  Mortality table: BR-EMS 2021 Male\n"))
cat(sprintf("  Retirement age:  %d\n", plan$retirement_age))

# ── 2. Generate participant portfolio ─────────────────────────────────────────
participants <- generate_portfolio(n_active = 500, n_retired = 200)
portfolio_summary(participants)

# ── 3. Calculate PMBaC and PMBC ──────────────────────────────────────────────
cat("\nCalculating actuarial liabilities...\n")
valuation <- value_portfolio(participants, act_main, plan)

active_val  <- filter(valuation, status == "active")
retired_val <- filter(valuation, status == "retired")

total_pmbac <- sum(active_val$pmbac)
total_pmbc  <- sum(retired_val$pmbc)
total_liab  <- total_pmbac + total_pmbc
total_nc    <- sum(active_val$normal_cost)

cat("\n")
cat(strrep("=", 55), "\n")
cat("ACTUARIAL VALUATION RESULTS\n")
cat(strrep("=", 55), "\n")
cat(sprintf("  Active participants:   %d\n",    nrow(active_val)))
cat(sprintf("  PMBaC total:          R$ %s\n",  format(round(total_pmbac), big.mark=",")))
cat(sprintf("  Normal cost total:    R$ %s\n",  format(round(total_nc),    big.mark=",")))
cat(sprintf("\n  Retired participants: %d\n",    nrow(retired_val)))
cat(sprintf("  PMBC total:           R$ %s\n",  format(round(total_pmbc), big.mark=",")))
cat(sprintf("\n  TOTAL LIABILITY:      R$ %s\n", format(round(total_liab), big.mark=",")))
cat(strrep("=", 55), "\n")

# ── 4. Liability by age group ────────────────────────────────────────────────
active_val <- active_val |>
  mutate(age_group = cut(age, breaks = c(25,35,45,55,65),
                         labels = c("25–34","35–44","45–54","55–64"),
                         right = FALSE))

liab_by_age <- active_val |>
  group_by(age_group) |>
  summarise(pmbac_m = sum(pmbac) / 1e6, .groups = "drop")

p1 <- ggplot(liab_by_age, aes(x = age_group, y = pmbac_m, fill = age_group)) +
  geom_col(alpha = 0.85, colour = "black", linewidth = 0.3, show.legend = FALSE) +
  geom_text(aes(label = paste0("R$", round(pmbac_m, 1), "M")),
            vjust = -0.4, fontface = "bold", size = 4.5) +
  scale_fill_brewer(palette = "Blues", direction = 1) +
  labs(
    title = "PMBaC by Age Group (Active Participants)",
    x = "Age Group", y = "PMBaC (R$ millions)"
  ) +
  theme_bw(base_size = 13) +
  ylim(0, max(liab_by_age$pmbac_m) * 1.15)

# Liability split pie
pie_df <- tibble(
  label = c("PMBaC\n(Active)", "PMBC\n(Retired)"),
  value = c(total_pmbac, total_pmbc)
)

p2 <- ggplot(pie_df, aes(x = "", y = value, fill = label)) +
  geom_col(width = 1, colour = "white") +
  coord_polar("y") +
  geom_text(aes(label = paste0(label, "\n",
                               scales::percent(value / sum(value), 0.1))),
            position = position_stack(vjust = 0.5),
            fontface = "bold", size = 5) +
  scale_fill_manual(values = c("steelblue","coral")) +
  labs(title = sprintf("Total Liability: R$ %sM",
                       round(total_liab / 1e6, 1))) +
  theme_void(base_size = 13) +
  theme(legend.position = "none")

library(patchwork)
p_liab <- p1 + p2
ggsave("../results/figures/06_liability_breakdown.png", p_liab,
       width = 13, height = 6, dpi = 300)
cat("Saved: 06_liability_breakdown.png\n")

# ── 5. Individual example ────────────────────────────────────────────────────
cat("\n--- Individual Participant Example ---\n")
ex_age <- 45; ex_svc <- 15; ex_sal <- 20000

pb  <- projected_benefit(ex_age, ex_svc, ex_sal, plan)
uc  <- unit_credit_benefit(ex_age, ex_svc, ex_sal, plan)
pv  <- calc_pmbac(act_main, ex_age, ex_svc, ex_sal, plan)
nc  <- calc_normal_cost(act_main, ex_age, ex_svc, ex_sal, plan)
a65 <- axn(act_main, x = 65)

cat(sprintf("  Age:                      %d\n",  ex_age))
cat(sprintf("  Service:                  %d yrs\n", ex_svc))
cat(sprintf("  Salary:                   R$ %s\n", format(ex_sal, big.mark=",")))
cat(sprintf("  Projected benefit (p.a.): R$ %s\n", format(round(pb$benefit), big.mark=",")))
cat(sprintf("  Unit credit benefit:      R$ %s\n", format(round(uc), big.mark=",")))
cat(sprintf("  ä_65 (annuity factor):    %.4f\n",  a65))
cat(sprintf("  PMBaC:                    R$ %s\n", format(round(pv), big.mark=",")))
cat(sprintf("  Normal cost (this yr):    R$ %s\n", format(round(nc), big.mark=",")))

# ── 6. Sensitivity: discount rate ────────────────────────────────────────────
rates  <- seq(0.04, 0.09, by = 0.005)
sens_r <- map_dfr(rates, function(r) {
  at <- build_act_table(brems_m, r, "temp")
  tibble(rate = r, pmbac = calc_pmbac(at, ex_age, ex_svc, ex_sal, plan))
})

p3 <- ggplot(sens_r, aes(x = rate * 100, y = pmbac / 1000)) +
  geom_line(linewidth = 2, colour = "steelblue") +
  geom_point(size = 3) +
  geom_vline(xintercept = i * 100, linetype = "dashed",
             colour = "red", linewidth = 1) +
  annotate("text", x = i * 100, y = max(sens_r$pmbac / 1000) * 0.95,
           label = paste0("PREVIC rate\n", scales::percent(i, 0.01)),
           hjust = -0.1, colour = "red", size = 4) +
  labs(
    title    = "PMBaC Sensitivity to Discount Rate",
    subtitle = paste0("Participant: age ", ex_age,
                      ", service ", ex_svc,
                      " yrs, salary R$", format(ex_sal, big.mark=",")),
    x = "Discount Rate (%)", y = "PMBaC (R$ thousands)"
  ) +
  theme_bw(base_size = 13)

ggsave("../results/figures/07_discount_rate_sensitivity.png", p3,
       width = 10, height = 5, dpi = 300)
cat("Saved: 07_discount_rate_sensitivity.png\n")

# ── 7. Longevity sensitivity ─────────────────────────────────────────────────
cat("\nRunning longevity sensitivity analysis...\n")
long_sens <- longevity_sensitivity(
  qx_base     = brems_m$qx,
  participants = participants,
  plan         = plan,
  shocks       = c(0, 1, 2, 3, 5)
)

cat("\nLongevity Sensitivity:\n")
print(long_sens)

p4 <- ggplot(long_sens, aes(x = factor(shock_years), y = change_pct,
                              fill = factor(shock_years))) +
  geom_col(alpha = 0.85, colour = "black", linewidth = 0.3,
           show.legend = FALSE) +
  geom_text(aes(label = ifelse(shock_years > 0,
                               paste0("+", round(change_pct, 1), "%"), "Base")),
            vjust = -0.4, fontface = "bold", size = 4.5) +
  scale_fill_manual(values = c("lightgray","steelblue","coral","tomato","darkred")) +
  labs(
    title    = "Longevity Risk: Impact on Total Pension Liability",
    subtitle = "If participants live longer than the mortality table predicts",
    x = "Additional Years of Life (vs. base table)",
    y = "Change in Liability (%)"
  ) +
  theme_bw(base_size = 13) +
  ylim(min(long_sens$change_pct) - 1, max(long_sens$change_pct) * 1.18)

ggsave("../results/figures/08_longevity_sensitivity.png", p4,
       width = 10, height = 6, dpi = 300)
cat("Saved: 08_longevity_sensitivity.png\n")

# ── 8. Export for Python/ALM ─────────────────────────────────────────────────
write_csv(valuation,    "../data/processed/valuation_results.csv")
write_csv(long_sens,    "../data/processed/longevity_sensitivity.csv")
write_csv(participants, "../data/processed/participants.csv")

# Summary stats for ALM notebook
summary_stats <- tibble(
  metric = c("n_active","n_retired","total_pmbac","total_pmbc",
             "total_liability","total_normal_cost","discount_rate"),
  value  = c(nrow(active_val), nrow(retired_val), total_pmbac, total_pmbc,
             total_liab, total_nc, i)
)
write_csv(summary_stats, "../data/processed/valuation_summary.csv")

cat("\nAll results exported to data/processed/\n")
