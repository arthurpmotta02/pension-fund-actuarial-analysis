# bd_valuation.R
# --------------
# BD plan valuation using lifecontingencies >= 1.4.4

library(lifecontingencies)
library(tidyverse)

default_plan <- list(
  retirement_age  = 65,
  benefit_rate    = 0.02,
  discount_rate   = 0.0575,
  salary_growth   = 0.02,
  max_benefit_pct = 0.70
)

projected_benefit <- function(current_age, years_service, salary,
                               plan = default_plan) {
  yrs_to_ret    <- max(plan$retirement_age - current_age, 0)
  total_service <- years_service + yrs_to_ret
  proj_salary   <- salary * (1 + plan$salary_growth)^yrs_to_ret
  benefit       <- min(
    plan$benefit_rate * total_service * proj_salary,
    plan$max_benefit_pct * proj_salary
  )
  list(benefit = benefit, projected_salary = proj_salary,
       total_service = total_service)
}

unit_credit_benefit <- function(current_age, years_service, salary,
                                 plan = default_plan) {
  pb <- projected_benefit(current_age, years_service, salary, plan)
  if (pb$total_service == 0) return(0)
  pb$benefit * years_service / pb$total_service
}

calc_pmbac <- function(act_table, current_age, years_service, salary,
                        plan = default_plan) {
  if (current_age >= plan$retirement_age) return(0)
  n      <- plan$retirement_age - current_age
  b_unit <- unit_credit_benefit(current_age, years_service, salary, plan)
  a_ret  <- axn(act_table, x = plan$retirement_age, k = 1)
  n_E_x  <- pxt(act_table, x = current_age, t = n) *
             (1 / (1 + plan$discount_rate))^n
  b_unit * a_ret * n_E_x
}

calc_pmbc <- function(act_table, retired_age, monthly_benefit,
                       plan = default_plan) {
  annual_benefit <- monthly_benefit * 13
  annual_benefit * axn(act_table, x = retired_age, k = 1)
}

calc_normal_cost <- function(act_table, current_age, years_service, salary,
                              plan = default_plan) {
  pv_now  <- calc_pmbac(act_table, current_age, years_service, salary, plan)
  pv_next <- calc_pmbac(act_table, current_age + 1,
                         years_service + 1,
                         salary * (1 + plan$salary_growth), plan)
  pv_next - pv_now * (1 + plan$discount_rate)
}

value_portfolio <- function(participants, act_table, plan = default_plan) {
  participants |>
    rowwise() |>
    mutate(
      pmbac = if_else(
        status == "active",
        calc_pmbac(act_table, age, years_service, salary, plan),
        0
      ),
      pmbc  = if_else(
        status == "retired",
        calc_pmbc(act_table, age, monthly_benefit, plan),
        0
      ),
      normal_cost = if_else(
        status == "active",
        calc_normal_cost(act_table, age, years_service, salary, plan),
        0
      )
    ) |>
    ungroup()
}

longevity_sensitivity <- function(qx_base, participants, plan = default_plan,
                                   shocks = c(0, 1, 2, 3, 5)) {
  build_table_from_qx <- function(qx) {
    lt <- probs2lifetable(probs = qx, radix = 100000, type = "qx", name = "temp")
    tryCatch(
      new("actuarialtable", x = lt@x, lx = lt@lx,
          interest = plan$discount_rate, name = "temp"),
      error = function(e)
        new("actuarialTable", x = lt@x, lx = lt@lx,
            interest = plan$discount_rate, name = "temp")
    )
  }

  base_table <- build_table_from_qx(qx_base)
  base_val   <- value_portfolio(participants, base_table, plan)
  base_total <- sum(base_val$pmbac) + sum(base_val$pmbc)

  map_dfr(shocks, function(shock) {
    qx_s      <- qx_base
    idx       <- which(seq_along(qx_base) - 1 >= 50)
    qx_s[idx] <- pmin(qx_s[idx] * (1 - 0.025 * shock), 1)

    t_s   <- build_table_from_qx(qx_s)
    val   <- value_portfolio(participants, t_s, plan)
    total <- sum(val$pmbac) + sum(val$pmbc)

    tibble(
      shock_years     = shock,
      total_liability = total,
      change_pct      = (total - base_total) / base_total * 100
    )
  })
}