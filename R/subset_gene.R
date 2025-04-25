#' SummarizedExperiment オブジェクトの遺伝子をフィルタリングする
#'
#' @param se SummarizedExperiment オブジェクト。
#' @param filter_conditions rowData 列に対するフィルタリング条件のリスト。
#'                          各要素は dplyr::filter スタイルの条件式（文字列）。
#'                          例: list("gene_biotype == 'protein_coding'", "mean_expression > 10")
#' @param logger_name ログ出力に使用するロガー名。
#'
#' @return フィルタリングされた SummarizedExperiment オブジェクト。
#' @export
#' @importFrom SummarizedExperiment SummarizedExperiment rowData rowData<- assays colData metadata metadata<-
#' @importFrom dplyr filter pull
#' @importFrom rlang parse_exprs eval_tidy
#' @importFrom futile.logger flog.info flog.debug flog.warn flog.error
#' @importFrom methods is
subset_gene <- function(se, filter_conditions, logger_name) {

  # 入力検証
  stopifnot(
    "se must be a SummarizedExperiment object" = is(se, "SummarizedExperiment"),
    "filter_conditions must be a list" = is.list(filter_conditions),
    "filter_conditions must contain characters" = all(sapply(filter_conditions, is.character)),
    "logger_name must be a character" = is.character(logger_name) && length(logger_name) == 1
  )

  flog.info("[%s] subset_gene: 関数開始", logger_name)
  flog.info("[%s] 入力SEの次元: %d 行 x %d 列", logger_name, nrow(se), ncol(se))
  flog.info("[%s] 適用するフィルター条件: %s", logger_name, paste(filter_conditions, collapse = " AND "))

  # rowData を取得
  rd <- as.data.frame(rowData(se))
  initial_rows <- nrow(rd)
  flog.debug("[%s] rowData を取得しました (%d 行)", logger_name, initial_rows)

  # フィルター条件を適用
  filtered_rd <- tryCatch({
    # 文字列の条件式をrlangの式に変換
    filter_exprs <- rlang::parse_exprs(unlist(filter_conditions))
    # dplyr::filter を使用してフィルタリング
    # 注意: ここでは環境を明示的に渡さないが、rowData の列を参照できる
    dplyr::filter(rd, !!!filter_exprs)
  }, error = function(e) {
    flog.error("[%s] フィルタリング中にエラーが発生しました: %s", logger_name, e$message)
    stop("フィルタリングエラー: ", e$message)
  })

  filtered_rows <- nrow(filtered_rd)
  flog.debug("[%s] フィルタリング後の rowData: %d 行", logger_name, filtered_rows)

  # フィルタリングされた遺伝子のインデックスを取得
  # rowDataの行名が元のSEの行名と一致することを想定
  if (!identical(rownames(rd), rownames(se))) {
      flog.warn("[%s] rowDataの行名が元のSEの行名と一致しません。フィルタリングが正しく行われない可能性があります。", logger_name)
  }
  filtered_indices <- rownames(filtered_rd)

  # 元のSEオブジェクトをサブセット化
  result_se <- se[filtered_indices, ]

  flog.info("[%s] フィルタリング後のSEの次元: %d 行 x %d 列", logger_name, nrow(result_se), ncol(result_se))

  # メタデータに履歴を追加
  input_dims <- list(rows = initial_rows, cols = ncol(se))
  output_dims <- list(rows = filtered_rows, cols = ncol(result_se))
  history_details <- sprintf("Filtered %d genes down to %d based on: %s",
                           initial_rows, filtered_rows, paste(filter_conditions, collapse = " AND "))

  # utility.R の add_pipeline_history を使用 (存在を仮定)
  # step_id は呼び出し元 (例: targets) から渡される想定だが、ここでは logger_name を使う
  if (exists("add_pipeline_history") && is.function(add_pipeline_history)){
      result_se <- add_pipeline_history(
          se = result_se,
          step_id = logger_name, # テスト時は仮の値
          function_name = "subset_gene",
          parameters = list(filter_conditions = filter_conditions),
          input_dimensions = input_dims,
          output_dimensions = output_dims,
          details = history_details,
          logger_name = logger_name # add_pipeline_history にもロガー名を渡す場合
      )
  } else {
      flog.warn("[%s] add_pipeline_history 関数が見つかりません。メタデータ履歴は追加されません。", logger_name)
  }


  flog.info("[%s] subset_gene: 関数終了", logger_name)
  return(result_se)
} 