# R関数仕様書: subset_gene

## 1. 概要
- **目的:** `SummarizedExperiment` オブジェクト内の遺伝子を、`rowData` に含まれる情報に基づいてフィルタリングする。
- **機能:** `rowData` の指定された列に対し、ユーザー定義の条件式を用いて遺伝子をサブセット化する。複数の条件を組み合わせてフィルタリングすることが可能。
- **作成日:** 2025-04-25
- **更新日:** 2025-04-25

## 2. 機能詳細
- `SummarizedExperiment` (SE) オブジェクトを入力として受け取る。
- `rowData` の特定の列を指定し、その列に対するフィルタリング条件（例: `gene_biotype == "protein_coding"`, `gene_symbol %in% c("GENE1", "GENE2")`）を適用する。
- `dplyr::filter()` スタイルの条件式（文字列または式）を複数受け付け、それらをすべて満たす（AND条件）遺伝子を抽出する。
- フィルタリング後の SE オブジェクトを返す。
- `project-rule.md` のデータ前処理や探索的データ解析のステップで利用されることを想定。

## 3. 入力 (Arguments)
| 引数名           | データ型                  | 説明                                                                                                                                | 必須/任意 | デフォルト値 |
|------------------|---------------------------|-----------------------------------------------------------------------------------------------------------------------------------|-----------|--------------|
| `se`             | `SummarizedExperiment`    | フィルタリング対象の SE オブジェクト。                                                                                              | 必須      | -            |
| `filter_conditions` | `list` of `character` or `expression` | フィルタリング条件を指定するリスト。各要素は `rowData` 列に対する条件式（例: `"gene_biotype == 'protein_coding'"`, `rlang::expr(p_value < 0.05)`)。すべての条件を満たす行が選択される。 | 必須      | -            |
| `logger_name`    | `character`               | ログ出力に使用するロガー名 (`run_with_logging` から渡される)。                                                                        | 必須      | -            |

## 4. 出力 (Return Value)
- **データ型:** `SummarizedExperiment`
- **説明:** `filter_conditions` で指定された条件を満たす遺伝子のみを含む、サブセット化された SE オブジェクト。入力 SE オブジェクトの他のアッセイ、`colData`、`metadata` は維持される。

## 5. 処理フロー / 主要ステップ
1. 入力引数 (`se`, `filter_conditions`) の検証。
2. `rowData(se)` を `data.frame` に変換。
3. `filter_conditions` リスト内の各条件式を順番に適用して `rowData` をフィルタリングする (`dplyr::filter()` を内部で使用)。
4. フィルタリングされた `rowData` に対応するインデックスを取得。
5. 元の `se` オブジェクトから、フィルタリングされたインデックスに基づいて遺伝子をサブセット化 (`se[filtered_indices, ]`)。
6. サブセット化された SE オブジェクトの `metadata$pipeline_history` に処理履歴を追加 (`add_pipeline_history` を使用)。
7. サブセット化された SE オブジェクトを返す。

## 6. 副作用 (Side Effects)
- **`SummarizedExperiment` のメタデータ更新:** `metadata()$pipeline_history` に以下の情報を含むリストが追加される。
    - `step_id`: `targets` パイプラインにおけるターゲット名。
    - `function_name`: `"subset_gene"`。
    - `timestamp`: 処理実行時のタイムスタンプ。
    - `parameters`: `filter_conditions` の内容。
    - `input_dimensions`: 入力 SE オブジェクトの次元。
    - `output_dimensions`: 出力 SE オブジェクトの次元。
    - `details`: 適用されたフィルタリング条件の概要。

## 7. ログ仕様 (`futile.logger`)
- **ログファイル名:** `logs/{experiment_id}/subset_gene.log`
- **主要ログメッセージ:**
    - `INFO`: 関数開始、入力SEの次元、適用されるフィルター条件。
    - `DEBUG`: `rowData` のフィルタリング処理開始/終了、フィルタリング前後の行数。
    - `INFO`: フィルタリング後のSEの次元、関数終了。
    - `WARN`: `filter_conditions` に指定された列が `rowData` に存在しない場合。
    - `ERROR`: フィルタリング処理中にエラーが発生した場合。

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-subset_gene.R`
- **テスト項目:**
    - **正常系:**
        - 単一条件 (例: `gene_biotype == "protein_coding"`) で正しくフィルタリングされるか。
        - 複数条件 (例: `gene_biotype == "protein_coding"`, `chromosome == "chr1"`) で正しくフィルタリングされるか（AND条件）。
        - 数値列に対する条件 (例: `mean_expression > 10`) が機能するか。
        - 文字列リストに対する条件 (`gene_symbol %in% c(...)`) が機能するか。
        - 出力SEの次元、`rowData`、`assay` の値が期待通りか。
        - `metadata$pipeline_history` が正しく更新されるか。
    - **異常系:**
        - `rowData` に存在しない列名を条件に使用した場合にエラーまたは警告が出るか。
        - 不正な条件式を指定した場合にエラーが発生するか。
        - 入力 `se` が `SummarizedExperiment` でない場合にエラーが発生するか。
        - `filter_conditions` がリストでない場合にエラーが発生するか。
- **テストデータ:** `tests/testdata/subset_gene/` に、テスト用の小さなSEオブジェクト (`.rds` 形式) と期待される出力データの一部を配置する。

## 9. 依存関係
- `SummarizedExperiment`
- `dplyr` (rowDataのフィルタリング用)
- `rlang` (条件式の評価用)
- `futile.logger` (ロギング用)
- `R/utility.R` (`add_pipeline_history`)
