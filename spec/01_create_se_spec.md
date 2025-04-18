# SEオブジェクト作成 仕様書 (raw_se)

*この仕様書は **`rmd-targets_rule.mdc` (ルール文書)** に基づき作成されています。実装前に必ずルールを確認してください。*

## 1. モジュールの概要

*   **モジュール名:** SEオブジェクト作成
*   **対応するターゲット名 (`_targets.R`):** `raw_se`
*   **目的:** 指定された `experiment_id` に基づき、カウントデータとサンプルメタデータを読み込み、基本的な `SummarizedExperiment` (SE) オブジェクトを生成する。
*   **担当者:** (任意)
*   **作成日:** (作成時に記述)
*   **更新日:** (更新時に記述)
*   **TDD適用:** 非推奨 (主にファイル読み込みとオブジェクト生成のため)

## 2. 依存関係 (`targets`) と入力データ

*   **依存するターゲット名:**
    *   (オプション) `ensure_log_dir`: ログディレクトリが存在することを保証する場合 (関数自体は直接ファイルにログ出力しないが、呼び出し元がログ出力する場合に依存)。
*   **入力 `SummarizedExperiment` オブジェクトの状態:** なし (パイプラインの開始点)
*   **その他の入力ファイル/パラメータ:**
    *   **カウントデータ:** `data/{experiment_id}/counts.csv` (ファイル形式は `config.yaml` 等で指定可能にするのが望ましい)
        *   形式: 最初の列が遺伝子ID (例: `gene_id_column` パラメータで指定)、後続の列がサンプルIDに対応するカウント値。
    *   **サンプルメタデータ:** `data/{experiment_id}/sample_metadata.csv`
        *   形式: 最初の列がサンプルID (例: `sample_id_column` パラメータで指定、カウントデータの列名と一致)、後続の列が実験条件などのメタデータ。
    *   **ファイルパス:**
        *   パスのテンプレート (例: `counts_file_path`) は `_targets.R` で `experiment_id` を使って具体化される。
        *   **必須:** 入力ファイルパス (絶対パス) と `experiment_id` をログ (`flog.info`) に記録。

## 3. 主要な実行ステップ (R 関数)

*   **実行形式:** R関数 (例: `create_se_object()`)
*   **関連ファイル:** `R/R01_create_se.R` (仮称)
*   **ステップ詳細:**
    1.  **[セットアップ]**
        *   **必須:** `library()` で必要なパッケージをロード (`SummarizedExperiment`, `readr` or `data.table`, `dplyr`, `fs`, `futile.logger`, `cli`, `stringr`, `biomaRt`)。
        *   **ログ:** この関数自体はロガー設定 (アペンダー、レイアウト) を**行わない**。呼び出し元 (`_targets.R`) で設定されたルートロガーを使用 (`flog.info()`, `flog.error()` など)。
        *   **推奨:** `cli_process_start()` で処理開始メッセージ表示。
        *   **必須:** 入力ファイルパス (絶対パス) と `experiment_id` をログ (`flog.info`) に記録。
        *   **必須:** `fs::file_exists()` で入力ファイルの存在確認。存在しない場合は `flog.error()` でエラーログを出力し、`stop()` で処理を中断。
    2.  **[データ読み込み]**
        *   絶対パスを使用してカウントデータとサンプルメタデータを読み込む (`readr::read_csv`, `data.table::fread` など)。
        *   **必須:** カウントデータの最初の列（遺伝子ID）を `rownames` として読み込むことを確認。
        *   読み込み時のエラーハンドリング (`tryCatch` など)。エラー発生時は `flog.error()` で記録し、`stop()`。
    3.  **[データ整合性チェック]**
        *   カウントデータの列名 (サンプルID) とメタデータのサンプルID (`colData` の行名になる) の完全一致、または部分一致と順序整合性を確認。不一致の場合は `flog.error()` でエラーを記録し、`stop()`。
        *   必要に応じて他のチェック (例: 重複サンプルID、必須メタデータ列の存在)。
    4.  **[遺伝子アノテーション取得 (`biomaRt`)]**
        *   **必須:** カウントデータの `rownames` (バージョン付き ENSEMBL ID) を取得。
        *   **必須:** バージョンなしの ENSEMBL ID を作成 (`stringr::str_remove` などを使用)。`flog.info` で変換前後の ID の数を記録。
        *   **必須:** `biomaRt::useMart` で Ensembl マートオブジェクトを作成。使用するホスト (`biomart_host`)、データセット (`biomart_dataset`) はパラメータ化する。
        *   **必須:** `biomaRt::getBM` を使用し、バージョンなし ENSEMBL ID (`ensembl_gene_id`) をキー (`filters`) として、必要な属性 (`attributes`: `ensembl_gene_id`, `external_gene_name` or `hgnc_symbol`, `transcript_length`, `gene_biotype`) を取得。
        *   **必須:** 取得したアノテーション情報を `rowData` の基礎となる `DataFrame` に整形する。
        *   **ログ:** `biomaRt` への接続試行、取得した属性の数、マッチした/しなかった遺伝子の数を `flog.info` で記録。エラー発生時は `flog.error` で記録し、適切に処理 (例: アノテーションなしで続行するか `stop`)。
    5.  **[`SummarizedExperiment` オブジェクト生成]**
        *   **必須:** カウントデータの `rownames` (バージョン付き ENSEMBL ID) が、ステップ 4 で作成したアノテーション `DataFrame` の遺伝子 ID と一致するように整合性を確認し、必要に応じて並べ替え/フィルタリングを行う。
        *   `SummarizedExperiment::SummarizedExperiment()` を使用。
        *   `assays = list(counts = count_matrix)`: カウントデータを `counts` アッセイとして格納。
        *   `colData = sample_metadata`: サンプルメタデータを格納 (サンプルIDが行名になるように整形)。
        *   `rowData = annotation_df`: ステップ 4 で取得・整形したアノテーション情報を含む `DataFrame` を格納。**`rownames(rowData)` は `rownames(assays$counts)` (バージョン付き ENSEMBL ID) と一致させる。** `rowData` には `ensemble_gene_id` (バージョンなし), `gene_name`, `gene_length`, `gene_biotype` 列が含まれる。
    6.  **[メタデータ初期化]**
        *   **必須:** `metadata(se)$experiment_id <- experiment_id`
        *   **必須:** `metadata(se)$pipeline_history <- list()` (空のリストとして初期化)
        *   `flog.info("Initialized SE metadata with experiment_id and empty pipeline_history.")`
    7.  **[完了ステップ]**
        *   **必須:** 生成された SE オブジェクトを返す (ターゲットとして保存される)。
        *   **推奨:** `cli_process_done()` で完了メッセージ表示。

## 4. 出力 (`targets`)

*   **出力ターゲット名:** `raw_se`
*   **出力 `SummarizedExperiment` オブジェクトの状態 (ターゲット名: `raw_se`):**
    *   **`assays`:**
        *   `counts`: 入力された生カウントデータ (matrix or dgCMatrix)。行名はバージョン付き ENSEMBL ID。
    *   **`colData`:**
        *   入力されたサンプルメタデータを含む DataFrame。行名はサンプルID。
    *   **`rowData`:**
        *   `biomaRt` から取得したアノテーション情報を含む DataFrame。
        *   **行名 (`rownames`):** バージョン付き ENSEMBL ID (`assays$counts` の行名と一致)。
        *   **必須列:**
            *   `ensemble_gene_id`: バージョンなし ENSEMBL ID。
            *   `gene_name`: 遺伝子シンボル (例: HGNC symbol)。列名は `biomaRt` の結果に依存 (例: `external_gene_name`, `hgnc_symbol`)。
            *   `gene_length`: 遺伝子長 (例: `transcript_length`)。列名は `biomaRt` の結果に依存。
            *   `gene_biotype`: 遺伝子の生物学的タイプ。
    *   **`metadata`:**
        *   `experiment_id`: このSEオブジェクトが由来する実験ID (**必須**)。
        *   `pipeline_history`: 空のリスト (**必須**)。
*   **生成されるファイル:** なし (SEオブジェクトは `targets` のストアに保存)。

## 5. 使用する主要パッケージと共通関数

*   **パッケージ:** `targets`, `SummarizedExperiment`, `readr` (または `data.table`), `dplyr`, `fs`, `futile.logger`, `cli`, `stringr`, `biomaRt`
    *   *`renv` 管理対象 (`renv::snapshot()` を適宜実行)。R スクリプト冒頭で `library()` 宣言が必須。*
*   **共通関数 (`R/` ディレクトリ):**
    *   現時点ではなし。将来的に共通のファイル読み込み/検証関数、ロガー設定関数などを使用する可能性あり。

## 6. パラメータ (`_targets.R` または `config.yaml` 経由)

*   *原則として `_targets.R` 上部または `config.yaml` で定義し、関数には引数として渡されることを想定。*
| パラメータ名           | 説明                                                         | 型        | デフォルト値/推奨値                     | 必須 | 提供元 (例)        |
| :--------------------- | :----------------------------------------------------------- | :-------- | :--------------------------------------- | :--- | :----------------- |
| `experiment_id`        | 解析対象の実験 ID                                            | character | -                                        | Yes  | `_targets.R`       |
| `counts_file_path`     | カウントデータの**絶対パス** (呼び出し元で生成)                 | character | -                                        | Yes  | `_targets.R` (動的) |
| `metadata_file_path`   | サンプルメタデータの**絶対パス** (呼び出し元で生成)           | character | -                                        | Yes  | `_targets.R` (動的) |
| `gene_id_column`       | カウントファイル内の遺伝子ID列名 (rownamesとして使用)          | character | `1` (最初の列)                         | No   | `config.yaml`      |
| `sample_id_column`     | メタデータファイル内のサンプルID列名                         | character | `"sample_id"`                            | No   | `config.yaml`      |
| `counts_file_format`   | カウントファイルの形式 (例: "csv", "tsv", "rds")               | character | `"csv"`                                  | No   | `config.yaml`      |
| `metadata_file_format` | メタデータファイルの形式 (例: "csv", "tsv")                 | character | `"csv"`                                  | No   | `config.yaml`      |
| `biomart_host`         | `biomaRt` で使用するホスト URL                               | character | `"https://ensembl.org"` (またはミラーサイト) | No   | `config.yaml`      |
| `biomart_dataset`      | `biomaRt` で使用するデータセット名 (例: "hsapiens_gene_ensembl") | character | - (種に応じて設定)                     | Yes  | `config.yaml`      |
| `biomart_attributes`   | `biomaRt` で取得する属性リスト                              | character vector | `c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")` | No | `config.yaml` |
* *注: パスパラメータ (`counts_file_path`, `metadata_file_path`) は、テンプレート文字列ではなく、`_targets.R` 内で `sprintf()` や `glue()` を使って `experiment_id` を埋め込み、`fs::path_abs()` で絶対パスに変換したものが渡される想定。*
* *注: `biomart_dataset` は解析対象の種に応じて適切に設定する必要があるため、必須パラメータとする。*

## 7. ログとメッセージ出力 (`futile.logger`, `cli`)

*   **ルール:** ルール文書の **セクション 3 (コーディング規約: ロギング)** に従うこと。
*   **ロガー設定:** **この関数内では行わない。** 呼び出し元 (`_targets.R`) で `futile.logger` のルートロガーが設定されていることを前提とする (例: `flog.appender(appender.tee(logfile))`, `flog.layout(...)`, `flog.threshold(INFO)`)。ログは `logs/{experiment_id}/_targets.log` に出力される想定。
*   **ログ記録 (`flog.info`, `flog.warn`, `flog.error`):**
    *   **必須:** 関数の開始/終了、入力ファイルパス、`experiment_id`、主要なチェックポイント (ファイル存在確認、整合性チェック)、**`biomaRt` への接続試行、使用データセット、取得属性、取得結果の概要 (成功/失敗、マッチ数など)**、エラー発生時の詳細情報 (`flog.error`)、SE オブジェクト生成完了、メタデータ初期化完了。
    *   **ログレベル:** 通常の情報は `INFO`、デバッグ用の詳細情報は `DEBUG` (呼び出し元で閾値設定)、エラーは `ERROR`。
*   **ユーザーメッセージ (`cli`):**
    *   `cli_process_start`/`cli_process_done` や `cli_alert_info`, `cli_alert_danger` などを使用し、主要なステップの開始/終了、成功/失敗をユーザーに分かりやすく表示。**特に `biomaRt` によるアノテーション取得の進捗や結果の概要を表示することが望ましい。**

## 8. 出力パスと命名規則

*   **SEオブジェクト:** `targets` のストア (`_targets/objects/raw_se`) に自動保存される。パスの直接操作はしない。
*   **その他:** なし

## 9. 可視化要件

*   なし

## 10. その他特記事項・制約条件

*   入力ファイルの具体的なフォーマット (区切り文字、ヘッダー有無、コメント文字など) は、読み込み関数 (例: `readr::read_csv`) の引数で調整可能である必要がある。`config.yaml` などで指定できるようにするのが望ましい。
*   現時点では遺伝子アノテーション (`rowData`) の詳細な付与は行わない (遺伝子IDのみ)。後続モジュールで実施。
*   大規模データの場合、`data.table::fread` の使用やメモリ効率の良いデータ構造 (例: `DelayedArray`, `HDF5Array`) の利用を将来的に検討する必要があるかもしれない。
*   `biomaRt` への接続は外部ネットワークに依存するため、タイムアウトやサーバーエラーが発生する可能性がある。適切なエラーハンドリング (`tryCatch` や再試行ロジック) を実装することが重要。オフライン環境での実行が必要な場合は、事前にアノテーションファイルをダウンロードしておくなどの代替策が必要になる。 