#' ログ密度プロットを作成し、ファイルに保存する
#'
#' SummarizedExperiment オブジェクトの指定されたアッセイデータを対数変換 (log1p) し、
#' サンプルごとのデータ分布を密度プロットとして可視化してファイルに保存する。
#'
#' @param se SummarizedExperiment オブジェクト。
#' @param experiment_id 実験ID。
#' @param assay_name プロットに使用するアッセイ名。
#' @param output_dir プロットファイルを保存するディレクトリ。
#' @param logger_name ログ出力に使用するロガー名。
#' @param target_name この関数を実行する `targets` ターゲット名。
#'
#' @return 生成されたプロットファイルの絶対パス (fs::path)。
#' @export
plot_log_density <- function(se,
                             experiment_id,
                             assay_name,
                             output_dir,
                             logger_name = "default",
                             target_name = "unknown_target") {

  # --- 入力チェック ---
  if (!inherits(se, "SummarizedExperiment")) {
    flog.error("Input 'se' must be a SummarizedExperiment object.", name = logger_name)
    stop("Input 'se' must be a SummarizedExperiment object.")
  }
  if (!(assay_name %in% assayNames(se))) {
    flog.error(glue::glue("Assay not found: '{assay_name}' is not in assayNames(se)."), name = logger_name)
    stop(glue::glue("Assay not found: '{assay_name}' is not in assayNames(se)."))
  }
  if (!fs::dir_exists(output_dir)) {
     flog.warn(glue::glue("Output directory '{output_dir}' does not exist. Attempting to create."), name = logger_name)
     tryCatch({
        fs::dir_create(output_dir, recurse = TRUE)
        flog.info(glue::glue("Created output directory: {output_dir}"), name = logger_name)
     }, error = function(e) {
        flog.error(glue::glue("Failed to create output directory '{output_dir}': {e}"), name = logger_name)
        stop(glue::glue("Failed to create output directory '{output_dir}': {e}"))
     })
  }

  flog.info(glue::glue("Starting plot_log_density for assay '{assay_name}'."), name = logger_name)
  flog.debug(glue::glue("Parameters: experiment_id='{experiment_id}', assay_name='{assay_name}', output_dir='{output_dir}'"), name = logger_name)

  # --- データ取得と変換 ---
  tryCatch({
    assay_data <- assay(se, assay_name)
    flog.debug(glue::glue("Successfully retrieved assay '{assay_name}'."), name = logger_name)

    log_data <- log1p(assay_data)
    flog.debug("Performed log1p transformation.", name = logger_name)

    log_df <- as.data.frame(log_data) %>%
      tibble::rownames_to_column("feature") %>%
      tidyr::pivot_longer(
        cols = -feature,
        names_to = "sample",
        values_to = "log_value"
      )
    flog.debug("Data reshaped to long format.", name = logger_name)

  }, error = function(e) {
    flog.error(glue::glue("Error during data retrieval or transformation: {e}"), name = logger_name)
    stop(glue::glue("Error during data retrieval or transformation: {e}"))
  })


  # --- プロット作成 ---
  tryCatch({
    gg <- ggplot(log_df, aes(x = log_value, colour = sample)) +
      geom_density() +
      theme_classic() +
      theme(
        plot.title = element_text(hjust = 0.5),
        legend.position = "bottom" # サンプル数が多い場合を考慮
        ) +
      labs(
        title = glue::glue("Density of log1p({assay_name})"),
        x = "log1p(value)",
        y = "Density",
        colour = "Sample"
      )
     flog.debug("ggplot object created successfully.", name = logger_name)
  }, error = function(e) {
     flog.error(glue::glue("Error creating ggplot object: {e}"), name = logger_name)
     stop(glue::glue("Error creating ggplot object: {e}"))
  })

  # --- ファイル保存 ---
  plot_filename <- glue::glue("log_density_{assay_name}_{experiment_id}.png")
  # output_dir が絶対パスでない可能性も考慮し、fs::path_abs を適用
  plot_filepath_abs <- fs::path_abs(fs::path(output_dir, plot_filename))

  tryCatch({
    flog.debug(glue::glue("Attempting to save plot to: {plot_filepath_abs}"), name = logger_name)
    ggsave(
        filename = plot_filepath_abs,
        plot = gg,
        width = 8, # サイズを少し大きめに
        height = 6,
        dpi = 300,
        device = "png"
    )
    flog.info(glue::glue("Log density plot saved successfully to: {plot_filepath_abs}"), name = logger_name)
  }, error = function(e) {
    flog.error(glue::glue("Failed to save plot to '{plot_filepath_abs}': {e}"), name = logger_name)
    stop(glue::glue("Failed to save plot to '{plot_filepath_abs}': {e}"))
  })

  # --- メタデータ更新は行わない ---

  flog.info("plot_log_density finished successfully.", name = logger_name)

  # プロジェクトルートからの相対パスではなく絶対パスを返す
  return(plot_filepath_abs)
} 