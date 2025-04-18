# [モジュール名] 仕様書 ([ターゲット名])

*ルール文書: `notepad/rmd-rule_long.md` 参照必須*

## 1. モジュール概要

*   **モジュール名:**
*   **対応ターゲット名:**
*   **目的:**
*   **担当者:** (任意)
*   **作成/更新日:** YYYY-MM-DD
*   **TDD適用:** (推奨/必須/非推奨 - ルール文書 **セクション 4** 参照)

## 2. 依存関係と入力

*   **依存ターゲット:** (主入力SEターゲット, `ensure_log_dir` など)
*   **入力SE状態 (`targets`経由):**
    *   `experiment_id` 一致
    *   `assays`: `counts` (必須), [その他]
    *   `colData`: `sample_id` (必須), `condition` (通常必須), [その他]
    *   `rowData`: [必要なアノテーション]
    *   `metadata`: `experiment_id` (必須), `pipeline_history` (必須 - ルール文書 **セクション 2** 参照), [その他]
*   **その他入力:** (パラメータ等)
    *   **ファイルパス:** **絶対パス**で渡される想定 (ルール文書 **セクション 1.1, 2** 参照)

## 3. 主要実行ステップ (Rmd or 関数)

*   **実行形式:** (Rmd (`tar_render`), R関数)
*   **関連ファイル:** (`Rmd/*.Rmd`, `R/*.R`)
*   **ステップ詳細:**
    1.  **[セットアップ (Rmd `setup`)]**
        *   **必須:** `library()` ロード
        *   **必須:** `futile.logger` 設定 (ルール文書 **セクション 3, 7**): ロガー名, 出力ファイル (絶対パス `params$output_log_file`), 閾値, レイアウト, アペンダー設定
        *   **推奨:** `cli` 開始メッセージ
        *   **必須:** `tar_load`/`tar_read` で入力ロード & ログ記録 (`flog.info`), バリデーション
    2.  **[ステップ2: (例: フィルタリング)]**
        *   アルゴリズム/関数
        *   主要パラメータ (由来明記, ログ記録)
    3.  **[ステップ3: (例: QC計算)]**
        *   パッケージ/関数
    4.  **[ステップ4: (例: プロット生成/保存)]**
        *   パッケージ
        *   **必須:** 出力ディレクトリ作成 (`fs::dir_create`)
        *   **必須:** **絶対パス** (`fs::path_abs()`) で保存 & パスをログ記録 (`flog.info`) (ルール文書 **セクション 8** 準拠)
    5.  **[ステップN: SEメタデータ更新]**
        *   **必須:** `metadata(se)$pipeline_history` に追記 (ルール文書 **セクション 2, 3** 参照)
            ```R
            # history_entry 構造例 (詳細はルール文書参照)
            history_entry <- list(module="...", target_name="...", timestamp=Sys.time(), parameters=list(...), input_dims=dim(input_se), output_dims=dim(se), summary="...")
            metadata(se)$pipeline_history <- c(metadata(se)$pipeline_history, list(history_entry))
            flog.info("Updated pipeline_history in SE metadata.")
            ```
    6.  **[完了ステップ]**
        *   **必須:** 結果オブジェクト返却
        *   **推奨:** `cli` 完了メッセージ
        *   **必須:** Rmdの場合、レポート生成 (パスはルール文書 **セクション 8** 参照)

## 4. 出力 (`targets`)

*   **出力ターゲット名:**
*   **出力SE状態:**
    *   `assays`: [追加/更新]
    *   `colData`: [追加/更新]
    *   `rowData`: [追加/更新]
    *   `metadata`: `experiment_id` (必須), `pipeline_history` (必須, 更新反映), `[module_name]_parameters` (推奨), `[module_name]_summary` (推奨), [その他]
*   **生成ファイル:** (プロット, テーブル, レポート等)
    *   **種別/ターゲット名/フォーマット:**
    *   **命名規則/保存場所:** ルール文書 (**セクション 1.1, 6, 8**) 準拠 **必須**
        *   **必須:** ディレクトリ作成 (`fs::dir_create`) + **絶対パス** (`fs::path_abs()`) 保存 + パスをログ出力
        *   構造例: `results/[exp_id]/plots/[module_id]/[exp_id]_[name].png`

## 5. 主要パッケージと共通関数

*   **パッケージ:** (`targets`, `SummarizedExperiment`, `fs`, `futile.logger`, `cli`, [その他])
    *   *`renv` 管理 (ルール文書 **セクション 5**)。`library()` 必須。*
*   **共通関数 (`R/`):** (関数名とソースファイル `R/*.R`)
    *   *新規作成時はテスト/仕様書検討 (ルール文書 **セクション 1.1, 4**)*

## 6. パラメータ (`_targets.R` or `config.yaml`)

*   *Rmd へは `params` で渡す (ルール文書 **セクション 1.1, 6**)*
| パラメータ名        | 説明 (簡潔に)                  | 型        | デフォルト/推奨 | 必須 | 提供元例      |
| :------------------ | :----------------------------- | :-------- | :------------- | :--- | :------------ |
| `experiment_id`     | 実験ID                         | character | -              | Yes  | `_targets.R`  |
| `rmd_file`          | Rmdファイルパス                | character | -              | Yes  | `_targets.R`  |
| `output_log_file`   | Rmdログ出力パス (絶対パス)     | character | -              | Yes  | `_targets.R`  |
| [その他パラメータ] | ...                            | ...       | ...            | ...  | `config.yaml` |
| ...                 | ...                            | ...       | ...            | ...  | ...           |

## 7. ログとメッセージ出力 (`futile.logger`, `cli`)

*   **ルール:** ルール文書 **セクション 3** 準拠 **必須**
*   **ロガー設定 (Rmd `setup`):** ロガー名, 出力ファイル, 閾値, レイアウト, アペンダー設定 **必須**
*   **ログ記録 (`flog.*`):**
    *   **必須:** 入力, 主要パラメータ, ステップ開始/終了, 出力ファイル **絶対パス**, SEメタデータ更新
    *   **推奨:** デバッグ情報 (`flog.debug`)
*   **ユーザーメッセージ (`cli`):** 主要ステップ, 要約, 警告/エラー (ログ記録とは別目的)

## 8. 出力パスと命名規則

*   **ルール:** ルール文書 **セクション 1.1, 6, 8** 準拠 **強く推奨**
*   **必須:** ディレクトリ作成 (`fs::dir_create`) + **絶対パス** (`fs::path_abs()`) 生成/保存 + パスをログ出力
*   **原則:**
    *   プロット: `results/[exp_id]/plots/[module_id]/[exp_id]_[name].png`
    *   テーブル: `results/[exp_id]/tables/[module_id]/[exp_id]_[name].csv`
    *   レポート: `results/[exp_id]/reports/[Rmdファイル名].html` (例)
    *   SEオブジェクト: `targets` ストア (直接操作回避)

## 9. 可視化要件 (レポート)

*   **ルール:** ルール文書 **セクション 8** 準拠 (`ggplot2` 標準)
*   **タイトル:** `experiment_id` 含む (`r params$exp_id`)
*   **必須プロット/テーブル:** (例: QCサマリー, PCA)
*   **推奨:** プロットに `experiment_id` 含む, インタラクティブ性
*   *`sessionInfo()` は `tar_render` が通常追加 (ルール文書 **セクション 5**)*
