# R MarkdownモジュールとRNAseqパイプラインテンプレート

## 1. 概要

このテンプレートは、RNA-seqパイプラインにおけるR Markdownモジュール（`tar_render`で実行される）の実装方法を定義します。パラメータ設定、ログ出力、_targets.Rでのターゲット設定などの規格化を目的としています。

## 2. R Markdownモジュールの基本構造

### 2.1 YAMLヘッダ

```yaml
---
title: "RNA-seq解析: [モジュール名] (実験ID: `r params$experiment_id`)"
date: "`r format(Sys.time(), '%Y-%m-%d %H:%M:%S')`"
params:
  experiment_id: "default_id"
  # 入力ファイル/オブジェクト
  input_se: NULL  # 前段階のSummarizedExperimentオブジェクト
  # 出力設定
  output_dir: ""  # 結果出力ディレクトリ（通常は_targets.Rから渡される）
  plot_dir: ""    # プロット出力ディレクトリ
  table_dir: ""   # テーブル出力ディレクトリ
  # 処理パラメータ
  param1: "default_value"
  param2: 10
  # 以下必要に応じて追加
---
```

### 2.2 セットアップチャンク（必須）

```r
```{r setup, include=FALSE}
# このチャンクはRmdファイルが読み込まれた時に最初に実行され、必要なパッケージの読み込みと設定を行う
library(futile.logger)
library(SummarizedExperiment)
library(here)
library(fs)
library(ggplot2)
library(dplyr)
library(knitr)
# 必要なパッケージを追加

# utility関数を読み込む
source(here("R", "utility.R"))

# ログ設定
# utility.Rで定義したsetup_logger関数を使用
module_name <- "[モジュール名]"  # ここをモジュール名に変更
logger_settings <- setup_logger(params$experiment_id, module_name)
flog.appender(logger_settings$appender)
flog.layout(logger_settings$layout)
flog.threshold(logger_settings$threshold)

# knitrオプションを設定 - メッセージと警告を表示しない
knitr::opts_chunk$set(
  message = FALSE, 
  warning = FALSE, 
  fig.width = 10,
  fig.height = 6,
  dpi = 300
)

# タイムスタンプの一貫性のためにタイムゾーンを統一
Sys.setenv(TZ = "Asia/Tokyo")

# グラフのテーマ設定
theme_set(theme_classic())

# 既存のオブジェクトをクリーンアップ（paramsは保持）
rm(list = setdiff(ls(), c("params")))

flog.info("--- セットアップ：R Markdownドキュメントを実行開始 ---")
flog.info("パラメータ情報: experiment_id = %s", params$experiment_id)
flog.debug("出力ディレクトリ: %s", params$output_dir)
flog.debug("プロットディレクトリ: %s", params$plot_dir)
flog.debug("テーブルディレクトリ: %s", params$table_dir)
# 他のパラメータもログに記録
flog.info("セットアップ完了")
```

### 2.3 入力データ確認チャンク（必須）

```r
```{r check_input, include=FALSE}
flog.info("--- 入力データの確認開始 ---")

# 入力SEオブジェクトの存在確認と基本チェック
if (is.null(params$input_se)) {
  # 初期モジュール（create_se等）の場合はこのチェックをスキップ
  flog.info("入力SEオブジェクトはNULLです（初期モジュールの場合は正常）")
} else {
  # SEオブジェクトのクラスと次元を確認
  if (!inherits(params$input_se, "SummarizedExperiment")) {
    msg <- "入力オブジェクトはSummarizedExperimentではありません"
    flog.error(msg)
    stop(msg)
  }
  
  flog.info("入力SEオブジェクトを確認: %d フィーチャー, %d サンプル", 
            nrow(params$input_se), ncol(params$input_se))
  flog.debug("入力SEオブジェクトの基本情報:")
  flog.debug("- assay名: %s", paste(assayNames(params$input_se), collapse=", "))
  flog.debug("- rowData列: %s", paste(colnames(rowData(params$input_se)), collapse=", "))
  flog.debug("- colData列: %s", paste(colnames(colData(params$input_se)), collapse=", "))
  flog.debug("- metadata: %s", paste(names(metadata(params$input_se)), collapse=", "))
}

# 出力ディレクトリの確認と作成
if (!is.null(params$plot_dir) && params$plot_dir != "") {
  if (!fs::dir_exists(params$plot_dir)) {
    flog.info("プロットディレクトリを作成します: %s", params$plot_dir)
    fs::dir_create(params$plot_dir, recursive = TRUE)
  }
}

if (!is.null(params$table_dir) && params$table_dir != "") {
  if (!fs::dir_exists(params$table_dir)) {
    flog.info("テーブルディレクトリを作成します: %s", params$table_dir)
    fs::dir_create(params$table_dir, recursive = TRUE)
  }
}

flog.info("--- 入力データの確認完了 ---")
```

### 2.4 主要解析チャンク（モジュール固有）

```r
```{r main_analysis, include=FALSE}
flog.info("--- 主要解析開始 ---")

# ここにモジュール固有の解析コードを記述
# 以下は例：

# 入力SEオブジェクトをコピー（変更する場合）
se <- params$input_se

# 解析を実行
# ...解析コード...

flog.info("--- 主要解析完了 ---")
```

### 2.5 結果可視化チャンク（レポート表示用）

```r
```{r visualize_results}
# ここに可視化コードを記述
# このチャンクはHTMLに表示されるので、flog出力は避ける

# 例：プロット表示
ggplot(data.frame(x = 1:10, y = 1:10), aes(x, y)) + 
  geom_point() + 
  labs(title = "サンプルプロット")
```

### 2.6 出力ファイル保存チャンク（必須）

```r
```{r save_outputs, include=FALSE}
flog.info("--- 出力ファイル保存開始 ---")

# プロットの保存例
if (!is.null(params$plot_dir) && params$plot_dir != "") {
  plot_path <- fs::path(params$plot_dir, "example_plot.png")
  flog.debug("プロットを保存: %s", plot_path)
  
  # プロットを保存
  ggsave(
    filename = plot_path,
    plot = last_plot(),  # または特定のプロットオブジェクト
    width = 10,
    height = 6,
    dpi = 300
  )
}

# テーブルの保存例
if (!is.null(params$table_dir) && params$table_dir != "") {
  table_path <- fs::path(params$table_dir, "example_table.csv")
  flog.debug("テーブルを保存: %s", table_path)
  
  # データフレームを保存（例）
  example_df <- data.frame(x = 1:10, y = 1:10)
  write.csv(example_df, file = table_path, row.names = FALSE)
}

flog.info("--- 出力ファイル保存完了 ---")
```

### 2.7 パイプライン履歴記録と返り値（必須）

```r
```{r record_history, include=FALSE}
flog.info("--- パイプライン履歴記録開始 ---")

# SEオブジェクトのメタデータに処理履歴を記録
se <- record_pipeline_history(
  se = se,
  module_name = module_name,
  description = "モジュールの説明",
  parameters = list(
    experiment_id = params$experiment_id,
    # その他のパラメータ
    param1 = params$param1,
    param2 = params$param2
  )
)

flog.info("パイプライン履歴を記録しました: pipeline_history$%s", module_name)
flog.info("--- パイプライン履歴記録完了 ---")
```

### 2.8 セッション情報（必須）

```r
```{r session_info}
# セッション情報の表示（パイプラインの再現性のため）
sessionInfo()
```

### 2.9 返り値設定（必須）

```r
```{r return_se, echo=FALSE, include=FALSE}
# targetsパッケージで使用するための戻り値を設定
flog.info("--- %s.Rmd 実行終了、SEオブジェクトを返します ---", module_name)
return(se)
```

## 3. _targets.Rでのモジュール設定方法

```r
# ターゲット定義例：新しいRmdモジュールの追加
tar_target(
  name = obj_se_[処理ステップ名],  # obj_se_filtered など
  command = {
    # 前のターゲットを参照
    se_object <- obj_se_[前ステップ名]
    
    # ディレクトリパスを設定
    flog.info("ターゲット開始: obj_se_[処理ステップ名]")
    plot_output_dir <- fs::path(plot_dir_path, "[処理ステップ名]")
    table_output_dir <- fs::path(table_dir_path, "[処理ステップ名]")
    
    # 必要なディレクトリを作成
    fs::dir_create(plot_output_dir, recurse = TRUE)
    fs::dir_create(table_output_dir, recurse = TRUE)
    
    # レポート出力パス
    output_path <- fs::path(report_dir_path, "[処理ステップ名].html")
    
    # Rmd環境を作成
    render_env <- new.env()
    
    # Rmdをレンダリング
    rmarkdown::render(
      input = fs::path_abs("Rmd/[処理ステップ名].Rmd"),
      output_file = output_path,
      output_format = common_output_format,  # _targets.Rで定義された共通フォーマット
      output_options = rmd_output_options,   # _targets.Rで定義された共通オプション
      params = list(
        experiment_id = experiment_id,
        input_se = se_object,  # 前段階のSEオブジェクト
        output_dir = fs::path_abs(report_dir_path),
        plot_dir = fs::path_abs(plot_output_dir),
        table_dir = fs::path_abs(table_output_dir),
        # モジュール固有のパラメータ
        param1 = "value1",
        param2 = 42
      ),
      envir = render_env,
      quiet = TRUE,
      knit_root_dir = fs::path_abs(".")
    )
    
    flog.info("[処理ステップ名].Rmd のレンダリング完了: %s", output_path)
    
    # レンダリング環境からSEオブジェクトを取得
    if (!exists("se", envir = render_env)) {
      msg <- "[処理ステップ名].Rmd の実行環境で 'se' オブジェクトが見つかりません。"
      flog.fatal(msg)
      stop(msg)
    }
    se_result <- get("se", envir = render_env)
    
    # SEオブジェクトの確認
    flog.info("取得したSEオブジェクト: %d フィーチャー, %d サンプル", 
              nrow(se_result), ncol(se_result))
    
    flog.info("ターゲット完了: obj_se_[処理ステップ名]")
    return(se_result)
  }
)
```

## 4. テスト作成のテンプレート

```r
# [module_name].Rmdのテスト

library(testthat)
library(SummarizedExperiment)
library(here)
library(fs)

# 共通の実験ID
EXPERIMENT_ID <- "test_experiment"
MODULE_NAME <- "[module_name]"  # テスト対象のモジュール名に変更

# 共通の出力ディレクトリ設定関数
setup_test_dirs <- function(test_condition) {
  results_dir <- here("results", EXPERIMENT_ID)
  return(list(
    results_dir = results_dir,
    output_html = file.path(results_dir, paste0(MODULE_NAME, "-", test_condition, ".html"))
  ))
}

test_that("基本機能: [module_name].Rmd が正常にSEオブジェクトを作成・更新する", {
  # テストデータの準備
  input_se <- SummarizedExperiment(
    assays = list(counts = matrix(1:12, nrow = 3, ncol = 4)),
    rowData = DataFrame(gene_id = paste0("gene", 1:3)),
    colData = DataFrame(sample_id = paste0("sample", 1:4))
  )
  metadata(input_se)$experiment_id <- EXPERIMENT_ID
  
  # 出力ディレクトリの設定
  test_condition <- "basic"
  dirs <- setup_test_dirs(test_condition)
  
  # パラメータ設定
  params <- list(
    experiment_id = EXPERIMENT_ID,
    input_se = input_se,
    output_dir = dirs$results_dir,
    plot_dir = file.path(dirs$results_dir, "plots"),
    table_dir = file.path(dirs$results_dir, "tables"),
    # モジュール固有のパラメータ
    param1 = "test_value",
    param2 = 10
  )
  
  # Rmdをレンダリング
  se <- render_with_biomart_mock(
    input_rmd_path = here("Rmd", paste0(MODULE_NAME, ".Rmd")),
    output_file_path = dirs$output_html,
    params_list = params,
    test_condition = test_condition
  )
  
  # SEオブジェクトの検証
  expect_s4_class(se, "SummarizedExperiment")
  expect_equal(metadata(se)$experiment_id, EXPERIMENT_ID)
  expect_true("pipeline_history" %in% names(metadata(se)))
  expect_true(MODULE_NAME %in% names(metadata(se)$pipeline_history))
  
  # モジュール固有の検証
  # 例：expect_true("normalized_counts" %in% assayNames(se))
})
```
