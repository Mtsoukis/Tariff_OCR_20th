# -------------------------------------------------------
# Process OCR Results
# -------------------------------------------------------
# This script serves 3 purposes:
# 1. Apply post-processing
# 2. Identify problematic products
# 3. Evaluate Performance
# -------------------------------------------------------

rm(list = ls())

library(dplyr)
library(tidyr)
library(readr)
library(stringr)

script_dir <- dirname(normalizePath(sys.frame(1)$ofile))
file_path <- file.path(script_dir, "..", "Play", "Images", "Images_processed.csv")

df <- read_csv(
  file      = file_path,
  col_types = cols(
    product_code = col_character(),
    .default     = col_guess()
  )
)

# -------------------------------------------------------
#  Initial Cleaning
# -------------------------------------------------------

# Drop down codes and product descriptions

df <- df %>%
  mutate(product_code = na_if(product_code, "0000000")) %>%
  fill(product_code, product_description, .direction = "down")

# Idea 1- If in field 'country' I have a number (I shouldn't) and
# the quantity field is empty- it probably belongs there. Also clean up so it is a number

df <- df %>%
  mutate(flag = grepl("\\d", country) & is.na(quantity)) %>%
  mutate(
    quantity = if_else(
      flag,
      as.numeric(
        gsub(
          "[^0-9]", "",
          chartr(
            "CBOIZR?", "0801228",
            sub("^[^0-9]*([0-9].*)$", "\\1", country)
          )
        )
      ),
      quantity
    ),
    country = if_else(
      flag,
      str_remove(country, "[0-9].*"),
      country
    )
  ) %>%
  select(-flag)

# Idea 2- Missing country ==  TOTAL : where OCR produced a blank‑country

df <- df %>%
  group_by(product_description) %>%
  mutate(
    has_total = any(country == "TOTAL", na.rm = TRUE),
    no_alpha  = !grepl("[[:alpha:]]", country) & !is.na(country),
    country   = if_else(no_alpha & !has_total, "TOTAL", country)
  ) %>%
  ungroup() %>%
  select(-has_total, -no_alpha)

# Idea 3- Prefix a second block of duplicate rows with "X" if a description has two "TOTAL".
#Basically- OCR missed the new product code or country- send to manual review. 

df <- df %>%
  group_by(product_description) %>%
  mutate(
    n_total      = sum(country == "TOTAL", na.rm = TRUE),
    row_in_group = row_number(),
    first_total  = if (any(country == "TOTAL")) which(country == "TOTAL")[1] else NA_integer_,
    product_code        = if_else(n_total == 2 & row_in_group > first_total,
                                  paste0("X", product_code),
                                  product_code),
    product_description = if_else(n_total == 2 & row_in_group > first_total,
                                  paste0("X", product_description),
                                  product_description)
  ) %>%
  ungroup() %>%
  select(-n_total, -row_in_group, -first_total)

# Idea 4- Sometimes, the unit or description run into proper rows rather than description. For now, delete, 
# after I will clean up and integrate into description & unit. 

df <- df %>%
  filter(!str_detect(coalesce(country, ""), regex("LB")))

# -------------------------------------------------------
#  First check- when do quantity and value sums of countries == TOTAL
# -------------------------------------------------------

summary_df <- df %>%
  group_by(product_description) %>%
  summarise(
    sum_qty   = sum(quantity[country != "TOTAL"], na.rm = TRUE),
    sum_val   = sum(value   [country != "TOTAL"], na.rm = TRUE),
    total_qty = sum(quantity[country == "TOTAL"], na.rm = TRUE),
    total_val = sum(value   [country == "TOTAL"], na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(
    qty_match = sum_qty == total_qty,
    val_match = sum_val == total_val
  )

bad_desc <- summary_df %>%
  filter(!(qty_match & val_match)) %>%
  pull(product_description)


# New idea- repeat what I did for NA quantity and number in country field to value.
# This applies only for products which do not match as is. 

df <- df %>%
  mutate(flag = product_description %in% bad_desc &
           grepl("\\d", country) &
           is.na(value)) %>%
  mutate(
    value = if_else(
      flag,
      as.numeric(
        gsub(
          "[^0-9]", "",
          chartr(
            "CBOIZR?", "0801228",
            sub("^[^0-9]*([0-9].*)$", "\\1", country)
          )
        )
      ),
      value
    ),
    country = if_else(
      flag,
      str_remove(country, "[0-9].*"),
      country
    )
  ) %>%
  select(-flag)

# -------------------------------------------------------
#  Second check- when do quantity and value sums of countries == TOTAL
# -------------------------------------------------------

summary_df_after <- df %>%
  group_by(product_description) %>%
  summarise(
    sum_qty   = sum(quantity[country != "TOTAL"], na.rm = TRUE),
    sum_val   = sum(value   [country != "TOTAL"], na.rm = TRUE),
    total_qty = sum(quantity[country == "TOTAL"], na.rm = TRUE),
    total_val = sum(value   [country == "TOTAL"], na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(
    qty_match = sum_qty == total_qty,
    val_match = sum_val == total_val
  )

# -------------------------------------------------------
#  Results
# -------------------------------------------------------

qty_matches  <- sum(summary_df_after$qty_match)
val_matches  <- sum(summary_df_after$val_match)
qty_unmatched <- sum(!summary_df_after$qty_match)
val_unmatched <- sum(!summary_df_after$val_match)

total_matches <- qty_matches + val_matches

cat("Matches (qty): ", qty_matches,  "\n")
cat("Matches (val): ", val_matches,  "\n")
cat("Unmatched (qty):", qty_unmatched, "\n")
cat("Unmatched (val):", val_unmatched, "\n")
cat("TOTAL matches (qty+val):", total_matches, "\n")


out_path <- file.path(script_dir, "..", "Output", "Images_processed_semi_final.csv")
# Enter your own 
write_csv(df, out_path)

