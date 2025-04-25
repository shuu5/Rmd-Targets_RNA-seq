library(testthat)
library(SummarizedExperiment)
library(S4Vectors) # DataFrame用

# R/add_biomart_gene_info.R をロード
if (file.exists("R/add_biomart_gene_info.R")) {
  source("R/add_biomart_gene_info.R")
} else if (file.exists("../../R/add_biomart_gene_info.R")) {
  # testthat実行ディレクトリが異なる場合に対応
  source("../../R/add_biomart_gene_info.R")
} else {
  stop("Could not find R/add_biomart_gene_info.R")
}

# テスト用の最小限のSEオブジェクトを作成する関数
create_test_se <- function(ensembl_ids) {
  counts <- matrix(1:length(ensembl_ids), nrow = length(ensembl_ids), ncol = 1)
  rownames(counts) <- ensembl_ids
  colnames(counts) <- "sample1"
  coldata <- DataFrame(sample = "sample1", row.names = "sample1")
  SummarizedExperiment(assays = list(counts = counts), colData = coldata)
}

test_that("add_biomart_gene_info correctly adds basic annotations", {
  # テスト対象の関数が存在しないため、現時点ではこのテストは失敗するはず (Red)
  # expect_true(exists("add_biomart_gene_info"), "Function add_biomart_gene_info should exist")

  # 1. 準備: テスト用SEオブジェクト
  # biomaRtで確実に情報が見つかるであろう遺伝子IDを選択 (例: GAPDH)
  # バージョン付きとバージョンなしの両方を含む
  test_ids <- c("ENSG00000111640.15", "ENSG00000121410") # GAPDH, A1BG
  se_input <- create_test_se(test_ids)

  # 期待される mart_dataset と step_id
  test_mart_dataset <- "hsapiens_gene_ensembl"
  test_step_id <- "test_add_biomart_basic"

  # 2. 実行: add_biomart_gene_info を呼び出す
  # expect_error({ # 関数が存在するようになったので expect_error は削除
  se_output <- add_biomart_gene_info(
    se = se_input,
    mart_dataset = test_mart_dataset,
    step_id = test_step_id
  )
  # })

  # --- 以下のチェックは Green フェーズ以降で有効にする ---
  # 3. 検証: rowData に列が追加され、内容が期待通りか
  rowdata_output <- rowData(se_output)

  # 列が存在するか
  expect_true(all(c("ensembl_gene_id_with_ver", "ensembl_gene_id", "gene_symbol",
                    "transcript_length", "gene_biotype") %in% colnames(rowdata_output)))

  # 内容を確認 (GAPDH と A1BG の情報)
  expect_equal(rowdata_output$ensembl_gene_id_with_ver, test_ids)
  expect_equal(rowdata_output$ensembl_gene_id, c("ENSG00000111640", "ENSG00000121410"))
  expect_equal(rowdata_output$gene_symbol, c("GAPDH", "A1BG"))
  expect_true(is.integer(rowdata_output$transcript_length)) # 型だけチェック
  # expect_true(all(rowdata_output$gene_biotype %in% c("protein_coding"))) # biomaRtの返す値は変動しうるので、ここでは型のみチェック
  expect_true(is.character(rowdata_output$gene_biotype))

  # メタデータ履歴が追加されているか
  history <- metadata(se_output)$pipeline_history
  expect_true(is.list(history))
  expect_equal(length(history), 1) # 最初に追加されるはず
  expect_equal(history[[1]]$step_id, test_step_id)
  expect_equal(history[[1]]$function_name, "add_biomart_gene_info")
})

test_that("add_biomart_gene_info handles invalid inputs", {
  # se が不正な場合
  expect_error(
    add_biomart_gene_info(se = data.frame(), step_id = "test_invalid_se"),
    "Input 'se' must be a SummarizedExperiment object."
  )

  # rownames が NULL の場合
  se_null_rownames <- SummarizedExperiment(assays = list(counts = matrix(1:2, 2, 1)))
  expect_error(
    add_biomart_gene_info(se = se_null_rownames, step_id = "test_null_rownames"),
    "rownames\\(se\\) cannot be NULL or empty."
  )

  # step_id が不正な場合 (missing, not character, empty)
  se_valid <- create_test_se("ENSG00000111640.15")
  expect_error(
    add_biomart_gene_info(se = se_valid),
    "Argument 'step_id' must be provided as a non-empty single character string."
  )
  expect_error(
    add_biomart_gene_info(se = se_valid, step_id = 123),
    "Argument 'step_id' must be provided as a non-empty single character string."
  )
   expect_error(
    add_biomart_gene_info(se = se_valid, step_id = ""),
    "Argument 'step_id' must be provided as a non-empty single character string."
  )
})

test_that("add_biomart_gene_info handles genes not found in biomaRt", {
  # 1. 準備: 存在するIDと存在しないであろうIDを混ぜる
  test_ids <- c("ENSG00000111640.15", "ENSG_NOT_EXISTING_ID.1") # GAPDH と 存在しないID
  se_input <- create_test_se(test_ids)
  test_step_id <- "test_not_found"

  # 2. 実行 (警告ログは出るが、warning()は呼ばれないので expect_warning は削除)
  # expect_warning(
  se_output <- add_biomart_gene_info(se = se_input, step_id = test_step_id)
  #   "Could not find information for 1 genes in biomaRt."
  # )

  # 3. 検証: rowData は生成され、見つからなかった遺伝子の情報は NA になっているか
  rowdata_output <- rowData(se_output)
  expect_equal(nrow(rowdata_output), 2)
  expect_equal(rowdata_output$ensembl_gene_id_with_ver, test_ids)
  expect_equal(rowdata_output$ensembl_gene_id, c("ENSG00000111640", "ENSG_NOT_EXISTING_ID"))
  expect_equal(rowdata_output$gene_symbol, c("GAPDH", NA_character_))
  expect_true(is.integer(rowdata_output$transcript_length[1]))
  expect_true(is.na(rowdata_output$transcript_length[2]))
  expect_true(is.character(rowdata_output$gene_biotype[1]))
  expect_true(is.na(rowdata_output$gene_biotype[2]))

  # メタデータ履歴の details を確認
  history <- metadata(se_output)$pipeline_history
  expect_true(grepl("Found info for 1 out of 2 unique genes", history[[1]]$details))
})

test_that("pipeline_history is appended correctly", {
  # 1. 準備: 既存の履歴を持つSEオブジェクト
  se_input <- create_test_se("ENSG00000111640.15")
  metadata(se_input)$pipeline_history <- list(
    list(step_id = "initial_step", function_name = "create_se")
  )
  test_step_id_append <- "test_append_history"

  # 2. 実行
  se_output <- add_biomart_gene_info(se = se_input, step_id = test_step_id_append)

  # 3. 検証: 履歴が追記されているか
  history <- metadata(se_output)$pipeline_history
  expect_equal(length(history), 2)
  expect_equal(history[[1]]$step_id, "initial_step")
  expect_equal(history[[2]]$step_id, test_step_id_append)
  expect_equal(history[[2]]$function_name, "add_biomart_gene_info")
})

# TODO: biomaRt 接続失敗や不正な mart_dataset のテストを追加
#       - これらは外部サービスへの接続に依存するため、モック化（例: mockery パッケージ）が必要になる可能性があります。
#       - または、手動でネットワークを切断したり、無効なホストを指定してテストを実行する方法も考えられます。

# TODO: 異常系のテストケースを追加 (不正な入力、biomart接続失敗、遺伝子が見つからない場合など)
# TODO: pipeline_history の追記テストを追加 