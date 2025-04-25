\
# Rmdモジュール仕様書: se_basic_info.Rmd

## 1. 概要
- **目的:** `targets` パイプラインから渡された SummarizedExperiment (SE) オブジェクトの基本的な構造と内容を確認するためのレポートを生成する。開発者や解析者がデータの中身を素早く把握することを目的とする。
- **レポート種類:** データ概要レポート
- **作成日:** 2025-04-25
- **更新日:** 2024-04-25

## 2. レポート内容詳細
- このRmdモジュールは以下の情報を含むレポートを生成する:
  - 入力されたSEオブジェクトの基本情報 (クラス、次元数、アッセイ名リスト)。
  - SEオブジェクトに含まれる各アッセイデータの先頭10行を表示 (静的なテーブル形式、例: `knitr::kable`)。
  - `colData` (サンプルメタデータ) の全内容を静的なテーブル形式で表示 (例: `knitr::kable`)。
  - `rowData` (フィーチャーメタデータ) の先頭10行を静的なテーブル形式で表示 (例: `knitr::kable`)。
  - ライブラリサイズ (サンプルごとの合計カウント数) のバープロットを表示。
  - ログ変換 (例: log1p) されたカウントデータの密度プロット (アッセイ名を指定可能) を表示。
- `project-rule.md` におけるデータQCや探索的データ解析 (EDA) の初期ステップに対応する。

## 3. 入力パラメータ (params)
- **パラメータ名:** `experiment_id`
  - **データ型:** `character`
  - **説明:** 解析対象の実験ID。ログファイルや出力ディレクトリのパス生成に使用される。`_targets.R` から渡される。
  - **必須/任意:** 必須
  - **デフォルト値:** なし (パイプライン実行時に指定)
- **パラメータ名:** `input_se_target`
  - **データ型:** `character`
  - **説明:** レポートで表示するSEオブジェクトを生成した `targets` ターゲットの名前。この名前を使って `tar_read()` でオブジェクトを読み込む。 (**注意:** このパラメータは依存ターゲットのシンボル名を決定するために使用されるが、Rmd内での `tar_read` は固定シンボル名 (`obj_se_input`) で行う。)
  - **必須/任意:** 必須
  - **デフォルト値:** なし

## 4. 依存ターゲット
- このRmdモジュールが `targets::tar_read(シンボル名)` で読み込む `targets` オブジェクトを **固定のシンボル名で** リストアップする。
- **ターゲット名:** `obj_se_input` (**シンボル名**)
  - **データ型:** `SummarizedExperiment`
  - **説明:** レポートで表示する主要なデータオブジェクト。`_targets.R` 内で `params$input_se_target` の値に基づいて決定される SE オブジェクト (例: `obj_se_filtered`, `obj_se_normalized`) がこのシンボル名に割り当てられる。
  - **必須/任意:** 必須
- **ターゲット名:** `file_plot_library_size` (**シンボル名**)
  - **データ型:** `fs::path` (または `character`)
  - **説明:** ライブラリサイズのバープロット画像ファイルのパスを示す `targets` オブジェクト。`R/` 内の関数 (例: `plot_library_size`) で生成され、`_targets.R` で `format = "file"` ターゲットとして定義される。
  - **必須/任意:** 必須
- **ターゲット名:** `file_plot_log_density` (**シンボル名**)
  - **データ型:** `fs::path` (または `character`)
  - **説明:** ログ変換後のカウントデータの密度プロット画像ファイルのパスを示す `targets` オブジェクト。`R/` 内の関数 (例: `plot_log_density`) で生成され、`_targets.R` で `format = "file"` ターゲットとして定義される。使用するアッセイは `_targets.R` で制御する。
  - **必須/任意:** 必須

## 5. 出力ファイル
- **ファイル名:** `se_basic_info.html`
- **ファイルパス:** `results/{params$experiment_id}/reports/se_basic_info.html`
- **ファイル形式:** HTML (推奨)
- **ファイル構成:** HTMLファイル単体。プロットは画像ファイルとして `results/{params$experiment_id}/plots/` に保存され、HTML内から参照される。
- **推奨出力設定:** (`_targets.R` の `tar_render` またはラッパー関数内で設定)
  ```r
  output_format = rmarkdown::html_document(
    toc = TRUE,          # 目次
    toc_float = TRUE,    # 浮動目次
    code_folding = "hide", # コード折りたたみ (推奨)
    theme = "flatly",    # テーマ (推奨)
    df_print = "paged",   # データフレーム表示方法 (推奨)
    keep_md = TRUE      # デバッグ用に中間マークダウンファイルを保持 (推奨)
  ),
  output_file = glue::glue("se_basic_info_{experiment_id}.html"), # ファイル名設定
  output_dir = file.path("results", experiment_id, "reports") # 出力ディレクトリ設定
  ```

## 6. レポート構成 / 主要セクション
- **推奨構成との対応:** このレポートは、推奨構成の「概要」「データ概要」「解析結果（一部）」「セッション情報」に対応するセクションを含む。
1.  **Setup (`setup_se_basic_info`)**:
    - `include=FALSE` で共通のロギング設定 (`Rmd/common/setup_logging.Rmd`) を `child` として読み込む。
    - このRmdモジュール固有で必要となるライブラリ (`SummarizedExperiment`, `knitr`, `dplyr`, `tibble`) を読み込む (`library()`)。
2.  **Load Data (`load_data`)**:
    - `tar_read(obj_se_input)` でSEオブジェクトを読み込む。
    - `tar_read(file_plot_library_size)` でライブラリサイズプロットのパスを読み込む。
    - `tar_read(file_plot_log_density)` でログ密度プロットのパスを読み込む。
    - 読み込み成功/失敗をログ記録 (`log_info`, `log_error`)。
3.  **SE Object Overview (`se_overview`)**:
    - `print()` や `show()` でSEオブジェクトの基本情報を表示 (クラス、次元など)。
    - `assayNames()` でアッセイ名を表示。
4.  **Assay Data Preview (`assay_preview`)**:
    - `assayNames()` で取得した各アッセイ名についてループ。
    - 各アッセイデータの先頭10行を `assay(se, assay_name)[1:10, ]` で取得し、`knitr::kable()` などで静的に表示。アッセイ名をセクションタイトルやキャプションに含める。
    - ログ (`log_debug`) に表示するアッセイ名と次元を記録。
5.  **Column Data (colData) (`coldata_table`)**:
    - `colData(se)` を `as.data.frame()` や `as_tibble()` で変換し、`knitr::kable()` などで静的に表示。
    - ログ (`log_info`) に `colData` の次元を記録。
6.  **Row Data (rowData) (`rowdata_table`)**:
    - `rowData(se)` を `as.data.frame()` や `as_tibble()` で変換し、`head(10)` で先頭10行を取得し、`knitr::kable()` などで静的に表示。
    - ログ (`log_info`) に `rowData` の次元を記録。
7.  **Library Size Plot (`library_size_plot`)**:
    - `tar_read(file_plot_library_size)` で取得したパスを `knitr::include_graphics()` で表示。
    - ファイル存在確認を行い、存在しない場合は警告ログ (`log_warn`) を出力。
    - キャプションを設定。
8.  **Log-Transformed Density Plot (`log_density_plot`)**:
    - `tar_read(file_plot_log_density)` で取得したパスを `knitr::include_graphics()` で表示。
    - ファイル存在確認を行い、存在しない場合は警告ログ (`log_warn`) を出力。
    - キャプションを設定。
9.  **Session Information (`session_info`)**:
    - `sessionInfo()` の結果を表示し、再現性を確保する。 (推奨: 共通の `Rmd/common/session_info.Rmd` を `child` として読み込む)

## 7. ログ仕様 (`futile.logger`)
- **`_targets.log` へのログ出力:** (主に `targets` パイプラインやラッパー関数 `render_rmd_with_logging` が担当)
    - ターゲット開始時: `INFO [...] Starting target 'rmd_se_basic_info' (logging to logs/{experiment_id}/se_basic_info.log)` (ターゲット名は `_targets.R` で定義されるもの)
    - ターゲット終了時: `INFO [...] Finished target 'rmd_se_basic_info'`
- **個別ログファイル (`logs/{params$experiment_id}/se_basic_info.log`) へのログ出力:**
    - `Rmd/common/setup_logging.Rmd` によりファイルが初期化される。
    - レンダリング開始/終了 (INFO): Rmdの先頭と末尾で `log_info` を呼び出す。
    - 依存ターゲット読み込み (INFO/DEBUG): `tar_read()` の前後で `log_info` や `log_debug` を使用 (例: `log_info("Loading target: obj_se_input")`)。
    - 各セクション/チャンクの処理開始 (INFO/DEBUG): `log_info` や `log_debug` でチャンク名を記録 (例: `log_debug("Executing chunk: se_overview")`)。
    - データ概要表示 (INFO): `log_info("SE object dimensions: %d features x %d samples", nrow(se), ncol(se))`
    - アッセイデータ表示 (DEBUG): `log_debug("Displaying assay: %s (first 10 rows)", assay_name)`
    - `colData` 表示 (INFO): `log_info("Displaying colData: %d samples x %d variables", nrow(colData(se)), ncol(colData(se)))`
    - `rowData` 表示 (INFO): `log_info("Displaying rowData: %d features x %d variables (first 10 rows)", nrow(rowData(se)), ncol(rowData(se)))`
    - プロットファイル読み込みと表示 (DEBUG/INFO): `log_debug("Including graphics: %s", plot_path)`
    - ファイルが見つからない場合の警告 (WARN): `log_warn("Plot file not found: %s", plot_path)`
    - エラー発生時の詳細 (ERROR): `tryCatch` などでエラーを捕捉し、`log_error` で記録。
- **ログファイル名:** `logs/{params$experiment_id}/se_basic_info.log`

## 8. 特殊機能・技術要件
- テーブル表示には `knitr::kable()` などの静的な形式を使用する。
- インタラクティブ要素は使用しない (`project-rule.md` および `notepad/Rmd-spec-rule.md` 参照)。

## 9. 依存パッケージ
- `targets`
- `SummarizedExperiment`
- `rmarkdown`
- `knitr`
- `ggplot2` (プロット生成R関数側で必要)
- `dplyr`
- `tidyr`
- `tibble`
- `futile.logger` (推奨)
- `fs`
- `glue`
- `htmltools` (静的なHTML要素の生成に限定的に使用される場合がある)

## 10. 関連ファイル
- `Rmd/common/setup_logging.Rmd`: 共通のロギング設定 (推奨)。
- `Rmd/common/session_info.Rmd`: 共通のセッション情報表示チャンク (推奨)。
- `R/plot_library_size.R` (仮): ライブラリサイズプロットを生成・保存する関数が含まれるスクリプト。
- `R/plot_log_density.R` (仮): ログ密度プロットを生成・保存する関数が含まれるスクリプト。
- `_targets.R`: このRmdをレンダリングし、依存ターゲット (`obj_se_input`, `file_plot_library_size`, `file_plot_log_density`) を定義するパイプラインスクリプト。
- 共通CSSファイル (あれば): (例: `www/styles.css`)

## 11. 再利用ガイドライン
- このRmdモジュールは、基本的なSEオブジェクトの概要を表示するための汎用コンポーネントとして設計されている。
- `_targets.R` で異なるSEオブジェクトを生成するターゲットを `obj_se_input` というシンボル名でこのRmdターゲットに渡すことで、パイプラインの様々な段階で再利用可能。
- 表示するプロットを変更したい場合は、`_targets.R` で `file_plot_library_size` や `file_plot_log_density` に対応するファイルターゲットを変更する。
- **モジュール化:** より複雑なレポートでは、共通のセクション（データ概要、セッション情報など）を別の子Rmdドキュメント (例: `Rmd/common/data_summary.Rmd`, `Rmd/common/session_info.Rmd`) として抽出し、`child` チャンクオプションで読み込むことを推奨する。
- カスタマイズが必要な場合は、このファイルをコピーして新しいRmdモジュールを作成するか、パラメータを追加して挙動を変更する。
- より詳細なQCレポートが必要な場合は、このモジュールをベースに拡張するか、別モジュール (`qc_report.Rmd` など) を作成する。 