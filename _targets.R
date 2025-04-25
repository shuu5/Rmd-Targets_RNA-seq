# _targets.R
suppressPackageStartupMessages({
  library(targets)
  library(tarchetypes)
  library(futile.logger)
  library(fs)
  library(SummarizedExperiment) # create_se_object 関数内で必要
  library(biomaRt) # add_biomart_gene_info で必要
  library(ggplot2) # プロット可視化に必要
  library(dplyr) # データ操作に必要
  library(tidyr) # pivot_longer に必要
  library(tibble) # rownames_to_column に必要
  library(scales) # カンマ区切りに必要
  library(glue) # ★ output_file の設定に使用
})

# --- 設定 ---
# experiment_id をグローバルオプションとして設定
options(TARGETS_EXPERIMENT_ID = "IFITM3_TAB3_Knockdown")
experiment_id <- getOption("TARGETS_EXPERIMENT_ID", default = "default_experiment")

# ロギング設定 (INFOレベル以上をコンソールとファイルに出力。起動時にファイルを削除)
log_dir_pipeline <- fs::path("logs", experiment_id)
fs::dir_create(log_dir_pipeline)
log_file_pipeline <- fs::path(log_dir_pipeline, "_targets.log")
if (fs::file_exists(log_file_pipeline)) fs::file_delete(log_file_pipeline)
flog.appender(appender.tee(log_file_pipeline))
flog.threshold(INFO)
flog.info("ターゲットパイプラインを開始します。実験ID: %s", experiment_id)

# --- パイプライン定義 ---
list(
  # R/ ディレクトリ内のすべての .R ファイルを読み込む
  tar_source("R"),

  # SE オブジェクトを作成するターゲット
  tar_target(
    name = obj_se_raw,
    command = run_with_logging( # ラッパー関数を使用
      func = create_se_object,
      # --- create_se_object の引数 ---
      experiment_id = experiment_id,
      data_dir = "data",
      counts_filename = "counts.csv",
      metadata_filename = "sample_metadata.csv",
      # --- run_with_logging の引数 ---
      target_name = "obj_se_raw", # ★ ターゲット名を渡す
      exp_id = experiment_id, # ★ experiment_id を exp_id に変更
      log_level = INFO
    )
  ),

  # biomaRt で遺伝子情報を追加するターゲット
  tar_target(
    name = obj_se_annotated,
    command = run_with_logging( # ラッパー関数を使用
      func = add_biomart_gene_info,
      # --- add_biomart_gene_info の引数 ---
      se = obj_se_raw, # ここで obj_se_raw を使用しているので依存関係は自動的に検出される
      step_id = "add_biomart_gene_info",
      experiment_id = experiment_id,
      # --- run_with_logging の引数 ---
      target_name = "obj_se_annotated", # ★ ターゲット名を渡す
      exp_id = experiment_id, # ★ experiment_id を exp_id に変更
      log_level = INFO
    )
  ),

  # 遺伝子タイプでサブセット化するターゲット (新規追加)
  tar_target(
    name = obj_se_subset_protein_coding,
    command = run_with_logging(
      func = subset_gene,
      # --- subset_gene の引数 ---
      se = obj_se_annotated, # obj_se_annotated に依存
      filter_conditions = list("gene_biotype == 'protein_coding'"),
      # --- run_with_logging の引数 ---
      target_name = "obj_se_subset_protein_coding",
      exp_id = experiment_id,
      log_level = INFO
    )
  ),

  # ライブラリサイズプロットを生成するターゲット (依存関係変更)
  tar_target(
    name = file_plot_library_size,
    command = run_with_logging(
      func = plot_library_size,
      # --- plot_library_size の引数 ---
      se = obj_se_subset_protein_coding, # obj_se_subset_protein_coding に依存変更
      assay_name = "counts", # 使用するアッセイを指定
      output_dir = fs::path("results", experiment_id, "plots"),
      experiment_id = experiment_id,
      # --- run_with_logging の引数 ---
      target_name = "file_plot_library_size",
      exp_id = experiment_id,
      log_level = INFO
    ),
    format = "file" # ファイルパスを返す
  ),

  # ログ密度プロット (counts アッセイ) を生成するターゲット (依存関係変更)
  tar_target(
    name = file_plot_log_density,
    command = run_with_logging(
      func = plot_log_density,
      # --- plot_log_density の引数 ---
      se = obj_se_subset_protein_coding, # obj_se_subset_protein_coding に依存変更
      assay_name = "counts", # 使用するアッセイを指定
      output_dir = fs::path("results", experiment_id, "plots"),
      experiment_id = experiment_id,
      # --- run_with_logging の引数 ---
      target_name = "file_plot_log_density",
      exp_id = experiment_id,
      log_level = INFO
    ),
    format = "file" # ファイルパスを返す
  ),

  # ヒートマップ (protein_coding, counts) を生成するターゲット (新規追加)
  tar_target(
    name = file_heatmap_protein_coding_counts,
    command = run_with_logging(
      func = plot_heatmap,
      # --- plot_heatmap の引数 ---
      se = obj_se_subset_protein_coding, # obj_se_subset_protein_coding に依存
      assay_name = "counts",
      annotation_cols = c("Group"), # "Group" 列でアノテーション (存在しない場合は NULL に変更)
      output_dir = fs::path("results", experiment_id, "plots"),
      filename_prefix = "heatmap_protein_coding_counts",
      # --- run_with_logging の引数 ---
      target_name = "file_heatmap_protein_coding_counts",
      exp_id = experiment_id,
      log_level = INFO
    ),
    format = "file" # ファイルパスを返す
  ),

  # SE 基本情報 Rmd をレンダリングするターゲット (依存関係はRmd内で解決)
  tarchetypes::tar_render(
    name = rmd_se_basic_info,
    path = "Rmd/se_basic_info.Rmd",
    output_file = "se_basic_info.html",
    output_dir = fs::path("results", experiment_id, "reports"),
    params = list(
      experiment_id = experiment_id
    )
  )
)
