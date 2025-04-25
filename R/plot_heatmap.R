#' Generate a heatmap from SummarizedExperiment data
#'
#' This function creates a heatmap from assay data in a SummarizedExperiment object,
#' performs optional log transformation and scaling, adds column annotations,
#' and saves the plot as a PNG file.
#'
#' @param se SummarizedExperiment object.
#' @param assay_name Character string specifying the assay to use.
#' @param annotation_cols Character vector of colData columns for annotation (or NULL).
#' @param log_transform Logical, whether to apply log2(count + 1).
#' @param scale_rows Logical, whether to scale rows (genes).
#' @param cluster_rows Logical, whether to cluster rows.
#' @param cluster_cols Logical, whether to cluster columns.
#' @param output_dir Character string (absolute path) of the output directory.
#' @param filename_prefix Character string for the output filename prefix.
#' @param logger_name Character string for the logger name.
#'
#' @return Absolute fs::path to the generated PNG file.
#' @export
#'
#' @import SummarizedExperiment
#' @import pheatmap
#' @import RColorBrewer
#' @import futile.logger
#' @import fs
#' @import dplyr
#' @import grDevices # for png()
#' @import graphics # for plot.new(), text()
#' @import matrixStats # ★ 追加: 行分散計算のため

plot_heatmap <- function(se,
                         assay_name,
                         annotation_cols = NULL,
                         log_transform = TRUE,
                         scale_rows = TRUE,
                         cluster_rows = TRUE,
                         cluster_cols = TRUE,
                         output_dir,
                         filename_prefix,
                         logger_name) {

  # --- Load necessary libraries ---
  # (roxygen2 @import handles this in package context,
  # but explicit library() calls ensure script execution works)
  library(SummarizedExperiment)
  library(pheatmap)
  library(RColorBrewer)
  library(futile.logger)
  library(fs)
  library(dplyr)
  library(grDevices)
  library(graphics)
  library(matrixStats) # ★ 追加

  # --- ログ開始 ---
  flog.info("関数 plot_heatmap 開始: assay='%s', output='%s/%s*.png'", 
            assay_name, output_dir, filename_prefix, name = logger_name)
  flog.debug("パラメータ: log_transform=%s, scale_rows=%s, cluster_rows=%s, cluster_cols=%s, annotation_cols=[%s]",
             log_transform, scale_rows, cluster_rows, cluster_cols, 
             paste(annotation_cols, collapse=", "), name = logger_name)
             
  # --- 入力検証 ---
  if (!inherits(se, "SummarizedExperiment")) {
    flog.error("入力 'se' は SummarizedExperiment オブジェクトではありません。", name = logger_name)
    stop("入力 'se' は SummarizedExperiment オブジェクトではありません。")
  }
  if (!assay_name %in% assayNames(se)) {
    flog.error("指定された assay_name '%s' は se オブジェクトに存在しません。利用可能なアッセイ: [%s]", 
               assay_name, paste(assayNames(se), collapse=", "), name = logger_name)
    stop(sprintf("指定された assay_name '%s' は se オブジェクトに存在しません。", assay_name))
  }
  output_dir <- fs::path_abs(output_dir) # 絶対パスに変換
  if (!fs::dir_exists(output_dir)) {
    flog.warn("出力ディレクトリが存在しないため作成します: %s", output_dir, name = logger_name)
    tryCatch({
      fs::dir_create(output_dir, recursive = TRUE)
    }, error = function(e) {
      flog.error("出力ディレクトリの作成に失敗しました: %s. エラー: %s", output_dir, conditionMessage(e), name = logger_name)
      stop(sprintf("出力ディレクトリの作成に失敗しました: %s", output_dir))
    })
  }
  # ToDo: 書き込み権限のチェック (fs::file_access() など)

  # --- データ抽出 ---
  flog.info("アッセイ '%s' からデータを抽出します。", assay_name, name = logger_name)
  mat <- assay(se, assay_name)
  flog.debug("抽出データ: %d 行 x %d 列", nrow(mat), ncol(mat), name = logger_name)
  if (!is.numeric(mat)) {
    flog.error("アッセイ '%s' のデータが数値ではありません。", assay_name, name = logger_name)
    stop(sprintf("アッセイ '%s' のデータが数値ではありません。", assay_name))
  }

  # --- ★ 上位変動遺伝子の選択 (ログ変換前) ---
  if (nrow(mat) > 0) {
    flog.info("アッセイ '%s' のデータで行分散を計算し、上位遺伝子を選択します。", assay_name, name = logger_name)
    row_variances <- matrixStats::rowVars(mat, na.rm = TRUE)
    n_select <- min(100, nrow(mat)) # 上位100件、ただし総数より多くは選ばない
    if (n_select < nrow(mat)) {
      flog.info("分散上位 %d 個の遺伝子を選択します。", n_select, name = logger_name)
      top_indices <- order(row_variances, decreasing = TRUE)[1:n_select]
      selected_genes <- rownames(mat)[top_indices]
      mat <- mat[top_indices, , drop = FALSE]
      flog.debug("フィルタリング後のデータ: %d 行 x %d 列。選択された遺伝子の例: [%s]",
                 nrow(mat), ncol(mat), paste(head(selected_genes), collapse=", "), name = logger_name)
      # ファイル名にサフィックスを追加
      filename_prefix <- paste0(filename_prefix, "_top100var")
    } else {
      flog.info("遺伝子数が %d 個以下のため、すべての遺伝子を使用します。", n_select, name = logger_name)
      # サフィックスは追加しないか、"_allvar" のようなものを追加するか選択可能
      # filename_prefix <- paste0(filename_prefix, "_allvar") # 必要なら
    }
  } else {
      flog.warn("入力データの行数が0のため、遺伝子選択はスキップします。", name = logger_name)
  }
  # -------------------------------------------

  # --- ログ変換 (フィルタリング後) ---
  if (log_transform) {
    flog.info("log2(count + 1) 変換を実行します (フィルタリング後)。", name = logger_name)
    mat <- log2(mat + 1)
  }
  
  # --- アノテーション準備 ---
  annotation_df <- NULL
  valid_annotation_cols <- character(0)
  if (!is.null(annotation_cols)) {
    flog.info("列アノテーションを準備します: [%s]", paste(annotation_cols, collapse=", "), name = logger_name)
    sample_info <- as.data.frame(colData(se))
    available_cols <- colnames(sample_info)
    valid_annotation_cols <- annotation_cols[annotation_cols %in% available_cols]
    invalid_annotation_cols <- annotation_cols[!annotation_cols %in% available_cols]
    
    if (length(invalid_annotation_cols) > 0) {
      flog.warn("指定されたアノテーション列のうち、colData に存在しないものがあります: [%s]", 
                paste(invalid_annotation_cols, collapse=", "), name = logger_name)
    }
    
    if (length(valid_annotation_cols) > 0) {
      flog.debug("有効なアノテーション列: [%s]", paste(valid_annotation_cols, collapse=", "), name = logger_name)
      annotation_df <- sample_info[, valid_annotation_cols, drop = FALSE] # select だとベクトルになる可能性
      # pheatmap は行名がカウント行列の列名と一致する必要がある
      rownames(annotation_df) <- rownames(sample_info) 
    } else {
      flog.warn("有効なアノテーション列が見つからなかったため、アノテーションは使用されません。", name = logger_name)
    }
  }

  # --- ファイル名生成 ---
  annotation_suffix <- ""
  if (!is.null(annotation_df) && length(valid_annotation_cols) > 0) {
    # ファイル名には実際に使用されたアノテーション列名を使う
    annotation_suffix <- paste0("_annot_", paste(valid_annotation_cols, collapse="_"))
  }
  # filename_prefix は上位遺伝子選択時に変更されている可能性あり
  filename <- paste0(filename_prefix, annotation_suffix, ".png")
  output_path <- fs::path(output_dir, filename)
  flog.info("ヒートマップをファイルに保存します: %s", output_path, name = logger_name)
  
  # --- ヒートマップ描画と保存 ---
  scale_param <- if (scale_rows) "row" else "none"
  flog.debug("pheatmap パラメータ: scale='%s', cluster_rows=%s, cluster_cols=%s", 
             scale_param, cluster_rows, cluster_cols, name = logger_name)
             
  # カラーパレット
  color_palette <- colorRampPalette(rev(RColorBrewer::brewer.pal(n = 9, name = "RdYlBu")))(100)
  
  tryCatch({
    pheatmap::pheatmap(
      mat = mat,
      annotation_col = annotation_df, # NULL でも可
      scale = scale_param,
      cluster_rows = cluster_rows,
      cluster_cols = cluster_cols,
      color = color_palette,
      filename = output_path,
      width = 8, # 必要に応じて調整
      height = 10
    )
    flog.info("ヒートマップの保存が完了しました: %s", output_path, name = logger_name)
  }, error = function(e) {
    flog.error("pheatmap 描画中にエラーが発生しました: %s", conditionMessage(e), name = logger_name)
    # エラー発生時に空のファイルを削除する試み (失敗しても止めない)
    try(fs::file_delete(output_path), silent = TRUE)
    stop(sprintf("pheatmap 描画中にエラーが発生しました: %s", conditionMessage(e)))
  })

  # --- 終了ログと戻り値 ---
  flog.info("関数 plot_heatmap 終了", name = logger_name)
  return(output_path)
} 