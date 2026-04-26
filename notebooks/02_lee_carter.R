# ============================================================
# Notebook 02: Lee-Carter Mortality Projection
# ============================================================
# Compatible with StMoMo 0.4.1 + demography 2.0.1

source("../src/R/mortality.R")

library(StMoMo)
library(demography)
library(tidyverse)
library(ggplot2)
library(patchwork)

dir.create("../results/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("../data/processed",  recursive = TRUE, showWarnings = FALSE)

# ── 1. Historical mortality matrix ───────────────────────────────────────────
cat("Building historical mortality matrix (1980-2022)...\n")

set.seed(42)
ages  <- 20:90
years <- 1980:2022
n_a   <- length(ages)
n_y   <- length(years)

log_mu_2022 <- -6.5 - 0.03 * ages + 0.001 * ages^1.5

improvement <- case_when(
  ages < 50 ~ 0.012,
  ages < 70 ~ 0.010,
  TRUE      ~ 0.008
)

Mx <- matrix(0, nrow = n_a, ncol = n_y,
             dimnames = list(as.character(ages), as.character(years)))

for (j in seq_along(years)) {
  yrs_from_2022 <- years[j] - 2022
  noise         <- rnorm(n_a, 0, 0.015)
  Mx[, j]       <- pmax(exp(log_mu_2022 + improvement * (-yrs_from_2022) + noise), 1e-6)
}

Ext <- matrix(100000, nrow = n_a, ncol = n_y,
              dimnames = list(as.character(ages), as.character(years)))
Dxt <- round(Mx * Ext)

cat(sprintf("Matrix: %d ages x %d years\n", n_a, n_y))

# ── 2. demogdata + fit ───────────────────────────────────────────────────────
brazil_demog <- demogdata(
  data = Mx, pop = Ext, ages = ages, years = years,
  type = "mortality", label = "Brazil", name = "total"
)

stmomo_data <- StMoMoData(brazil_demog, series = "total", type = "central")

LC  <- lc(link = "log")
fit <- fit(LC, data = stmomo_data, ages.fit = ages, years.fit = years)

ax_vec    <- as.vector(fit$ax)
bx_vec    <- as.vector(fit$bx[[1]])
kt_vec    <- as.vector(fit$kt[1, ])
fit_ages  <- fit$ages
fit_years <- fit$years
drift     <- mean(diff(kt_vec))

cat(sprintf("Lee-Carter fitted. k_t drift: %.4f per year\n", drift))

# ── 3. Parameters plot ───────────────────────────────────────────────────────
params_df <- tibble(age = fit_ages, ax = ax_vec, bx = bx_vec)
kt_df     <- tibble(year = fit_years, kt = kt_vec)

p_ax <- ggplot(params_df, aes(age, ax)) +
  geom_line(linewidth = 1.2, colour = "steelblue") +
  labs(title = "a_x: Mean Log-Mortality", x = "Age", y = "a_x") + theme_bw(12)

p_bx <- ggplot(params_df, aes(age, bx)) +
  geom_line(linewidth = 1.2, colour = "coral") +
  labs(title = "b_x: Age Sensitivity", x = "Age", y = "b_x") + theme_bw(12)

p_kt <- ggplot(kt_df, aes(year, kt)) +
  geom_line(linewidth = 1.2, colour = "darkgreen") +
  labs(title = "k_t: Mortality Index\n(declining = improving)", x = "Year", y = "k_t") +
  theme_bw(12)

ggsave("../results/figures/03_lc_parameters.png",
       p_ax + p_bx + p_kt + plot_annotation(title = "Lee-Carter Parameters (StMoMo)"),
       width = 14, height = 5, dpi = 300)
cat("Saved: 03_lc_parameters.png\n")

# ── 4. Forecast ──────────────────────────────────────────────────────────────
cat("Projecting 43 years ahead (2023-2065)...\n")
fc <- forecast(fit, h = 43, level = c(80, 95))

# Inspect structure once
cat("fc$rates class:", class(fc$rates), "\n")
cat("fc$rates dim:  ", paste(dim(fc$rates), collapse = " x "), "\n")

# k_t projection
kt_f_mean <- as.vector(fc$kt.f$mean[1, ])
kt_f_lo   <- as.vector(fc$kt.f$lower[1, , "95%"])
kt_f_hi   <- as.vector(fc$kt.f$upper[1, , "95%"])
proj_years_kt <- as.integer(names(fc$kt.f$mean[1, ]))

kt_proj <- tibble(year = proj_years_kt, kt = kt_f_mean,
                  kt_low = kt_f_lo, kt_hi = kt_f_hi)

p_kt_proj <- ggplot() +
  geom_line(data = kt_df,   aes(year, kt), colour = "black", linewidth = 1.5) +
  geom_ribbon(data = kt_proj, aes(year, ymin = kt_low, ymax = kt_hi),
              fill = "steelblue", alpha = 0.25) +
  geom_line(data = kt_proj, aes(year, kt), colour = "steelblue", linewidth = 1.5) +
  geom_vline(xintercept = 2022, linetype = "dashed") +
  labs(title = "k_t: Historical + Projected (95% CI)", x = "Year", y = "k_t") +
  theme_bw(13)

ggsave("../results/figures/04_kt_projection.png", p_kt_proj,
       width = 10, height = 5, dpi = 300)
cat("Saved: 04_kt_projection.png\n")

# ── 5. Extract projected rates ───────────────────────────────────────────────
# fc$rates is a 3D array: ages x years x scenarios (mean/lower/upper)
# OR it may be a plain matrix (only mean). Detect and handle both.

cat("Extracting projected rates...\n")

if (is.array(fc$rates) && length(dim(fc$rates)) == 3) {
  # 3D array: [age, year, scenario]
  cat("  Format: 3D array [age x year x scenario]\n")
  cat("  Dimnames[[3]]:", paste(dimnames(fc$rates)[[3]], collapse = ", "), "\n")
  dn3 <- dimnames(fc$rates)[[3]]

  # Find mean scenario name
  mean_nm <- dn3[grep("mean|50", dn3, ignore.case = TRUE)][1]
  lo_nm   <- dn3[grep("95|upper|hi",  dn3, ignore.case = TRUE)][1]
  hi_nm   <- dn3[grep("5|lower|lo",   dn3, ignore.case = TRUE)][1]

  # If CI not present, use mean for all
  if (is.na(lo_nm)) lo_nm <- mean_nm
  if (is.na(hi_nm)) hi_nm <- mean_nm

  r_mean <- fc$rates[,, mean_nm]
  r_lo   <- fc$rates[,, lo_nm]
  r_hi   <- fc$rates[,, hi_nm]

} else if (is.array(fc$rates) && length(dim(fc$rates)) == 2) {
  # Plain matrix: only mean
  cat("  Format: 2D matrix (mean only)\n")
  r_mean <- fc$rates
  r_lo   <- fc$rates
  r_hi   <- fc$rates

} else if (is.list(fc$rates)) {
  cat("  Format: list\n")
  r_mean <- fc$rates$mean
  r_lo   <- fc$rates[["upper"]] %||% fc$rates$mean
  r_hi   <- fc$rates[["lower"]] %||% fc$rates$mean

} else {
  cat("  Format: unknown — using as-is\n")
  r_mean <- as.matrix(fc$rates)
  r_lo   <- r_mean
  r_hi   <- r_mean
}

proj_years <- as.integer(colnames(r_mean))
proj_ages  <- as.integer(rownames(r_mean))
idx65      <- which(proj_ages >= 65)

cat(sprintf("  Projected years: %d-%d\n", min(proj_years), max(proj_years)))
cat(sprintf("  Projected ages:  %d-%d\n", min(proj_ages),  max(proj_ages)))

# ── 6. Life expectancy ───────────────────────────────────────────────────────
compute_ex <- function(qx_vec) {
  qx <- pmin(pmax(as.vector(qx_vec), 0), 0.9999)
  n  <- length(qx)
  lx <- numeric(n + 1); lx[1] <- 1
  for (i in seq_len(n)) lx[i+1] <- lx[i] * (1 - qx[i])
  Lx <- (lx[1:n] + lx[2:(n+1)]) / 2
  rev(cumsum(rev(Lx)))[1] / lx[1]
}

idx65_hist <- which(fit_ages >= 65)

# Historical
e_hist <- map_dfr(fit_years, function(yr) {
  mu <- fit$Dxt[, as.character(yr)] / fit$Ext[, as.character(yr)]
  qx <- 1 - exp(-pmax(mu, 0))
  tibble(year = yr,
         e0   = compute_ex(qx),
         e65  = if (length(idx65_hist) > 0) compute_ex(qx[idx65_hist]) else NA_real_)
})

# Projected
e_proj <- map_dfr(proj_years, function(yr) {
  yr_c    <- as.character(yr)
  qx_mean <- 1 - exp(-pmax(r_mean[, yr_c], 0))
  qx_lo   <- 1 - exp(-pmax(r_hi[,  yr_c], 0))   # higher mu = lower e
  qx_hi   <- 1 - exp(-pmax(r_lo[,  yr_c], 0))

  tibble(
    year     = yr,
    e0_mean  = compute_ex(qx_mean),
    e0_low   = compute_ex(qx_lo),
    e0_high  = compute_ex(qx_hi),
    e65_mean = if (length(idx65) > 0) compute_ex(qx_mean[idx65]) else NA_real_,
    e65_low  = if (length(idx65) > 0) compute_ex(qx_lo[idx65])   else NA_real_,
    e65_high = if (length(idx65) > 0) compute_ex(qx_hi[idx65])   else NA_real_
  )
})

last <- tail(e_proj, 1)
cat(sprintf("\nProjected e0  2065: %.1f yrs (%.1f-%.1f)\n",
            last$e0_mean, last$e0_low, last$e0_high))
cat(sprintf("Projected e65 2065: %.1f yrs (%.1f-%.1f)\n",
            last$e65_mean, last$e65_low, last$e65_high))

# ── 7. Plot e65 ──────────────────────────────────────────────────────────────
e65_2022 <- filter(e_hist, year == 2022)$e65

p_e65 <- ggplot() +
  geom_line(data = e_hist, aes(year, e65),
            colour = "black", linewidth = 1.5, na.rm = TRUE) +
  geom_ribbon(data = e_proj,
              aes(year, ymin = e65_low, ymax = e65_high),
              fill = "steelblue", alpha = 0.25, na.rm = TRUE) +
  geom_line(data = e_proj, aes(year, e65_mean),
            colour = "steelblue", linewidth = 1.5, na.rm = TRUE) +
  geom_vline(xintercept = 2022, linetype = "dashed") +
  annotate("text", x = 2022, y = e65_2022,
           label = sprintf("2022: %.1f yrs", e65_2022),
           hjust = 1.1, fontface = "bold", size = 4.5) +
  annotate("text", x = last$year, y = last$e65_mean,
           label = sprintf("2065: %.1f yrs", last$e65_mean),
           hjust = 1.1, fontface = "bold", size = 4.5) +
  labs(
    title    = "Life Expectancy at 65 — Lee-Carter Projection (StMoMo)",
    subtitle = "Each additional year of life ≈ 6-8% increase in pension liability",
    x = "Year", y = "e65 (years remaining)"
  ) +
  theme_bw(13)

ggsave("../results/figures/05_life_expectancy_65.png", p_e65,
       width = 11, height = 6, dpi = 300)
cat("Saved: 05_life_expectancy_65.png\n")

# ── 8. Export ─────────────────────────────────────────────────────────────────
write_csv(e_hist,  "../data/processed/e_historical.csv")
write_csv(e_proj,  "../data/processed/e_projected.csv")
write_csv(kt_df,   "../data/processed/kt_historical.csv")
write_csv(kt_proj, "../data/processed/kt_projected.csv")

cat("\nAll results saved to data/processed/\n")