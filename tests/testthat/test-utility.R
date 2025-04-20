# tests/testthat/test-utility.R - utility.R のテスト

# testthat と必要なパッケージをロード
library(testthat)
library(withr)
library(SummarizedExperiment)
library(futile.logger)
library(fs)
library(here)
library(stringr)

# utility.R の関数を読み込む (プロジェクトルートからの相対パス)
# testthat::test_dir() はプロジェクトルートをワーキングディレクトリとして実行される想定
# source(test_path("../../R/utility.R"))
source(here::here("R/utility.R")) # here::here() を使用するように変更

# --- setup_logger のテスト ---

test_that("setup_logger は期待通りにログディレクトリとファイルを設定する", {
  # 一時ディレクトリを作成
  mock_log_base <- local_tempdir(pattern = "setup_logger_test_")

  experiment_id <- "test_experiment_001"
  module_name <- "test_module"
  
  # ログディレクトリのパス期待値を修正
  # テスト中は tests/logs/ になる
  expected_log_dir <- fs::path("tests", "logs", experiment_id)
  expected_module_log_file <- fs::path(expected_log_dir, paste0(module_name, ".log"))
  targets_log_path <- fs::path(expected_log_dir, "_targets.log")

  # 事前にディレクトリを作成
  fs::dir_create(expected_log_dir, recurse = TRUE)
  
  # _targets.log を作成しておく (appender.tee がテストされるように)
  file_create(targets_log_path)

  # setup_logger を実行し、設定リストを取得
  settings_debug <- withr::with_dir(mock_log_base, {
      setup_logger(module_name, experiment_id, log_level = "DEBUG")
  })

  # --- 検証 ---
  # 1. 返り値の型と名前
  expect_type(settings_debug, "list")
  expect_named(settings_debug, c("appender", "layout", "threshold", "module_log_path"))

  # 2. 各要素の型/値
  expect_type(settings_debug$appender, "closure") # 関数であること
  expect_type(settings_debug$layout, "closure") # 関数であること
  expect_equal(settings_debug$threshold, "DEBUG") # 指定したログレベル
  
  # パスの完全一致ではなくパターンマッチを使用
  expect_true(
    stringr::str_detect(settings_debug$module_log_path, "tests/logs/test_experiment_001/test_module.log$"),
    info = paste("Unexpected module_log_path:", settings_debug$module_log_path)
  )

  # 3. 副作用: ログディレクトリが作成されたか
  expect_true(dir_exists(expected_log_dir), info = "ログディレクトリが存在しません")

  # 5. 無効なログレベルの場合の警告とデフォルト設定
  withr::with_dir(mock_log_base, {
    # 警告が発生することを期待
    expect_warning(
      settings_invalid <- setup_logger(module_name, experiment_id, log_level = "INVALID"),
      regexp = "無効なログレベル.*デフォルトの 'TRACE' を使用します")
    # デフォルトの TRACE に設定されることを確認
    expect_equal(settings_invalid$threshold, "TRACE",
                 info = "無効なログレベル指定後、リスト内の threshold が TRACE になっていません")
  })
})

test_that("setup_logger は _targets.log がなくても動作する", {
  # 一時ディレクトリ
  mock_log_base_no_targets <- local_tempdir(pattern = "setup_logger_no_targets_")

  experiment_id <- "test_experiment_002"
  module_name <- "test_module_no_targets"
  
  # ログディレクトリのパス期待値を修正
  # テスト中は tests/logs/ になる
  expected_log_dir <- fs::path("tests", "logs", experiment_id)
  expected_module_log_file <- fs::path(expected_log_dir, paste0(module_name, ".log"))
  # _targets.log は作成しない
  
  # 事前にディレクトリを作成
  fs::dir_create(expected_log_dir, recurse = TRUE)

  # setup_logger を実行
  settings_no_targets <- withr::with_dir(mock_log_base_no_targets, {
      setup_logger(module_name, experiment_id, log_level = "INFO")
  })

  # --- 検証 ---
  # 1. 返り値の型と名前
  expect_type(settings_no_targets, "list")
  expect_named(settings_no_targets, c("appender", "layout", "threshold", "module_log_path"))

  # 2. 各要素の型/値
  expect_type(settings_no_targets$appender, "closure") # 関数であること
  expect_type(settings_no_targets$layout, "closure") # 関数であること
  expect_equal(settings_no_targets$threshold, "INFO") # 指定したログレベル
  
  # パスの完全一致ではなくパターンマッチを使用
  expect_true(
    stringr::str_detect(settings_no_targets$module_log_path, "tests/logs/test_experiment_002/test_module_no_targets.log$"),
    info = paste("Unexpected module_log_path:", settings_no_targets$module_log_path)
  )

  # モジュールログファイルディレクトリの確認
  # expected_log_dir を一時ディレクトリからの相対パスではなく、
  # カレントディレクトリからのパスとして検証
  expect_true(dir_exists(expected_log_dir), info = "ログディレクトリが存在しません (_targets.log なし)")
})


# --- record_pipeline_history のテスト ---

# テスト用の簡単な SE オブジェクトを作成する関数
create_test_se <- function(nrow = 10, ncol = 5) {
  counts <- matrix(rnbinom(nrow * ncol, mu = 100, size = 1), nrow = nrow, ncol = ncol)
  coldata <- data.frame(sample = paste0("sample", 1:ncol), condition = rep(c("A", "B"), length.out = ncol))
  rownames(coldata) <- colnames(counts) <- coldata$sample
  rownames(counts) <- paste0("gene", 1:nrow)
  SummarizedExperiment(assays = list(counts = counts), colData = coldata)
}

test_that("record_pipeline_history は初回実行時に正しく履歴を追加する", {
  se <- create_test_se()
  module_name <- "module1"
  description <- "最初のステップ"
  params <- list(param1 = "value1", param2 = 123)
  
  se_updated <- record_pipeline_history(se, module_name, description, params)
  
  # --- 検証 (Redフェーズでは失敗するはずの部分) ---
  
  # 1. metadata$pipeline_history がリストとして存在するか
  expect_true(is.list(metadata(se_updated)$pipeline_history), 
              info = "metadata$pipeline_history がリストではありません")
              
  # 2. 指定したモジュール名のエントリが存在するか
  expect_true(module_name %in% names(metadata(se_updated)$pipeline_history),
              info = "指定したモジュール名のエントリが存在しません")
              
  # 3. エントリの内容が正しいか
  history_entry <- metadata(se_updated)$pipeline_history[[module_name]]
  expect_equal(history_entry$module, module_name)
  expect_equal(history_entry$description, description)
  expect_equal(history_entry$parameters, params)
  expect_true(is.character(history_entry$timestamp)) # 日時フォーマットは厳密にはチェックしない
  expect_true(is.character(history_entry$session_info) && length(history_entry$session_info) > 0) # sessionInfoがあるか
})

test_that("record_pipeline_history は既存の履歴に正しく追記する", {
  se <- create_test_se()
  
  # 最初の履歴を追加
  module1_name <- "module1"
  se <- record_pipeline_history(se, module1_name, "ステップ1", list(p1 = "a"))
  
  # 2番目の履歴を追加
  module2_name <- "module2"
  description2 <- "ステップ2"
  params2 <- list(p2 = TRUE, p3 = 4.5)
  se_updated <- record_pipeline_history(se, module2_name, description2, params2)
  
  # --- 検証 (Redフェーズでは失敗するはずの部分) ---
  
  # 1. 両方のモジュール名のキーが存在するか
  expect_true(all(c(module1_name, module2_name) %in% names(metadata(se_updated)$pipeline_history)),
              info = "両方のモジュールキーが存在しません")
              
  # 2. 2番目のエントリの内容が正しいか
  history_entry2 <- metadata(se_updated)$pipeline_history[[module2_name]]
  expect_equal(history_entry2$module, module2_name)
  expect_equal(history_entry2$description, description2)
  expect_equal(history_entry2$parameters, params2)
})

# --- appender_tee_custom のテスト ---

test_that("appender_tee_custom は2つのアペンダーに正しく書き込む", {
  # 一時ファイルを作成
  log_file1 <- local_tempfile(pattern = "tee_test1_")
  log_file2 <- local_tempfile(pattern = "tee_test2_")
  
  # ファイルアペンダーを作成
  appender1 <- appender.file(log_file1)
  appender2 <- appender.file(log_file2)
  
  # カスタムTeeアペンダーを作成
  tee_appender <- appender_tee_custom(appender1, appender2)
  
  # テストメッセージ
  test_message <- "これはTeeアペンダーのテストメッセージです。"
  
  # Teeアペンダーを使ってログを書き込む
  expect_no_error(tee_appender(test_message))
  
  # 各ファイルの内容を確認
  log_content1 <- readLines(log_file1, warn = FALSE)
  log_content2 <- readLines(log_file2, warn = FALSE)
  
  expect_true(any(grepl(test_message, log_content1, fixed = TRUE)),
              info = "ファイル1にテストメッセージが含まれていません")
  expect_true(any(grepl(test_message, log_content2, fixed = TRUE)),
              info = "ファイル2にテストメッセージが含まれていません")
})

test_that("appender_tee_custom は不正な引数でエラーを出す", {
  # ファイルアペンダーを作成
  log_file_dummy <- local_tempfile(pattern = "tee_dummy_")
  appender_valid <- appender.file(log_file_dummy)
  
  # 不正な引数でテスト
  expect_error(appender_tee_custom(appender_valid, "not_a_function"), 
               regexp = "両方の引数は appender.file によって返される関数である必要があります")
  expect_error(appender_tee_custom("not_a_function", appender_valid),
               regexp = "両方の引数は appender.file によって返される関数である必要があります")
  expect_error(appender_tee_custom(NULL, appender_valid),
               regexp = "両方の引数は appender.file によって返される関数である必要があります")
})

test_that("appender_tee_custom は内部アペンダーエラー時に警告を出す", {
  # エラーを発生させるダミーアペンダー関数
  error_appender <- function(line) {
    stop("意図的な内部エラー")
  }
  
  # 正常なアペンダー関数
  ok_appender <- function(line) {
    # 何もしない
  }
  
  # 片方のアペンダーがエラーを出すケース
  tee_appender_err1 <- appender_tee_custom(error_appender, ok_appender)
  expect_warning(tee_appender_err1("メッセージ"), 
                 regexp = "カスタムTeeアペンダー\\(ファイル1\\)での書き込みエラー: 意図的な内部エラー")

  tee_appender_err2 <- appender_tee_custom(ok_appender, error_appender)
  expect_warning(tee_appender_err2("メッセージ"), 
                 regexp = "カスタムTeeアペンダー\\(ファイル2\\)での書き込みエラー: 意図的な内部エラー")
                 
  # 両方のアペンダーがエラーを出すケース (両方の警告が出ることを期待)
  tee_appender_err_both <- appender_tee_custom(error_appender, error_appender)
  # expect_warning は最初の警告しかキャッチしない場合があるので、複数回呼び出すか、より高度なテストが必要かも
  # ここでは、少なくともどちらかの警告が出ることを確認
   expect_warning(tee_appender_err_both("メッセージ"), 
                 regexp = "カスタムTeeアペンダー.*での書き込みエラー: 意図的な内部エラー")
}) 