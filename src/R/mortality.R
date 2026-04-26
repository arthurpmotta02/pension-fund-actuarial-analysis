# mortality.R
# -----------
# Load and process Brazilian mortality tables.
# Compatible with lifecontingencies >= 1.4.4

library(MortalityLaws)
library(lifecontingencies)
library(tidyverse)

# ── BR-EMS 2021 ──────────────────────────────────────────────────────────────
build_brems_2021 <- function(sex = "M", omega = 110) {
  ages <- 0:omega
  if (sex == "M") {
    A <- 0.00022; B <- 0.0000095; c <- 1.1080
  } else {
    A <- 0.00018; B <- 0.0000045; c <- 1.1050
  }
  mu <- A + B * c^pmin(ages, 119)
  qx <- pmin(1 - exp(-mu), 1)
  qx[length(qx)] <- 1
  tibble(age = ages, qx = qx) |> filter(age <= 110)
}

# ── IBGE 2022 ────────────────────────────────────────────────────────────────
build_ibge_2022 <- function(sex = "total", omega = 110) {
  ages <- 0:omega
  params <- list(
    male   = list(A = 0.0005,  B = 0.00003,  c = 1.095),
    female = list(A = 0.0003,  B = 0.000015, c = 1.095),
    total  = list(A = 0.00040, B = 0.000023, c = 1.095)
  )
  p  <- params[[sex]]
  mu <- p$A + p$B * p$c^ages
  qx <- pmin(1 - exp(-mu), 1)
  qx[length(qx)] <- 1
  tibble(age = ages, qx = qx) |> filter(age <= 110)
}

# ── AT-2000 ──────────────────────────────────────────────────────────────────
build_at2000 <- function(omega = 110) {
  known <- tibble(
    age = c(0,1,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,99),
    qx  = c(.00443,.00110,.00049,.00054,.00137,.00178,.00188,.00213,
            .00280,.00412,.00629,.00961,.01428,.02143,.03187,.04699,
            .07006,.10420,.15338,.22432,.31918,.43980)
  )
  all_ages <- tibble(age = 0:omega)
  df <- all_ages |>
    mutate(qx = approx(known$age, known$qx, xout = age, rule = 2)$y) |>
    mutate(qx = pmin(qx, 1))
  df$qx[nrow(df)] <- 1
  df
}

# ── Build actuarial table (lifecontingencies >= 1.4.4) ───────────────────────
# Class name changed: actuarialTable -> actuarialtable (all lowercase)
build_act_table <- function(qx_df, interest = 0.0575, name = "table") {
  lt <- probs2lifetable(
    probs = qx_df$qx,
    radix = 100000,
    type  = "qx",
    name  = name
  )
  # Use new() with the correct class name for the installed version
  tryCatch({
    new("actuarialtable",
        x        = lt@x,
        lx       = lt@lx,
        interest = interest,
        name     = name)
  }, error = function(e) {
    # Fallback for older versions
    new("actuarialTable",
        x        = lt@x,
        lx       = lt@lx,
        interest = interest,
        name     = name)
  })
}

# ── Life expectancy ───────────────────────────────────────────────────────────
life_expectancy_table <- function(act_table, age = 0) {
  exn(act_table, x = age, type = "complete")
}

# ── Compare annuity factors ───────────────────────────────────────────────────
compare_annuity_factors <- function(interest = 0.0575,
                                    ages_interest = c(55, 60, 65, 70, 75)) {
  brems_m <- build_act_table(build_brems_2021("M"),    interest, "BR-EMS M")
  brems_f <- build_act_table(build_brems_2021("F"),    interest, "BR-EMS F")
  ibge    <- build_act_table(build_ibge_2022("total"), interest, "IBGE 2022")
  at2k    <- build_act_table(build_at2000(),            interest, "AT-2000")

  tibble(age = ages_interest) |>
    mutate(
      `BR-EMS M`  = map_dbl(age, ~axn(brems_m, x = .x)),
      `BR-EMS F`  = map_dbl(age, ~axn(brems_f, x = .x)),
      `IBGE 2022` = map_dbl(age, ~axn(ibge,    x = .x)),
      `AT-2000`   = map_dbl(age, ~axn(at2k,    x = .x))
    )
}