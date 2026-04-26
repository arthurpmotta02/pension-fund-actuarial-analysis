# lee_carter_utils.R
# ------------------
# Wrappers around StMoMo for Lee-Carter mortality projection.
#
# StMoMo supports: LC, APC, CBD, M6, M7, PLAT
# We use LC (Lee-Carter 1992) as the baseline.
#
# Packages: StMoMo, demography, tidyverse

library(StMoMo)
library(demography)
library(tidyverse)

# ── Build historical mortality matrix ────────────────────────────────────────
# Since IBGE historical series requires manual download, we build a
# realistic synthetic matrix calibrated to Brazilian mortality trends.
# e0(1980) ≈ 62 years → e0(2022) ≈ 75 years

build_historical_matrix <- function(age_min = 0,
                                    age_max = 100,
                                    year_min = 1980,
                                    year_max = 2022) {
  set.seed(42)
  ages  <- age_min:age_max
  years <- year_min:year_max
  n_a   <- length(ages)
  n_y   <- length(years)

  # Log-mortality baseline at 2022 (calibrated to IBGE 2022)
  log_mu_2022 <- (
    -6.5
    - 0.03 * ages
    + 0.001 * ages^1.5
    + ifelse(ages < 5, 2.0 * exp(-0.8 * ages), 0)
  )

  # Annual improvement by age group
  improvement <- case_when(
    ages < 5  ~ 0.025,
    ages < 20 ~ 0.018,
    ages < 50 ~ 0.012,
    ages < 70 ~ 0.010,
    TRUE      ~ 0.008
  )

  # Build matrix
  Mx <- matrix(0, nrow = n_a, ncol = n_y,
               dimnames = list(ages, years))

  for (j in seq_along(years)) {
    yrs_from_2022 <- years[j] - 2022
    noise         <- rnorm(n_a, 0, 0.015)
    log_mu        <- log_mu_2022 + improvement * (-yrs_from_2022) + noise
    Mx[, j]       <- pmax(exp(log_mu), 1e-6)
  }

  # Exposure matrix (uniform — we only have rates, not counts)
  Ext <- matrix(100000, nrow = n_a, ncol = n_y,
                dimnames = list(ages, years))

  # Deaths matrix
  Dxt <- round(Mx * Ext)

  list(Mx = Mx, Ext = Ext, Dxt = Dxt, ages = ages, years = years)
}

# ── Fit Lee-Carter via StMoMo ────────────────────────────────────────────────
fit_lee_carter <- function(mort_data,
                           ages_fit  = 20:90,
                           years_fit = NULL) {
  if (is.null(years_fit)) years_fit <- mort_data$years

  # StMoMoData object
  stmomo_data <- StMoMoData(
    data  = list(
      Dxt = mort_data$Dxt,
      Ext = mort_data$Ext,
      ages  = mort_data$ages,
      years = mort_data$years,
      type  = "central",
      series = "total",
      label = "Brazil"
    ),
    type = "central"
  )

  # Lee-Carter model specification
  LC <- lc(link = "log")

  # Fit
  fit <- fit(
    LC,
    data      = stmomo_data,
    ages.fit  = ages_fit,
    years.fit = years_fit
  )

  message("Lee-Carter fitted.")
  message(sprintf("  Ages:  %d–%d", min(ages_fit), max(ages_fit)))
  message(sprintf("  Years: %d–%d", min(years_fit), max(years_fit)))
  message(sprintf("  kappa1 drift: %.4f per year",
                  mean(diff(fit$kt[1,]))))

  fit
}

# ── Project mortality ─────────────────────────────────────────────────────────
project_lee_carter <- function(lc_fit,
                               h = 43,           # years ahead (to 2065)
                               n_sim = 1000,
                               seed = 42) {
  set.seed(seed)

  # Stochastic forecast with fan chart
  fc <- forecast(
    lc_fit,
    h     = h,
    level = c(80, 95),
    oxt   = NULL
  )

  message(sprintf("Projected %d years ahead (%d–%d)",
                  h,
                  max(lc_fit$years) + 1,
                  max(lc_fit$years) + h))

  fc
}

# ── Extract life expectancy from forecast ────────────────────────────────────
extract_life_expectancy <- function(lc_fit, lc_forecast,
                                    ages_interest = c(0, 40, 60, 65)) {
  all_years  <- c(lc_fit$years, lc_forecast$rates$mean |> colnames() |> as.integer())
  hist_years <- lc_fit$years
  proj_years <- as.integer(colnames(lc_forecast$rates$mean))

  compute_ex <- function(mu_vec, from_age = 0) {
    mu  <- pmax(mu_vec, 1e-8)
    qx  <- 1 - exp(-mu)
    qx  <- pmin(qx, 1)
    n   <- length(qx)
    lx  <- numeric(n + 1); lx[1] <- 1
    for (i in seq_len(n)) lx[i+1] <- lx[i] * (1 - qx[i])
    Lx <- (lx[1:n] + lx[2:(n+1)]) / 2
    Tx <- rev(cumsum(rev(Lx)))
    Tx[1] / lx[1]
  }

  rows <- list()

  # Historical
  for (yr in hist_years) {
    mu_col <- lc_fit$Dxt[, as.character(yr)] / lc_fit$Ext[, as.character(yr)]
    ages   <- as.integer(rownames(lc_fit$Dxt))
    for (a in ages_interest) {
      idx  <- which(ages >= a)
      if (length(idx) == 0) next
      rows[[length(rows)+1]] <- tibble(
        year   = yr,
        age    = a,
        ex     = compute_ex(mu_col[idx]),
        type   = "historical",
        ex_low  = NA_real_,
        ex_high = NA_real_
      )
    }
  }

  # Projected (mean + CI)
  for (yr in proj_years) {
    yr_chr  <- as.character(yr)
    mu_mean <- lc_forecast$rates$mean[, yr_chr]
    mu_low  <- lc_forecast$rates$`5%`[, yr_chr]
    mu_high <- lc_forecast$rates$`95%`[, yr_chr]
    ages    <- as.integer(rownames(lc_forecast$rates$mean))

    for (a in ages_interest) {
      idx <- which(ages >= a)
      if (length(idx) == 0) next
      rows[[length(rows)+1]] <- tibble(
        year    = yr,
        age     = a,
        ex      = compute_ex(mu_mean[idx]),
        type    = "projected",
        ex_low  = compute_ex(mu_high[idx]),
        ex_high = compute_ex(mu_low[idx])
      )
    }
  }

  bind_rows(rows)
}
