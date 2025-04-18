```yaml
---
title: "RNA-seq解析: `r params$module_name` (実験ID: `r params$exp_id`)"
output:
  html_document:
    toc: true
    toc_float: true
    code_folding: "hide"
  md_document:
    variant: "gfm"
params:
  exp_id: NA
  module_name: NA
  input_se: NA
  output_se: NA
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(
  echo = TRUE,
  warning = FALSE,
  message = FALSE,
  fig.path = fs::path_abs(sprintf("results/%s/plots/%s/", params$exp_id, params$module_name))
)

# 必要なライブラリ
library(targets)
library(SummarizedExperiment)
library(futile.logger)
library(fs)

# ログ設定
log_dir <- fs::path_abs(sprintf("logs/%s", params$exp_id))
if (!fs::dir_exists(log_dir)) fs::dir_create(log_dir, recurse = TRUE)
log_file <- fs::path(log_dir, paste0(params$module_name, ".log"))
flog.logger(params$module_name)
flog.threshold(INFO)
flog.layout(layout.format(paste0("[%t] [%l] [", params$module_name, "] %m")))
flog.appender(appender.file(log_file))

# 出力ディレクトリ
plot_dir <- fs::path_abs(sprintf("results/%s/plots/%s", params$exp_id, params$module_name))
table_dir <- fs::path_abs(sprintf("results/%s/tables/%s", params$exp_id, params$module_name))
if (!fs::dir_exists(plot_dir)) fs::dir_create(plot_dir, recurse = TRUE)
if (!fs::dir_exists(table_dir)) fs::dir_create(table_dir, recurse = TRUE)

flog.info("====== モジュール実行開始: %s ======", params$module_name)
```

# モジュール概要

```{r load_data}
# データ読み込み
se <- tar_read(params$input_se)
flog.info("入力SEオブジェクト: %d サンプル, %d 遺伝子", ncol(se), nrow(se))
```

# 解析

```{r analysis}
# 解析コード（必要に応じて変更）
flog.info("解析を実行します")

# ここに解析コードを記述

flog.info("解析が完了しました")
```

# 結果

```{r results, echo=FALSE}
# 結果の表示（必要に応じて変更）
```

# SEオブジェクト更新

```{r update_se}
# パイプライン履歴メタデータの初期化
if (is.null(metadata(se)$pipeline_history)) {
  metadata(se)$pipeline_history <- list()
}

# モジュール実行情報をメタデータに追加
module_info <- list(
  module_name = params$module_name,
  execution_time = Sys.time(),
  parameters = list(),
  results = list()
)

# パイプライン履歴に追加
metadata(se)$pipeline_history[[params$module_name]] <- module_info
flog.info("SEオブジェクトのメタデータを更新しました")

# 更新されたSEオブジェクトを返す
```

```{r session_info, echo=FALSE}
sessionInfo()
flog.info("====== モジュール実行完了 ======")
``` 