library(testthat)
library(SummarizedExperiment)
library(fs)
library(futile.logger)
library(S4Vectors) # rowData のために追加

# plot_heatmap 関数を読み込む
# Rプロジェクトのルートから実行することを想定
# source("R/plot_heatmap.R") 
# テストファイルの場所から相対的に指定する
source("../../R/plot_heatmap.R")

# テスト用のヘルパー関数: 簡単な SE オブジェクトを作成
create_test_se <- function(nrows = 10, ncols = 6, assay_name = "counts", add_gene_symbol = TRUE) { # ncols を6に変更、add_gene_symbol追加
  set.seed(123)
  counts <- matrix(rnbinom(nrows * ncols, mu = 100, size = 1), nrow = nrows)
  rownames(counts) <- paste0("gene_id_", 1:nrows) # rowname は ID 形式にする
  colnames(counts) <- paste0("sample", 1:ncols)
  
  coldata <- data.frame(
    condition = factor(rep(c("A", "B", "C"), each = ncols / 3)), # 3 condition
    batch = factor(rep(c("X", "Y"), times = ncols / 2)), # 2 batch
    numeric_var = rnorm(ncols),
    row.names = colnames(counts)
  )
  
  # rowData を作成
  rowdata_df <- DataFrame(row.names = rownames(counts))
  if (add_gene_symbol) {
    rowdata_df$gene_symbol <- paste0("SYMBOL", 1:nrows)
  }
  
  assays_list <- list(counts)
  names(assays_list) <- assay_name
  
  SummarizedExperiment(assays = assays_list, colData = coldata, rowData = rowdata_df) # rowData を追加
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

test_that("plot_heatmap basic functionality (gene_symbol, no annotation, default options)", {
  # 準備 (gene_symbol 付き)
  se <- create_test_se(add_gene_symbol = TRUE)
  assay_to_use <- "counts"
  prefix <- "basic_heatmap_genesymbol"
  
  # 関数呼び出し
  output_file <- plot_heatmap(
    se = se,
    assay_name = assay_to_use,
    output_dir = test_output_dir,
    filename_prefix = prefix,
    logger_name = test_logger_name
    # show_rownames = TRUE, show_colnames = TRUE (デフォルト)
  )

  # --- 期待される結果 ---
  # 上位変動遺伝子選択がなくなったため、_top100var サフィックスはつかない
  expected_filename <- paste0(prefix, ".png") # アノテーションなし
  expected_filepath_abs <- path_abs(file.path(test_output_dir, expected_filename))
  
  # 1. 返り値が期待される絶対パスであること
  expect_equal(output_file, expected_filepath_abs)
  expect_s3_class(output_file, "fs_path")

  # 2. 指定されたパスにファイルが実際に生成されていること
  expect_true(file.exists(output_file))
  expect_gt(file.info(output_file)$size, 0) # ファイルサイズが0より大きい
})

test_that("plot_heatmap with annotation and gene_symbol works", {
  # 準備 (gene_symbol 付き)
  se <- create_test_se(add_gene_symbol = TRUE)
  assay_to_use <- "counts"
  prefix <- "annot_heatmap_genesymbol"
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
  # 上位変動遺伝子選択がなくなったため、_top100var サフィックスはつかない
  expected_filename <- paste0(prefix, annotation_suffix, ".png")
  expected_filepath_abs <- path_abs(file.path(test_output_dir, expected_filename))

  expect_equal(output_file, expected_filepath_abs)
  expect_s3_class(output_file, "fs_path")
  expect_true(file.exists(output_file))
  expect_gt(file.info(output_file)$size, 0)
  
  # 数値アノテーションもテスト (gene_symbol 付き)
  prefix_numeric <- "annot_numeric_heatmap_genesymbol"
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
  # 上位変動遺伝子選択がなくなったため、_top100var サフィックスはつかない
  expected_filename_numeric <- paste0(prefix_numeric, annotation_suffix_numeric, ".png")
  expected_filepath_abs_numeric <- path_abs(file.path(test_output_dir, expected_filename_numeric))
  expect_equal(output_file_numeric, expected_filepath_abs_numeric)
  expect_true(file.exists(output_file_numeric))
})

test_that("plot_heatmap options (log_transform, scale_rows, cluster) work with gene_symbol", {
  se <- create_test_se(add_gene_symbol = TRUE)
  assay_to_use <- "counts"
  
  # ログ変換なし
  prefix_nolog <- "nolog_heatmap_gs"
  output_nolog <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_nolog, logger_name=test_logger_name, log_transform = FALSE)
  expect_true(file.exists(output_nolog)) # ファイル名に _top100var はつかない

  # スケーリングなし
  prefix_noscale <- "noscale_heatmap_gs"
  output_noscale <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_noscale, logger_name=test_logger_name, scale_rows = FALSE)
  expect_true(file.exists(output_noscale)) # ファイル名に _top100var はつかない

  # クラスタリングなし
  prefix_noclust <- "noclust_heatmap_gs"
  output_noclust <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_noclust, logger_name=test_logger_name, cluster_rows = FALSE, cluster_cols = FALSE)
  expect_true(file.exists(output_noclust)) # ファイル名に _top100var はつかない
  
  # 組み合わせ（比較は困難なためファイル生成のみ確認）
  prefix_comb <- "comb_opt_heatmap_gs"
  output_comb <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_comb, logger_name=test_logger_name, 
                            log_transform = FALSE, scale_rows = FALSE, cluster_rows = FALSE, cluster_cols = FALSE)
  expect_true(file.exists(output_comb)) # ファイル名に _top100var はつかない
})

test_that("plot_heatmap show_rownames and show_colnames options work", {
  se <- create_test_se(add_gene_symbol = TRUE)
  assay_to_use <- "counts"
  prefix <- "hide_names_heatmap"

  # 関数呼び出し (両方 FALSE)
  output_file <- plot_heatmap(
    se = se,
    assay_name = assay_to_use,
    output_dir = test_output_dir,
    filename_prefix = prefix,
    logger_name = test_logger_name,
    show_rownames = FALSE,
    show_colnames = FALSE
  )

  # --- 期待される結果 ---
  # 上位変動遺伝子選択がなくなったため、_top100var サフィックスはつかない
  expected_filename <- paste0(prefix, ".png")
  expected_filepath_abs <- path_abs(file.path(test_output_dir, expected_filename))

  expect_equal(output_file, expected_filepath_abs)
  expect_true(file.exists(output_file))
  expect_gt(file.info(output_file)$size, 0) 
  # PNGの内容を直接テストするのは難しいが、エラーなく生成されることを確認
  
  # 片方だけ FALSE のケースも追加可能
  prefix_hide_rows <- "hide_rows_heatmap"
  output_hide_rows <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_hide_rows, logger_name=test_logger_name, show_rownames = FALSE)
  expect_true(file.exists(output_hide_rows))

  prefix_hide_cols <- "hide_cols_heatmap"
  output_hide_cols <- plot_heatmap(se, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix_hide_cols, logger_name=test_logger_name, show_colnames = FALSE)
  expect_true(file.exists(output_hide_cols))
})


# --- 異常系のテスト --- 
test_that("plot_heatmap handles errors correctly", {
  se_gs <- create_test_se(add_gene_symbol = TRUE)
  se_nogs <- create_test_se(add_gene_symbol = FALSE)
  assay_to_use <- "counts"
  prefix <- "error_heatmap"

  # 1. 存在しない assay_name
  expect_error(
    plot_heatmap(se_gs, "nonexistent_assay", output_dir=test_output_dir, filename_prefix=prefix, logger_name=test_logger_name),
    regexp = "指定された assay_name 'nonexistent_assay' は se オブジェクトに存在しません。"
  )

  # 2. 不正な annotation_cols (警告は出るがエラーにはならないことを確認)
  #    -> 現状の実装では警告を出すので、expect_warning を使う
  #    注意: plot_heatmap 内の flog.warn は testthat の warning 補足対象外の可能性あり
  #    pheatmap 自体が warning を出すか、自前で warning() を呼ぶ必要あり。
  #    今回は実装が flog.warn のみなので、エラーにならないことだけ確認する。
  prefix_invalid_annot <- "invalid_annot_heatmap"
  expect_no_error({ # エラーにならないことの確認
      output_invalid <- plot_heatmap(
          se = se_gs, 
          assay_name = assay_to_use, 
          annotation_cols = c("condition", "invalid_col"), 
          output_dir=test_output_dir, 
          filename_prefix=prefix_invalid_annot, 
          logger_name=test_logger_name
      )
      # 警告は出るはずだが、ファイルは有効な 'condition' だけで生成される
      valid_annot_cols <- "condition"
      annotation_suffix <- paste0("_annot_", paste(valid_annot_cols, collapse="_"))
      # 上位変動遺伝子選択なし
      expected_filename <- paste0(prefix_invalid_annot, annotation_suffix, ".png")
      expected_filepath_abs <- path_abs(file.path(test_output_dir, expected_filename))
      expect_equal(output_invalid, expected_filepath_abs)
      expect_true(file.exists(output_invalid))
  })


  # 3. gene_symbol が rowData に存在しない場合のエラー
  expect_error(
    plot_heatmap(se_nogs, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix, logger_name=test_logger_name),
    regexp = "rowData\\(se\\) に 'gene_symbol' 列が存在しません。" # エラーメッセージは実装に合わせる
  )
  
  # 4. 不正な se オブジェクト
  expect_error(
      plot_heatmap(list(), assay_to_use, output_dir=test_output_dir, filename_prefix=prefix, logger_name=test_logger_name),
      regexp = "入力 'se' は SummarizedExperiment オブジェクトではありません。"
  )

  # 5. アッセイデータが数値でない場合 (テストデータ作成を工夫する必要あり)
  se_char <- create_test_se(add_gene_symbol=TRUE)
  assay(se_char, "counts", withDimnames=FALSE) <- matrix(as.character(assay(se_char, "counts")), 
                                                      nrow=nrow(se_char), 
                                                      dimnames=dimnames(assay(se_char, "counts"))) # dimnamesを維持
  expect_error(
      plot_heatmap(se_char, assay_to_use, output_dir=test_output_dir, filename_prefix=prefix, logger_name=test_logger_name),
      regexp = "アッセイ 'counts' のデータが数値ではありません。"
  )

}) 