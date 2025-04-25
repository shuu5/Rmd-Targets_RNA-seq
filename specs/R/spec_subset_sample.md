# R関数仕様書: subset_sample

## 1. 概要
- **目的:** SummarizedExperiment オブジェクトからサンプル条件に基づいてサブセットを作成する
- **機能:** colData の指定された列と条件式を用いてサンプル（列）のサブセットを作成し、処理履歴を記録する
- **作成日:** 2025-04-25
- **更新日:** 2025-04-25

## 2. 機能詳細
- SummarizedExperiment オブジェクトの colData 内の指定列に対して条件式を評価し、条件を満たすサンプルのみを抽出する
- 抽出条件をメタデータとして記録し、パイプライン履歴に追加する
- サブセットの名前を条件に基づいて自動生成する（例：`IFITM3-KD`）
- project-rule.md の「データ処理・前処理」ステップに対応

## 3. 入力 (Arguments)
- **se:**
  - **データ型:** `SummarizedExperiment`
  - **説明:** サブセット対象となる SummarizedExperiment オブジェクト
  - **必須/任意:** 必須
  - **デフォルト値:** なし

- **column_name:**
  - **データ型:** `character`
  - **説明:** サブセット条件を適用する colData の列名
  - **必須/任意:** 必須
  - **デフォルト値:** なし

- **condition:**
  - **データ型:** `character` または `expression`
  - **説明:** サブセットに使用する条件式（文字列または式オブジェクト）
  - **必須/任意:** 必須
  - **デフォルト値:** なし

- **subset_name:**
  - **データ型:** `character`
  - **説明:** 生成するサブセットの名前（指定しない場合は条件から自動生成）
  - **必須/任意:** 任意
  - **デフォルト値:** NULL

- **logger_name:**
  - **データ型:** `character`
  - **説明:** ロギングに使用するロガー名
  - **必須/任意:** 必須
  - **デフォルト値:** なし

## 4. 出力 (Return Value)
- **データ型:** `SummarizedExperiment`
- **説明:** 条件に基づいてサブセットされた SummarizedExperiment オブジェクト
- **ファイル出力:** なし（オブジェクトのみ返却）

## 5. 処理フロー / 主要ステップ
1. 入力パラメータの検証
   - `se` が SummarizedExperiment オブジェクトであることを確認
   - `column_name` が colData に存在することを確認
   - `condition` が有効な条件式であることを確認
2. サブセット条件の評価
   - 文字列の場合は式に変換
   - colData の指定列に対して条件式を評価
   - 条件を満たすサンプルのインデックスを取得
3. サブセット名の決定
   - `subset_name` が指定されていない場合、条件から自動生成
   - 例: `column_name-condition` 形式（`treatment-control` など）
4. SummarizedExperiment オブジェクトのサブセット作成
   - `se[, subset_indices]` を使用して列方向のサブセットを作成
5. メタデータとパイプライン履歴の更新
   - 元のサンプル数と新しいサンプル数を記録
   - 使用した条件とサブセット名を記録
   - `add_pipeline_history` を使用してメタデータを更新
6. サブセットされた SummarizedExperiment オブジェクトを返却

## 6. 副作用 (Side Effects)
- **SummarizedExperiment のメタデータ更新:**
  - `metadata()$pipeline_history` に以下の内容で新しいエントリを追加:
    - `step_id`: ターゲット名（例: "obj_se_subset"）
    - `function_name`: "subset_sample"
    - `timestamp`: 処理実行時のタイムスタンプ
    - `parameters`: リスト（column_name, condition, subset_name）
    - `input_dimensions`: 元の SE オブジェクトの次元
    - `output_dimensions`: サブセット後の SE オブジェクトの次元
    - `details`: サブセット条件と結果のサンプル数に関する説明
  - `metadata()$subset_info` に以下の内容を追加または更新:
    - `column_name`: サブセットに使用した列名
    - `condition`: 適用した条件
    - `subset_name`: 設定されたサブセット名
    - `original_samples`: 元のサンプル数
    - `subset_samples`: サブセット後のサンプル数

## 7. ログ仕様 (`futile.logger`)
- **ログファイル名:** `logs/{experiment_id}/subset_sample.log`
- **主要ログメッセージ:**
  - **INFO:** 関数開始: "Starting sample subsetting with column '%s' and condition '%s'"
  - **DEBUG:** 列の値の確認: "Values in column '%s': %s"
  - **INFO:** サブセット結果: "Subset resulted in %d out of %d samples (%.1f%%)"
  - **DEBUG:** サブセット名: "Using subset name: '%s'"
  - **WARN:** サブセット結果が0件: "Subsetting resulted in 0 samples. Check condition '%s' on column '%s'"
  - **ERROR:** 列が存在しない: "Column '%s' does not exist in colData"
  - **ERROR:** 条件式評価エラー: "Error evaluating condition '%s': %s"
  - **INFO:** 関数終了: "Sample subsetting completed. Returning SE object with %d samples"

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-subset_sample.R`
- **テスト項目:**
  - **正常系:**
    - 単純な条件（等値）でサブセットが正しく機能することを確認
    - 複雑な条件（論理演算、正規表現など）でサブセットが正しく機能することを確認
    - サブセット名の自動生成が期待通りに機能することを確認
    - 明示的にサブセット名を指定した場合に正しく機能することを確認
  - **異常系:**
    - 存在しない列名を指定した場合にエラーとなることを確認
    - 無効な条件式を指定した場合にエラーとなることを確認
    - サブセット結果が0件の場合に警告が発生することを確認
  - **副作用:**
    - メタデータの pipeline_history が正しく更新されることを確認
    - メタデータの subset_info が正しく設定されることを確認
- **テストデータ:** `tests/testdata/subset_sample/` にモック SE オブジェクトを配置

## 9. 依存関係
- **パッケージ:**
  - `SummarizedExperiment`: SE オブジェクトの操作
  - `futile.logger`: ロギング
  - `S4Vectors`: SE オブジェクトの metadata 操作
- **自作関数:**
  - `add_pipeline_history`: パイプライン履歴更新用共通関数 (utility.R) 