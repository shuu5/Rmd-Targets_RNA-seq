# R関数仕様書: plot_log_density

## 1. 概要
- **目的:** SummarizedExperiment オブジェクトの指定されたアッセイデータを対数変換 (log1p) し、サンプルごとのデータ分布を密度プロットとして可視化してファイルに保存する。
- **機能:** アッセイデータの対数変換、データの整形、ggplot2による密度プロット作成、プロットのファイル保存、ファイルパスの返却。
- **作成日:** 2024-08-01
- **更新日:** 2024-08-01

## 2. 機能詳細
- 指定されたアッセイデータを `log1p()` (log(x+1)) で対数変換する。
- 変換後のデータをサンプルごとに縦持ち形式 (long format) に整形する (`tidyr::pivot_longer` など)。
- サンプルごとに色分けされた密度プロットを `ggplot2` で作成する。
- プロットのテーマは `theme_classic()` を基本とし、テキストは英語表記とする (`project-rule.md` 準拠)。
- 生成されたプロットを指定されたディレクトリにPNGファイルとして保存する。
- `project-rule.md` のデータQCや正規化効果の確認ステップに対応する。

## 3. 入力 (Arguments)
- **引数名:** `se`
    - **データ型:** `SummarizedExperiment`
    - **説明:** 解析対象のSEオブジェクト。`assay()` で指定されたアッセイデータを含む必要がある。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `experiment_id`
    - **データ型:** `character`
    - **説明:** 実験ID。出力ファイルパスの生成に使用される。`run_with_logging` から渡される想定。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `assay_name`
    - **データ型:** `character`
    - **説明:** 対数変換とプロットに使用するアッセイ名。`assayNames(se)` に含まれている必要がある。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `output_dir`
    - **データ型:** `character` (パス)
    - **説明:** プロットファイルを保存するディレクトリ。通常は `results/{experiment_id}/plots`。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `logger_name`
    - **データ型:** `character`
    - **説明:** ログ出力に使用するロガー名。`run_with_logging` から渡される想定。
    - **必須/任意:** 必須
    - **デフォルト値:** `"default"`
- **引数名:** `target_name`
    - **データ型:** `character`
    - **説明:** この関数を実行する `targets` ターゲット名。`add_pipeline_history` で使用する。`run_with_logging` から渡される想定。
    - **必須/任意:** 必須
    - **デフォルト値:** `"unknown_target"`

## 4. 出力 (Return Value)
- **データ型:** `fs::path` (または `character`)
- **説明:** 生成されたプロットファイルの**絶対パス**。
- **ファイル出力:**
    - **ファイルパス:** `{output_dir}/log_density_{assay_name}_{experiment_id}.png`
    - **ファイル形式:** PNG
    - **ファイル内容:** 指定アッセイデータのlog1p変換後のサンプル別密度プロット。

## 5. 処理フロー / 主要ステップ
1.  入力引数の検証。
2.  `flog.info` で関数開始と主要パラメータをログ記録。
3.  `assay(se, assay_name)` で指定アッセイデータを取得。
4.  `log1p()` でデータを対数変換。
5.  変換後データを `data.frame` または `tibble` にし、縦持ち形式に変換 (`tidyr::pivot_longer`)。列はサンプル名 (`sample`) と対数値 (`log_value`) を含む。
6.  `flog.debug` でデータ整形完了をログ記録。
7.  `ggplot()` を使用して密度プロットオブジェクト (`gg`) を作成。
    - `aes(x = log_value, colour = sample)`
    - `geom_density()`
    - `theme_classic()` + `theme(plot.title = element_text(hjust = 0.5))`
    - `labs(title = glue::glue("Density of log1p({assay_name})"), x = "log1p(value)", y = "Density", colour = "Sample")`
8.  `flog.debug` でプロットオブジェクト作成完了をログ記録。
9.  出力ファイルパスを生成 (絶対パス)。
10. `ggplot2::ggsave()` でプロットをPNGファイルとして保存 (解像度、サイズ指定)。
11. `flog.info` でファイル保存完了とパスをログ記録。
12. メタデータ更新は行わない。
13. `flog.info` で関数終了をログ記録。
14. 生成されたファイルの絶対パスを返す。

## 6. 副作用 (Side Effects)
- 指定された `output_dir` にプロットファイル (`log_density_{assay_name}_{experiment_id}.png`) を書き込む。
- SEオブジェクトのメタデータ更新は行わない。

## 7. ログ仕様 (`futile.logger`)
- **ログレベル:** INFO, DEBUG, WARN, ERROR
- **ログ内容:**
    - 関数開始 (INFO, 引数)
    - アッセイデータ取得成功/失敗 (DEBUG/ERROR)
    - 対数変換完了 (DEBUG)
    - データ整形完了 (DEBUG)
    - プロットオブジェクト作成完了 (DEBUG)
    - ファイル保存試行 (DEBUG, パス)
    - ファイル保存成功 (INFO, パス)
    - ファイル保存失敗 (ERROR)
    - 関数終了 (INFO)
- **ログファイル名:** `logs/{experiment_id}/plot_log_density.log` (`run_with_logging` が設定)

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-plot_log_density.R`
- **テスト項目:**
    - **正常系:**
        - 正しい入力で関数がエラーなく実行される。
        - 戻り値が期待されるファイルパスである。
        - 期待されるパスにPNGファイルが生成されている。
        - (発展) 生成された `ggplot` オブジェクトが期待通りか (例: `geom_density` を含むか)。
    - **異常系:**
        - `se` が不正な場合にエラー。
        - `assay_name` が存在しない場合にエラー。
        - `output_dir` が不正な場合にエラー。
- **テストデータ:** テスト内で簡単なSEオブジェクトを作成。

## 9. 依存関係
- `SummarizedExperiment`
- `ggplot2`
- `dplyr`
- `tidyr`
- `tibble`
- `futile.logger`
- `fs`
- `glue` 