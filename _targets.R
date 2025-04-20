library(targets)
library(tarchetypes)
library(yaml)
library(fs)
library(futile.logger)

# ユーティリティ関数の読み込み
source("R/utility.R")

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

# --- パス設定 ---
log_dir_path <- fs::path_abs(sprintf("logs/%s", experiment_id))
log_file_path <- fs::path(log_dir_path, "_targets.log")
report_dir_path <- fs::path_abs(sprintf("results/%s/reports", experiment_id))
# 将来的に必要になるかもしれない他の結果ディレクトリパスもここで定義可能
# plot_dir_path <- fs::path_abs(sprintf("results/%s/plots", experiment_id))
# table_dir_path <- fs::path_abs(sprintf("results/%s/tables", experiment_id))

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

# Rmd共通の出力フォーマット
common_output_format <- "html_document"

# Rmdモジュールの標準出力オプション設定
rmd_output_options <- list( # 変数名を options に変更
  toc = TRUE,
  toc_float = TRUE,
  code_folding = "hide",
  keep_md = TRUE
)

# ターゲットリスト
list(
  # ターゲット 0: 必要なディレクトリを作成し、ロガーを設定（常に実行）
  tar_target(
    name = ensure_directories,
    command = {
      # ログとレポートのディレクトリを作成
      fs::dir_create(log_dir_path)
      fs::dir_create(report_dir_path)
      # 必要であれば他のディレクトリも作成
      # fs::dir_create(plot_dir_path)
      # fs::dir_create(table_dir_path)

      # _targets.logファイルを初期化（パイプライン開始時に古いログを削除）
      if (fs::file_exists(log_file_path)) {
        fs::file_delete(log_file_path)
      }

      # --- ロギング設定 (ディレクトリ作成後に行う) ---
      # 注：ここではutility.Rのsetup_logger関数は使わず、_targets.R専用の設定を使う
      # Rmdモジュール内ではsetup_logger関数を使用するが、_targets.Rでは専用の設定を維持
      
      # コンソールとファイルに出力するカスタムアペンダーを作成
      # utility.R で定義した関数を使用
      
      # まず、ファイルハンドルを作成（削除済みなので新規作成モードで開く）
      log_con <- file(log_file_path, open = "wt")
      
      # カスタムアペンダーで、コンソールとファイルの両方に出力
      custom_appender <- function(line) {
        # コンソールに出力
        cat(line)
        # ファイルに出力して同期
        cat(line, file = log_con)
        flush(log_con)
      }
      
      # カスタムアペンダーを設定
      flog.appender(custom_appender)
      flog.layout('[%t] [%l] [_targets.R] %m')
      flog.threshold(INFO)

      flog.info("必要なディレクトリを作成し、ロガーを初期化しました (experiment_id: %s)", experiment_id)
      flog.info("ログファイルは %s に書き込まれます", log_file_path)
      flog.info("レポートディレクトリ: %s", report_dir_path)

      # このターゲットが生成するものを明示するためにパスのリストを返す
      return(list(log_dir = log_dir_path, report_dir = report_dir_path))
    },
    cue = tar_cue(mode = "always") # パイプライン実行時に常にこのターゲットを実行
  ),

  # ターゲット 1: 初期の SummarizedExperiment オブジェクトを作成
  # ensure_directories に依存
  tar_target(
    name = obj_se_raw,
    command = {
      # ensure_directories が実行されるようにコマンド内で参照
      dir_paths <- ensure_directories
      flog.info("ターゲット開始: obj_se_raw (ensure_directories に依存)")

      # 入力ファイルのパスを作成
      counts_path <- fs::path_abs(sprintf(counts_file_path_tmpl, experiment_id))
      metadata_path <- fs::path_abs(sprintf(metadata_file_path_tmpl, experiment_id))

      flog.info("実験ID: %s のSEオブジェクト作成を開始します。", experiment_id)
      flog.info("カウントファイルパス: %s", counts_path)
      flog.info("メタデータファイルパス: %s", metadata_path)
      flog.info("遺伝子ID列: %s", gene_id_col)
      flog.info("サンプルID列: %s", sample_id_col)
      flog.info("biomaRt ホスト: %s", biomart_host_cfg)
      flog.info("biomaRt データセット: %s", biomart_dataset_cfg)
      flog.info("biomaRt 属性: %s", paste(biomart_attributes_cfg, collapse=", "))

      # 出力パスを構築 (ensure_directoriesからレポートディレクトリパスを使用)
      output_path <- fs::path(dir_paths$report_dir, "create_se.html")

      # ★ 変更点: render が使用する環境を保持
      render_env <- new.env()

      # Rmd をレンダリング（レポート生成のため）
      rmarkdown::render(
        input = fs::path_abs("Rmd/create_se.Rmd"),
        output_file = output_path,
        output_format = common_output_format, # 変数を使用
        output_options = rmd_output_options, # オプションを別引数で渡す
        params = list(
          experiment_id = experiment_id,
          counts_file_path = counts_path,
          metadata_file_path = metadata_path,
          gene_id_column = gene_id_col,
          sample_id_column = sample_id_col,
          biomart_host = biomart_host_cfg,
          biomart_dataset = biomart_dataset_cfg,
          biomart_attributes = biomart_attributes_cfg
        ),
        envir = render_env, # ★ 保持した環境を使用
        quiet = TRUE, # 必要に応じてレンダリング出力を抑制
        knit_root_dir = fs::path_abs(".") # ★ 追加: プロジェクトルートを基準に実行
      )

      flog.info("create_se.Rmd のレンダリング完了: %s", output_path)

      # ★ 変更点: render_env から SE オブジェクトを取得
      # create_se.Rmd が 'se' という名前でオブジェクトを作成すると仮定
      if (!exists("se", envir = render_env)) {
         msg <- "create_se.Rmd の実行環境で 'se' オブジェクトが見つかりません。"
         flog.fatal(msg)
         stop(msg)
      }
      se_object <- get("se", envir = render_env)

      # ★ デバッグログ追加: 取得したオブジェクトのクラス確認
      flog.info("[_targets.R] render_env から取得したオブジェクト (se_object) のクラス: %s", paste(class(se_object), collapse=", "))
      if (!inherits(se_object, "SummarizedExperiment")) {
          msg <- sprintf("[_targets.R] 取得したオブジェクトは SummarizedExperiment ではありません。クラス: %s", paste(class(se_object), collapse=", "))
          flog.error(msg)
          # ここで stop せず、下の return で返すことで、report_check_se 側のログで再度確認できるようにする
          # stop(msg)
      }

      flog.info("ターゲット完了: obj_se_raw (SummarizedExperiment オブジェクトを返します)")
      return(se_object) # ★ 変更点: SE オブジェクトを返す
    }
  )
)
