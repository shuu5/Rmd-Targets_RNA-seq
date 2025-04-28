#' SummarizedExperiment データからヒートマップを生成する
#'
#' この関数は、SummarizedExperiment オブジェクトのアッセイデータからヒートマップを作成し、
#' オプションでログ変換とスケーリングを行い、列アノテーションを追加し、
#' プロットを PNG ファイルとして保存します。
#'
#' @param se SummarizedExperiment オブジェクト。
#' @param assay_name 使用するアッセイを指定する文字列。
#' @param annotation_cols アノテーションに使用する colData の列名の文字ベクトル（または NULL）。
#' @param log_transform 論理値。log2(count + 1) 変換を適用するかどうか。
#' @param scale_rows 論理値。行（遺伝子）をスケーリングするかどうか。
#' @param cluster_rows 論理値。行をクラスタリングするかどうか。
#' @param cluster_cols 論理値。列をクラスタリングするかどうか。
#' @param show_rownames 論理値。行名 (`rowData(se)$gene_symbol`) を表示するかどうか。
#' @param show_colnames 論理値。列名 (サンプル名) を表示するかどうか。
#' @param output_dir 出力ディレクトリの文字列表現（絶対パス）。
#' @param filename_prefix 出力ファイル名の接頭辞となる文字列。
#' @param logger_name ロガー名の文字列。
#'
#' @return 生成された PNG ファイルへの絶対パス (`fs::path`)。
#' @export
#'
#' @import SummarizedExperiment
#' @import pheatmap
#' @import RColorBrewer
#' @import futile.logger
#' @import fs
#' @import dplyr
#' @import grDevices # png() のため
#' @import graphics # plot.new(), text() のため
#' @import S4Vectors # rowData のために追加

plot_heatmap <- function(se,
                         assay_name,
                         annotation_cols = NULL,
                         log_transform = TRUE,
                         scale_rows = TRUE,
                         cluster_rows = TRUE,
                         cluster_cols = TRUE,
                         show_rownames = TRUE,
                         show_colnames = TRUE,
                         output_dir,
                         filename_prefix,
                         logger_name) {

  # --- 必要なライブラリの読み込み ---
  # (roxygen2 の @import がパッケージコンテキストで処理しますが、
  #  明示的な library() 呼び出しでスクリプト実行を確実にします)
  library(SummarizedExperiment)
  library(pheatmap)
  library(RColorBrewer)
  library(futile.logger)
  library(fs)
  library(dplyr)
  library(grDevices)
  library(graphics)
  library(S4Vectors) # library() も追加

  # --- ログ開始 ---
  flog.info("関数 plot_heatmap 開始: assay='%s', output='%s/%s*.png'",
            assay_name, output_dir, filename_prefix, name = logger_name)
  flog.debug("パラメータ: log_transform=%s, scale_rows=%s, cluster_rows=%s, cluster_cols=%s, annotation_cols=[%s], show_rownames=%s, show_colnames=%s",
             log_transform, scale_rows, cluster_rows, cluster_cols,
             paste(annotation_cols, collapse=", "), 
             show_rownames, show_colnames, # デバッグログに追加
             name = logger_name)

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
  # gene_symbol の存在チェック
  if (!"gene_symbol" %in% colnames(rowData(se))) {
    flog.error("rowData(se) に 'gene_symbol' 列が存在しません。", name = logger_name)
    stop("rowData(se) に 'gene_symbol' 列が存在しません。")
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

  # --- ログ変換 (フィルタリング後) ---
  if (log_transform) {
    flog.info("log2(count + 1) 変換を実行します。", name = logger_name)
    mat <- log2(mat + 1)
  }

  # --- データチェック: NA/NaN/Inf ---
  if (any(!is.finite(mat))) {
      num_nonfinite <- sum(!is.finite(mat))
      flog.warn("行列 'mat' に %d 個の非有限値 (NA/NaN/Inf) が含まれています。これらの値を含む行はヒートマップから除外される可能性があります。", num_nonfinite, name = logger_name)
      # pheatmap 自体が NA を処理できる場合もあるが、NaN/Inf は問題を起こす可能性が高い
      # 必要であればここで非有限値を含む行を除外する処理を追加:
      # finite_rows <- apply(mat, 1, function(row) all(is.finite(row)))
      # mat <- mat[finite_rows, , drop = FALSE]
      # flog.info("%d 行の非有限値を含む行を除外しました。", sum(!finite_rows), name = logger_name)
  }

  # --- データチェックとフィルタリング: ゼロ分散 (スケーリング時) ---
  if (scale_rows && nrow(mat) > 0) {
      flog.debug("行のスケーリングが有効なため、分散ゼロの行をチェックします。", name = logger_name)
      # rowVars は matrixStats パッケージにあるが、依存関係を増やさないために apply を使用
      # 非常に小さい分散も問題になる可能性があるので、閾値を設定
      row_variances <- apply(mat, 1, var, na.rm = TRUE)
      zero_var_threshold <- 1e-8 # ゼロとみなす閾値
      zero_var_rows <- !is.na(row_variances) & row_variances < zero_var_threshold

      if (any(zero_var_rows)) {
          num_zero_var <- sum(zero_var_rows)
          flog.warn("行のスケーリングが有効ですが、%d 行で分散がほぼゼロです。これらの行はヒートマップから除外されます。", num_zero_var, name = logger_name)
          flog.trace("分散ゼロの行: [%s]", paste(rownames(mat)[zero_var_rows], collapse=", "), name = logger_name)
          mat <- mat[!zero_var_rows, , drop = FALSE]
          if (nrow(mat) == 0) {
              flog.error("分散ゼロの行を除外した結果、行列が空になりました。ヒートマップは生成できません。", name = logger_name)
              stop("分散ゼロの行を除外した結果、行列が空になりました。")
          }
          flog.info("分散ゼロの行を除外した後、行列の次元: %d 行 x %d 列", nrow(mat), ncol(mat), name = logger_name)
      }
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
  # filename_prefix は上位変動遺伝子選択ロジック削除により変更されなくなった
  filename <- paste0(filename_prefix, annotation_suffix, ".png")
  output_path <- fs::path(output_dir, filename)
  flog.info("ヒートマップをファイルに保存します: %s", output_path, name = logger_name)

  # --- ヒートマップ描画と保存 ---
  scale_param <- if (scale_rows) "row" else "none"
  flog.debug("pheatmap パラメータ: scale='%s', cluster_rows=%s, cluster_cols=%s",
             scale_param, cluster_rows, cluster_cols, name = logger_name)

  # カラーパレット
  color_palette <- colorRampPalette(rev(RColorBrewer::brewer.pal(n = 9, name = "RdYlBu")))(100)

  # 行ラベルの準備
  row_labels <- rowData(se)$gene_symbol
  # matrix がフィルタリングされた場合に備えて、matrix の rownames に基づいて rowData をフィルタリング
  # ★注意: 上位変動遺伝子選択が削除されたため、matのrownamesとrowDataのrownamesは一致するはずだが、念のため残す。
  #       もし将来的にフィルタリングが再導入される場合は、このロジックが重要になる。
  if (!identical(rownames(mat), rownames(rowData(se)))) {
      flog.warn("ヒートマップ用行列の行名がrowDataの行名と一致しません。行列の行名に基づいてgene_symbolを選択します。", name=logger_name)
      # rowData を DataFrame に変換してからフィルタリングする方が安全な場合がある
      rd_df <- as.data.frame(rowData(se))
      # ★注意: mat がフィルタリングされた可能性があるため、rownames(mat) に存在する遺伝子のみを選択
      valid_rownames <- rownames(mat)[rownames(mat) %in% rownames(rd_df)]
      if (length(valid_rownames) < nrow(mat)) {
          flog.warn("rowData に存在しない行名が mat に含まれています。", name = logger_name)
      }
      row_labels <- rd_df[valid_rownames, "gene_symbol"]
      # row_labels の長さが mat の行数と一致するか確認
      if(length(row_labels) != nrow(mat)) {
           flog.warn("行列フィルタリング後、row_labels の長さが行数と一致しません。rownamesを使用します。", name=logger_name)
           row_labels <- rownames(mat) # フォールバック
           show_rownames <- TRUE # 行名を表示するように強制
      } else if (any(is.na(row_labels))) {
          flog.warn("一部の遺伝子のgene_symbolが見つかりませんでした。NA または rownames が使用されます。", name=logger_name)
          # NAの代わりにrownamesを使うなどの処理も可能
          na_indices <- is.na(row_labels)
          row_labels[na_indices] <- rownames(mat)[na_indices]
      }
  }
  # row_labelsの長さが0またはすべてNAでないことを確認
  if(length(row_labels) == 0 || all(is.na(row_labels))) {
      flog.warn("有効なgene_symbolが見つからなかったため、行ラベルは表示されません（rownamesが使用されます）。", name=logger_name)
      row_labels <- rownames(mat) # フォールバックとして元のrownamesを使用
      # あるいはエラーにするか、show_rownames=FALSEを強制する選択肢もある
      # show_rownames <- FALSE
  }

  tryCatch({
    pheatmap::pheatmap(
      mat = mat,
      annotation_col = annotation_df, # NULL でも可
      scale = scale_param,
      cluster_rows = cluster_rows,
      cluster_cols = cluster_cols,
      color = color_palette,
      labels_row = row_labels,      # gene_symbol を使用
      show_rownames = show_rownames, # 引数を渡す
      show_colnames = show_colnames, # 引数を渡す
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