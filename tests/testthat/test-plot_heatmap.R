library(testthat)
library(SummarizedExperiment)
library(fs)
library(futile.logger)

# plot_heatmap 関数を読み込む
# Rプロジェクトのルートから実行することを想定
# source("R/plot_heatmap.R") 
# テストファイルの場所から相対的に指定する
source("../../R/plot_heatmap.R")

# テスト用のヘルパー関数: 簡単な SE オブジェクトを作成
create_test_se <- function(nrows = 10, ncols = 6, assay_name = "counts") { # ncols を6に変更してアノテーションの組み合わせを増やす
  set.seed(123)
  counts <- matrix(rnbinom(nrows * ncols, mu = 100, size = 1), nrow = nrows)
  rownames(counts) <- paste0("gene", 1:nrows)
  colnames(counts) <- paste0("sample", 1:ncols)
  
  coldata <- data.frame(
    condition = factor(rep(c("A", "B", "C"), each = ncols / 3)), # 3 condition
    batch = factor(rep(c("X", "Y"), times = ncols / 2)), # 2 batch
    numeric_var = rnorm(ncols),
    row.names = colnames(counts)
  )
  
  assays_list <- list(counts)
  names(assays_list) <- assay_name
  
  SummarizedExperiment(assays = assays_list, colData = coldata)
}

# テスト用の設定
test_output_dir <- file.path(tempdir(), "test_plot_heatmap_output")
test_logger_name <- "test_plot_heatmap"

# テスト実行前に出力ディレクトリをクリーンアップ・作成
setup({
  if (dir.exists(test_output_dir)) {
    unlink(test_output_dir, recursive = TRUE)
    cat("Cleaned up existing test directory:", test_output_dir, "\n")
  }
  dir.create(test_output_dir, recursive = TRUE)
  cat("Created test directory:", test_output_dir, "\n")
  # テスト中は INFO レベル以上のログのみコンソールに出力 (任意)
  flog.threshold(INFO, name = test_logger_name)
  # futile.logger の他の設定 (ファイル出力など) は関数側で行う
})

# テストスイート終了時にテスト用ディレクトリを削除
teardown({
  if (dir.exists(test_output_dir)) {
    unlink(test_output_dir, recursive = TRUE)
    cat("Cleaned up test directory:", test_output_dir, "\n")
  }
})

test_that("plot_heatmap basic functionality (no annotation, default options)", {
  # 準備
  se <- create_test_se()
  assay_to_use <- "counts"
  prefix <- "basic_heatmap"
  
  # 関数呼び出し
  output_file <- plot_heatmap(
    se = se,
    assay_name = assay_to_use,
    output_dir = test_output_dir,
    filename_prefix = prefix,
    logger_name = test_logger_name
  )

  # --- 期待される結果 ---
  expected_filename <- paste0(prefix, ".png") # アノテーションなし
  expected_filepath_abs <- path_abs(file.path(test_output_dir, expected_filename))
  
  # 1. 返り値が期待される絶対パスであること
  expect_equal(output_file, expected_filepath_abs)
  expect_s3_class(output_file, "fs_path")

  # 2. 指定されたパスにファイルが実際に生成されていること
  expect_true(file.exists(output_file))
  expect_gt(file.info(output_file)$size, 0) # ファイルサイズが0より大きい
})

test_that("plot_heatmap with annotation works", {
  # 準備
  se <- create_test_se()
  assay_to_use <- "counts"
  prefix <- "annot_heatmap"
  annot_cols <- c("condition", "batch")

  # 関数呼び出し
  output_file <- plot_heatmap(
    se = se,
    assay_name = assay_to_use,
    annotation_cols = annot_cols,
    output_dir = test_output_dir,
    filename_prefix = prefix,
    logger_name = test_logger_name
  )

  # --- 期待される結果 ---
  annotation_suffix <- paste0("_annot_", paste(annot_cols, collapse="_"))
  expected_filename <- paste0(prefix, annotation_suffix, ".png")
  expected_filepath_abs <- path_abs(file.path(test_output_dir, expected_filename))

  expect_equal(output_file, expected_filepath_abs)
  expect_s3_class(output_file, "fs_path")
  expect_true(file.exists(output_file))
  expect_gt(file.info(output_file)$size, 0)
  
  # 数値アノテーションもテスト
  prefix_numeric <- "annot_numeric_heatmap"
  annot_cols_numeric <- c("condition", "numeric_var")
  output_file_numeric <- plot_heatmap(
    se = se,
    assay_name = assay_to_use,
    annotation_cols = annot_cols_numeric,
    output_dir = test_output_dir,
    filename_prefix = prefix_numeric,
    logger_name = test_logger_name
  )
  annotation_suffix_numeric <- paste0("_annot_", paste(annot_cols_numeric, collapse="_"))
  expected_filename_numeric <- paste0(prefix_numeric, annotation_suffix_numeric, ".png")
  expected_filepath_abs_numeric <- path_abs(file.path(test_output_dir, expected_filename_numeric))
  expect_equal(output_file_numeric, expected_filepath_abs_numeric)
  expect_true(file.exists(output_file_numeric))
})

test_that("plot_heatmap options (log_transform, scale_rows, cluster) work", {
  se <- create_test_se()
  assay_to_use <- "counts"
  
  # ログ変換なし
  prefix_nolog <- "nolog_heatmap"
  output_nolog <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_nolog, logger_name=test_logger_name, log_transform = FALSE)
  expect_true(file.exists(output_nolog))

  # スケーリングなし
  prefix_noscale <- "noscale_heatmap"
  output_noscale <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_noscale, logger_name=test_logger_name, scale_rows = FALSE)
  expect_true(file.exists(output_noscale))

  # クラスタリングなし
  prefix_noclust <- "noclust_heatmap"
  output_noclust <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_noclust, logger_name=test_logger_name, cluster_rows = FALSE, cluster_cols = FALSE)
  expect_true(file.exists(output_noclust))
  
  # 組み合わせ（比較は困難なためファイル生成のみ確認）
  prefix_comb <- "comb_opt_heatmap"
  output_comb <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_comb, logger_name=test_logger_name, 
                            log_transform = FALSE, scale_rows = FALSE, cluster_rows = FALSE, cluster_cols = FALSE)
  expect_true(file.exists(output_comb))
})

# --- 異常系のテストは後で追加 --- 