#' ライブラリサイズのバープロットを作成し保存する
#'
#' SummarizedExperiment オブジェクトの指定されたアッセイデータから
#' サンプルごとのライブラリサイズ (合計カウント数) を計算し、
#' バープロットとして指定されたディレクトリにPNG形式で保存する。
#'
#' @param se SummarizedExperiment オブジェクト。
#' @param experiment_id 実験ID (character)。出力ファイル名に使用。
#' @param assay_name ライブラリサイズ計算に使用するアッセイ名 (character)。
#' @param output_dir プロットファイルを保存するディレクトリパス (character)。
#' @param logger_name ログ出力に使用するロガー名 (character)。
#' @param target_name targets のターゲット名 (character)。ログ用。
#'
#' @return 生成されたPNGファイルの絶対パス (character)。
#' @export
#' @import SummarizedExperiment
#' @import ggplot2
#' @import dplyr
#' @import tibble
#' @import futile.logger
#' @import fs
#' @import glue
plot_library_size <- function(se, experiment_id, assay_name, output_dir, logger_name = "default", target_name = "unknown_target") {

  # --- 引数チェック --- #
  if (!inherits(se, "SummarizedExperiment")) {
    stop("'se' must be a SummarizedExperiment object.")
  }
  if (!assay_name %in% assayNames(se)) {
    msg <- glue::glue("Assay not found: '{assay_name}' in the SE object. Available assays: {paste(assayNames(se), collapse = ', ')}")
    futile.logger::flog.error(msg, name = logger_name)
    stop(msg)
  }
  if (!dir.exists(output_dir)) {
    msg <- glue::glue("Output directory does not exist: {output_dir}")
    futile.logger::flog.error(msg, name = logger_name)
    stop(msg)
  }

  futile.logger::flog.info("[%s] Starting plot_library_size for assay '%s'. Target: %s",
                         logger_name, assay_name, target_name,
                         name = logger_name)

  # --- データ取得と計算 --- #
  futile.logger::flog.debug("[%s] Extracting assay data: %s", logger_name, assay_name, name = logger_name)
  assay_data <- SummarizedExperiment::assay(se, assay_name)

  futile.logger::flog.debug("[%s] Calculating library sizes (colSums)", logger_name, name = logger_name)
  library_sizes <- colSums(assay_data)

  plot_df <- tibble::tibble(
    sample_name = names(library_sizes),
    library_size = library_sizes
  ) |> dplyr::mutate(sample_name = factor(sample_name, levels = sample_name)) # プロット順維持

  futile.logger::flog.debug("[%s] Library size calculation complete.", logger_name, name = logger_name)

  # --- プロット作成 --- #
  gg <- ggplot2::ggplot(plot_df, ggplot2::aes(x = sample_name, y = library_size)) +
    ggplot2::geom_bar(stat = "identity", fill = "steelblue") +
    ggplot2::theme_classic() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1) # サンプル名が長い場合に備える
    ) +
    ggplot2::labs(
      title = "Library Size per Sample",
      x = "Sample",
      y = "Total Counts"
    )

  futile.logger::flog.debug("[%s] ggplot object created.", logger_name, name = logger_name)

  # --- ファイル保存 --- #
  output_filename <- glue::glue("library_size_{assay_name}_{experiment_id}.png")
  output_filepath <- fs::path(output_dir, output_filename)
  output_filepath_abs <- fs::path_abs(output_filepath)

  futile.logger::flog.debug("[%s] Attempting to save plot to: %s", logger_name, output_filepath_abs, name = logger_name)

  tryCatch({
    ggplot2::ggsave(
      filename = output_filepath_abs,
      plot = gg,
      device = "png",
      width = 7,
      height = 5,
      dpi = 300
    )
    futile.logger::flog.info("[%s] Plot successfully saved to: %s", logger_name, output_filepath_abs, name = logger_name)
  }, error = function(e) {
    msg <- glue::glue("Failed to save plot to {output_filepath_abs}. Error: {conditionMessage(e)}")
    futile.logger::flog.error("[%s] %s", logger_name, msg, name = logger_name)
    stop(msg)
  })

  # --- 終了 --- #
  futile.logger::flog.info("[%s] Finished plot_library_size.", logger_name, name = logger_name)
  return(output_filepath_abs)
} 