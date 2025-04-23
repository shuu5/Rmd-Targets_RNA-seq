library(targets)
library(tarchetypes)
# library(yaml) # yamlパッケージの読み込みを削除
library(fs)
library(futile.logger)

# ユーティリティ関数の読み込み
source("R/utility.R")

# --- 基本設定 ---

# 実験を識別するための一意なID
experiment_id <- "250418_RNA-seq"

# targets パイプライン全体で使用するパッケージリスト
tar_option_set(
  packages = c(
    "SummarizedExperiment", # RNA-seqデータの格納・操作
    "readr",              # CSVファイルの高速読み込み
    "dplyr",              # データ操作
    "tibble",             # データフレーム操作
    "cli",                # コマンドラインインターフェースの強化
    "S4Vectors",          # SummarizedExperiment の基盤
    "futile.logger",      # ログ出力
    "fs",                 # ファイルシステム操作
    "rmarkdown"           # R Markdownレポートの生成
  ),
  # targets が中間データや結果を保存するデフォルトのファイル形式
  format = "rds" 
)

# --- パス設定 ---

# 各種出力ディレクトリのパスを生成するためのテンプレート
# `%s` は experiment_id で置き換えられます
logs_dir_tmpl <- "logs/%s"              # ログファイル用ディレクトリ
reports_dir_tmpl <- "results/%s/reports" # R Markdownレポート用ディレクトリ
plots_dir_tmpl <- "results/%s/plots"     # プロット画像用ディレクトリ
tables_dir_tmpl <- "results/%s/tables"    # 結果テーブル用ディレクトリ

# 上記テンプレートと experiment_id から実際のディレクトリパスを作成
log_dir_path <- fs::path_abs(sprintf(logs_dir_tmpl, experiment_id))
report_dir_path <- fs::path_abs(sprintf(reports_dir_tmpl, experiment_id))
plot_dir_path <- fs::path_abs(sprintf(plots_dir_tmpl, experiment_id))
table_dir_path <- fs::path_abs(sprintf(tables_dir_tmpl, experiment_id))

# ターゲット実行ログファイルのフルパス
log_file_path <- fs::path(log_dir_path, "_targets.log")


# --- 入力ファイル設定 ---

# 入力ファイルのパスを生成するためのテンプレート
# `%s` は experiment_id で置き換えられます
counts_file_path_tmpl <- "data/%s/counts.csv"           # 発現カウントデータファイル
metadata_file_path_tmpl <- "data/%s/sample_metadata.csv" # サンプルメタデータファイル

# 入力データファイル内で使用される列名
gene_id_col <- "gene_id"      # 遺伝子IDが含まれる列の名前
sample_id_col <- "sample_id"    # サンプルIDが含まれる列の名前 (メタデータで使用)


# --- BiomaRt 設定 ---
# Ensembl BioMart から遺伝子アノテーションを取得するための設定
biomart_host_cfg <- "https://ensembl.org" # 接続する BioMart ホスト
biomart_dataset_cfg <- "hsapiens_gene_ensembl" # 使用するデータセット (例: ヒト)
biomart_attributes_cfg <- c(              # 取得する遺伝子属性
  "ensembl_gene_id",    # Ensembl 遺伝子ID
  "external_gene_name", # 一般的な遺伝子名 (HGNC symbolなど)
  "transcript_length",  # 転写産物長 (TPM計算などに利用可能)
  "gene_biotype"        # 遺伝子の種類 (protein_coding, lncRNAなど)
)


# --- R Markdown レポート設定 ---

# R Markdown ファイルをレンダリングする際の共通設定
# 出力フォーマット (例: "html_document", "pdf_document")
common_output_format <- "html_document"
# 出力フォーマットごとのオプション (rmarkdown::render の output_options 引数に対応)
rmd_output_options <- list(
  toc = TRUE,            # 目次(Table of Contents)を表示するかどうか
  toc_float = TRUE,      # 目次をサイドバーにフロート表示するかどうか
  code_folding = "hide", # コードチャンクをデフォルトで折りたたむか ("none", "show", "hide")
  keep_md = TRUE         # レンダリング後の中間マークダウンファイルを保持するかどうか
)


# --- ターゲットリスト定義開始 ---
list(
  # ターゲット 0: 必要なディレクトリを作成し、ロガーを設定（常に実行）
  tar_target(
    name = ensure_directories,
    command = {
      # ログとレポートのディレクトリを作成
      fs::dir_create(log_dir_path)
      fs::dir_create(report_dir_path)
      # 必要であれば他のディレクトリも作成
      fs::dir_create(plot_dir_path)
      fs::dir_create(table_dir_path)
      
      # モジュール別ディレクトリを作成
      module_name <- "deg_edgeR"
      # サンプルグループごとのディレクトリを作成
      sample_groups <- c("hct116_ifitm3", "hct116_tab3", "sw620_ifitm3", "sw620_tab3")
      
      # 各サンプルグループに対するプロットディレクトリとテーブルディレクトリを作成
      group_plot_dirs <- list()
      group_table_dirs <- list()
      
      for (group in sample_groups) {
        # プロットディレクトリ
        group_plot_dir <- fs::path(plot_dir_path, module_name, group)
        fs::dir_create(group_plot_dir, recurse = TRUE)
        group_plot_dirs[[group]] <- group_plot_dir
        
        # テーブルディレクトリ
        group_table_dir <- fs::path(table_dir_path, module_name, group)
        fs::dir_create(group_table_dir, recurse = TRUE)
        group_table_dirs[[group]] <- group_table_dir
      }

      # _targets.logファイルを初期化（パイプライン開始時に古いログを削除）
      if (fs::file_exists(log_file_path)) {
        fs::file_delete(log_file_path)
      }

      # --- ロギング設定 (ディレクトリ作成後に行う) ---
      # _targets.R 用のカスタムレイアウト関数を定義
      custom_layout <- function(level, msg, ...) {
        # メッセージ内の書式指定子を処理
        if (length(list(...)) > 0) {
          msg <- do.call(sprintf, c(list(msg), list(...)))
        }
        
        # 最終的なログメッセージ形式を作成
        formatted_msg <- sprintf("[%s] [%s] [_targets.R] %s\n", 
                                format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                                level,
                                msg)
        return(formatted_msg)
      }
      
      # _targets.log ファイルへのアペンダーを設定
      flog.appender(appender.file(log_file_path))
      flog.layout(custom_layout)
      flog.threshold(INFO)

      flog.info("必要なディレクトリを作成し、ロガーを初期化しました (experiment_id: %s)", experiment_id)
      flog.info("ログファイルは %s に書き込まれます", log_file_path)
      flog.info("レポートディレクトリ: %s", report_dir_path)
      flog.info("プロットディレクトリ: %s", plot_dir_path)
      flog.info("テーブルディレクトリ: %s", table_dir_path)
      flog.info("サンプルグループごとのプロットディレクトリとテーブルディレクトリを作成しました")

      # このターゲットが生成するものを明示するためにパスのリストを返す
      return(list(
        log_dir = log_dir_path, 
        report_dir = report_dir_path,
        plot_dir = plot_dir_path,
        table_dir = table_dir_path,
        group_plot_dirs = group_plot_dirs,
        group_table_dirs = group_table_dirs
      ))
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
  ),
  
  # HCT116 & IFITM3 のDEG解析
  tar_target(
    name = rmd_deg_hct116_ifitm3,
    command = {
      dir_paths <- ensure_directories
      se_object <- obj_se_raw
      flog.info("ターゲット開始: rmd_deg_hct116_ifitm3 (DEG解析 HCT116 & IFITM3)")
      
      # サンプルグループ名
      sample_group <- "hct116_ifitm3"
      
      # 出力パスを構築
      output_path <- fs::path(dir_paths$report_dir, "deg_hct116_ifitm3.html")
      
      # グループ固有のプロットディレクトリとテーブルディレクトリを取得
      group_plot_dir <- dir_paths$group_plot_dirs[[sample_group]]
      group_table_dir <- dir_paths$group_table_dirs[[sample_group]]
      
      # レンダリング環境を作成
      render_env <- new.env()
      
      # deg_edgeR.Rmdをレンダリング
      rmarkdown::render(
        input = fs::path_abs("Rmd/deg_edgeR.Rmd"),
        output_file = output_path,
        output_format = common_output_format,
        output_options = rmd_output_options,
        params = list(
          experiment_id = experiment_id,
          input_se = se_object,
          output_dir = dir_paths$report_dir,
          plot_dir = group_plot_dir,
          table_dir = group_table_dir,
          filter_columns = list(cell_line = "HCT116", target_gene = "IFITM3"),
          control = "scramble",
          targets = c("sh1", "sh2"),
          condition_column = "condition",
          housekeeping_gene_set = "standard",
          fdr_threshold = 0.05,
          log2fc_threshold = 1
        ),
        envir = render_env,
        quiet = TRUE,
        knit_root_dir = fs::path_abs(".")
      )
      
      flog.info("deg_edgeR.Rmd のレンダリング完了: %s", output_path)
      flog.info("プロット保存先: %s", group_plot_dir)
      flog.info("テーブル保存先: %s", group_table_dir)
      
      # レンダリング環境から結果のSEオブジェクトを取得
      if (!exists("se", envir = render_env)) {
        msg <- "deg_edgeR.Rmd の実行環境で 'se' オブジェクトが見つかりません。"
        flog.fatal(msg)
        stop(msg)
      }
      result_se <- get("se", envir = render_env)
      
      flog.info("ターゲット完了: rmd_deg_hct116_ifitm3")
      return(result_se)
    }
  ),
  
  # HCT116 & TAB3 のDEG解析
  tar_target(
    name = rmd_deg_hct116_tab3,
    command = {
      dir_paths <- ensure_directories
      se_object <- obj_se_raw
      flog.info("ターゲット開始: rmd_deg_hct116_tab3 (DEG解析 HCT116 & TAB3)")
      
      # サンプルグループ名
      sample_group <- "hct116_tab3"
      
      # 出力パスを構築
      output_path <- fs::path(dir_paths$report_dir, "deg_hct116_tab3.html")
      
      # グループ固有のプロットディレクトリとテーブルディレクトリを取得
      group_plot_dir <- dir_paths$group_plot_dirs[[sample_group]]
      group_table_dir <- dir_paths$group_table_dirs[[sample_group]]
      
      # レンダリング環境を作成
      render_env <- new.env()
      
      # deg_edgeR.Rmdをレンダリング
      rmarkdown::render(
        input = fs::path_abs("Rmd/deg_edgeR.Rmd"),
        output_file = output_path,
        output_format = common_output_format,
        output_options = rmd_output_options,
        params = list(
          experiment_id = experiment_id,
          input_se = se_object,
          output_dir = dir_paths$report_dir,
          plot_dir = group_plot_dir,
          table_dir = group_table_dir,
          filter_columns = list(cell_line = "HCT116", target_gene = "TAB3"),
          control = "scramble",
          targets = c("sh1", "sh2"),
          condition_column = "condition",
          housekeeping_gene_set = "standard",
          fdr_threshold = 0.05,
          log2fc_threshold = 1
        ),
        envir = render_env,
        quiet = TRUE,
        knit_root_dir = fs::path_abs(".")
      )
      
      flog.info("deg_edgeR.Rmd のレンダリング完了: %s", output_path)
      flog.info("プロット保存先: %s", group_plot_dir)
      flog.info("テーブル保存先: %s", group_table_dir)
      
      # レンダリング環境から結果のSEオブジェクトを取得
      if (!exists("se", envir = render_env)) {
        msg <- "deg_edgeR.Rmd の実行環境で 'se' オブジェクトが見つかりません。"
        flog.fatal(msg)
        stop(msg)
      }
      result_se <- get("se", envir = render_env)
      
      flog.info("ターゲット完了: rmd_deg_hct116_tab3")
      return(result_se)
    }
  ),
  
  # SW620 & IFITM3 のDEG解析
  tar_target(
    name = rmd_deg_sw620_ifitm3,
    command = {
      dir_paths <- ensure_directories
      se_object <- obj_se_raw
      flog.info("ターゲット開始: rmd_deg_sw620_ifitm3 (DEG解析 SW620 & IFITM3)")
      
      # サンプルグループ名
      sample_group <- "sw620_ifitm3"
      
      # 出力パスを構築
      output_path <- fs::path(dir_paths$report_dir, "deg_sw620_ifitm3.html")
      
      # グループ固有のプロットディレクトリとテーブルディレクトリを取得
      group_plot_dir <- dir_paths$group_plot_dirs[[sample_group]]
      group_table_dir <- dir_paths$group_table_dirs[[sample_group]]
      
      # レンダリング環境を作成
      render_env <- new.env()
      
      # deg_edgeR.Rmdをレンダリング
      rmarkdown::render(
        input = fs::path_abs("Rmd/deg_edgeR.Rmd"),
        output_file = output_path,
        output_format = common_output_format,
        output_options = rmd_output_options,
        params = list(
          experiment_id = experiment_id,
          input_se = se_object,
          output_dir = dir_paths$report_dir,
          plot_dir = group_plot_dir,
          table_dir = group_table_dir,
          filter_columns = list(cell_line = "SW620", target_gene = "IFITM3"),
          control = "scramble",
          targets = c("sh1", "sh2"),
          condition_column = "condition",
          housekeeping_gene_set = "standard",
          fdr_threshold = 0.05,
          log2fc_threshold = 1
        ),
        envir = render_env,
        quiet = TRUE,
        knit_root_dir = fs::path_abs(".")
      )
      
      flog.info("deg_edgeR.Rmd のレンダリング完了: %s", output_path)
      flog.info("プロット保存先: %s", group_plot_dir)
      flog.info("テーブル保存先: %s", group_table_dir)
      
      # レンダリング環境から結果のSEオブジェクトを取得
      if (!exists("se", envir = render_env)) {
        msg <- "deg_edgeR.Rmd の実行環境で 'se' オブジェクトが見つかりません。"
        flog.fatal(msg)
        stop(msg)
      }
      result_se <- get("se", envir = render_env)
      
      flog.info("ターゲット完了: rmd_deg_sw620_ifitm3")
      return(result_se)
    }
  ),
  
  # SW620 & TAB3 のDEG解析
  tar_target(
    name = rmd_deg_sw620_tab3,
    command = {
      dir_paths <- ensure_directories
      se_object <- obj_se_raw
      flog.info("ターゲット開始: rmd_deg_sw620_tab3 (DEG解析 SW620 & TAB3)")
      
      # サンプルグループ名
      sample_group <- "sw620_tab3"
      
      # 出力パスを構築
      output_path <- fs::path(dir_paths$report_dir, "deg_sw620_tab3.html")
      
      # グループ固有のプロットディレクトリとテーブルディレクトリを取得
      group_plot_dir <- dir_paths$group_plot_dirs[[sample_group]]
      group_table_dir <- dir_paths$group_table_dirs[[sample_group]]
      
      # レンダリング環境を作成
      render_env <- new.env()
      
      # deg_edgeR.Rmdをレンダリング
      rmarkdown::render(
        input = fs::path_abs("Rmd/deg_edgeR.Rmd"),
        output_file = output_path,
        output_format = common_output_format,
        output_options = rmd_output_options,
        params = list(
          experiment_id = experiment_id,
          input_se = se_object,
          output_dir = dir_paths$report_dir,
          plot_dir = group_plot_dir,
          table_dir = group_table_dir,
          filter_columns = list(cell_line = "SW620", target_gene = "TAB3"),
          control = "scramble",
          targets = c("sh1", "sh2"),
          condition_column = "condition",
          housekeeping_gene_set = "standard",
          fdr_threshold = 0.05,
          log2fc_threshold = 1
        ),
        envir = render_env,
        quiet = TRUE,
        knit_root_dir = fs::path_abs(".")
      )
      
      flog.info("deg_edgeR.Rmd のレンダリング完了: %s", output_path)
      flog.info("プロット保存先: %s", group_plot_dir)
      flog.info("テーブル保存先: %s", group_table_dir)
      
      # レンダリング環境から結果のSEオブジェクトを取得
      if (!exists("se", envir = render_env)) {
        msg <- "deg_edgeR.Rmd の実行環境で 'se' オブジェクトが見つかりません。"
        flog.fatal(msg)
        stop(msg)
      }
      result_se <- get("se", envir = render_env)
      
      flog.info("ターゲット完了: rmd_deg_sw620_tab3")
      return(result_se)
    }
  )
)
