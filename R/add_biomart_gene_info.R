#' add_biomart_gene_info
#'
#' @description SummarizedExperiment オブジェクトの rowData に biomaRt を使用して遺伝子アノテーションを追加する。
#' ロギングは呼び出し元のラッパー (例: run_with_logging) によって設定されることを想定。
#' 仕様書: specs/R/spec_add_biomart_gene_info.md
#'
#' @param se SummarizedExperiment オブジェクト。rownames は Ensembl ID (バージョン付き可)。
#' @param mart_dataset biomaRt で使用するデータセット名。デフォルトは "hsapiens_gene_ensembl"。
#' @param biomart_host biomaRt のホスト URL。デフォルトは "https://ensembl.org"。
#' @param step_id pipeline_history に記録するステップ識別子。
#' @param experiment_id 解析対象の実験ID。
#' @param logger_name run_with_logging から渡される、この関数専用のロガー名。
#'
#' @return rowData にアノテーションが追加された SummarizedExperiment オブジェクト。
#' @export
#'
#' @import SummarizedExperiment
#' @import biomaRt
#' @import dplyr
#' @import stringr
#' @import S4Vectors
#' @import futile.logger
#' @importFrom methods is
#' @importFrom fs path file_exists dir_create
add_biomart_gene_info <- function(se,
                                  mart_dataset = "hsapiens_gene_ensembl",
                                  biomart_host = "https://ensembl.org",
                                  step_id,
                                  experiment_id,
                                  logger_name) {

  # --- 引数チェックを先に行う (experiment_id もチェック) ---
  if (missing(step_id) || !is.character(step_id) || length(step_id) != 1 || nchar(step_id) == 0) {
    stop("引数 'step_id' は空でない単一の文字列として提供する必要があります。")
  }
  if (missing(experiment_id) || !is.character(experiment_id) || length(experiment_id) != 1 || nchar(experiment_id) == 0) {
    stop("引数 'experiment_id' は空でない単一の文字列として提供する必要があります。")
  }

  flog.info("[%s] 開始: biomaRt 遺伝子情報の追加", step_id, name = logger_name)
  flog.debug("[%s] パラメータ: mart_dataset='%s', biomart_host='%s', experiment_id='%s'",
             step_id, mart_dataset, biomart_host, experiment_id, name = logger_name)

  # 依存パッケージの読み込み (エラーメッセージ抑制)
  suppressPackageStartupMessages({
    # library(SummarizedExperiment) # 呼び出し元でロード済み想定
    # library(biomaRt) # 呼び出し元でロード済み想定
    library(dplyr)
    library(stringr)
    # library(S4Vectors) # 呼び出し元でロード済み想定
    library(futile.logger)
    library(methods)
    library(fs) # fs::path などで使用
  })

  # --- 入力検証 ---
  flog.debug("[%s] 入力引数の検証中", step_id, name = logger_name)
  if (!is(se, "SummarizedExperiment")) {
    flog.error("[%s] 入力 'se' は SummarizedExperiment オブジェクトである必要があります。", step_id, name = logger_name)
    stop("入力 'se' は SummarizedExperiment オブジェクトである必要があります。")
  }
  if (is.null(rownames(se)) || length(rownames(se)) == 0) {
    flog.error("[%s] rownames(se) は NULL または空であってはなりません。", step_id, name = logger_name)
    stop("rownames(se) は NULL または空であってはなりません。")
  }
  input_dims <- dim(se)
  flog.debug("[%s] 入力 SE の次元: %d 行, %d 列", step_id, input_dims[1], input_dims[2], name = logger_name)

  # --- rowData 準備 ---
  flog.debug("[%s] アノテーション用の rowData を準備中", step_id, name = logger_name)
  rdat <- rowData(se)
  if (!is(rdat, "DataFrame")) {
      flog.debug("[%s] rowData を DataFrame として初期化", step_id, name = logger_name)
      rdat <- DataFrame(row.names = rownames(se))
  }
  rdat$ensembl_gene_id_with_ver <- rownames(se)
  rdat$ensembl_gene_id <- stringr::str_remove(rdat$ensembl_gene_id_with_ver, ".[0-9]+$")
  flog.info("[%s] biomaRt クエリ用に %d 個の遺伝子IDを準備しました。", step_id, length(unique(rdat$ensembl_gene_id)), name = logger_name)

  # --- biomaRt 接続とクエリ ---
  gene_info <- data.frame() # 初期化
  mart <- NULL
  tryCatch({
    flog.info("[%s] biomaRt に接続中。 データセット: %s, ホスト: %s", step_id, mart_dataset, biomart_host, name = logger_name)
    mart <- biomaRt::useMart(
      biomart = "ensembl",
      dataset = mart_dataset,
      host = biomart_host
    )
    flog.info("[%s] biomaRt への接続に成功しました。", step_id, name = logger_name)

    unique_ensembl_ids <- unique(rdat$ensembl_gene_id)
    flog.debug("[%s] %d 個の一意な Ensembl ID に対して biomaRt クエリを実行中", step_id, length(unique_ensembl_ids), name = logger_name)
    # トレースログでIDの一部を表示（多すぎる場合は制限）
    display_ids <- head(unique_ensembl_ids, 10)
    flog.trace("[%s] クエリ対象ID (最初の %d 個): %s", step_id, length(display_ids), paste(display_ids, collapse=", "), name = logger_name)

    gene_info_raw <- biomaRt::getBM(
      attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype"),
      filters = "ensembl_gene_id",
      values = unique_ensembl_ids,
      mart = mart,
      useCache = FALSE # キャッシュを使わない（再現性のため、または最新情報を取得するため）
    )
    flog.info("[%s] biomaRt から %d 件の生エントリを取得しました。", step_id, nrow(gene_info_raw), name = logger_name)

    # 重複を除去 (ensembl_gene_id ごとに最初のエントリを採用)
    # dplyr::distinct の前に ungroup() は不要のはずだが念のため
    gene_info <- dplyr::distinct(gene_info_raw, ensembl_gene_id, .keep_all = TRUE)
    flog.info("[%s] 重複を除去した後、%d 個の一意な遺伝子の情報を使用します。", step_id, nrow(gene_info), name = logger_name)

    # 列名を仕様に合わせる
    if (nrow(gene_info) > 0) {
      # 元の列名と新しい列名をデバッグログに出力
      flog.trace("[%s] biomaRt 列名の変更: %s -> %s", step_id,
                 paste(colnames(gene_info_raw), collapse=", "), # 元の列名が良いかもしれない
                 paste(c("ensembl_gene_id", "gene_symbol", "transcript_length", "gene_biotype"), collapse=", "), name = logger_name)
      colnames(gene_info) <- c("ensembl_gene_id", "gene_symbol", "transcript_length", "gene_biotype")
    }

  }, error = function(e) {
    flog.error("[%s] biomaRt への接続またはクエリに失敗しました: %s", step_id, e$message, name = logger_name)
    # エラー発生時でも処理を続行できるようにするが、警告は出す
    warning(sprintf("[%s] biomaRt からの情報の取得に失敗しました: %s", step_id, e$message))
    # 空のデータフレームを保証（後続のマージでNAが入るように）
    gene_info <<- data.frame(
        ensembl_gene_id = character(),
        gene_symbol = character(),
        transcript_length = integer(),
        gene_biotype = character()
    )
    # ここで stop せず処理を続行する（仕様に基づく）
    flog.warn("[%s] 空の biomaRt 結果で実行を継続します。", step_id, name = logger_name)
  })

  # --- 情報マージ ---
  flog.debug("[%s] biomaRt 情報を rowData にマージ中", step_id, name = logger_name)
  n_genes_before_merge <- nrow(rdat)
  n_genes_found <- nrow(gene_info)
  n_genes_not_found <- length(unique(rdat$ensembl_gene_id)) - n_genes_found

  if (n_genes_found > 0) {
      # DataFrame を data.frame に変換して結合し、DataFrame に戻す
      rdat_df <- as.data.frame(rdat)
      # gene_infoに存在しない列があればNAで作成しておく（結合エラー防止）
      expected_cols <- c("ensembl_gene_id", "gene_symbol", "transcript_length", "gene_biotype")
      for (col in expected_cols) {
        if (!col %in% colnames(gene_info)) {
          # データ型を推定してNA列を追加 (より堅牢にするなら要改善)
          if (col == "transcript_length") gene_info[[col]] <- NA_integer_
          else gene_info[[col]] <- NA_character_
          flog.warn("[%s] 列 '%s' が biomaRt の結果に見つかりません。NA 列を追加します。", step_id, col, name = logger_name)
        }
      }
      # 念のため、結合前にgene_infoの型を確認・変換
      # NA になる可能性も考慮 -> suppressWarnings
      suppressWarnings({
        gene_info <- gene_info %>%
          dplyr::mutate(transcript_length = as.integer(transcript_length))
      })

      flog.trace("[%s] マージ前の次元: rdat_df (%d, %d), gene_info (%d, %d)",
                 step_id, nrow(rdat_df), ncol(rdat_df), nrow(gene_info), ncol(gene_info), name = logger_name)
      merged_df <- dplyr::left_join(rdat_df, gene_info, by = "ensembl_gene_id")
      flog.trace("[%s] マージ後の次元: merged_df (%d, %d)", step_id, nrow(merged_df), ncol(merged_df), name = logger_name)

      # row.names を保持して DataFrame に戻す
      if (nrow(merged_df) != nrow(rdat_df)) {
          flog.warn("[%s] マージ後に総行数が変化しました: %d -> %d。結合の挙動を確認してください。", step_id, nrow(rdat_df), nrow(merged_df), name = logger_name)
          # 問題があればより詳細なログを出力
          flog.trace("[%s] rdat 行名: %s", step_id, paste(head(rownames(rdat_df)), collapse=","), name=logger_name)
          flog.trace("[%s] merged 行名: %s", step_id, paste(head(rownames(merged_df)), collapse=","), name=logger_name)
      }
      # マージ後の row.names が元の rdat と同じであることを確認する方が安全
      rdat <- S4Vectors::DataFrame(merged_df, row.names = rownames(rdat_df))

      flog.info("[%s] %d 個の遺伝子の情報を rowData にマージしました。", step_id, n_genes_found, name = logger_name)
      if (n_genes_not_found > 0) {
        flog.warn("[%s] biomaRt で %d 個の遺伝子の情報が見つかりませんでした。", step_id, n_genes_not_found, name = logger_name)
      }
    } else {
      flog.warn("[%s] biomaRt から情報が取得できませんでした。rowData に NA 列を追加します。", step_id, name = logger_name)
      # gene_info が空または期待する列がない場合、NAで列を追加
      rdat$gene_symbol <- NA_character_
      rdat$transcript_length <- NA_integer_
      rdat$gene_biotype <- NA_character_
    }

  # マージ後の行数チェック（デバッグ用）
  if (nrow(rdat) != n_genes_before_merge) {
      # 上で既に警告済みだが、念のため
      flog.warn("[%s] 最終行数チェック: マージ後に行数が変化しました: %d -> %d。", step_id, n_genes_before_merge, nrow(rdat), name = logger_name)
  }

  # rowData を更新
  flog.trace("[%s] SummarizedExperiment オブジェクトの rowData を更新中", step_id, name = logger_name)
  rowData(se) <- rdat

  # --- メタデータ記録 ---
  flog.debug("[%s] パイプライン履歴を記録中", step_id, name = logger_name)
  
  # 共通関数を使用してパイプライン履歴を追加
  details <- sprintf("biomaRt を使用して遺伝子アノテーションを追加/更新しました。%d 個の一意な遺伝子のうち %d 個の情報が見つかりました。",
                     n_genes_found + n_genes_not_found, n_genes_found)
  
  se <- add_pipeline_history(
    se = se,
    step_id = step_id,
    function_name = "add_biomart_gene_info",
    parameters = list(
      mart_dataset = mart_dataset, 
      biomart_host = biomart_host,
      experiment_id = experiment_id
    ),
    details = details,
    input_dimensions = input_dims,
    logger_name = logger_name
  )

  flog.info("[%s] 終了: biomaRt 遺伝子情報の追加が完了しました。", step_id, name = logger_name)

  # 更新された SE オブジェクトを返す
  return(se)
}
