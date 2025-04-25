# R/utility.R または R/logging_utils.R に追加

#' 関数実行前に専用のログファイルを設定し、関数を実行するラッパー
#'
#' @param func 実行する関数オブジェクト
#' @param ... func に渡す引数
#' @param target_name targetsでのターゲット名（ログファイル名に使用）
#' @param exp_id 実験ID
#' @param log_level 個別ログファイルのログレベル (例: futile.logger::TRACE)
#'
#' @return func の実行結果
run_with_logging <- function(func, ..., target_name, exp_id, log_level = futile.logger::TRACE) {
  # ロガー名とログファイルパスをターゲット名から生成
  # "obj_" や "file_" プレフィックスを除去して関数名に近いものにする
  clean_target_name <- sub("^(obj|file)_", "", target_name)
  logger_name <- paste0("log_", clean_target_name)
  log_dir_func <- fs::path("logs", exp_id)
  fs::dir_create(log_dir_func)
  log_file_func <- fs::path(log_dir_func, paste0(clean_target_name, ".log"))

  # ログファイルを初期化（既存のファイルは上書き）
  if (fs::file_exists(log_file_func)) {
    fs::file_delete(log_file_func)
  }
  
  # 個別ログ用ファイルアペンダを設定
  # 既存のアペンダを一度削除するには flog.remove.appender が必要だが、
  # 初回実行時には存在しないため、try でエラーを無視
  try(futile.logger::flog.remove.appender(logger_name), silent = TRUE)
  
  # 個別ログ用ファイルアペンダを設定
  futile.logger::flog.appender(futile.logger::appender.file(log_file_func), name = logger_name)
  # 個別ログの閾値を設定
  futile.logger::flog.threshold(log_level, name = logger_name)

  # デフォルトロガー (_targets.log やコンソール) にも INFO レベルで開始/終了を出力
  futile.logger::flog.info("Starting target '%s' (logging to %s)", target_name, log_file_func)
  # 個別ログファイルに詳細な開始ログを出力
  futile.logger::flog.trace("--- Starting target: %s ---", target_name, name = logger_name)
  # 引数をログに出力（logger_nameを除く）
  original_args <- list(...)
  futile.logger::flog.debug("Arguments: %s", paste(names(original_args), unlist(original_args), sep = "=", collapse = ", "), name = logger_name)

  # 本来の関数を実行。logger_name を引数に追加して渡す。
  result <- tryCatch({
    # 引数リストを作成し、logger_name を追加
    args_to_pass <- c(list(...), list(logger_name = logger_name))
    # do.call を使って関数を呼び出す
    do.call(func, args_to_pass)
  }, error = function(e) {
    futile.logger::flog.fatal("Error in target '%s': %s", target_name, conditionMessage(e), name = logger_name)
    futile.logger::flog.error("Target '%s' failed with error.", target_name) # デフォルトロガーにも記録
    stop(e) # エラーを再度発生させてtargetsに失敗を伝える
  })

  # 終了ログ
  futile.logger::flog.trace("--- Finished target: %s ---", target_name, name = logger_name)
  futile.logger::flog.info("Finished target '%s'", target_name)

  # アペンダを削除 (次のターゲットに影響を与えないように)
  # futile.logger::flog.remove.appender(logger_name)
  # remove しない方が、後でログレベルを変更するなどの操作はしやすいかもしれない。
  # targets は各ターゲットを別プロセスで実行することがあるため、影響は限定的か。

  return(result)
}

#' Rmdファイル用のロギング設定を行う
#'
#' Rmdファイルのセットアップチャンクで呼び出す共通ロギング設定関数。
#' Rmdファイル名から個別ログファイルパスを生成し、TRACEレベルでログを記録する。
#'
#' @param experiment_id 実験ID
#' @param rmd_path knitr::current_input()で取得したRmdファイルパス
#'
#' @return logger_name - ロガー名 (後続チャンクでログ出力する際に使用)
#' @export
setup_rmd_logging <- function(experiment_id, rmd_path = knitr::current_input()) {
  # ファイル名から拡張子を除いた部分をログ名に使用
  rmd_basename <- tools::file_path_sans_ext(basename(rmd_path))
  logger_name_rmd <- paste0("rmd_", rmd_basename)
  
  # ログディレクトリとファイルパスを設定
  log_dir_rmd <- fs::path("logs", experiment_id)
  fs::dir_create(log_dir_rmd)
  log_file_rmd <- fs::path(log_dir_rmd, paste0(rmd_basename, ".log"))
  
  # 既存のログファイルを削除（新規作成）
  if (fs::file_exists(log_file_rmd)) fs::file_delete(log_file_rmd)
  
  # 既存のアペンダがあれば削除（再実行時にクリアするため）
  try(futile.logger::flog.remove.appender(logger_name_rmd), silent = TRUE)
  
  # 個別ログ用ファイルアペンダを設定
  futile.logger::flog.appender(futile.logger::appender.file(log_file_rmd), name = logger_name_rmd)
  # 個別ログの閾値をTRACEに設定
  futile.logger::flog.threshold(futile.logger::TRACE, name = logger_name_rmd)
  
  # デフォルトロガー (_targets.log やコンソール) にもINFOレベルで開始を出力
  futile.logger::flog.info("Starting Rmd: %s (Log file: %s)", rmd_basename, log_file_rmd)
  # 個別ログファイルに詳細な開始ログを出力
  futile.logger::flog.info("--- Starting Rmd: %s ---", rmd_basename, name = logger_name_rmd)
  futile.logger::flog.debug("experiment_id: %s", experiment_id, name = logger_name_rmd)
  
  # レンダリングでのデフォルトログレベルをINFOに設定
  # HTML/コンソールにはINFO以上のみが出力され、TRACEはログファイルのみに記録される
  futile.logger::flog.threshold(futile.logger::INFO)
  
  # ロガー名を返す（後続チャンクで使用するため）
  return(logger_name_rmd)
}

#' SEオブジェクトのメタデータにパイプライン履歴を追加する (ダミー関数修正)
#'
#' @param se SummarizedExperiment オブジェクト
#' @param step_id ターゲット名など、ステップを識別するID
#' @param function_name 実行された関数名
#' @param parameters 使用された主要パラメータのリスト
#' @param details その他の詳細情報
#' @param input_dimensions 入力SEの次元 (リスト: list(rows=..., cols=...))
#' @param output_dimensions 出力SEの次元 (リスト: list(rows=..., cols=...))
#' @param logger_name ロガー名 (オプション)
#' @param ... その他の引数 (将来の拡張用)
#' @return 更新された SummarizedExperiment オブジェクト
add_pipeline_history <- function(se, step_id, function_name, parameters, details,
                                 input_dimensions = NULL, output_dimensions = NULL,
                                 logger_name = NULL, ...) {
  # ダミー実装: リストを追加
  if (!is.list(metadata(se))) metadata(se) <- list()
  if (is.null(metadata(se)$pipeline_history)) {
    metadata(se)$pipeline_history <- list()
  }
  history_entry <- list(
    step_id = step_id,
    function_name = function_name,
    timestamp = Sys.time(),
    parameters = parameters,
    input_dimensions = input_dimensions,
    output_dimensions = output_dimensions,
    details = details
    # ... 引数をここに追加することも可能
  )
  metadata(se)$pipeline_history <- c(metadata(se)$pipeline_history, list(history_entry))

  if (!is.null(logger_name)) {
      futile.logger::flog.debug("[%s] Pipeline history added for %s", logger_name, function_name)
  }
  return(se)
}

