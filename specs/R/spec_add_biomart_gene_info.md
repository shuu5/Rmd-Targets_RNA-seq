# R関数仕様書: add_biomart_gene_info

## 1. 概要
- **目的:** SummarizedExperiment オブジェクトの rowData に、biomaRt を使用して Ensembl 遺伝子 ID に基づくアノテーション情報（遺伝子シンボル、転写産物長、遺伝子バイオタイプ）を追加する。
- **機能:** 入力 SE オブジェクトの rownames (Ensembl ID with version) からバージョンを除去し、biomaRt で遺伝子情報を取得し、rowData にマージする。
- **作成日:** 2024-08-01
- **更新日:** 2024-08-01

## 2. 機能詳細
- 入力 SE オブジェクトのアッセイの rownames を元に `ensembl_gene_id_with_ver` 列を rowData に作成する。
- `ensembl_gene_id_with_ver` 列からバージョン情報（例: ".1"）を除去し、`ensembl_gene_id` 列を作成する。
- `biomaRt::useMart` で Ensembl データベース (hsapiens_gene_ensembl) に接続する。
- `biomaRt::getBM` を使用し、`ensembl_gene_id` をキーとして以下の属性を取得する:
    - `external_gene_name` (rowData では `gene_symbol` として保存)
    - `transcript_length`
    - `gene_biotype`
- 取得した情報を `ensembl_gene_id` をキーに rowData に左結合 (left join) する。
- 処理の履歴を `metadata(se)$pipeline_history` に記録する (`spec-rule.md` 準拠)。
- この関数は、典型的には `create_se_object` の後に実行される解析ステップに対応する。

## 3. 入力 (Arguments)
- **引数名:** `se`
- **データ型:** `SummarizedExperiment`
- **説明:** rowData に遺伝子情報を追加する対象の SE オブジェクト。rownames には Ensembl 遺伝子 ID (バージョン付き、例: "ENSG00000123456.7") が含まれている必要がある。assay スロットは存在している必要があるが、中身は問わない (rownames を使用するため)。
- **必須/任意:** 必須
- **デフォルト値:** なし

- **引数名:** `mart_dataset`
- **データ型:** `character`
- **説明:** `biomaRt::useMart` で使用するデータセット名。通常はヒトゲノム "hsapiens_gene_ensembl" を指定する。
- **必須/任意:** 任意
- **デフォルト値:** `"hsapiens_gene_ensembl"`

- **引数名:** `biomart_host`
- **データ型:** `character`
- **説明:** `biomaRt::useMart` で接続する Ensembl のホスト URL。通常はデフォルトで良いが、ミラーサイトを指定することも可能。
- **必須/任意:** 任意
- **デフォルト値:** `"https://ensembl.org"` (または `biomaRt` のデフォルト)

- **引数名:** `step_id`
- **データ型:** `character`
- **説明:** `pipeline_history` に記録する際のステップ識別子。通常は `targets` のターゲット名を指定する。
- **必須/任意:** 必須
- **デフォルト値:** なし

## 4. 出力 (Return Value)
- **データ型:** `SummarizedExperiment`
- **説明:** 入力 `se` オブジェクトの `rowData` に以下の列が追加または更新されたもの:
    - `ensembl_gene_id_with_ver` (`character`): 元の rownames (バージョン付き Ensembl ID)。
    - `ensembl_gene_id` (`character`): バージョンを除去した Ensembl ID。
    - `gene_symbol` (`character`): 遺伝子シンボル (`external_gene_name`)。biomaRt で見つからない場合は `NA`。
    - `transcript_length` (`integer`): 転写産物の長さ。biomaRt で見つからない場合は `NA`。
    - `gene_biotype` (`character`): 遺伝子のバイオタイプ。biomaRt で見つからない場合は `NA`。
- **ファイル出力:** なし。

## 5. 処理フロー / 主要ステップ
1. **ロガー設定:** `futile.logger` を設定する (`INFO` レベル以上を出力)。
2. **入力検証:** `se` が `SummarizedExperiment` であること、rownames が存在することを確認。
3. **rowData 準備:**
    - `se` の `rowData` を取得 (存在しない場合は空の DataFrame を作成)。
    - `rownames(se)` を `ensembl_gene_id_with_ver` 列として `rowData` に追加。
    - `stringr::str_remove` を使用して `ensembl_gene_id_with_ver` から ".\d+$" パターンを除去し、`ensembl_gene_id` 列を作成。
4. **biomaRt 接続:**
    - `tryCatch` を使用して `biomaRt::useMart` で Ensembl データベースに接続。エラー発生時はエラーログを出力し、処理を中断。
5. **biomaRt クエリ:**
    - `unique(rowData$ensembl_gene_id)` を取得。
    - `tryCatch` を使用して `biomaRt::getBM` で `ensembl_gene_id`, `external_gene_name`, `transcript_length`, `gene_biotype` を取得。エラー発生時は警告ログを出力し、空のデータフレームを返す。
    - 取得結果を `gene_info` (data.frame) に格納。列名を `ensembl_gene_id`, `gene_symbol`, `transcript_length`, `gene_biotype` に変更。
6. **情報マージ:**
    - `dplyr::left_join` を使用して、`rowData` と `gene_info` を `ensembl_gene_id` で結合。
    - 結合後の `rowData` で SE オブジェクトの `rowData` を更新 (`rowData(se) <- ...`)。
7. **メタデータ記録:**
    - `metadata(se)$pipeline_history` に処理情報をリストとして追加 (`spec-rule.md` 参照)。
        - `step_id`: 引数で指定された値。
        - `function_name`: "add_biomart_gene_info"。
        - `timestamp`: `Sys.time()`。
        - `parameters`: 使用した主要引数 (`mart_dataset`, `biomart_host`)。
        - `input_dimensions`: 入力 SE の次元。
        - `output_dimensions`: 出力 SE の次元。
        - `details`: "Added gene annotation using biomaRt."
8. **ログ出力:** 処理開始、biomaRt 接続、情報取得、マージ、完了などのログを出力。見つからなかった遺伝子の数をログに出力。
9. **戻り値:** 更新された `se` オブジェクトを返す。

## 6. 副作用 (Side Effects)
- **`SummarizedExperiment` のメタデータ更新:** `metadata(se)$pipeline_history` に処理履歴が追加される。
- **ログファイル出力:** `futile.logger` の設定に従い、ログファイルが生成または追記される (通常 `logs/{experiment_id}/add_biomart_gene_info.log`)。
- **ネットワークアクセス:** Ensembl の biomaRt サーバーに接続する。

## 7. ログ仕様 (`futile.logger`)
- **ログレベル:** INFO, WARN, ERROR
- **ログ内容:**
    - INFO: 関数開始/終了、使用する Ensembl データセット、取得対象の遺伝子数、biomaRt から取得した情報数、rowData にマージした情報数、見つからなかった遺伝子の数。
    - WARN: biomaRt での情報取得に失敗した場合 (空の結果が返された場合)、一部の遺伝子情報が見つからなかった場合。
    - ERROR: 入力 SE オブジェクトが無効な場合、biomaRt サーバーへの接続に失敗した場合。
- **ログファイル名:** `logs/{experiment_id}/add_biomart_gene_info.log` (呼び出し側で設定されることを想定)。

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-add_biomart_gene_info.R`
- **テスト項目:**
    - **正常系:**
        - 既知の Ensembl ID (バージョン付き) を持つ SE オブジェクトを入力とし、期待される `gene_symbol`, `transcript_length`, `gene_biotype` が `rowData` に正しく追加されることを確認。
        - `ensembl_gene_id_with_ver` と `ensembl_gene_id` が正しく生成されていることを確認。
        - バージョンなしの Ensembl ID が rownames に含まれる場合でも動作することを確認（推奨されないが）。
        - `pipeline_history` に正しい情報が記録されることを確認。
    - **異常系:**
        - 入力 `se` が `SummarizedExperiment` でない場合にエラーが発生することを確認。
        - `rownames(se)` が `NULL` または空の場合にエラーが発生することを確認。
        - 不正な `mart_dataset` を指定した場合に `biomaRt::useMart` でエラーが発生し、それが適切に捕捉・ログ記録されることを確認。
        - 意図的に biomaRt 接続を失敗させ (例: 不正なホスト)、エラーが捕捉されることを確認。
        - biomaRt で全く情報が取得できない場合に、`rowData` の追加列がすべて `NA` になり、警告ログが出力されることを確認。
    - **副作用:**
        - `pipeline_history` が正しく追記されること（既存の履歴が消えないこと）。
- **テストデータ:** `tests/testdata/add_biomart_gene_info/`
    - 少数の遺伝子 (既知のもの、biomaRt に存在しない可能性のあるものを含む) を持つ `SummarizedExperiment` オブジェクトの RDS ファイル。
    - 期待される出力 `rowData` の一部を含む CSV または RDS ファイル。

## 9. 依存関係
- R パッケージ: `SummarizedExperiment`, `biomaRt`, `dplyr`, `stringr`, `futile.logger`, `S4Vectors` (DataFrame 用)
- 他の自作関数: なし (直接依存はないが、通常は `create_se_object` のような関数で作成された SE を入力とする) 