# R Markdown & `targets` RNA-seq パイプライン AI構築ルール (要約版)

## 1. 基本方針
- パイプライン制御: `targets` パッケージを使用。
- 解析ステップ: R Markdown (Rmd) モジュール (`tar_render`) で実装。
- データ中心: `SummarizedExperiment` (SE) オブジェクトを使用。
- 履歴記録: SEの `metadata()$pipeline_history` に処理履歴を記録。

## 2. ディレクトリ構造とファイル命名
- **必須:**
    - `_targets.R`: パイプライン定義。
    - `config.yaml`: `experiment_id` 等の設定。
    - `R/`: 共通関数 (`Rxx_*.R`)。
    - `Rmd/`: 解析モジュール (`RMDxx_*.Rmd`)。
    - `data/{experiment_id}/`: 実験ごとの入力データ。
    - `results/{experiment_id}/`: 実験ごとの出力 (plots/, tables/, reports/)。
    - `logs/{experiment_id}/`: 実験ごとのログ。
- **ファイルパス:** 原則として `fs::path_abs()` で絶対パスを使用。

## 3. データフロー
- **SE中心:** 入力SE -> 処理 -> 出力SE (更新)。
- **メタデータ:** 各モジュールは実行内容、パラメータ、日時等を `metadata()$pipeline_history` に追記。
- **制御:** `_targets.R` でSEメタデータによる条件分岐を検討。

## 4. ロギング (`futile.logger` 必須)
- **目的:** 実行追跡、デバッグ、再現性向上。
- **設定:**
    - **出力先:** `logs/{experiment_id}/` (ターゲットで作成を保証)。
    - **ファイル名:** `_targets.log`, `RMDxx_*.log`, (必要なら `Rxx_*.log`)。
    - **レベル:** 基本 `INFO`。
    - **フォーマット:** `[タイムスタンプ] [レベル] [識別子] メッセージ`。
    - **アペンダー:** `appender.file()` (または `appender.tee()`)。
- **必須ログ内容:**
    - **`_targets.R`:** パイプライン開始/終了、設定値、ターゲット開始/終了、関数/Rmd呼び出し情報。
    - **Rmd:** セットアップチャンクでロガー設定 (`logs/{id}/{Rmd名}.log`へ出力)、入力/出力オブジェクト・ファイルパス、主要ステップ、パラメータ、メタデータ更新内容。
    - **R関数:** 呼び出し、引数、主要処理、エラー情報 (呼び出し元のロガーを使用)。

## 5. コーディング規約とテスト
- **スタイル:** Tidyverse + Bioconductor。
- **コメント:** 日本語。
- **テスト:** TDD (`testthat` Red-Green-Refactor) を推奨。

## 6. 再現性とパッケージ管理
- **再現性:** `targets` で依存関係とキャッシュを管理。
- **パッケージ:** `renv` を使用 (`renv::snapshot()`)。

## 7. モジュール仕様書 (AI向け指示の必須項目)
指示には以下を含むこと:
- **ターゲット名:** (例: `se_filtered`)
- **目的:**
- **入力:** 依存ターゲット、期待されるSE状態 (assay/coldata/rowdata/metadata履歴)、他ファイル/パラメータ (`experiment_id` 依存パス明記)。
- **実行処理:** `tar_render` or 関数、関連ファイル名、主要ステップ/パラメータ (`experiment_id` を params で渡す)、SEメタデータ更新ロジック、必須ログ項目とロガー名、ログ出力先 (`logs/{id}/...`)。
- **出力:** 期待されるSE状態 (更新後)、生成ファイルリストと保存場所 (`results/{id}/...`、絶対パス推奨)。
- **レポート要件 (Rmd):** 含める図表/情報、YAMLでの出力形式設定推奨 (`html_document`, `md_document` など)。

## 8. パイプライン構成 (`_targets.R`)
- **実行順序:** ターゲット間の依存関係で定義。
- **柔軟性:** `experiment_id` の変更で別データに同一フロー適用可能。 

## 9. 可視化とレポート
- **標準パッケージ:** `ggplot2`(プロット), `pheatmap`/`ComplexHeatmap`(ヒートマップ), `RColorBrewer`/`viridis`(配色)。
- **プロットスタイル:**
  - **テーマ:** 基本 `theme_classic()`、必要に応じて独自テーマ関数で一貫性維持。**プロットタイトルは中央寄せ (`theme(plot.title = element_text(hjust = 0.5))`) にする。**
  - **言語:** プロット内ラベル/タイトル/凡例は**英語**のみ（レポート本文は日本語可）。
  - **形式:** 基本PNG (`ggsave(..., width=7, height=5, dpi=300)`)、大型ヒートマップはPDF、対話的プロットはHTML。
  - **命名規則:** `{プロットタイプ}_{データタイプ}_{条件}.{拡張子}`
  - **保存場所:** `results/{experiment_id}/plots/` (絶対パスで指定)。
- **生成と管理:**
  - 重要プロットは独立関数として実装、再利用可能に。
  - `targets`ターゲットとして自動生成。
  - 生成時は`futile.logger`でログ記録。 