library(testthat)
library(SummarizedExperiment)
library(ggplot2)
library(fs)
library(withr)

# plot_library_size がまだ存在しないため、このテストは失敗する (Red)

# テスト用の簡単なSEオブジェクトを作成する関数
create_test_se <- function(n_rows = 10, n_cols = 4, assay_name = "counts") {
  counts <- matrix(rnbinom(n_rows * n_cols, mu = 100, size = 1), nrow = n_rows)
  rownames(counts) <- paste0("gene", 1:n_rows)
  colnames(counts) <- paste0("sample", 1:n_cols)
  assays_list <- list()
  assays_list[[assay_name]] <- counts
  
  coldata <- data.frame(
    condition = factor(rep(c("A", "B"), each = n_cols / 2)),
    row.names = colnames(counts)
  )
  
  SummarizedExperiment(assays = assays_list, colData = coldata)
}

test_that("plot_library_size works correctly in the normal case", {
  # テスト用データ準備
  se <- create_test_se(assay_name = "raw_counts")
  experiment_id <- "test_exp"
  assay_name_to_plot <- "raw_counts"
  
  # 一時ディレクトリでテスト
  temp_dir <- withr::local_tempdir(.local_envir = environment())
  
  # 関数実行
  output_file <- plot_library_size(
    se = se,
    experiment_id = experiment_id,
    assay_name = assay_name_to_plot,
    output_dir = temp_dir,
    logger_name = "test_logger",
    target_name = "test_target"
  )
  
  # 期待されるファイル名
  expected_filename <- glue::glue("library_size_{assay_name_to_plot}_{experiment_id}.png")
  expected_filepath_abs <- fs::path_abs(fs::path(temp_dir, expected_filename))
  
  # アサーション
  expect_equal(output_file, as.character(expected_filepath_abs)) # 返り値が絶対パスか
  expect_true(fs::file_exists(output_file)) # ファイルが生成されたか
  expect_gt(fs::file_info(output_file)$size, 0) # ファイルサイズが0より大きいか
})

test_that("plot_library_size handles errors correctly", {
  # テスト用データ準備
  se <- create_test_se()
  experiment_id <- "test_exp_error"
  valid_assay <- assayNames(se)[1]
  
  temp_dir <- withr::local_tempdir(.local_envir = environment())

  # 不正なSEオブジェクト
  expect_error(
    plot_library_size(se = data.frame(), experiment_id, valid_assay, temp_dir),
    regexp = "'se' must be a SummarizedExperiment object"
  )
  
  # 存在しないアッセイ名
  expect_error(
    plot_library_size(se, experiment_id, "nonexistent_assay", temp_dir),
    regexp = "Assay not found: 'nonexistent_assay'"
  )
  
  # 存在しない出力ディレクトリ
  expect_error(
    plot_library_size(se, experiment_id, valid_assay, "nonexistent_dir"),
    regexp = "Output directory does not exist: nonexistent_dir"
  )
})

# 他の異常系テスト (不正なSEオブジェクト、存在しないoutput_dirなど) も追加可能 