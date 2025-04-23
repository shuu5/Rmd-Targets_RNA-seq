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
              例: $0 vis targets_only = TRUE     # ターゲットのみ表示
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
    Rscript R/generate_vis_png.R --output targets_network.png $*
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
  help | -h | --help)
    usage
    ;;
  *)
    echo "Error: Unknown command '$COMMAND'" >&2
    usage
    ;;
esac

exit 0
