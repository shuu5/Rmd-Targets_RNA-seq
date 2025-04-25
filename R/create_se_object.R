#' SummarizedExperiment オブジェクトを作成する
#'
#' カウントデータとサンプルメタデータから SummarizedExperiment オブジェクトを生成します。
#'
#' @param experiment_id character: 解析対象の実験ID。
#' @param data_dir fs::path: データファイルが格納されている親ディレクトリ。
#' @param counts_filename character: カウントデータファイル名。
#' @param metadata_filename character: サンプルメタデータファイル名。
#' @param counts_options list: カウントデータ読み込みオプション。
#' @param metadata_options list: メタデータ読み込みオプション。
#' @param logger_name character: run_with_loggingから渡されるロガー名。
#'
#' @return SummarizedExperiment オブジェクト。
#' @export
#'
#' @import SummarizedExperiment
#' @import S4Vectors
#' @importFrom data.table fread
#' @importFrom fs path_join file_exists path_abs
#' @import futile.logger
#' @import sessioninfo
#'
#' @examples
#' # テストデータ準備
#' temp_dir <- tempdir()
#' data_subdir <- file.path(temp_dir, "example_exp")
#' dir.create(data_subdir)
#' write.csv(data.frame(SampleA=c(1,2), SampleB=c(3,4)), 
#'           file.path(data_subdir, "counts.csv"), row.names=TRUE)
#' write.csv(data.frame(Group=c("A", "B")), 
#'           file.path(data_subdir, "sample_metadata.csv"), row.names=TRUE)
#' 
#' # 関数実行 (現時点ではダミー、実際にはエラーになる)
#' # create_se_object("example_exp", data_dir = temp_dir)
#' 
#' # クリーンアップ
#' unlink(data_subdir, recursive = TRUE)

# ライブラリ読み込み (実行時に必要)
suppressPackageStartupMessages({
  library(SummarizedExperiment)
  library(S4Vectors)
  library(data.table)
  library(fs)
  library(futile.logger)
  library(sessioninfo)
})

# fread 結果から行名を処理するヘルパー関数 (内部使用)
.process_rownames <- function(df_raw, options, type = "data", logger_name = NULL) {
  
  # 入力データフレームの基本的なチェック
  if (!is.data.frame(df_raw) || ncol(df_raw) == 0) {
    msg <- sprintf("%s の読み込みに失敗したか、ファイルが空または形式が正しくありません。", type)
    if (!is.null(logger_name)) flog.error(msg, name = logger_name)
    stop(msg)
  }

  df_processed <- df_raw # 元のデータフレームから開始
  row_names_col_index <- options$row.names
  use_rownames_from_col <- FALSE

  if (!is.null(row_names_col_index) && is.numeric(row_names_col_index) && 
      row_names_col_index >= 1 && row_names_col_index <= ncol(df_raw)) 
  {
    if (row_names_col_index > ncol(df_raw)) {
      msg <- sprintf("指定された row.names 列インデックス (%d) は %s (%d 列) の範囲外です。", 
                     row_names_col_index, type, ncol(df_raw))
      if (!is.null(logger_name)) flog.error(msg, name = logger_name)
      stop(msg)
    }
    
    ids <- df_raw[[row_names_col_index]]
    
    # IDの重複チェック (メタデータでは致命的、カウントデータでは警告)
    if(anyDuplicated(ids)) {
      msg <- sprintf("%s ファイル (列 %d) に重複した ID が見つかりました。", type, row_names_col_index)
      if (type == "metadata") {
        if (!is.null(logger_name)) flog.error(msg, name = logger_name)
        stop(msg)
      } else {
        if (!is.null(logger_name)) flog.warn(msg, name = logger_name)
      }
    }
    
    df_processed <- df_raw[, -row_names_col_index, drop = FALSE]
    tryCatch({
        rownames(df_processed) <- ids
        use_rownames_from_col <- TRUE
      },
      error = function(e) {
        msg <- sprintf("%s の行名の設定に失敗しました: %s", type, e$message)
        if (!is.null(logger_name)) flog.error(msg, name = logger_name)
        stop(msg)
      }
    )
    
  } else {
    msg <- sprintf("%s_options の row.names 設定が正しくないか欠落している可能性があります (%s)。データから行名を設定できません。", 
                   type, options$row.names)
    if (!is.null(logger_name)) flog.warn(msg, name = logger_name)
    # row.names 設定が無効/欠損の場合、df_processed は df_raw のまま保持
  }
  
  # 最終チェック: データフレームであり、メタデータには行名があることを確認
  if (!is.data.frame(df_processed)) {
     msg <- sprintf("%s データが行名処理後に data.frame ではありません。", type)
     if (!is.null(logger_name)) flog.error(msg, name = logger_name)
     stop(paste("内部エラー:", msg))
  }
  # メタデータには行名が必要
  if (type == "metadata" && is.null(rownames(df_processed))) {
      msg <- sprintf("%s のサンプルID (行名) を特定できませんでした。", type)
      if (!is.null(logger_name)) flog.error(msg, name = logger_name)
      stop("メタデータの行名が見つかりません。メタデータファイルとオプションを確認してください。")
  }

  return(df_processed)
}

create_se_object <- function(experiment_id,
                             data_dir = "data",
                             counts_filename = "counts.csv",
                             metadata_filename = "sample_metadata.csv",
                             counts_options = list(header = TRUE, row.names = 1),
                             metadata_options = list(header = TRUE, row.names = 1),
                             logger_name) {

  # 1. ログの開始 - run_with_loggingから提供されたlogger_nameを使用
  flog.info("create_se_object 関数を開始します。", name = logger_name)
  flog.debug("パラメータ: experiment_id='%s', data_dir='%s', counts_filename='%s', metadata_filename='%s'", 
             experiment_id, data_dir, counts_filename, metadata_filename, name = logger_name)
  flog.trace("counts_options: %s", paste(capture.output(dput(counts_options)), collapse="\\n"), name = logger_name)
  flog.trace("metadata_options: %s", paste(capture.output(dput(metadata_options)), collapse="\\n"), name = logger_name)

  # 2. ファイルパス構築
  experiment_path <- fs::path_join(c(data_dir, experiment_id))
  counts_file_path <- fs::path_join(c(experiment_path, counts_filename))
  metadata_file_path <- fs::path_join(c(experiment_path, metadata_filename))
  flog.debug("カウントファイルパス: %s", counts_file_path, name = logger_name)
  flog.debug("メタデータファイルパス: %s", metadata_file_path, name = logger_name)

  # 3. ファイル存在確認
  if (!fs::file_exists(counts_file_path)) {
    flog.error("カウントファイルが見つかりません: %s", counts_file_path, name = logger_name)
    stop("カウントファイルが見つかりません: ", counts_file_path)
  }
  if (!fs::file_exists(metadata_file_path)) {
    flog.error("メタデータファイルが見つかりません: %s", metadata_file_path, name = logger_name)
    stop("メタデータファイルが見つかりません: ", metadata_file_path)
  }

  # 4. カウントデータ読み込み と rowname 処理
  flog.info("カウントデータを読み込みます: %s", counts_file_path, name = logger_name)
  counts_read_options <- counts_options[!names(counts_options) %in% c("row.names")]
  counts_read_options$file <- counts_file_path
  counts_read_options$data.table <- FALSE
  counts_df_raw <- do.call(data.table::fread, counts_read_options)
  
  counts_df <- .process_rownames(counts_df_raw, counts_options, type = "counts", logger_name = logger_name)

  # data.frame を matrix に変換
  count_matrix <- as.matrix(counts_df)
  if (!is.numeric(count_matrix)){
    flog.error("カウントデータに数値以外の値が含まれています。", name = logger_name)
    stop("カウントデータに数値以外の値が含まれています。")
  }
  flog.debug("カウント行列の次元: %d 行, %d 列", nrow(count_matrix), ncol(count_matrix), name = logger_name)

  # 5. メタデータ読み込み と rowname 処理
  flog.info("メタデータを読み込みます: %s", metadata_file_path, name = logger_name)
  metadata_read_options <- metadata_options[!names(metadata_options) %in% c("row.names")]
  metadata_read_options$file <- metadata_file_path
  metadata_read_options$data.table <- FALSE
  metadata_df_raw <- do.call(data.table::fread, metadata_read_options)

  metadata_df <- .process_rownames(metadata_df_raw, metadata_options, type = "metadata", logger_name = logger_name)

  # DataFrame に変換
  metadata_df_s4 <- S4Vectors::DataFrame(metadata_df, row.names = rownames(metadata_df))
  flog.debug("メタデータ DataFrame の次元: %d 行, %d 列", nrow(metadata_df_s4), ncol(metadata_df_s4), name = logger_name)

  # 6. データ整合性チェック (サンプルIDの一致と順序合わせ)
  flog.info("カウントデータとメタデータのサンプルIDの一致を確認します。", name = logger_name)
  count_samples <- colnames(count_matrix)
  metadata_samples <- rownames(metadata_df_s4)

  if (!identical(sort(count_samples), sort(metadata_samples))) {
    flog.error("カウント (%d) とメタデータ (%d) のサンプルIDが一致しません。", 
               length(count_samples), length(metadata_samples), name = logger_name)
    flog.debug("カウントサンプル: %s", paste(count_samples, collapse=", "), name = logger_name)
    flog.debug("メタデータサンプル: %s", paste(metadata_samples, collapse=", "), name = logger_name)
    stop("カウントデータとメタデータのサンプルIDが一致しません。")
  }
  
  # メタデータのサンプル順序をカウントデータに合わせる
  metadata_df_s4 <- metadata_df_s4[count_samples, , drop = FALSE]
  flog.debug("サンプルIDが一致しました。メタデータの順序をカウントデータに合わせます。", name = logger_name)

  # 7. SummarizedExperiment オブジェクト作成
  flog.info("SummarizedExperiment オブジェクトを作成します。", name = logger_name)
  se <- SummarizedExperiment::SummarizedExperiment(
    assays = list(counts = count_matrix),
    colData = metadata_df_s4,
    rowData = S4Vectors::DataFrame(row.names = rownames(count_matrix)) # 処理済み count_matrix の行名を使用
  )

  # 8. メタデータ追加
  flog.info("メタデータを追加します (sessionInfo, input_files, pipeline_history)。", name = logger_name)
  # sessionInfo 取得 (sessioninfo パッケージ推奨)
  S4Vectors::metadata(se)$sessionInfo <- sessioninfo::session_info()
  # 入力ファイルパス (絶対パスで記録)
  S4Vectors::metadata(se)$input_files <- list(
    counts = fs::path_abs(counts_file_path),
    metadata = fs::path_abs(metadata_file_path)
  )
  
  # 9. パイプライン履歴追加 (共通関数を使用)
  se <- add_pipeline_history(
    se = se,
    step_id = NULL, # この関数には入力SEオブジェクトはない
    function_name = "create_se_object",
    parameters = list(
      experiment_id = experiment_id,
      data_dir = data_dir,
      counts_filename = counts_filename,
      metadata_filename = metadata_filename,
      counts_options = counts_options,
      metadata_options = metadata_options
    ),
    details = "CSVからの初期SEオブジェクト作成。",
    logger_name = logger_name
  )

  # 10. ログ終了
  flog.info("SummarizedExperiment オブジェクトが正常に作成されました (%d 行, %d 列)。", 
            nrow(se), ncol(se), name = logger_name)
  flog.info("create_se_object 関数を終了します。", name = logger_name)

  # 11. 戻り値
  return(se)
} 