# _targets.R 仕様書

## 概要
本ドキュメントは、RNA-seqデータ解析パイプラインの制御ファイル「_targets.R」の設計仕様を定義します。このパイプラインは`targets`パッケージを用いた依存関係管理システムで、実験IDをパラメータとして、同一の解析フローを異なるデータセットに適用することができます。

## 基本情報
- **ファイル名**: `_targets.R`
- **目的**: RNA-seqパイプラインの実行制御と依存関係管理
- **依存ライブラリ**: targets, tarchetypes, yaml, fs, futile.logger
- **入力**: 設定ファイル (`config.yaml`) とカウントデータ
- **出力**: ログファイルとSummarizedExperimentオブジェクト

## ファイル構成

### 1. ライブラリ読み込み
```r
library(targets)
library(tarchetypes)
library(yaml)
library(fs)
library(futile.logger)

# ユーティリティ関数の読み込み
source("R/utility.R")
```

### 2. ターゲットオプション設定
```r
tar_option_set(
  packages = c("SummarizedExperiment", "readr", "dplyr", "tibble", "cli", "S4Vectors", "yaml", "futile.logger", "fs"),
  format = "rds" # デフォルトの保存形式
)
```

### 3. 設定ファイル読み込みと変数設定
```r
# config.yaml から設定を読み込む
config <- yaml::read_yaml("config.yaml")

# 実験ID（必須パラメータ）
experiment_id <- config$experiment_id
if (is.null(experiment_id)) {
  stop("experiment_id が config.yaml に見つかりません")
}

# パスの設定
log_dir_path <- fs::path_abs(sprintf("logs/%s", experiment_id))
log_file_path <- fs::path(log_dir_path, "_targets.log")
report_dir_path <- fs::path_abs(sprintf("results/%s/reports", experiment_id))

# 入力ファイルパスのテンプレート
counts_file_path_tmpl <- config$counts_file_template %||% "data/%s/counts.csv"
metadata_file_path_tmpl <- config$metadata_file_template %||% "data/%s/sample_metadata.csv"

# パラメータ設定
gene_id_col <- config$gene_id_column %||% "gene_id"
sample_id_col <- config$sample_id_column %||% "sample_id"

# biomaRt設定
biomart_dataset_cfg <- config$biomart_dataset
if (is.null(biomart_dataset_cfg)) {
  stop("biomart_dataset は config.yaml で指定する必要があります")
}
biomart_host_cfg <- config$biomart_host %||% "https://ensembl.org"
biomart_attributes_cfg <- config$biomart_attributes %||% c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")

# Rmd出力設定
common_output_format <- "html_document"
rmd_output_options <- list(
  toc = TRUE,
  toc_float = TRUE,
  code_folding = "hide",
  keep_md = TRUE
)
```

## ターゲット定義

### ターゲット1: ensure_directories
**目的**: 必要なディレクトリ構造を作成し、ロガーを設定する

**入力**: なし（常に実行）

**処理**:
- ログディレクトリとレポートディレクトリを作成
- 既存のログファイルをローテーション
- `futile.logger`を設定して実行開始をログに記録

**出力**: 作成したディレクトリパスのリスト

**コード**:
```r
tar_target(
  name = ensure_directories,
  command = {
    # ログとレポートのディレクトリを作成
    fs::dir_create(log_dir_path)
    fs::dir_create(report_dir_path)
    
    # ログファイルのローテーション
    log_file_path_before <- fs::path(log_dir_path, "_targets_before.log")
    if (fs::file_exists(log_file_path)) {
      if (fs::file_exists(log_file_path_before)) {
        fs::file_delete(log_file_path_before)
      }
      flog.info("既存のログファイル %s を %s に移動します", log_file_path, log_file_path_before)
      fs::file_move(log_file_path, log_file_path_before)
    }
    
    # ロギング設定
    flog.appender(appender.tee(log_file_path))
    flog.layout('[%t] [%l] [_targets.R] %m')
    flog.threshold(INFO)
    flog.info("必要なディレクトリを作成し、ロガーを初期化しました (experiment_id: %s)", experiment_id)
    
    # パスのリストを返す
    return(list(log_dir = log_dir_path, report_dir = report_dir_path))
  },
  cue = tar_cue(mode = "always") # 毎回実行
)
```

### ターゲット2: obj_se_raw
**目的**: 生のカウントデータからSummarizedExperimentオブジェクトを作成

**入力**: 
- ensure_directories（依存関係）
- 設定ファイルから読み込んだ実験パラメータ

**処理**:
- 入力ファイルパスを構築（実験IDに基づく）
- Rmdモジュール（create_se.Rmd）をレンダリング
- レンダリング環境からSEオブジェクトを取得

**出力**: SummarizedExperimentオブジェクト

**コード**:
```r
tar_target(
  name = obj_se_raw,
  command = {
    # ensure_directories が実行されるようにコマンド内で参照
    dir_paths <- ensure_directories
    flog.info("ターゲット開始: obj_se_raw")

    # 入力ファイルのパスを作成
    counts_path <- fs::path_abs(sprintf(counts_file_path_tmpl, experiment_id))
    metadata_path <- fs::path_abs(sprintf(metadata_file_path_tmpl, experiment_id))
    
    # 出力パスを構築
    output_path <- fs::path(dir_paths$report_dir, "create_se.html")
    
    # render 用の環境を作成
    render_env <- new.env()
    
    # Rmd をレンダリング
    rmarkdown::render(
      input = fs::path_abs("Rmd/create_se.Rmd"),
      output_file = output_path,
      output_format = common_output_format,
      output_options = rmd_output_options,
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
      envir = render_env,
      quiet = TRUE,
      knit_root_dir = fs::path_abs(".")
    )
    
    # render_env から SE オブジェクトを取得
    if (!exists("se", envir = render_env)) {
      msg <- "create_se.Rmd の実行環境で 'se' オブジェクトが見つかりません。"
      flog.fatal(msg)
      stop(msg)
    }
    se_object <- get("se", envir = render_env)
    
    # SE オブジェクトのクラス確認
    flog.info("SEオブジェクトのクラス: %s", paste(class(se_object), collapse=", "))
    
    flog.info("ターゲット完了: obj_se_raw")
    return(se_object)
  }
)
```

## ロギング仕様
- **ログレベル**: `_targets.R`では基本的に`INFO`以上を記録
- **ロガー名**: `[_targets.R]`をログメッセージに含める
- **タイムスタンプ形式**: `[YYYY-MM-DD HH:MM:SS]`
- **ログファイルパス**: `logs/{experiment_id}/_targets.log`
- **ローテーション**: パイプライン実行前にログファイルをバックアップ

## エラーハンドリング
- 設定ファイル読み込み失敗時は明示的なエラーメッセージを表示
- Rmdレンダリング失敗時はエラーをキャッチしログに記録
- SEオブジェクト取得失敗時は適切なエラーメッセージを表示

## 拡張性
現在のパイプラインは以下の2ステップで構成:
1. ディレクトリ作成（ensure_directories）
2. SEオブジェクト作成（obj_se_raw）

将来的に以下のようなターゲットを追加することで拡張可能:
- 品質管理（QC）ターゲット
- フィルタリングターゲット
- 正規化ターゲット
- 差異発現解析ターゲット
- 機能エンリッチメント解析ターゲット

## 実行方法
```r
# パイプライン全体を実行
targets::tar_make()

# 特定のターゲットのみを実行
targets::tar_make(obj_se_raw)

# パイプラインの状態を可視化
targets::tar_visnetwork()
```

## 注意点と制約
- `experiment_id`はパイプラインの基本単位となる重要なパラメータ
- 入出力ファイルのパスは基本的に`fs::path_abs()`を使用して絶対パスで扱う
- biomaRt設定は実験対象の生物種に応じて適切に設定する必要がある
- ログ出力とコンソール出力は別々に管理し、HTMLレポートにログメッセージを含めない 