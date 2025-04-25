library(testthat)
library(SummarizedExperiment)
library(futile.logger) # ロギング追加

# Helper function to get last history entry
get_last_history <- function(se) {
  if (!is.null(metadata(se)$pipeline_history)) {
    return(tail(metadata(se)$pipeline_history, 1)[[1]])
  } else {
    return(NULL)
  }
}

# utility.R と subset_gene.R を source (command_testthat.sh が実行してくれるはずだが念のため)
# ただし、command_testthat.sh が source 済みであれば不要
if (!exists("add_pipeline_history")) {
  try(source(file.path("..", "..", "R", "utility.R")))
}
if (!exists("subset_gene")) {
  try(source(file.path("..", "..", "R", "subset_gene.R")))
}

# テストデータ読み込み
# command_testthat.sh は tests/testthat 内で実行されることを想定
test_data_path <- file.path("..", "testdata", "subset_gene", "test_se.rds")
test_se <- readRDS(test_data_path)

test_that("subset_gene filters by a single character condition", {
  # 関数の存在確認 (実装されたので TRUE になるはず)
  expect_true(exists("subset_gene"), info = "Function 'subset_gene' should exist.")

  # ダミー関数定義 (削除)
  # subset_gene <- function(...) stop("Function not implemented yet")

  # フィルタリング条件
  filter_cond <- list("gene_biotype == 'protein_coding'")

  # 実行 (エラーなく実行されるはず)
  # expect_error(
  #   subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger"),
  #   "Function not implemented yet"
  # )

  # --- 実装後のテスト --- (コメント解除)
  result_se <- subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger_single")

  # 結果の検証
  expect_s4_class(result_se, "SummarizedExperiment")
  expect_equal(nrow(result_se), 5, info = "Should filter to 5 protein coding genes.")
  expect_true(all(rowData(result_se)$gene_biotype == "protein_coding"), info = "All remaining genes should be protein_coding.")
  expect_equal(ncol(result_se), ncol(test_se), info = "Number of columns should remain unchanged.")
  expect_equal(assayNames(result_se), assayNames(test_se), info = "Assay names should remain unchanged.")
  expect_equal(metadata(result_se)$experiment_id, metadata(test_se)$experiment_id, info = "Metadata should be preserved (except history).")

  # 履歴の確認
  expect_true("pipeline_history" %in% names(metadata(result_se)), info = "pipeline_history should be added to metadata.")
  last_history <- get_last_history(result_se)
  expect_false(is.null(last_history), info = "pipeline_history should not be empty.")
  expect_equal(last_history$function_name, "subset_gene", info = "Function name in history should be correct.")
  # パラメータ名の修正: history_entry$parameters$filter_conditions
  expect_equal(last_history$parameters$filter_conditions, filter_cond, info = "Filter conditions in history should be correct.")
  expect_equal(last_history$input_dimensions$rows, 10)
  expect_equal(last_history$output_dimensions$rows, 5)
})

test_that("subset_gene filters by multiple conditions (AND)", {
  filter_cond <- list(
    "gene_biotype == 'lncRNA'",
    "chromosome == 'chr1'"
  )
  result_se <- subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger_multi")

  expect_s4_class(result_se, "SummarizedExperiment")
  # lncRNA (Gene6-10), chr1 (Gene1,3,5,7,9)
  # -> Gene7, Gene9
  expect_equal(nrow(result_se), 2, info = "Should filter to 2 lncRNA genes on chr1.")
  expect_true(all(rowData(result_se)$gene_biotype == "lncRNA"), info = "Filtered genes should be lncRNA.")
  expect_true(all(rowData(result_se)$chromosome == "chr1"), info = "Filtered genes should be on chr1.")

  # Check history
  last_history <- get_last_history(result_se)
  expect_equal(last_history$function_name, "subset_gene")
  expect_equal(last_history$parameters$filter_conditions, filter_cond)
  expect_equal(last_history$input_dimensions$rows, 10)
  expect_equal(last_history$output_dimensions$rows, 2)
})

test_that("subset_gene filters by a numeric condition", {
  filter_cond <- list("mean_expression > 30")
  result_se <- subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger_numeric")

  expect_s4_class(result_se, "SummarizedExperiment")
  # mean_expression > 30 (Gene7-10)
  expect_equal(nrow(result_se), 4, info = "Should filter to 4 genes with mean_expression > 30.")
  expect_true(all(rowData(result_se)$mean_expression > 30), info = "Filtered genes should have mean_expression > 30.")

  # Check history
  last_history <- get_last_history(result_se)
  expect_equal(last_history$function_name, "subset_gene")
  expect_equal(last_history$parameters$filter_conditions, filter_cond)
  expect_equal(last_history$input_dimensions$rows, 10)
  expect_equal(last_history$output_dimensions$rows, 4)
})

test_that("subset_gene filters using %in% operator", {
  filter_cond <- list('gene_id %in% c("Gene1", "Gene5", "Gene10")')
  result_se <- subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger_in")

  expect_s4_class(result_se, "SummarizedExperiment")
  expect_equal(nrow(result_se), 3, info = "Should filter to 3 specified genes.")
  expect_equal(sort(rownames(result_se)), c("Gene1", "Gene10", "Gene5"), info = "Correct genes should be selected.") # ソートして比較

  # Check history
  last_history <- get_last_history(result_se)
  expect_equal(last_history$function_name, "subset_gene")
  expect_equal(last_history$parameters$filter_conditions, filter_cond)
  expect_equal(last_history$input_dimensions$rows, 10)
  expect_equal(last_history$output_dimensions$rows, 3)
})

test_that("subset_gene errors with non-existent column", {
  filter_cond <- list("non_existent_column == 'value'")
  expect_error(
    subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger_error_col"),
    regexp = "フィルタリングエラー.*In argument: `non_existent_column == \"value\"`"
  )
})

test_that("subset_gene errors with invalid condition syntax", {
  filter_cond <- list("gene_biotype = ") # Invalid syntax
  expect_error(
    subset_gene(se = test_se, filter_conditions = filter_cond, logger_name = "test_logger_error_syntax"),
    regexp = "フィルタリングエラー"
    # エラーメッセージはパーサーに依存するため、より一般的なregexpを使用
  )
})

test_that("subset_gene errors with wrong input types", {
  # SE が SummarizedExperiment でない場合
  expect_error(
    subset_gene(se = data.frame(a=1), filter_conditions = list("a > 0"), logger_name = "test_logger_error_type1"),
    regexp = "se must be a SummarizedExperiment object"
  )

  # filter_conditions がリストでない場合
  expect_error(
    subset_gene(se = test_se, filter_conditions = "a > 0", logger_name = "test_logger_error_type2"),
    regexp = "filter_conditions must be a list"
  )

  # filter_conditions の要素が文字でない場合
  expect_error(
    subset_gene(se = test_se, filter_conditions = list(a > 0), logger_name = "test_logger_error_type3"),
    regexp = "filter_conditions must contain characters"
  )
})