# R関数仕様書: create_se_object

## 1. 概要
- **目的:** 指定された実験IDに対応するカウントデータとサンプルメタデータファイルを読み込み、解析の基礎となる `SummarizedExperiment` オブジェクトを作成する。
- **機能:**
    - `counts.csv` ファイルを読み込み、アッセイデータ（counts）として格納する。
    - `sample_metadata.csv` ファイルを読み込み、列データ (`colData`) として格納する。
    - `sessionInfo()` の情報をメタデータに格納する。
    - `project-rule.md` に基づき、処理履歴をメタデータ (`pipeline_history`) に記録する。
- **作成日:** 2024-07-28
- **更新日:** 2024-07-28

## 2. 機能詳細
- この関数は、RNA-seq解析パイプラインの初期ステップとして、生のカウントデータとサンプル情報を統合した `SummarizedExperiment` オブジェクトを生成する。
- `counts.csv` は遺伝子を行、サンプルを列とする数値行列（またはデータフレーム）を期待する。
- `sample_metadata.csv` はサンプルを行、メタデータ項目を列とするデータフレームを期待する。行名は `counts.csv` の列名と一致する必要がある。
- `project-rule.md` の「データ読み込みと初期オブジェクト生成」ステップに対応する。

## 3. 入力 (Arguments)

| 引数名             | データ型     | 説明                                                                                                                               | 必須/任意 | デフォルト値                                     |
| ------------------ | ------------ | ---------------------------------------------------------------------------------------------------------------------------------- | --------- | ---------------------------------------------- |
| `experiment_id`    | `character`  | 解析対象の実験ID。`data/{experiment_id}/` ディレクトリパスの構築に使用される。                                                        | 必須      | なし                                             |
| `data_dir`         | `fs::path`   | データファイルが格納されている親ディレクトリ (`data/` に相当)。                                                                      | 任意      | `"data"`                                         |
| `counts_filename`  | `character`  | カウントデータファイル名。`data_dir/{experiment_id}/` 内のファイル名を指定。                                                        | 任意      | `"counts.csv"`                                 |
| `metadata_filename`| `character`  | サンプルメタデータファイル名。`data_dir/{experiment_id}/` 内のファイル名を指定。                                                      | 任意      | `"sample_metadata.csv"`                        |
| `counts_options`   | `list`       | カウントデータ読み込み関数（例: `data.table::fread`）に渡す追加オプションのリスト。`(例: list(sep = ",", header = TRUE, row.names = 1))` | 任意      | `list(header = TRUE, row.names = 1, check.names = FALSE)` |
| `metadata_options` | `list`       | メタデータ読み込み関数（例: `data.table::fread`）に渡す追加オプションのリスト。`(例: list(sep = ",", header = TRUE, row.names = 1))`   | 任意      | `list(header = TRUE, row.names = 1, check.names = FALSE)` |

## 4. 出力 (Return Value)
- **データ型:** `SummarizedExperiment`
- **説明:** 以下の要素を含む `SummarizedExperiment` オブジェクト。
    - `assay`:
        - `counts`: 読み込まれたカウントデータを含む行列 (`matrix`)。行名は遺伝子ID、列名はサンプルID。
    - `colData`: 読み込まれたサンプルメタデータを含む `DataFrame`。行名はサンプルID。
    - `rowData`: 現時点では空の `DataFrame`。行名は遺伝子ID。
    - `metadata`: 以下の情報を含むリスト。
        - `sessionInfo`: `sessioninfo::session_info()` または `utils::sessionInfo()` の実行結果。
        - `pipeline_history`: `spec-rule.md` に定義されたフォーマットに従う処理履歴のリスト。この関数によって追加されるエントリには、`step_id` (例: 対応する `targets` ターゲット名)、`function_name` ("create_se_object")、`timestamp`、`parameters` (主要引数)、`output_dimensions` が含まれる。
        - `input_files`: 読み込んだカウントファイルとメタデータファイルの絶対パスを含むリスト (`list(counts = ..., metadata = ...)`）。
- **ファイル出力:** なし。

## 5. 処理フロー / 主要ステップ
1.  **ログ開始:** `futile.logger` を用いて処理開始をログ記録 (`INFO`)。入力パラメータも記録 (`DEBUG`)。
2.  **ファイルパス構築:** `data_dir`, `experiment_id`, `counts_filename`, `metadata_filename` から完全なファイルパスを生成 (`fs::path_join`)。
3.  **ファイル存在確認:** 両方の入力ファイルが存在するか確認。存在しない場合はエラーログ (`ERROR`) を記録し、処理を停止。
4.  **カウントデータ読み込み:** 指定されたパスとオプション (`counts_options`) を用いてカウントデータファイルを読み込む (推奨: `data.table::fread`)。数値行列に変換。
5.  **メタデータ読み込み:** 指定されたパスとオプション (`metadata_options`) を用いてサンプルメタデータファイルを読み込む (推奨: `data.table::fread`)。`DataFrame` に変換。
6.  **データ整合性チェック:**
    - カウントデータの列名とメタデータの行名が一致するか確認。
    - 一致しない、または重複がある場合は警告ログ (`WARN`) またはエラーログ (`ERROR`) を記録し、必要に応じて処理を停止。
    - カウントデータとメタデータのサンプル順序を一致させる。
7.  **`SummarizedExperiment` オブジェクト作成:**
    - `assays`: `list(counts = count_matrix)`
    - `colData`: `metadata_df`
    - `rowData`: `DataFrame(row.names = rownames(count_matrix))` (初期状態)
    - `SummarizedExperiment::SummarizedExperiment()` を呼び出してオブジェクトを生成。
8.  **メタデータ追加:**
    - `metadata(se)$sessionInfo <- sessioninfo::session_info()` (または `utils::sessionInfo()`)
    - `metadata(se)$input_files <- list(counts = fs::path_abs(counts_file_path), metadata = fs::path_abs(metadata_file_path))`
    - `pipeline_history` エントリを作成 (`spec-rule.md` のフォーマットに従う)。
        - `step_id`: (例: "obj_create_se")
        - `function_name`: "create_se_object"
        - `timestamp`: `Sys.time()`
        - `parameters`: `list(experiment_id = ..., data_dir = ..., counts_filename = ..., ...)`
        - `input_dimensions`: `NULL`
        - `output_dimensions`: `list(rows = nrow(se), cols = ncol(se))`
        - `details`: "Initial SE object creation from CSV."
    - 作成したエントリを `metadata(se)$pipeline_history` リストに追加。
9.  **ログ終了:** 処理完了 (`INFO`) と生成されたSEオブジェクトの次元数 (`DEBUG`) をログ記録。
10. **戻り値:** 作成された `SummarizedExperiment` オブジェクトを返す。

## 6. 副作用 (Side Effects)
- **`SummarizedExperiment` のメタデータ更新:** `metadata()$pipeline_history` に、`spec-rule.md` で定義されたフォーマットに従う実行記録エントリが追加される。
- その他、ファイルI/Oやグローバルオプションの変更は行わない。

## 7. ログ仕様 (`futile.logger`)
- **ログファイル名:** `logs/{experiment_id}/create_se_object.log` (関数内で設定想定)
- **主要ログメッセージ:**
    - `INFO`: 関数開始・終了。
    - `DEBUG`: 入力引数値、読み込んだデータの次元数、生成されたSEオブジェクトの次元数。
    - `INFO` / `DEBUG`: 読み込むファイルパス。
    - `WARN`: カウントデータとメタデータのサンプルID不一致（処理継続可能な場合）。
    - `ERROR`: 入力ファイルが見つからない、読み込みエラー、サンプルIDの致命的な不整合。

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-create_se_object.R`
- **テストデータ:** `tests/testdata/create_se_object/` (正常系 CSV、メタデータCSV、不整合データなど)
- **テスト項目:**
    - **正常系:**
        - 正しい形式の `counts.csv` と `sample_metadata.csv` からSEオブジェクトが正常に作成されること。
        - `assay`, `colData`, `metadata` の内容が期待通りであること（次元数、列名、行名、`sessionInfo` の存在など）。
        - `pipeline_history` に適切な情報が記録されること。
        - `counts_options`, `metadata_options` が正しく反映されること (例: 区切り文字変更)。
    - **異常系:**
        - `counts.csv` または `sample_metadata.csv` が存在しない場合にエラーが発生すること (`expect_error`)。
        - CSVファイルが空または不正な形式の場合にエラーが発生すること。
        - カウントデータの列名とメタデータの行名が全く一致しない場合にエラーが発生すること。
        - 必須引数 (`experiment_id`) が欠損している場合にエラーが発生すること。
    - **副作用:**
        - `pipeline_history` が正しく更新されること。

## 9. 依存関係
- **パッケージ:** `SummarizedExperiment`, `S4Vectors`, `IRanges`, `GenomicRanges`, `Biobase`, `futile.logger`, `fs`, `sessioninfo` (推奨), `data.table` (推奨)
- **自作関数:** なし (現時点)

## 10. 注意点・特記事項
- 入力CSVファイルのエンコーディングはUTF-8を想定。
- カウントデータは非負整数であることを期待するが、厳密な型チェックは実装レベルで検討する。
- サンプルID（カウントデータの列名、メタデータの行名）の一致は厳密に行う。
- 大規模データを扱う場合は `data.table::fread` の利用を強く推奨。 