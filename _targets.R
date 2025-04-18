library(targets)
library(tarchetypes)
library(yaml)
library(fs)
library(futile.logger)

# 関数を読み込む
source("R/R01_create_se.R")

# ターゲットオプションの設定:
# targets::tar_option_set() は、{targets} で推奨される方法として、
# スクリプト本体で library() を使う代わりに使用します。
# パイプラインに必要なパッケージを指定
tar_option_set(
  packages = c("SummarizedExperiment", "readr", "dplyr", "tibble", "cli", "S4Vectors", "yaml", "futile.logger", "fs"), # futile.logger と fs を追加
  format = "rds" # デフォルトの保存形式
)

# --- 設定ファイルの読み込み ---
# config.yaml から設定を読み込む
config <- yaml::read_yaml("config.yaml")

# config から実験 ID を抽出
experiment_id <- config$experiment_id
if (is.null(experiment_id)) {
  stop("experiment_id が config.yaml に見つかりません")
}

# --- ロギング設定 (パス定義のみ、初期化はターゲット内で行う) ---
# experiment_id が確定した後にログパスを設定
log_dir_path <- fs::path_abs(sprintf("logs/%s", experiment_id))
log_file_path <- fs::path(log_dir_path, "_targets.log")

# --- データディレクトリ構造 ---
# パイプラインは、入力データが 'data' ディレクトリ以下に、
# experiment_id と同じ名前のサブディレクトリ内に構成されていることを想定します。
# 例: data/250418_RNA-seq/counts.csv
#     data/250418_RNA-seq/sample_metadata.csv

# --- ファイルパスのテンプレートとパラメータ ---
# experiment_id で置き換えられるテンプレートを使用します。
# 必要に応じて、config.yaml でデフォルト値を上書きできます。
counts_file_path_tmpl <- config$counts_file_template %||% "data/%s/counts.csv"
metadata_file_path_tmpl <- config$metadata_file_template %||% "data/%s/sample_metadata.csv"
gene_id_col <- config$gene_id_column %||% "gene_id"
sample_id_col <- config$sample_id_column %||% "sample_id"

# config またはデフォルトから biomaRt 設定
biomart_dataset_cfg <- config$biomart_dataset # 必須、デフォルトなし、config.yaml に記述が必要
if (is.null(biomart_dataset_cfg)) {
  stop("biomart_dataset は config.yaml で指定する必要があります")
}
biomart_host_cfg <- config$biomart_host %||% "https://ensembl.org"
biomart_attributes_cfg <- config$biomart_attributes %||% c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")

# デフォルト値のためのヘルパー演算子を定義
`%||%` <- function(a, b) if (!is.null(a)) a else b

# ターゲットリスト
list(
  # ターゲット 0: ログディレクトリを作成し、ロガーを設定
  tar_target(
    name = ensure_log_dir,
    command = {
      fs::dir_create(log_dir_path)

      # --- ログファイルのローテーション ---
      # 古いログファイルをリネーム
      log_file_path_before <- fs::path(log_dir_path, "_targets_before.log")
      if (fs::file_exists(log_file_path)) {
        flog.info("既存のログファイル %s を %s に移動します", log_file_path, log_file_path_before)
        fs::file_move(log_file_path, log_file_path_before)
      } else {
        flog.info("ログファイル %s が存在しないため、リネームをスキップします。", log_file_path)
      }

      # --- ロギング設定 (ディレクトリ作成とローテーション後に行う) ---
      # appender.tee はファイルとコンソールに出力
      # layout.format はログメッセージの形式を指定
      # flog.threshold はログレベルを設定 (INFO以上を出力)
      flog.appender(appender.tee(log_file_path))
      flog.layout('[%t] [%l] [_targets.R] %m')
      flog.threshold(INFO)
      flog.info("ログディレクトリを作成し、ロガーを初期化しました (experiment_id: %s)", experiment_id)
      flog.info("ログファイルは %s に書き込まれます", log_file_path)

      # このターゲットが生成するものを明示するためにパスを返す
      return(log_dir_path)
    },
    cue = tar_cue(mode = "always")
  ),

  # ターゲット 1: 初期の SummarizedExperiment オブジェクトを作成
  # ensure_log_dir に依存
  tar_target(
    name = raw_se,
    command = {
      # ensure_log_dir が実行されるようにコマンド内で参照
      log_dir_placeholder <- ensure_log_dir
      flog.info("ターゲット開始: raw_se (ensure_log_dir に依存)")
      se <- create_se_object(
        experiment_id = experiment_id,
        counts_file_path = sprintf(counts_file_path_tmpl, experiment_id),
        metadata_file_path = sprintf(metadata_file_path_tmpl, experiment_id),
        gene_id_column = gene_id_col,
        sample_id_column = sample_id_col,
        # config/デフォルトから biomaRt パラメータを追加
        biomart_dataset = biomart_dataset_cfg,
        biomart_host = biomart_host_cfg,
        biomart_attributes = biomart_attributes_cfg
      )
      flog.info("ターゲット完了: raw_se")
      return(se)
    }
  ),

  # ターゲット 2: レポート出力ディレクトリが存在することを確認
  # ensure_log_dir に依存
  tar_target(
    name = ensure_report_dir,
    command = {
      # ensure_log_dir が実行されるようにコマンド内で参照
      log_dir_placeholder <- ensure_log_dir
      flog.info("ターゲット開始: ensure_report_dir (ensure_log_dir に依存)")
      dir_path <- sprintf("results/%s/reports", experiment_id)
      fs::dir_create(dir_path)
      # このターゲットが生成するものを明示するためにパスを返す
      flog.info("レポートディレクトリを確認しました: %s", dir_path)
      return(dir_path)
    }
  ),

  # ターゲット 3 (旧ターゲット2): SE チェックレポートをレンダリング
  # ensure_report_dir に明示的に依存 (間接的に ensure_log_dir にも依存)
  tar_target(
    name = report_check_se,
    command = {
      # ディレクトリターゲットが最初に実行されることを確認
      dir_path_placeholder <- ensure_report_dir # 依存関係を確立
      flog.info("ターゲット開始: report_check_se (ensure_report_dir に依存)")
      # 相対出力パスを定義
      relative_output_path <- sprintf("results/%s/reports/RMD02_check_se.html", experiment_id)
      # 絶対パスに変換
      output_path <- fs::path_abs(relative_output_path)
      output_dir <- dirname(output_path)

      flog.debug("Rmd をレンダリング中: input=%s, output=%s, knit_root_dir=%s",
                 fs::path_abs("Rmd/RMD02_check_se.Rmd"), output_path, fs::path_abs("."))

      # レンダリング直前に出力ディレクトリが存在することを確認
      fs::dir_create(output_dir) # ここでも作成を試みる (ensure_report_dir が既に行っているはず)

      flog.debug("dir_create 後の出力ディレクトリ存在確認: %s", fs::dir_exists(output_dir))

      # レンダリング直前に再度存在を確認
      if (!fs::dir_exists(output_dir)) {
          flog.error("レンダリング直前に出力ディレクトリが存在しません: %s", output_dir)
          stop("レンダリング直前に絶対ディレクトリが存在しません: ", output_dir)
      }

      # 絶対パスを使用してドキュメントをレンダリング
      render_result <- tryCatch({
          rmarkdown::render(
            input = fs::path_abs("Rmd/RMD02_check_se.Rmd"), # 入力にも絶対パスを使用
            output_file = output_path, # すでに絶対パス
            params = list(
              exp_id = experiment_id,
              module_name = "RMD02_check_se", 
              input_se = "raw_se",
              output_se = "raw_se"
            ),
            envir = parent.frame(), # Rmd 内の tar_load に重要
            knit_root_dir = fs::path_abs(".") # 絶対 knit_root_dir を明示的に設定
          )
          flog.info("Rmd のレンダリングに成功しました: %s", output_path)
          output_path # 成功したらパスを返す
        }, error = function(e) {
          flog.error("Rmd '%s' のレンダリングに失敗しました: %s", fs::path_abs("Rmd/RMD02_check_se.Rmd"), e$message)
          stop(e) # エラーを再スローしてターゲットを失敗させる
        })
      # 絶対出力ファイルパスを返す
      return(render_result)
    },
    # このターゲットがファイルを生成することを示す
    format = "file"
  )
)
