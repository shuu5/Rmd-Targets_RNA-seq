# tests/test-create_se.R

# --- 必要なライブラリの読み込み ---
library(testthat)
# library(testrmd) # testrmd は直接使用しない
library(SummarizedExperiment)
library(fs)
library(rmarkdown) # rmarkdown を追加
library(here) # here を追加
library(readr)
# ヘルパーファイルに移動したためmockeryは不要
# library(mockery) 

# --- テスト設定 ---
# Rmd ファイルへのパス (プロジェクトルート基準)
rmd_file <- here::here("Rmd", "create_se.Rmd")
# ダミーデータへのパス (プロジェクトルート基準)
dummy_counts_path <- here::here("tests", "testdata", "counts_test.csv")
dummy_metadata_path <- here::here("tests", "testdata", "metadata_test.csv")
# 存在しないファイルパス (これはそのままで良い)
nonexistent_path <- "path/to/nonexistent/file.csv"
# テスト用の出力ディレクトリ（一時的に作成）
test_output_dir <- fs::file_temp("test_create_se_")
fs::dir_create(test_output_dir)
# テスト終了時に一時ディレクトリを削除
withr::defer(fs::dir_delete(test_output_dir), envir = parent.frame())

# --- ヘルパー関数の定義はhelper-biomart_mock.Rに移動 ---

# --- テストコンテキスト ---
context("Rmd/create_se.Rmd - SummarizedExperiment 作成モジュール (render, here)")

# --- テストケース ---

test_that("入力ファイルが存在しない場合にエラーを発生させる", {
  # カウントファイルが存在しない場合
  expect_error(
    render_with_biomart_mock(
        rmd_file,
        fs::path(test_output_dir, "error_no_counts.html"),
        params = list(
            experiment_id = "test_no_counts",
            counts_file_path = nonexistent_path,
            metadata_file_path = dummy_metadata_path,
            biomart_dataset = "hsapiens_gene_ensembl"
        )
    ),
    regexp = "カウントファイルが見つかりません"
  )

  # メタデータファイルが存在しない場合
  expect_error(
    render_with_biomart_mock(
        rmd_file,
        fs::path(test_output_dir, "error_no_metadata.html"),
        params = list(
            experiment_id = "test_no_metadata",
            counts_file_path = dummy_counts_path,
            metadata_file_path = nonexistent_path,
            biomart_dataset = "hsapiens_gene_ensembl"
        )
    ),
    regexp = "メタデータファイルが見つかりません"
  )
})

test_that("正常な入力で SummarizedExperiment オブジェクトが作成される (biomaRtモック使用)", {
  # biomaRtモックを使用してテスト - スキップをコメントアウト
  # skip("時間がかかるので必要時のみ実行")
  
  se <- render_with_biomart_mock(
    rmd_file,
    fs::path(test_output_dir, "success.html"),
    params = list(
      experiment_id = "test_success",
      counts_file_path = dummy_counts_path,
      metadata_file_path = dummy_metadata_path,
      biomart_dataset = "hsapiens_gene_ensembl",
      biomart_host = "https://ensembl.org",
      biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")
    ),
    debug = TRUE
  )
  
  expect_s4_class(se, "SummarizedExperiment")
})


test_that("作成された SE オブジェクトの内容が期待通りである (biomaRtモック使用)", {
  # スキップをコメントアウト
  # skip("時間がかかるので必要時のみ実行")
  
  se <- render_with_biomart_mock(
    rmd_file,
    fs::path(test_output_dir, "content.html"),
    params = list(
      experiment_id = "test_content",
      counts_file_path = dummy_counts_path,
      metadata_file_path = dummy_metadata_path,
      biomart_dataset = "hsapiens_gene_ensembl",
      gene_id_column = "gene_id",
      sample_id_column = "sample_id",
      biomart_host = "https://ensembl.org",
      biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")
    )
  )

  # オブジェクトが NULL でないことを確認
  expect_false(is.null(se), info = "Rendered Rmd did not return an SE object.")
  # SE オブジェクトのクラスを再度確認
  expect_s4_class(se, "SummarizedExperiment")

  # 1. Assay の確認
  expect_true("counts" %in% assayNames(se))
  expect_equal(dim(assay(se, "counts")), c(2, 2), info = "Assay dimensions mismatch.") # ダミーデータ: 2遺伝子 x 2サンプル
  expect_equal(assay(se, "counts")[1,1], 10, info = "Assay value mismatch.") # 具体的な値もチェック

  # 2. colData の確認
  expect_equal(nrow(colData(se)), 2, info = "colData row count mismatch.") # 2サンプル
  expect_true("condition" %in% colnames(colData(se)), info = "colData 'condition' column missing.") # ダミーメタデータ列
  # ★重要: colData の rownames はカウントデータのサンプル名になるはず
  expect_equal(rownames(colData(se)), c("sample1", "sample2"), info = "colData rownames mismatch.")
  expect_equal(colData(se)$sample_id, c("sample1", "sample2"), info = "colData 'sample_id' column mismatch.") # サンプルID列も確認

  # 3. rowData の確認 (biomaRt の結果に依存するため、基本的な列の存在を確認)
  expect_equal(nrow(rowData(se)), 2, info = "rowData row count mismatch.") # 2遺伝子
  expect_true("ensembl_gene_id" %in% colnames(rowData(se)), info = "rowData 'ensembl_gene_id' column missing.")
  expect_true("gene_name" %in% colnames(rowData(se)), info = "rowData 'gene_name' column missing.") # Rmd内で列名変更後
  expect_true("gene_length" %in% colnames(rowData(se)), info = "rowData 'gene_length' column missing.") # Rmd内で列名変更後
  expect_true("gene_biotype" %in% colnames(rowData(se)), info = "rowData 'gene_biotype' column missing.")
  expect_equal(rownames(rowData(se)), c("ENSG000001", "ENSG000002"), info = "rowData rownames mismatch.") # 元の遺伝子ID

  # 4. metadata の確認
  expect_equal(metadata(se)$experiment_id, "test_content", info = "Metadata experiment_id mismatch.")
  expect_true(!is.null(metadata(se)$pipeline_history$create_se), info = "Metadata pipeline_history missing.")
  expect_true(!is.null(metadata(se)$pipeline_history$create_se$timestamp), info = "Metadata timestamp missing.")
  expect_equal(metadata(se)$pipeline_history$create_se$parameters$experiment_id, "test_content", info = "Metadata parameter mismatch.")

})

test_that("サンプル間の発現量分布を比較するdensity plotが正しく作成される (biomaRtモック使用)", {
  # スキップをコメントアウト 
  # skip("時間がかかるので必要時のみ実行")
  
  # テスト用の一時ディレクトリにプロットファイルが保存されるか確認
  plot_dir <- fs::path(test_output_dir, "plots")
  fs::dir_create(plot_dir)
  
  se <- render_with_biomart_mock(
    rmd_file,
    fs::path(test_output_dir, "density_plot_test.html"),
    params = list(
      experiment_id = "test_density_plot",
      counts_file_path = dummy_counts_path,
      metadata_file_path = dummy_metadata_path,
      biomart_dataset = "hsapiens_gene_ensembl",
      biomart_host = "https://ensembl.org",
      biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
      plot_output_dir = plot_dir
    )
  )
  
  # Rmdがレンダリングされたときにplot_expression_density関数が存在するか確認
  # モックを使用してレンダリング環境を作成
  render_env <- new.env(parent = globalenv())
  
  with_biomart_mock({
    rmarkdown::render(
      input = fs::path_abs(rmd_file),
      output_file = fs::path_abs(fs::path(test_output_dir, "density_plot_function_test.html")),
      params = list(
        experiment_id = "test_density_plot_function",
        counts_file_path = dummy_counts_path,
        metadata_file_path = dummy_metadata_path,
        biomart_dataset = "hsapiens_gene_ensembl"
      ),
      envir = render_env,
      quiet = TRUE,
      knit_root_dir = here::here()
    )
  })
  
  # 以下のどちらかの方法で検証
  # 1. 関数が環境内に存在するか確認
  expect_true(exists("plot_expression_density", envir = render_env), 
              info = "plot_expression_density関数が定義されていません")
  
  # 2. SEオブジェクトからプロット作成可能か確認
  # これはSEオブジェクトが正しく作成されていることを前提とする
  expect_s4_class(se, "SummarizedExperiment")
  
  # プロット関数が存在する場合、実行できるはず
  if (exists("plot_expression_density", envir = render_env)) {
    # テスト用にログを無効化して実行
    # ログディレクトリを作成（プロット関数内でflog.infoが使われているため）
    test_log_dir <- fs::path("tests", "logs", "test_density_plot_function")
    fs::dir_create(test_log_dir, recurse = TRUE)
    
    # 元のappenderを保存
    old_appender <- futile.logger::flog.appender()
    
    # テスト中は一時的にログを無効化または別の場所に出力
    futile.logger::flog.appender(futile.logger::appender.console())
    
    # プロット関数のテスト
    tryCatch({
      expect_no_error(render_env$plot_expression_density(se, log_transform = TRUE))
    }, finally = {
      # 元のappenderに戻す
      futile.logger::flog.appender(old_appender)
    })
  }
})

test_that("protein_coding遺伝子のライブラリサイズがbar plotで比較される (biomaRtモック使用)", {
  # スキップをコメントアウト
  # skip("時間がかかるので必要時のみ実行")
  
  # テスト用の一時ディレクトリにプロットファイルが保存されるか確認
  plot_dir <- fs::path(test_output_dir, "plots")
  fs::dir_create(plot_dir)
  
  se <- render_with_biomart_mock(
    rmd_file,
    fs::path(test_output_dir, "protein_coding_barplot_test.html"),
    params = list(
      experiment_id = "test_protein_coding_barplot",
      counts_file_path = dummy_counts_path,
      metadata_file_path = dummy_metadata_path,
      biomart_dataset = "hsapiens_gene_ensembl",
      biomart_host = "https://ensembl.org",
      biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
      plot_output_dir = plot_dir
    )
  )
  
  # レンダリング環境で関数が定義されているか確認
  render_env <- new.env(parent = globalenv())
  
  with_biomart_mock({
    rmarkdown::render(
      input = fs::path_abs(rmd_file),
      output_file = fs::path_abs(fs::path(test_output_dir, "protein_coding_barplot_function_test.html")),
      params = list(
        experiment_id = "test_protein_coding_barplot_function",
        counts_file_path = dummy_counts_path,
        metadata_file_path = dummy_metadata_path,
        biomart_dataset = "hsapiens_gene_ensembl"
      ),
      envir = render_env,
      quiet = TRUE,
      knit_root_dir = here::here()
    )
  })
  
  # 以下のどちらかの方法で検証
  # 1. プロット関数が存在するか確認
  expect_true(exists("plot_protein_coding_library_size", envir = render_env), 
              info = "plot_protein_coding_library_size関数が定義されていません")
  
  # 2. SEオブジェクトからプロット作成可能か確認
  expect_s4_class(se, "SummarizedExperiment")
  
  # プロット関数が存在する場合、実行できるはず
  if (exists("plot_protein_coding_library_size", envir = render_env)) {
    # テスト用にログを無効化して実行
    # ログディレクトリを作成（プロット関数内でflog.infoが使われているため）
    test_log_dir <- fs::path("tests", "logs", "test_protein_coding_barplot_function")
    fs::dir_create(test_log_dir, recurse = TRUE)
    
    # 元のappenderを保存
    old_appender <- futile.logger::flog.appender()
    
    # テスト中は一時的にログを無効化または別の場所に出力
    futile.logger::flog.appender(futile.logger::appender.console())
    
    # プロット関数のテスト
    tryCatch({
      expect_no_error(render_env$plot_protein_coding_library_size(se))
    }, finally = {
      # 元のappenderに戻す
      futile.logger::flog.appender(old_appender)
    })
  }
  
  # 3. ヘルパー関数を使用してprotein_coding遺伝子のライブラリサイズを計算
  library_sizes <- calculate_protein_coding_library_size(se)
  expect_false(is.null(library_sizes))
  expect_equal(length(library_sizes), 2)  # 2サンプル
  expect_equal(sum(library_sizes), 70)  # モックデータでの合計値: 25(sample1) + 45(sample2) = 70
})

test_that("サンプルIDがカウントとメタデータで一致しない場合にエラーを発生させる", {
  # ダミーデータのパス
  dummy_counts_mismatch_path <- here::here("tests", "testdata", "counts_mismatch.csv")
  dummy_metadata_mismatch_path <- here::here("tests", "testdata", "metadata_mismatch.csv")

  # ダミーファイルを作成 (テスト実行前に存在させる)
  # counts_mismatch.csv
  readr::write_csv(
    data.frame(gene_id = c("ENSG000001", "ENSG000002"), sample1 = c(10L, 20L), sample3 = c(30L, 40L)),
    dummy_counts_mismatch_path
  )
  # metadata_mismatch.csv
  readr::write_csv(
    data.frame(sample_id = c("sample1", "sample2"), condition = c("control", "treatment"), extra_col = c("A", "B")),
    dummy_metadata_mismatch_path
  )
  # テスト終了時にダミーファイルを削除
  withr::defer(fs::file_delete(dummy_counts_mismatch_path), envir = parent.frame())
  withr::defer(fs::file_delete(dummy_metadata_mismatch_path), envir = parent.frame())


  expect_error(
    render_with_biomart_mock(
        rmd_file,
        fs::path(test_output_dir, "error_sample_id_mismatch.html"),
        params = list(
            experiment_id = "test_sample_id_mismatch",
            counts_file_path = dummy_counts_mismatch_path, # 不一致データ
            metadata_file_path = dummy_metadata_mismatch_path, # 不一致データ
            biomart_dataset = "hsapiens_gene_ensembl" # biomaRtは使うが、その前のチェックで失敗するはず
        )
    ),
    regexp = "メタデータの並べ替え中に問題が発生しました" # create_se.Rmd L253 のエラーメッセージを期待
  )
})

# biomaRtのモックを使用した簡易テスト
test_that("biomaRtモックが正しく機能する", {
  # モック関数が期待通りの戻り値を返すか確認
  mart <- mock_useMart("ensembl", "hsapiens_gene_ensembl", "https://ensembl.org")
  expect_equal(mart$biomart, "ensembl")
  expect_equal(mart$dataset, "hsapiens_gene_ensembl")
  expect_equal(mart$host, "https://ensembl.org")
  
  # getBMのモックをテスト
  result <- mock_getBM(
    attributes = c("ensembl_gene_id", "external_gene_name"),
    filters = "ensembl_gene_id",
    values = c("ENSG000001", "ENSG000002"),
    mart = mart
  )
  
  expect_equal(nrow(result), 2)
  expect_equal(result$ensembl_gene_id, c("ENSG000001", "ENSG000002"))
  expect_equal(result$gene_biotype, c("protein_coding", "protein_coding"))
  
  # ライブラリサイズ計算テスト用の簡易SEオブジェクト
  se_test <- SummarizedExperiment(
    assays = list(counts = matrix(c(10, 15, 20, 25), nrow = 2, ncol = 2, 
                                 dimnames = list(c("ENSG000001", "ENSG000002"), c("sample1", "sample2")))),
    rowData = DataFrame(
      ensembl_gene_id = c("ENSG000001", "ENSG000002"),
      gene_name = c("GENE1", "GENE2"),
      gene_length = c(1000, 2000),
      gene_biotype = c("protein_coding", "protein_coding")
    )
  )
  
  # ライブラリサイズ計算
  library_sizes <- calculate_protein_coding_library_size(se_test)
  expect_equal(library_sizes, c(sample1 = 25, sample2 = 45))
})

# 注意: biomaRt への接続はネットワーク状況により失敗する可能性があります。
# 上記のモックテストを使用することで、ネットワーク接続がなくてもテストが可能になります。 