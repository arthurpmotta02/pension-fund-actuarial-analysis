# plan_data.R
# -----------
# Synthetic participant portfolio for a Brazilian EFPC pension fund.
# Profile calibrated to IRB Brasil RE / PreviRB employee characteristics.

library(tidyverse)

generate_portfolio <- function(n_active  = 500,
                                n_retired = 200,
                                seed      = 42) {
  set.seed(seed)

  # ── Active participants ────────────────────────────────────────────────────
  active <- tibble(
    id             = sprintf("ACT%04d", seq_len(n_active)),
    status         = "active",
    age            = pmax(25, pmin(64, round(rnorm(n_active, 45, 10)))),
    years_service  = pmax(1L, pmin(age - 22L,
                                   round(runif(n_active, 1, age - 22)))),
    salary         = pmax(8000, pmin(60000,
                          rlnorm(n_active, log(15000), 0.5) *
                          (1 + 0.015 * years_service))),
    monthly_benefit = NA_real_
  )

  # ── Retired participants ───────────────────────────────────────────────────
  retired <- tibble(
    id              = sprintf("RET%04d", seq_len(n_retired)),
    status          = "retired",
    age             = pmax(65, pmin(88, round(rnorm(n_retired, 72, 6)))),
    years_service   = 30L,
    salary          = 0,
    monthly_benefit = pmax(4000, pmin(35000,
                           rlnorm(n_retired, log(20000), 0.4) *
                           runif(n_retired, 0.45, 0.70)))
  )

  bind_rows(active, retired) |>
    mutate(across(where(is.double), ~round(.x, 2)))
}

portfolio_summary <- function(df) {
  active  <- filter(df, status == "active")
  retired <- filter(df, status == "retired")

  cat(strrep("=", 60), "\n")
  cat("PARTICIPANT PORTFOLIO SUMMARY\n")
  cat(strrep("=", 60), "\n")
  cat(sprintf("\nActive participants:     %d\n", nrow(active)))
  cat(sprintf("  Mean age:              %.1f\n", mean(active$age)))
  cat(sprintf("  Mean service (years):  %.1f\n", mean(active$years_service)))
  cat(sprintf("  Mean salary:           R$ %s\n",
              format(round(mean(active$salary)), big.mark = ",")))
  cat(sprintf("\nRetired participants:    %d\n", nrow(retired)))
  cat(sprintf("  Mean age:              %.1f\n", mean(retired$age)))
  cat(sprintf("  Mean monthly benefit:  R$ %s\n",
              format(round(mean(retired$monthly_benefit)), big.mark = ",")))
  cat(strrep("=", 60), "\n")
}
