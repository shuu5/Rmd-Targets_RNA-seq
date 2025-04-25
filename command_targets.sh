#!/bin/bash

# Function to display help message
usage() {
  cat << EOF
使用法: $0 <コマンド> [targetsオプション...]

targetsコマンドを便利に実行するためのラッパースクリプトです。

コマンド:
  make        パイプラインを実行します (targets::tar_make())。
              例: $0 make reporter = \"verbose\"  # 詳細なレポーターを使用
              例: $0 make callr_function = NULL  # callr を無効化
              例: $0 make workers = 4           # 4つのワーカーで並列実行

  vis         パイプラインのグラフを可視化します (targets::tar_visnetwork())。
              デフォルトではtargets_only=TRUEが適用されます。
              例: $0 vis                        # デフォルトでターゲットのみ表示
              例: $0 vis targets_only = FALSE   # 関数も含めて表示
              例: $0 vis label = \"branches\"    # ブランチ名を表示
              例: $0 vis level_separation = 150 # ノード間の距離を調整

  outdated    古いターゲットを表示します (targets::tar_outdated())。
              例: $0 outdated branches = TRUE    # ブランチの古さもチェック
              例: $0 outdated reporter = \"summary\" # 要約レポーターを使用

  prune       不要になったファイルやメタデータを削除します (targets::tar_prune())。
              パイプラインから削除されたターゲットに関連するファイルをクリーンアップします。
              例: $0 prune

  destroy     ターゲットストア (_targets/ オブジェクトとメタデータ) を完全に削除します (targets::tar_destroy())。
              注意: この操作は元に戻せません。
              例: $0 destroy ask = FALSE          # 確認プロンプトをスキップ

  validate    _targets.R ファイルを検証します (targets::tar_validate())。
              例: $0 validate callr_function = NULL # callr を無効化

  graph       パイプラインの依存関係グラフをテキストで表示します (targets::tar_network())。
              例: $0 graph targets_only = TRUE     # ターゲットのみ表示
              例: $0 graph reporter = \"forecast\"  # 予測レポーターを使用

  manifest    パイプラインのマニフェスト (ターゲットの詳細情報) を表示します (targets::tar_manifest())。
              例: $0 manifest fields = c(name, command) # 名前とコマンドのみ表示

  rerun       指定したターゲットを無効化して再実行します。
              最初にターゲット名を指定し、その後に追加の make オプションを指定できます。
              例: $0 rerun obj_se_raw            # obj_se_raw を再実行
              例: $0 rerun obj_se_raw workers=2  # obj_se_raw をワーカー2つで再実行

  help, -h, --help   このヘルプメッセージを表示します

追加の引数は、それぞれのtargets関数に直接渡されます。
= や TRUE/FALSE の前後にスペースを入れないでください (例: targets_only=TRUE)。
文字列を引数として渡す場合は、\" \" で囲んでください (例: reporter=\"verbose\")。
EOF
  exit 1
}

# Check if any argument is provided
if [ $# -eq 0 ]; then
  usage
fi

COMMAND=$1
shift # Remove the command argument, leaving only options for targets

# Main command execution logic
case "$COMMAND" in
  make)
    Rscript -e "targets::tar_make($*)"
    ;;
  vis)
    echo "Generating PNG visualization (targets_network.png)..."
    # チェックして targets_only=FALSE が明示的に指定されている場合はその値を使用
    # そうでなければデフォルトで targets_only=TRUE を適用
    if [[ "$*" == *"targets_only = FALSE"* ]] || [[ "$*" == *"targets_only=FALSE"* ]]; then
      # targets_only=FALSE が指定されている場合はそのまま渡す
      Rscript scripts/generate_vis_png.R --output targets_network.png $*
    else
      # targets_only が指定されていないか、TRUE が指定されている場合
      # targets_only=TRUE が既に含まれているかチェック
      if [[ "$*" == *"targets_only = TRUE"* ]] || [[ "$*" == *"targets_only=TRUE"* ]]; then
        # 既に targets_only=TRUE が指定されている場合はそのまま渡す
        Rscript scripts/generate_vis_png.R --output targets_network.png $*
      else
        # targets_only が指定されていない場合はデフォルト値を追加
        Rscript scripts/generate_vis_png.R --output targets_network.png targets_only=TRUE $*
      fi
    fi
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
      echo "PNG generated successfully: targets_network.png"
    else
      echo "Error generating PNG."
      exit $EXIT_CODE
    fi
    ;;
  outdated)
    Rscript -e "targets::tar_outdated($*)"
    ;;
  prune)
    Rscript -e "targets::tar_prune($*)"
    ;;
  destroy)
    Rscript -e "targets::tar_destroy($*)"
    ;;
  validate)
    Rscript -e "targets::tar_validate($*)"
    ;;
  graph)
    Rscript -e "targets::tar_network($*)"
    ;;
  manifest)
    Rscript -e "targets::tar_manifest($*)"
    ;;
  rerun)
    if [ -z "$1" ]; then
      echo "Error: rerun コマンドにはターゲット名を指定する必要があります。" >&2
      usage
    fi
    TARGET_NAME=$1
    shift # ターゲット名を取り除く
    echo "Invalidating target: ${TARGET_NAME}..."
    Rscript -e "targets::tar_invalidate(name = ${TARGET_NAME})"
    INVALIDATE_EXIT_CODE=$?
    if [ $INVALIDATE_EXIT_CODE -ne 0 ]; then
      echo "Error invalidating target ${TARGET_NAME}." >&2
      exit $INVALIDATE_EXIT_CODE
    fi
    echo "Running make to rerun ${TARGET_NAME} and downstream targets..."
    Rscript -e "targets::tar_make($*)" # 残りの引数は make に渡す
    MAKE_EXIT_CODE=$?
    if [ $MAKE_EXIT_CODE -ne 0 ]; then
      echo "Error running make after invalidation." >&2
      exit $MAKE_EXIT_CODE
    fi
    echo "Target ${TARGET_NAME} rerun complete."
    ;;
  help | -h | --help)
    usage
    ;;
  *)
    echo "Error: Unknown command '$COMMAND'" >&2
    usage
    ;;
esac

exit 0
