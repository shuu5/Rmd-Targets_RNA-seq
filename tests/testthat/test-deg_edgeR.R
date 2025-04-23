# deg_edgeR.Rmdのテスト

library(testthat)
library(SummarizedExperiment)
library(here)
library(fs)
library(edgeR)

# 共通の実験ID
EXPERIMENT_ID <- "test_experiment"
MODULE_NAME <- "deg_edgeR"

# 共通の出力ディレクトリ設定関数
setup_test_dirs <- function(test_condition) {
  results_dir <- here("results", EXPERIMENT_ID)
  return(list(
    results_dir = results_dir,
    output_html = file.path(results_dir, paste0(MODULE_NAME, "-", test_condition, ".html"))
  ))
}

# レプリケートがある場合のテスト前準備
setup_replicate_test <- function() {
  # テストデータのパス
  test_data_dir <- here("tests", "testdata", "deg_edgeR")
  counts_path <- file.path(test_data_dir, "counts_test.csv")
  metadata_path <- file.path(test_data_dir, "metadata_test.csv")
  
  # カウントデータとメタデータ読み込み
  counts_data <- read.csv(counts_path, row.names = 1, check.names = FALSE)
  metadata <- read.csv(metadata_path, check.names = FALSE)
  
  # SEオブジェクト作成
  se <- SummarizedExperiment(
    assays = list(counts = as.matrix(counts_data)),
    colData = DataFrame(metadata[match(colnames(counts_data), metadata$sample_id), ])
  )
  
  # メタデータに実験情報を追加
  metadata(se)$experiment_id <- EXPERIMENT_ID
  metadata(se)$pipeline_history <- list()
  
  return(se)
}

# レプリケートがない場合のテスト前準備
setup_no_replicate_test <- function() {
  # テストデータのパス
  test_data_dir <- here("tests", "testdata", "deg_edgeR")
  counts_path <- file.path(test_data_dir, "counts_no_rep_test.csv")
  metadata_path <- file.path(test_data_dir, "metadata_no_rep_test.csv")
  
  # カウントデータとメタデータ読み込み
  counts_data <- read.csv(counts_path, row.names = 1, check.names = FALSE)
  metadata <- read.csv(metadata_path, check.names = FALSE)
  
  # SEオブジェクト作成
  se <- SummarizedExperiment(
    assays = list(counts = as.matrix(counts_data)),
    colData = DataFrame(metadata[match(colnames(counts_data), metadata$sample_id), ])
  )
  
  # メタデータに実験情報を追加
  metadata(se)$experiment_id <- EXPERIMENT_ID
  metadata(se)$pipeline_history <- list()
  
  return(se)
}

test_that("deg_edgeR.Rmd が正常にDEG解析を実行する（レプリケートあり）", {
  # SEオブジェクト作成
  input_se <- setup_replicate_test()
  
  # 出力ディレクトリの設定
  test_condition <- "with_replicates"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ
    target_gene = "IFITM3",
    assay = "knockdown",
    # DEG解析パラメータ
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "condition",
    housekeeping_gene_set = "standard",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # 出力検証
  expect_s4_class(se, "SummarizedExperiment")
  
  # SEオブジェクトの検証
  expect_true("pipeline_history" %in% names(metadata(se)))
  expect_true("deg_edgeR" %in% names(metadata(se)$pipeline_history))
  
  # DEG解析結果が保存されているか
  expect_true("deg_results" %in% names(metadata(se)))
  expect_true(all(c("sh1_vs_scramble", "sh2_vs_scramble") %in% names(metadata(se)$deg_results)))
  
  # DEG結果ファイルが生成されたか
  expect_true(file.exists(file.path(table_dir, "deg_sh1_vs_scramble.csv")))
  expect_true(file.exists(file.path(table_dir, "deg_sh2_vs_scramble.csv")))
  
  # プロットが生成されたか
  expect_true(file.exists(file.path(plot_dir, "ma_plot_sh1_vs_scramble.png")))
  expect_true(file.exists(file.path(plot_dir, "volcano_plot_sh1_vs_scramble.png")))
  expect_true(file.exists(file.path(plot_dir, "ma_plot_sh2_vs_scramble.png")))
  expect_true(file.exists(file.path(plot_dir, "volcano_plot_sh2_vs_scramble.png")))
})

test_that("deg_edgeR.Rmd が正常にDEG解析を実行する（レプリケートなし）", {
  # SEオブジェクト作成
  input_se <- setup_no_replicate_test()
  
  # 出力ディレクトリの設定
  test_condition <- "no_replicates"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ
    target_gene = "IFITM3",
    assay = "knockdown",
    # DEG解析パラメータ
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "condition",
    housekeeping_gene_set = "standard",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # 出力検証
  expect_s4_class(se, "SummarizedExperiment")
  
  # SEオブジェクトの検証
  expect_true("pipeline_history" %in% names(metadata(se)))
  expect_true("deg_edgeR" %in% names(metadata(se)$pipeline_history))
  
  # DEG解析結果が保存されているか
  expect_true("deg_results" %in% names(metadata(se)))
  expect_true(all(c("sh1_vs_scramble", "sh2_vs_scramble") %in% names(metadata(se)$deg_results)))
  
  # ハウスキーピング遺伝子を使用したcommon dispersionが設定されているか
  expect_true("common_dispersion" %in% names(metadata(se)))
  
  # DEG結果ファイルが生成されたか
  expect_true(file.exists(file.path(table_dir, "deg_sh1_vs_scramble.csv")))
  expect_true(file.exists(file.path(table_dir, "deg_sh2_vs_scramble.csv")))
  
  # プロットが生成されたか
  expect_true(file.exists(file.path(plot_dir, "ma_plot_sh1_vs_scramble.png")))
  expect_true(file.exists(file.path(plot_dir, "volcano_plot_sh1_vs_scramble.png")))
  expect_true(file.exists(file.path(plot_dir, "ma_plot_sh2_vs_scramble.png")))
  expect_true(file.exists(file.path(plot_dir, "volcano_plot_sh2_vs_scramble.png")))
})

test_that("deg_edgeR.Rmd で異なるハウスキーピング遺伝子セットを使用できる", {
  # SEオブジェクト作成
  input_se <- setup_no_replicate_test()
  
  # 出力ディレクトリの設定
  test_condition <- "alternative_hk"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ
    target_gene = "IFITM3",
    assay = "knockdown",
    # DEG解析パラメータ
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "condition",
    housekeeping_gene_set = "alternative",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # 出力検証
  expect_s4_class(se, "SummarizedExperiment")
  
  # 使用したハウスキーピング遺伝子セットがメタデータに記録されているか
  expect_equal(metadata(se)$pipeline_history$deg_edgeR$parameters$housekeeping_gene_set, "alternative")
})

test_that("サンプルフィルタリングが正しく動作する", {
  # SEオブジェクト作成 - 追加のサンプルを含むSEを作成
  se_with_extra <- setup_replicate_test()
  
  # 異なるtarget_geneを持つサンプルを追加
  extra_coldata <- DataFrame(
    sample_id = c("other1", "other2"),
    condition = c("scramble", "sh1"),
    target_gene = c("TP53", "TP53"),
    assay = c("knockdown", "knockdown"),
    replicate = c(1, 1)
  )
  
  # 既存のcolDataに追加行を追加
  new_coldata <- rbind(colData(se_with_extra), extra_coldata)
  
  # 行名リストを取得（必要な行数だけの遺伝子ID）
  gene_ids <- rownames(assay(se_with_extra, "counts"))
  
  # extraサンプル用のカウントを追加
  # 各遺伝子に対応した値を用意（行数を合わせる）
  extra_counts <- matrix(
    c(
      # 各遺伝子に対応した値（other1用の14個の値）
      100, 50, 200, 100, 50, 25, 10, 5, 2, 1, 1000, 1200, 500, 800,
      # other2用の14個の値
      90, 45, 180, 90, 45, 20, 9, 4, 1, 1, 900, 1100, 450, 700
    ),
    nrow = length(gene_ids),
    ncol = 2,
    byrow = FALSE,
    dimnames = list(gene_ids, c("other1", "other2"))
  )
  
  # 既存のカウントマトリックスにextraカウントを追加
  combined_counts <- cbind(assay(se_with_extra, "counts"), extra_counts)
  
  # 新しいSEオブジェクトを作成
  se_combined <- SummarizedExperiment(
    assays = list(counts = combined_counts),
    colData = new_coldata[match(colnames(combined_counts), new_coldata$sample_id), ]
  )
  
  metadata(se_combined)$experiment_id <- EXPERIMENT_ID
  metadata(se_combined)$pipeline_history <- list()
  
  # 出力ディレクトリの設定
  test_condition <- "filtering"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = se_combined,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ
    target_gene = "IFITM3",
    assay = "knockdown",
    # DEG解析パラメータ
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "condition",
    housekeeping_gene_set = "standard",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # フィルタリング後のサンプル数を確認 - IFITM3のみが残るはず
  expect_equal(ncol(se), 6)  # IFITM3サンプルのみ
  expect_true(all(colData(se)$target_gene == "IFITM3"))
})

test_that("deg_edgeR.Rmd が filter_columns パラメータを使ってサンプルをフィルタリングできる", {
  # SEオブジェクト作成
  input_se <- setup_replicate_test()
  
  # 出力ディレクトリの設定
  test_condition <- "filter_columns"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定 - filter_columnsを使用
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ - 新しい方法
    filter_columns = list(target_gene = "IFITM3", assay = "knockdown"),
    # DEG解析パラメータ
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "condition",
    housekeeping_gene_set = "standard",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # 出力検証
  expect_s4_class(se, "SummarizedExperiment")
  
  # SEオブジェクトの検証
  expect_true("pipeline_history" %in% names(metadata(se)))
  expect_true("deg_edgeR" %in% names(metadata(se)$pipeline_history))
  expect_true("filter_columns" %in% names(metadata(se)$pipeline_history$deg_edgeR$parameters))
  
  # フィルタリング条件が保存されているか
  expect_equal(metadata(se)$pipeline_history$deg_edgeR$parameters$filter_columns$target_gene, "IFITM3")
  expect_equal(metadata(se)$pipeline_history$deg_edgeR$parameters$filter_columns$assay, "knockdown")
  
  # DEG解析結果が保存されているか
  expect_true("deg_results" %in% names(metadata(se)))
  expect_true(all(c("sh1_vs_scramble", "sh2_vs_scramble") %in% names(metadata(se)$deg_results)))
})

test_that("deg_edgeR.Rmd が 単一のフィルタリング列（cell_lineのみ）を使用できる", {
  # SEオブジェクト作成
  input_se <- setup_replicate_test()
  
  # cell_line列を追加（テスト用）
  colData(input_se)$cell_line <- rep(c("HEK293", "HeLa"), each = 3)
  
  # 出力ディレクトリの設定
  test_condition <- "filter_by_cell_line"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定 - cell_lineのみでフィルタリング
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ - cell_lineのみ
    filter_columns = list(cell_line = "HEK293"),
    # DEG解析パラメータ
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "condition",
    housekeeping_gene_set = "standard",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # 出力検証
  expect_s4_class(se, "SummarizedExperiment")
  
  # フィルタリング結果を確認
  expect_equal(ncol(se), 3)  # HEK293のサンプルのみ
  expect_true(all(colData(se)$cell_line == "HEK293"))
  
  # フィルタリング条件が保存されているか
  expect_equal(metadata(se)$pipeline_history$deg_edgeR$parameters$filter_columns$cell_line, "HEK293")
  
  # DEG解析結果が保存されているか
  expect_true("deg_results" %in% names(metadata(se)))
})

test_that("deg_edgeR.Rmd が 異なる条件列名(treatment_group)を使用できる", {
  # SEオブジェクト作成
  input_se <- setup_replicate_test()
  
  # treatment_group列を追加（条件列として使用）
  colData(input_se)$treatment_group <- colData(input_se)$condition
  
  # 出力ディレクトリの設定
  test_condition <- "custom_condition_column"
  dirs <- setup_test_dirs(test_condition)
  
  # 出力ディレクトリの作成
  plot_dir <- file.path(dirs$results_dir, "plots")
  table_dir <- file.path(dirs$results_dir, "tables")
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  # パラメータ設定 - treatment_groupを条件列として使用
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = plot_dir,
    table_dir = table_dir,
    # フィルタリングパラメータ
    filter_columns = list(target_gene = "IFITM3", assay = "knockdown"),
    # DEG解析パラメータ - カスタム条件列
    control = "scramble",
    targets = c("sh1", "sh2"),
    condition_column = "treatment_group",  # 異なる条件列名
    housekeeping_gene_set = "standard",
    fdr_threshold = 0.05,
    log2fc_threshold = 1
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "deg_edgeR.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # 出力検証
  expect_s4_class(se, "SummarizedExperiment")
  
  # 条件列の設定が保存されているか
  expect_equal(metadata(se)$pipeline_history$deg_edgeR$parameters$condition_column, "treatment_group")
  
  # DEG解析結果が保存されているか
  expect_true("deg_results" %in% names(metadata(se)))
  expect_true(all(c("sh1_vs_scramble", "sh2_vs_scramble") %in% names(metadata(se)$deg_results)))
}) 