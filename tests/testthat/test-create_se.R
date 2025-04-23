# create_se.Rmdのテスト
# biomartをモック化してSummarizedExperimentオブジェクト作成をテスト

library(testthat)
library(SummarizedExperiment)
library(here)
library(fs)

# 注: helper-biomart_mock.R は testthat によって自動的に読み込まれる

# 共通の実験ID
EXPERIMENT_ID <- "test_experiment"
MODULE_NAME <- "create_se"

# 共通の出力ディレクトリ設定関数
setup_test_dirs <- function(test_condition) {
  # 出力ディレクトリは helper-biomart_mock.R で自動的に作成されるので、
  # ここでは返すパスだけを定義する
  results_dir <- here("results", EXPERIMENT_ID)
  return(list(
    results_dir = results_dir,
    output_html = file.path(results_dir, paste0(MODULE_NAME, "-", test_condition, ".html"))
  ))
}

test_that("create_se.Rmd が正常にSEオブジェクトを作成する", {
  # テストデータのパス
  test_data_dir <- here("tests", "testdata", "create_se")
  counts_path <- file.path(test_data_dir, "counts_test.csv")
  metadata_path <- file.path(test_data_dir, "metadata_test.csv")
  
  # 出力ディレクトリの設定
  test_condition <- "basic"
  dirs <- setup_test_dirs(test_condition)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    counts_file_path = counts_path,
    metadata_file_path = metadata_path,
    gene_id_column = "gene_id",
    sample_id_column = "sample_id",
    biomart_host = "https://ensembl.org",
    biomart_dataset = "hsapiens_gene_ensembl",
    biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
    plot_output_dir = dirs$results_dir
  )
  
  # biomartをモック化してRmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "create_se.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # SEオブジェクトが正しく作成されたかのテスト
  expect_s4_class(se, "SummarizedExperiment")
  expect_equal(ncol(se), 2)  # サンプル数
  expect_equal(nrow(se), 2)  # 遺伝子数
  
  # assayが正しく設定されているか
  expect_true("counts" %in% assayNames(se))
  expect_equal(dim(assay(se, "counts")), c(2, 2))
  
  # colDataが正しく設定されているか
  expect_equal(nrow(colData(se)), 2)
  expect_true("condition" %in% colnames(colData(se)))
  expect_equal(rownames(colData(se)), c("sample1", "sample2"))
  
  # rowDataが正しく設定されているか
  expect_equal(nrow(rowData(se)), 2)
  expect_true("ensembl_gene_id" %in% colnames(rowData(se)))
  expect_true("gene_name" %in% colnames(rowData(se)))  # external_gene_nameから変換
  expect_true("gene_biotype" %in% colnames(rowData(se)))
  expect_true(all(rowData(se)$gene_biotype == "protein_coding"))  # モックの設定による
  
  # メタデータが正しく設定されているか
  expect_true("experiment_id" %in% names(metadata(se)))
  expect_equal(metadata(se)$experiment_id, EXPERIMENT_ID)
  expect_true("pipeline_history" %in% names(metadata(se)))
  expect_true("create_se" %in% names(metadata(se)$pipeline_history))
})

test_that("サンプルIDの不一致をエラーまたは警告で処理する", {
  # テストデータのパス
  test_data_dir <- here("tests", "testdata", "create_se")
  counts_path <- file.path(test_data_dir, "counts_mismatch.csv")
  metadata_path <- file.path(test_data_dir, "metadata_test.csv")
  
  # 出力ディレクトリの設定
  test_condition <- "mismatch"
  dirs <- setup_test_dirs(test_condition)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    counts_file_path = counts_path,
    metadata_file_path = metadata_path,
    gene_id_column = "gene_id",
    sample_id_column = "sample_id",
    biomart_host = "https://ensembl.org",
    biomart_dataset = "hsapiens_gene_ensembl",
    biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
    plot_output_dir = dirs$results_dir
  )
  
  # 警告が発生し、かつRmdは実行完了する（警告のみのケース）
  se <- expect_warning(
    render_with_biomart_mock(
      input_rmd_path = here("Rmd", "create_se.Rmd"),
      output_file_path = dirs$output_html,
      params_list = params, 
      test_condition = test_condition
    ),
    regexp = NULL  # 任意の警告を許容
  )
  
  # SEオブジェクトが作成されたことを確認
  expect_s4_class(se, "SummarizedExperiment")
  
  # カウントデータのサンプルが "sample1", "sample3" でメタデータは "sample1", "sample2"
  # なので、共通の "sample1" のみが結果に含まれるはず
  expect_equal(ncol(se), 1)  # 共通サンプルのみ（sample1）
  expect_equal(colnames(se), "sample1")  # sample1のみ含まれる
})

test_that("protein_coding遺伝子のライブラリサイズが正しく計算される", {
  # テストデータのパス
  test_data_dir <- here("tests", "testdata", "create_se")
  counts_path <- file.path(test_data_dir, "counts_test.csv")
  metadata_path <- file.path(test_data_dir, "metadata_test.csv")
  
  # 出力ディレクトリの設定
  test_condition <- "library_size"
  dirs <- setup_test_dirs(test_condition)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    counts_file_path = counts_path,
    metadata_file_path = metadata_path,
    gene_id_column = "gene_id",
    sample_id_column = "sample_id",
    biomart_host = "https://ensembl.org",
    biomart_dataset = "hsapiens_gene_ensembl",
    biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
    plot_output_dir = dirs$results_dir
  )
  
  # biomartをモック化してRmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", "create_se.Rmd"),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # ヘルパー関数でライブラリサイズを計算
  library_sizes <- calculate_protein_coding_library_size(se)
  
  # ライブラリサイズが計算できることを確認
  expect_false(is.null(library_sizes))
  expect_equal(length(library_sizes), 2)  # サンプル数と同じ
  
  # モックでは全遺伝子がprotein_codingなので、ライブラリサイズはカウントの合計と一致するはず
  expected_sizes <- c(
    sample1 = 10 + 20,  # ENSG000001とENSG000002のカウント合計
    sample2 = 30 + 40   # ENSG000001とENSG000002のカウント合計
  )
  expect_equal(library_sizes, expected_sizes)
})

test_that("入力ファイルが存在しない場合にエラーとなる", {
  # 存在しないファイルパス
  nonexistent_counts <- here("tests", "testdata", "create_se", "nonexistent_counts.csv")
  metadata_path <- here("tests", "testdata", "create_se", "metadata_test.csv")
  
  # 出力ディレクトリの設定
  test_condition <- "file_not_found"
  dirs <- setup_test_dirs(test_condition)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    counts_file_path = nonexistent_counts,
    metadata_file_path = metadata_path,
    gene_id_column = "gene_id",
    sample_id_column = "sample_id",
    biomart_host = "https://ensembl.org",
    biomart_dataset = "hsapiens_gene_ensembl",
    biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
    plot_output_dir = dirs$results_dir
  )
  
  # エラーが発生することを期待
  expect_error(
    render_with_biomart_mock(
      input_rmd_path = here("Rmd", "create_se.Rmd"),
      output_file_path = dirs$output_html,
      params_list = params,
      test_condition = test_condition
    ),
    regexp = "カウントファイルが見つかりません"
  )
}) 