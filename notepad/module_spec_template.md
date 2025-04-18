# [モジュール名] 仕様書 ([ターゲット名])

*この仕様書は `R_markdown_rule.md` に基づき作成されています。実装前に必ずルールを確認してください。*

## 1. モジュールの概要

*   **モジュール名:** (例: 品質管理とフィルタリング)
*   **対応するターゲット名 (`_targets.R`):** (例: `qc_filtered_se`, `qc_report`)
*   **目的:** (例: 生カウントデータに対して品質チェックを行い、低発現遺伝子や低品質サンプルを除去する)
*   **担当者:** (任意)
*   **作成日:** YYYY-MM-DD
*   **更新日:** YYYY-MM-DD
*   **TDD適用:** (例: 推奨（コアロジック関数に適用）, 必須, 非推奨)
    *   *`R_markdown_rule.md` のテスト方針 (セクション 4) に従ってください。特に共通関数や複雑なロジックには適用を検討してください。*

## 2. 依存関係 (`targets`) と入力データ

*   **依存するターゲット名:**
    *   (例: `raw_se`) - 主たる入力となる `SummarizedExperiment` オブジェクトを提供するターゲット。
    *   (例: `annotation_data`) - アノテーション情報を提供するターゲット (もしあれば)。
    *   [その他、パラメータセットなど、依存するターゲットがあれば記述]
*   **入力 `SummarizedExperiment` オブジェクトの状態:**
    *   **期待される `assays`:**
        *   `counts`: 生カウントデータ (必須)
        *   [その他、必要なアッセイがあれば記述]
    *   **期待される `colData`:**
        *   `sample_id`: サンプル識別子 (必須)
        *   `condition`: 実験条件 (必須、または特定のステップで必要)
        *   [その他、必要なサンプルメタデータがあれば記述]
    *   **期待される `rowData`:**
        *   [必要な遺伝子アノテーション情報があれば記述]
    *   **期待される `metadata`:**
        *   `experiment_id`: 実験ID (必須)
        *   `pipeline_history`: これまでの処理履歴を示すリスト (必須、`R_markdown_rule.md` セクション 2 参照)
        *   [その他、条件分岐等に必要なメタデータがあれば記述]
*   **その他の入力ファイル/パラメータ:**
    *   (例: フィルタリング閾値を定義したYAMLファイル、`_targets.R` から渡されるパラメータなど)

## 3. 主要な実行ステップ (Rmd または 関数)

*   **実行形式:** (例: R Markdown (`tar_render` を使用), R関数)
*   **ステップ詳細:**
    1.  [ステップ1: 例: 入力SEオブジェクトとパラメータのバリデーション]
        *   *`R_markdown_rule.md` のコーディング規約 (セクション 3) に従い、`cli` でメッセージ出力推奨。*
    2.  [ステップ2: 例: 低発現遺伝子のフィルタリング]
        *   使用アルゴリズム/手法: (例: `edgeR::filterByExpr` 関数)
        *   主要パラメータ: (例: `min.count`, `min.total.count`, `group`) - パラメータの由来 (`_targets.R` or YAML等) も明記。
    3.  [ステップ3: 例: 品質評価メトリクスの計算と `colData` への追加]
        *   使用パッケージ/関数: (例: `scater::addPerCellQC`)
    4.  [ステップ4: 例: 品質評価プロットの生成 (PCA, ライブラリサイズ分布など)]
        *   使用パッケージ: (例: `ggplot2`, `scater`, `ggfortify`)
        *   *`R_markdown_rule.md` の可視化ルール (セクション 8) に準拠。*
    5.  [ステップ5: SE オブジェクトのメタデータ更新]
        *   **必須:** このモジュールで実行した処理の概要、主要パラメータ、完了日時などを `metadata(se)$pipeline_history` に追記する。(`R_markdown_rule.md` セクション 2, 3 参照)
        *   **具体例:**
            ```R
            # metadata(se)$pipeline_history リストに追記
            history_entry <- list(
              module = "Quality Control and Filtering",
              target_name = "qc_filtered_se", # この処理に対応するターゲット名
              timestamp = Sys.time(),
              parameters = list( # 使用した主要パラメータ
                filter_method = "filterByExpr",
                min.count = params$min_count, # params から渡された値を記録
                min.total.count = params$min_total_count
              ),
              summary = paste( # 処理結果の要約
                "Filtered genes:", sum(rowData(se)$is_filtered),
                "Remaining genes:", nrow(se[!rowData(se)$is_filtered, ])
              )
            )
            metadata(se)$pipeline_history <- c(metadata(se)$pipeline_history, list(history_entry))
            ```
    6.  [ステップ6: ...]

## 4. 出力 (`targets`)

*   **出力ターゲット名:** (例: `qc_filtered_se`, `qc_plot_list`, `qc_summary_table`)
*   **出力 `SummarizedExperiment` オブジェクトの状態 (ターゲット名: 例 `qc_filtered_se`):**
    *   **追加/更新される `assays`:**
        *   [例: `logcounts` (正規化する場合)]
    *   **追加/更新される `colData`:**
        *   `qc_metrics`: (例: `scater` のQCメトリクスを含むDataFrame)
        *   `is_low_quality_sample`: (例: サンプルフィルタリングフラグ)
    *   **追加/更新される `rowData`:**
        *   `is_filtered`: (例: 遺伝子フィルタリングフラグ)
    *   **追加/更新される `metadata`:**
        *   **`pipeline_history`:** ステップ3で記述した更新内容が反映されていること (**必須**)
        *   `qc_parameters`: このモジュールで使用した全パラメータのリスト
        *   `filtering_summary`: フィルタリング結果の詳細な要約 (例: 何遺伝子がどの基準で除外されたか)
        *   [その他、後続のモジュールで利用する可能性のある情報]
*   **生成されるファイル (プロット、テーブルなど):**
    *   **ファイル種別:** (例: PCAプロット, QCサマリーテーブル)
    *   **対応するターゲット名:** (例: `qc_pca_plot`, `qc_summary_csv`)
    *   **フォーマット:** (例: PDF, PNG, CSV)
    *   **命名規則:**
        *   *`R_markdown_rule.md` で定義された命名規則に**必ず**従ってください。*
        *   (例: `{metadata(se)$experiment_id}_pca_plot.pdf`, `{metadata(se)$experiment_id}_qc_summary.csv`)
    *   **保存場所:**
        *   *`R_markdown_rule.md` で定義されたディレクトリ構造に従ってください (例: `results/plots/qc`, `results/tables/qc`)。*
        *   *逸脱が必要な場合は、その理由と具体的なパスを明記してください。*

## 5. 使用する主要パッケージと共通関数

*   **パッケージ:** (例: `SummarizedExperiment`, `targets`, `tarchetypes`, `edgeR`, `scater`, `ggplot2`, `dplyr`, `futile.logger`, `cli`)
    *   *`renv` 管理対象 (`renv::snapshot()` を実行すること)。Rmdやスクリプト冒頭で `library()` 宣言が必要。*
*   **共通関数 (from `src/utils.R` or パッケージ):**
    *   (例: `src/utils/plotting.R` の `theme_publication()`, `src/utils/se_helpers.R` の `add_metadata_history()`) 
    *   *共通関数を利用する場合は、その関数名とソースファイルを明記してください。新規に関数を作成する場合は `utility.md` への追加を検討してください。*

## 6. パラメータ (`_targets.R` または設定ファイル経由)

*   *`_targets.R` 上部または外部設定ファイル (YAML等) で管理されることを想定。Rmd内では `params$` 経由でアクセス。*
| パラメータ名          | 説明                                           | 型      | デフォルト値/推奨値 | 必須 | 提供元 (例)        |
| :-------------------- | :--------------------------------------------- | :------ | :----------------- | :--- | :----------------- |
| `min_count`           | `filterByExpr` の最小カウント閾値              | integer | `10`               | Yes  | `_targets.R`       |
| `min_total_count`     | `filterByExpr` の最小トータルカウント閾値      | integer | `15`               | Yes  | `_targets.R`       |
| `group_variable`      | `filterByExpr` で使用するグループ変数 (colData名) | character | `"condition"`    | Yes  | `_targets.R`       |
| `pca_color_by`        | PCAプロットの色分けに使用する変数 (colData名)  | character | `"condition"`    | No   | `params.yaml`      |
| ...                   | ...                                            | ...     | ...                | ...  | ...                |

## 7. ログとメッセージ出力

*   *`R_markdown_rule.md` の規約 (セクション 3) に従ってください。*
*   **ログレベル:** `INFO` (デフォルト)
*   **ログ記録 (`futile.logger`):** 内部的な処理ステップ、重要な変数の状態、パラメータ値などを記録 (冗長にならないよう注意)。
*   **ユーザーメッセージ (`cli`):** 主要ステップの開始/終了、重要な結果 (例: フィルタリングされた遺伝子数/サンプル数)、警告/エラーを表示。
*   **ログファイルの扱い:** 原則として標準出力/標準エラー出力へのログを基本とする。ファイル出力が必要な場合は理由と仕様を明記。

## 8. 出力パスと命名規則

*   *`R_markdown_rule.md` の定義に従うことを**強く推奨**します。*
*   **原則:**
    *   プロット: `results/plots/[モジュール名 or 目的]/[ターゲット名 or 詳細].{pdf,png,...}`
    *   テーブル: `results/tables/[モジュール名 or 目的]/[ターゲット名 or 詳細].{csv,tsv,...}`
    *   Rオブジェクト: `targets` のストア (`_targets/objects/`) に保存 (直接パス指定は避ける)。
*   **特記事項:** (ルールから逸脱する場合や、補足が必要な場合のみ記述)

## 9. 可視化要件

*   *`R_markdown_rule.md` の可視化原則 (セクション 8) に従ってください。*
*   **必須プロット:** (例: PCAプロット (サンプルラベル付き), ライブラリサイズ分布図, 上位変動遺伝子のヒートマップ)
*   **カラースキーム:** (例: `condition` 列に基づいて、ルールで定義されたパレットを使用)
*   **インタラクティブ性:** (例: PCAプロットは `plotly::ggplotly()` を使用してインタラクティブにする)
*   **その他:** (例: プロットの解像度、ファイル形式の指定など)

## 10. その他特記事項・制約条件

*   (例: このモジュールはヒト(hg38)データのみを想定している。)
*   (例: 大規模データセットの場合、メモリ使用量に注意し、必要であればチャンク処理などを検討する。)
*   (例: `DESeq2` の代わりに `edgeR` を使用する理由: [...]) 