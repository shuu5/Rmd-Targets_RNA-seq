#' Subset SummarizedExperiment by Column Condition
#'
#' Creates a subset of a SummarizedExperiment object based on a condition
#' applied to a specified column in its colData.
#'
#' @param se SummarizedExperiment object to subset.
#' @param column_name Character string specifying the column in colData to filter on.
#'                    While the `condition` might involve multiple columns, this name
#'                    is used for logging and potentially for default subset naming.
#' @param condition Character string or expression representing the condition for subsetting.
#'                  This will be evaluated in the context of the colData.
#' @param subset_name Optional character string for the name of the subset.
#'                    If NULL, a name is generated automatically.
#' @param logger_name Character string specifying the logger name for futile.logger.
#'
#' @return A SummarizedExperiment object containing the subset of samples.
#' @export
#' @import SummarizedExperiment
#' @import futile.logger
#' @import rlang # For expression evaluation
#' @import stringr # For subset name generation
#' @import S4Vectors # For metadata access
#' @importFrom methods is # To check class inheritance robustly
#' @importFrom stats setNames # For cleaner list creation if needed

# Define dependencies explicitly for renv (and clarity)
library(SummarizedExperiment)
library(futile.logger)
library(rlang)
library(stringr)
library(S4Vectors)
library(methods)

# --- Load utility functions ---
# NOTE: Sourcing utility functions directly like this is fragile.
# Creating an R package for shared functions (like utility.R) is the recommended approach
# for better code management, testing, and dependency handling.
utility_file <- "R/utility.R"
if (file.exists(utility_file)) {
  source(utility_file)
} else {
  # Define a placeholder if utility.R or add_pipeline_history is missing
  add_pipeline_history <- function(se, step_id, function_name, parameters, input_dimensions, output_dimensions, details, ...) {
    warning("add_pipeline_history function not found or utility.R failed to source. Metadata history will not be recorded.")
    # Return the original SE object
    se
  }
}

#' @describeIn subset_sample Main function implementation.
subset_sample <- function(se,
                          column_name,
                          condition,
                          subset_name = NULL,
                          logger_name) {

  # --- 1. Input Validation ---
  flog.trace("[%s] Validating input parameters...", logger_name, name = logger_name)
  if (!methods::is(se, "SummarizedExperiment")) {
    flog.error("[%s] Input 'se' must be a SummarizedExperiment object.", logger_name, name = logger_name)
    stop("Input 'se' must be a SummarizedExperiment object.")
  }
  if (!is.character(column_name) || length(column_name) != 1) {
    flog.error("[%s] 'column_name' must be a single character string.", logger_name, name = logger_name)
    stop("'column_name' must be a single character string.")
  }
  # Check if the specified column exists, even if the condition uses others.
  if (!(column_name %in% colnames(colData(se)))) {
      flog.error("[%s] Column '%s' does not exist in colData.", logger_name, column_name, name = logger_name)
      stop(paste0("Column '", column_name, "' does not exist in colData."))
  }
  if (!is.character(logger_name) || length(logger_name) != 1) {
    # This error might not be logged if logger_name itself is invalid, but try anyway.
    flog.error("[%s] 'logger_name' must be a single character string.", logger_name, name = logger_name)
    stop("'logger_name' must be a single character string.")
  }
  if (!is.character(condition) && !rlang::is_expression(condition)) {
      flog.error("[%s] 'condition' must be a character string or an expression.", logger_name, name = logger_name)
      stop("'condition' must be a character string or an expression.")
  }

  flog.info("[%s] Starting sample subsetting using column '%s' (primarily for context/naming) with condition: %s",
            logger_name, column_name, condition, name = logger_name)
  flog.debug("[%s] Original dimensions: %d features, %d samples",
             logger_name, nrow(se), ncol(se), name = logger_name)


  # --- 2. Evaluate Condition ---
  col_data_df <- as.data.frame(colData(se)) # Evaluate in context of colData

  # Determine evaluation strategy based on condition type
  if (is.character(condition) && length(condition) == 1 && !grepl("[<>=!&|()]", condition)) {
    # --- 2a. Simple Equality Check for Single Character String --- 
    # Assume it's a value to match in the specified column_name
    condition_text <- condition # Original string
    flog.trace("[%s] Applying simple equality condition: %s == \"%s\"", 
               logger_name, column_name, condition_text, name = logger_name)
    col_values <- col_data_df[[column_name]]
    subset_logical <- col_values == condition_text
    # Handle potential NAs in the column itself
    n_na_col <- sum(is.na(subset_logical))
    if (n_na_col > 0) {
        flog.warn("[%s] Column '%s' contains %d NA values. They will not match the condition '%s'.",
                  logger_name, column_name, n_na_col, condition_text, name = logger_name)
        subset_logical[is.na(subset_logical)] <- FALSE # NAs in data don't match condition
    }

  } else {
    # --- 2b. Expression Evaluation using rlang --- 
    if (is.character(condition)) {
        condition_text <- condition # Store original text for metadata/logging
        flog.trace("[%s] Parsing character condition as expression: %s", logger_name, condition_text, name = logger_name)
        condition_expr <- tryCatch({
            rlang::parse_expr(condition_text)
        }, error = function(e) {
            flog.error("[%s] Error parsing condition string '%s': %s", logger_name, condition_text, e$message, name = logger_name)
            stop(paste("Error parsing condition string:", condition_text, "-", e$message))
        })
    } else {
        condition_expr <- condition
        condition_text <- rlang::expr_deparse(condition_expr) # Deparse expression for metadata/logging
        flog.trace("[%s] Using provided expression condition: %s", logger_name, condition_text, name = logger_name)
    }

    flog.trace("[%s] Evaluating expression condition in the context of colData columns: %s",
                logger_name, paste(colnames(col_data_df), collapse=", "), name = logger_name)

    # Use tryCatch to handle evaluation errors gracefully
    subset_logical <- tryCatch({
        rlang::eval_tidy(condition_expr, data = col_data_df)
    }, error = function(e) {
        flog.error("[%s] Error evaluating condition expression '%s': %s", logger_name, condition_text, e$message, name = logger_name)
        stop(paste("Error evaluating condition expression:", condition_text, "-", e$message,
                   ". Ensure column names in the condition exist in colData."))
    })

    # Validate the result of evaluation
    if (!is.logical(subset_logical)) {
        flog.error("[%s] Condition expression '%s' did not evaluate to a logical vector.", logger_name, condition_text, name = logger_name)
        stop(paste("Condition expression", condition_text, "did not evaluate to a logical vector."))
    }
    if (length(subset_logical) != ncol(se)) {
        flog.error("[%s] Condition expression evaluation result length (%d) does not match number of samples (%d).",
                    logger_name, length(subset_logical), ncol(se), name = logger_name)
        stop("Condition expression evaluation result length does not match number of samples.")
    }

    # Handle NAs produced by the condition evaluation (treat NA as FALSE for subsetting)
    n_na_eval <- sum(is.na(subset_logical))
    if (n_na_eval > 0) {
        flog.warn("[%s] Condition expression evaluation resulted in %d NA values, treating them as FALSE for subsetting.",
                  logger_name, n_na_eval, name = logger_name)
        subset_logical[is.na(subset_logical)] <- FALSE
    }
  }

  subset_indices <- which(subset_logical)
  n_original <- ncol(se)
  n_subset <- length(subset_indices)
  subset_percentage <- ifelse(n_original > 0, (n_subset / n_original) * 100, 0)

  flog.info("[%s] Subset condition evaluated. Result: %d out of %d samples selected (%.1f%%).",
            logger_name, n_subset, n_original, subset_percentage, name = logger_name)

  if (n_subset == 0) {
      flog.warn("[%s] Subsetting resulted in 0 samples. Check condition '%s' on column '%s' (and potentially other columns involved).",
                logger_name, condition, column_name, name = logger_name)
      # Return an SE with 0 columns but update metadata before returning
  }

  # --- 3. Determine Subset Name ---
  if (is.null(subset_name) || subset_name == "") {
    # Generate name based on column and a sanitized version of the condition
    # Replace non-alphanumeric characters (allowing ., -, _) with underscore
    safe_condition_part <- stringr::str_replace_all(condition_text, "[^a-zA-Z0-9_.-]", "_")
    # Truncate if too long
    max_len <- 30 # Arbitrary length limit for condition part
    if (nchar(safe_condition_part) > max_len) {
        safe_condition_part <- substr(safe_condition_part, 1, max_len)
    }
    subset_name <- paste(column_name, safe_condition_part, sep = "-")
    flog.debug("[%s] Generated subset name: '%s'", logger_name, subset_name, name = logger_name)
  } else {
    flog.debug("[%s] Using provided subset name: '%s'", logger_name, subset_name, name = logger_name)
  }

  # --- 4. Create Subset SE ---
  original_dims <- dim(se)
  # Handle the 0 subset case specifically for indexing
  if (n_subset == 0) {
      subset_se <- se[, integer(0)]
  } else {
      subset_se <- se[, subset_indices]
  }
  subset_dims <- dim(subset_se)

  # --- 5. Update Metadata ---
  flog.trace("[%s] Updating metadata for the subsetted SE object.", logger_name, name = logger_name)

  # --- 5.1. subset_info ---
  subset_info_list <- list(
      column_name = column_name, # The primary column name provided
      condition = condition_text, # The condition string used
      subset_name = subset_name,
      original_samples = original_dims[2],
      subset_samples = subset_dims[2]
  )
  # Ensure metadata list exists before assigning
  if (!"subset_info" %in% names(metadata(subset_se))) {
      metadata(subset_se)$subset_info <- list()
  }
  # Append or overwrite? Let's overwrite for simplicity, assuming one subset step defines this info.
  metadata(subset_se)$subset_info <- subset_info_list
  flog.debug("[%s] Added/updated metadata()$subset_info.", logger_name, name = logger_name)

  # --- 5.2. pipeline_history ---
  params_list <- list(
      column_name = column_name,
      condition = condition_text, # Store the actual condition string/deparsed expr
      subset_name = subset_name   # Store the final name used
      # Note: original condition object (if expression) isn't easily serializable here
  )
  details_text <- sprintf("Subset on '%s' (context) with condition '%s'. Result: %d/%d samples. Subset name: '%s'. %d NA conditions treated as FALSE.",
                          column_name, condition_text, subset_dims[2], original_dims[2], subset_name, 
                          ifelse(exists("n_na_eval"), n_na_eval, 0)) # Use n_na_eval if expression path was taken

  # Call the utility function to add history
  # Use logger_name as step_id for now, assuming it relates to the target name.
  # This might need refinement based on how run_with_logging passes target_name.
  subset_se <- tryCatch({
      add_pipeline_history(
          se = subset_se,
          step_id = logger_name, # <<< Assumption: logger_name is derived from target name
          function_name = "subset_sample",
          parameters = params_list,
          input_dimensions = original_dims,
          output_dimensions = subset_dims,
          details = details_text
      )
  }, error = function(e) {
      flog.warn("[%s] Failed to add pipeline history: %s. Continuing without history update.",
                logger_name, e$message, name = logger_name)
      # Return the subset_se without the history update in case of error
      subset_se
  })
  flog.debug("[%s] Updated metadata()$pipeline_history.", logger_name, name = logger_name)


  # --- 6. Return Subset ---
  flog.info("[%s] Sample subsetting completed. Returning SE object with %d features and %d samples.",
            logger_name, nrow(subset_se), ncol(subset_se), name = logger_name)
  return(subset_se)
} 