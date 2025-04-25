library(testthat)
library(SummarizedExperiment)
library(S4Vectors) # For DataFrame

# Load the function to be tested (assuming it will be in R/subset_sample.R)
# source("../../R/subset_sample.R") # Adjust path as needed if running interactively
# Note: When run via testthat::test_dir or similar, sourcing might not be needed
# if the package structure is recognized or functions are loaded globally.

# --- Mock Data Creation ---
create_mock_se <- function(nrows = 10, ncols = 6) {
  counts <- matrix(rnbinom(nrows * ncols, mu = 100, size = 1), ncol = ncols)
  rownames(counts) <- paste0("gene", 1:nrows)
  colnames(counts) <- paste0("sample", 1:ncols)

  col_data <- DataFrame(
    sample_id = colnames(counts),
    treatment = rep(c("control", "treated", "control"), each = 2),
    batch = rep(c("A", "B"), times = 3),
    value = rnorm(ncols, mean = 10),
    row.names = colnames(counts)
  )

  SummarizedExperiment(assays = List(counts = counts), colData = col_data)
}

# --- Test Context ---
context("Testing subset_sample function")

# Placeholder test to ensure the file is created correctly
test_that("Test file setup is correct", {
  expect_true(TRUE)
})

# --- Basic Success Case ---
test_that("subset_sample correctly subsets based on a simple character condition", {
  mock_se <- create_mock_se()
  # Dummy logger_name for now
  logger_name <- "test_subset_logger"

  # Expect subset_sample to exist and work
  subset_se <- subset_sample(
    se = mock_se,
    column_name = "treatment",
    condition = "control",
    logger_name = logger_name
  )

  # Verify dimensions
  expect_equal(nrow(subset_se), nrow(mock_se))
  expect_equal(ncol(subset_se), 4) # control samples should be 4

  # Verify colData content
  expect_true(all(subset_se$treatment == "control"))
})

# --- More Complex Conditions (Requires rlang evaluation) ---
test_that("subset_sample handles numeric conditions correctly", {
  mock_se <- create_mock_se()
  logger_name <- "test_subset_numeric"

  # Condition on numeric column 'value'
  # Create heterogeneity for testing
  colData(mock_se)$value <- c(5, 15, 8, 12, 9, 11)

  subset_se <- subset_sample(
    se = mock_se,
    column_name = "value",
    condition = "value > 10", # Condition as full expression string
    logger_name = logger_name
  )

  expect_equal(ncol(subset_se), 3) # Samples with value > 10 (15, 12, 11)
  expect_true(all(subset_se$value > 10))
})

test_that("subset_sample handles logical conditions using rlang", {
  mock_se <- create_mock_se()
  logger_name <- "test_subset_logical"

  # Condition using multiple columns
  subset_se <- subset_sample(
    se = mock_se,
    column_name = "treatment", # Use a valid column name for context, even if condition uses others
    condition = "treatment == 'treated' & batch == 'A'",
    logger_name = logger_name
  )

  expect_equal(ncol(subset_se), 1) # sample3 is treated and batch A
  expect_equal(subset_se$sample_id, "sample3")
})

# --- Subset Name Handling ---
test_that("subset_sample generates subset name automatically", {
  mock_se <- create_mock_se()
  logger_name <- "test_subset_auto_name"

  subset_se_eq <- subset_sample(mock_se, "treatment", "control", logger_name = logger_name)
  # Expected auto name: treatment-control
  expect_equal(metadata(subset_se_eq)$subset_info$subset_name, "treatment-control")

  # Test with a more complex condition string (assuming implementation handles it)
  colData(mock_se)$value <- c(5, 15, 8, 12, 9, 11)
  subset_se_gt <- subset_sample(mock_se, "value", "value > 10", logger_name = logger_name)
  # Expected auto name might be tricky, let's assume a simple sanitization for now
  # The implementation will likely need refinement for complex conditions.
  # Example expectation: "value-value_gt_10" or similar (based on current sanitization)
  expect_match(metadata(subset_se_gt)$subset_info$subset_name, "^value-value")
})

test_that("subset_sample uses provided subset name", {
  mock_se <- create_mock_se()
  logger_name <- "test_subset_provided_name"
  my_name <- "my_favorite_controls"

  subset_se <- subset_sample(
    se = mock_se,
    column_name = "treatment",
    condition = "control",
    subset_name = my_name,
    logger_name = logger_name
  )

  expect_equal(metadata(subset_se)$subset_info$subset_name, my_name)
}) 