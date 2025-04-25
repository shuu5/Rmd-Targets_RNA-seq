library(testthat)
library(SummarizedExperiment)
library(fs)

# plot_log_density がまだ存在しないため、このテストは失敗する (Red)

# テスト用の簡単なSEオブジェクトを作成する関数 (test-plot_library_size.R と共通化可能)
create_test_se <- function(nrow = 10, ncol = 4, assay_name = "counts") {
  counts <- matrix(rnbinom(nrow * ncol, mu = 100, size = 1), nrow = nrow, ncol = ncol)
  colnames(counts) <- paste0("sample", 1:ncol)
  rownames(counts) <- paste0("gene", 1:nrow)
  assays_list <- list()
  assays_list[[assay_name]] <- counts
  SummarizedExperiment(assays = assays_list)
}

test_that("plot_log_density generates a file and returns its path", {
  # Arrange
  se <- create_test_se()
  exp_id <- "test_exp_dens"
  assay_name <- "counts"
  test_output_dir <- fs::path_temp(exp_id, "plots")
  fs::dir_create(test_output_dir)
  logger_name <- "test_plot_log_density"
  target_name <- "file_plot_log_dens"

  expected_filename <- glue::glue("log_density_{assay_name}_{exp_id}.png")
  expected_filepath_abs <- fs::path_abs(fs::path(test_output_dir, expected_filename))

  # Act
  # plot_log_density 関数が存在しない、または未実装のためエラーになるはず
  # expect_error({
  actual_filepath <- plot_log_density(
    se = se,
    experiment_id = exp_id,
    assay_name = assay_name,
    output_dir = test_output_dir,
    logger_name = logger_name,
    target_name = target_name
  )
  # })

  # # --- Greenフェーズで有効化するアサーション ---
  # Assert
  expect_equal(actual_filepath, expected_filepath_abs)
  expect_true(fs::file_exists(expected_filepath_abs))
  expect_gt(fs::file_info(expected_filepath_abs)$size, 0)
  # # --- ここまで ---

  # Clean up
  # 一時ディレクトリ全体を削除するように修正
  unlink(fs::path_temp(exp_id), recursive = TRUE, force = TRUE)
})

test_that("plot_log_density handles missing assay", {
  # Arrange
  se <- create_test_se(assay_name = "other_counts")
  exp_id <- "test_exp_dens_assay"
  assay_name <- "counts" # 存在しないアッセイ名
  test_output_dir <- fs::path_temp(exp_id, "plots")
  fs::dir_create(test_output_dir)
  logger_name <- "test_plot_log_density_error"
  target_name <- "file_plot_log_dens_err"

  # Act & Assert
  expect_error(
    plot_log_density(
      se = se,
      experiment_id = exp_id,
      assay_name = assay_name,
      output_dir = test_output_dir,
      logger_name = logger_name,
      target_name = target_name
    ),
    regexp = "Assay not found"
  )

  # Clean up
  fs::dir_delete(fs::path_temp(exp_id))
}) 