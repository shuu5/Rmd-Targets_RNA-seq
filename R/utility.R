# utility.R - RNA-seq パイプラインのための共通ユーティリティ関数

#' 2つのファイルアペンダーに書き込むカスタムアペンダー関数
#' 
#' futile.logger はデフォルトで複数のファイルアペンダーを直接サポートしないため、
#' この関数はメッセージを受け取り、指定された2つのファイルアペンダーに書き込みます。
#' 
#' @param file1_appender 1つ目の appender.file() で作成されたアペンダー関数
#' @param file2_appender 2つ目の appender.file() で作成されたアペンダー関数
#' @return futile.logger が期待するアペンダー関数
appender_tee_custom <- function(file1_appender, file2_appender) {
  if (!is.function(file1_appender) || !is.function(file2_appender)) {
    stop("両方の引数は appender.file によって返される関数である必要があります")
  }
  function(line) {
    # 各アペンダー関数を実行してファイルに書き込む
    tryCatch(file1_appender(line), error = function(e) {
      warning(sprintf("カスタムTeeアペンダー(ファイル1)での書き込みエラー: %s", e$message))
    })
    tryCatch(file2_appender(line), error = function(e) {
      warning(sprintf("カスタムTeeアペンダー(ファイル2)での書き込みエラー: %s", e$message))
    })
  }
}

#' ロガーを設定する関数
#'
#' 指定されたモジュール名のログファイルと_targets.logの両方にログを出力するように設定します。
#' モジュール名はログメッセージの一部として含まれ、ソースを識別しやすくします。
#'
#' @param experiment_id 実験ID (例: "250418_RNA-seq")
#' @param module_name モジュール名 (例: "create_se")
#' @param log_level ログレベル (デフォルト: "TRACE")
#' @return ロガー設定（アペンダー、レイアウト、閾値）を含むリスト
#' @examples
#' logger_settings <- setup_logger(params$experiment_id, "create_se")
#' futile.logger::flog.appender(logger_settings$appender)
#' futile.logger::flog.layout(logger_settings$layout)
#' futile.logger::flog.threshold(logger_settings$threshold)
#' futile.logger::flog.info("ロガー設定適用完了")
setup_logger <- function(experiment_id, module_name, log_level = "TRACE") {
  # library(futile.logger) # 関数内でロードする必要はなくなる
  library(fs)
  library(here)

  # ログディレクトリを確認・作成
  # すべてのケースで logs/{experiment_id} に出力する
  log_dir <- fs::path("logs", experiment_id)
  
  if (!fs::dir_exists(log_dir)) {
    fs::dir_create(log_dir, recurse = TRUE)
  }

  # ログファイルパスを設定
  module_log_file <- fs::path(log_dir, paste0(module_name, ".log"))
  targets_log_file <- fs::path(log_dir, "_targets.log")

  # モジュール固有のログは上書きモードで（既存ファイルを削除）
  if (fs::file_exists(module_log_file)) {
    fs::file_delete(module_log_file)
  }
  
  # モジュール固有のログファイルへのアペンダー（上書きモード）
  appender_module <- appender.file(module_log_file)

  # _targets.log へのアペンダー（追記モード）- _targets.Rで初期化される前提
  appender_targets <- if (fs::file_exists(targets_log_file)) {
    # 追記モードのアペンダー
    function(line) {
      cat(line, file = targets_log_file, append = TRUE)
    }
  } else {
    # ファイルが存在しない場合はディレクトリを作成して新規作成
    if (!fs::dir_exists(fs::path_dir(targets_log_file))) {
      fs::dir_create(fs::path_dir(targets_log_file), recurse = TRUE)
    }
    function(line) {
      cat(line, file = targets_log_file, append = FALSE)
    }
  }

  # アペンダーを設定 (関数を返す)
  # カスタムTeeアペンダーを使用して両方のファイルに書き込む
  final_appender <- appender_tee_custom(appender_module, appender_targets)

  # レイアウト関数を定義（layout.format の代わりに直接関数を定義）
  final_layout <- function(level, msg, ...) {
    # level: ログレベル（INFO, ERROR など）
    # msg: ログメッセージ
    # ...: その他のパラメータ
    
    # メッセージ内の書式指定子を処理
    if (length(list(...)) > 0) {
      # flog.debug などに渡された追加パラメータがある場合、それらを使ってフォーマット
      msg <- do.call(sprintf, c(list(msg), list(...)))
    }
    
    # 最終的なログメッセージ形式を作成
    formatted_msg <- sprintf("[%s] [%s] [%s] %s\n", 
                            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                            level,
                            module_name,
                            msg)
    return(formatted_msg)
  }

  # ログレベル (文字列を返す)
  log_level_upper <- toupper(log_level)
  valid_levels <- c("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL")
  if (!(log_level_upper %in% valid_levels)) {
    warning(sprintf("無効なログレベル '%s' が指定されました。デフォルトの 'TRACE' を使用します。", log_level))
    log_level_upper <- "TRACE"
  }

  # 設定をリストで返す
  return(
    list(
      appender = final_appender,
      layout = final_layout,
      threshold = log_level_upper,
      module_log_path = module_log_file # 呼び出し元で参照できるようにパスも返す
    )
  )
}

#' SummarizedExperiment オブジェクトのパイプライン履歴にモジュール実行情報を記録
#'
#' @param se SummarizedExperiment オブジェクト
#' @param module_name モジュール名
#' @param description モジュールの説明
#' @param parameters パラメータのリスト
#' @return 更新された SummarizedExperiment オブジェクト
#' @examples
#' se <- record_pipeline_history(se, "create_se", "SEオブジェクト作成", params)
record_pipeline_history <- function(se, module_name, description, parameters) {
  # パイプライン履歴リストが存在しない場合は初期化
  if (is.null(metadata(se)$pipeline_history)) {
    metadata(se)$pipeline_history <- list()
  }
  
  # モジュール実行情報を記録
  metadata(se)$pipeline_history[[module_name]] <- list(
    module = module_name,
    timestamp = format(Sys.time(), '%Y-%m-%d %H:%M:%S'),
    description = description,
    parameters = parameters,
    session_info = capture.output(sessionInfo())
  )
  
  return(se)
} 