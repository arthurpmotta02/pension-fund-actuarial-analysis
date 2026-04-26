# ============================================================
# Notebook 01: Mortality Tables
# ============================================================
# Compares BR-EMS 2021, IBGE 2022 and AT-2000.
# Computes annuity factors using lifecontingencies.
# Exports processed tables to data/processed/

source("../src/R/mortality.R")

library(tidyverse)
library(ggplot2)
library(lifecontingencies)

dir.create("../results/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("../results/tables",  recursive = TRUE, showWarnings = FALSE)
dir.create("../data/processed",  recursive = TRUE, showWarnings = FALSE)

# ── 1. Build tables ──────────────────────────────────────────────────────────
brems_m <- build_brems_2021("M")
brems_f <- build_brems_2021("F")
ibge    <- build_ibge_2022("total")
at2k    <- build_at2000()

cat("Tables built:\n")
cat(sprintf("  BR-EMS 2021 M: %d ages\n",  nrow(brems_m)))
cat(sprintf("  BR-EMS 2021 F: %d ages\n",  nrow(brems_f)))
cat(sprintf("  IBGE 2022:     %d ages\n",  nrow(ibge)))
cat(sprintf("  AT-2000:       %d ages\n",  nrow(at2k)))

# ── 2. Build actuarial tables ────────────────────────────────────────────────
i <- 0.0575   # PREVIC 2024

act_brems_m <- build_act_table(brems_m, i, "BR-EMS 2021 M")
act_brems_f <- build_act_table(brems_f, i, "BR-EMS 2021 F")
act_ibge    <- build_act_table(ibge,    i, "IBGE 2022")
act_at2k    <- build_act_table(at2k,    i, "AT-2000")

# ── 3. Life expectancy ───────────────────────────────────────────────────────
cat("\nLife expectancy at birth (e0):\n")
for (nm in c("BR-EMS 2021 M","BR-EMS 2021 F","IBGE 2022","AT-2000")) {
  at <- get(paste0("act_", c("brems_m","brems_f","ibge","at2k")[
    match(nm, c("BR-EMS 2021 M","BR-EMS 2021 F","IBGE 2022","AT-2000"))]))
  cat(sprintf("  %-20s  e0  = %.1f yrs\n", nm,
              exn(at, x = 0, type = "complete")))
}

cat("\nLife expectancy at 65 (e65):\n")
for (nm in c("BR-EMS 2021 M","BR-EMS 2021 F","IBGE 2022","AT-2000")) {
  at <- get(paste0("act_", c("brems_m","brems_f","ibge","at2k")[
    match(nm, c("BR-EMS 2021 M","BR-EMS 2021 F","IBGE 2022","AT-2000"))]))
  cat(sprintf("  %-20s  e65 = %.1f yrs\n", nm,
              exn(at, x = 65, type = "complete")))
}

# ── 4. Annuity factors ───────────────────────────────────────────────────────
ann_comp <- compare_annuity_factors(interest = i)
cat("\nAnnuity factors ä_x:\n")
print(ann_comp)

# ── 5. Plot: qx comparison ───────────────────────────────────────────────────
age_range <- 30:90
qx_long <- bind_rows(
  brems_m |> filter(age %in% age_range) |> mutate(table = "BR-EMS 2021 M"),
  brems_f |> filter(age %in% age_range) |> mutate(table = "BR-EMS 2021 F"),
  ibge    |> filter(age %in% age_range) |> mutate(table = "IBGE 2022"),
  at2k    |> filter(age %in% age_range) |> mutate(table = "AT-2000")
)

p1 <- ggplot(qx_long, aes(x = age, y = qx, colour = table, linetype = table)) +
  geom_line(linewidth = 1) +
  scale_y_log10(labels = scales::scientific) +
  scale_colour_brewer(palette = "Set1") +
  labs(
    title    = "Mortality Rate by Table (log scale)",
    subtitle = "Brazilian actuarial tables — ages 30–90",
    x = "Age", y = "qx (log scale)",
    colour = "Table", linetype = "Table"
  ) +
  theme_bw(base_size = 13) +
  theme(legend.position = "bottom")

ggsave("../results/figures/01_qx_comparison.png", p1,
       width = 10, height = 6, dpi = 300)
cat("Saved: 01_qx_comparison.png\n")

# ── 6. Plot: annuity factors ─────────────────────────────────────────────────
ann_long <- ann_comp |>
  pivot_longer(-age, names_to = "table", values_to = "ax")

p2 <- ggplot(ann_long, aes(x = factor(age), y = ax, fill = table)) +
  geom_col(position = "dodge", alpha = 0.85, colour = "black", linewidth = 0.3) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title    = paste0("Whole-Life Annuity Factors ä_x  (i = ", scales::percent(i, 0.01), ")"),
    subtitle = "Higher factor = more conservative = higher liability",
    x = "Age", y = "ä_x", fill = "Table"
  ) +
  theme_bw(base_size = 13) +
  theme(legend.position = "bottom")

ggsave("../results/figures/02_annuity_factors.png", p2,
       width = 10, height = 6, dpi = 300)
cat("Saved: 02_annuity_factors.png\n")

# ── 7. Save processed data ───────────────────────────────────────────────────
write_csv(brems_m, "../data/processed/brems_male.csv")
write_csv(brems_f, "../data/processed/brems_female.csv")
write_csv(ibge,    "../data/processed/ibge_2022.csv")
write_csv(at2k,    "../data/processed/at2000.csv")
write_csv(ann_comp,"../data/processed/annuity_factors.csv")

cat("\nAll tables saved to data/processed/\n")
