#!/bin/bash

# Function to display help message
usage() {
  cat << EOF
使用法: $0 <コマンド> [テストオプション...]

testthatコマンドを便利に実行するためのラッパースクリプトです。

コマンド:
  all         すべてのテストを実行します。
              例: $0 all reporter = \"summary\"       # 要約レポーターを使用
              例: $0 all filter = \"deg\"            # "deg"を含むテストのみ実行

  file        特定のテストファイルを実行します。
              例: $0 file test-deg_edgeR.R
              例: $0 file test-utility.R reporter = \"progress\"

  dir         特定のディレクトリのテストを実行します。
              例: $0 dir tests/testthat/
              例: $0 dir tests/testthat/ filter = \"create\"

  list        利用可能なテストファイルを一覧表示します。
              例: $0 list

  snapshot    スナップショットテストを更新します。
              例: $0 snapshot update = TRUE
              
  help, -h, --help   このヘルプメッセージを表示します

追加の引数は、それぞれのtestthat関数に直接渡されます。
= や TRUE/FALSE の前後にスペースを入れないでください (例: filter=\"deg\")。
文字列を引数として渡す場合は、\" \" で囲んでください (例: reporter=\"progress\")。

利用可能なレポーター:
- summary: 簡潔な要約レポート（デフォルト）
- progress: プログレスバー付きの詳細レポート
- minimal: 最小限の出力
- check: R CMD check形式の出力
- fail: 失敗したテストのみ表示
- tap: Test Anything Protocol形式
EOF
  exit 1
}

# ログディレクトリの作成
ensure_log_dir() {
  local log_dir="tests/logs"
  if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    echo "ログディレクトリを作成しました: $log_dir"
  fi
}

# Check if any argument is provided
if [ $# -eq 0 ]; then
  usage
fi

COMMAND=$1
shift # Remove the command argument, leaving only options for testthat

# Main command execution logic
case "$COMMAND" in
  all)
    ensure_log_dir
    echo "すべてのテストを実行中..."
    Rscript -e "sapply(list.files('R', pattern='\\\\.R$', full.names=TRUE), source); testthat::test_dir('tests/testthat', $*)" 2>&1 | tee "tests/logs/test_all_latest.log"
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
      echo "すべてのテストが成功しました。"
    else
      echo "テスト実行中にエラーが発生しました。詳細はログファイルを確認してください。"
    fi
    exit $exit_status
    ;;
  file)
    ensure_log_dir
    if [ $# -eq 0 ]; then
      echo "エラー: テストファイル名を指定してください" >&2
      usage
    fi
    test_file=$1
    shift # ファイル名を削除し、残りのオプションを testthat に渡す
    
    # ファイルへのパスを修正（必要に応じて）
    if [[ "$test_file" != "tests/testthat/"* && "$test_file" != "/"* ]]; then
      test_file="tests/testthat/$test_file"
    fi
    
    if [ ! -f "$test_file" ]; then
      echo "エラー: テストファイル '$test_file' が見つかりません" >&2
      exit 1
    fi
    
    echo "テストファイル '$test_file' を実行中..."
    file_basename=$(basename "$test_file")
    # R関数をロードしてからテストを実行 (R/ 内の全 .R ファイルを source する)
    Rscript -e "sapply(list.files('R', pattern='\\\\.R$', full.names=TRUE), source); testthat::test_file('$test_file', $*)" 2>&1 | tee "tests/logs/test_${file_basename%.*}_latest.log"
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
      echo "テストが成功しました。"
    else
      echo "テスト実行中にエラーが発生しました。詳細はログファイルを確認してください。"
    fi
    exit $exit_status
    ;;
  dir)
    ensure_log_dir
    if [ $# -eq 0 ]; then
      echo "エラー: テストディレクトリを指定してください" >&2
      usage
    fi
    test_dir=$1
    shift # ディレクトリ名を削除し、残りのオプションを testthat に渡す
    
    if [ ! -d "$test_dir" ]; then
      echo "エラー: テストディレクトリ '$test_dir' が見つかりません" >&2
      exit 1
    fi
    
    echo "ディレクトリ '$test_dir' のテストを実行中..."
    dir_basename=$(basename "$test_dir")
    # R関数をロードしてからテストを実行
    Rscript -e "sapply(list.files('R', pattern='\\\\.R$', full.names=TRUE), source); testthat::test_dir('$test_dir', $*)" 2>&1 | tee "tests/logs/test_dir_${dir_basename}_latest.log"
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
      echo "テストが成功しました。"
    else
      echo "テスト実行中にエラーが発生しました。詳細はログファイルを確認してください。"
    fi
    exit $exit_status
    ;;
  list)
    # テストファイルの一覧を表示
    echo "利用可能なテストファイル:"
    find tests/testthat -name "test-*.R" | sort
    exit 0
    ;;
  snapshot)
    ensure_log_dir
    echo "スナップショットテストを更新中..."
    # R関数をロードしてからテストを実行
    Rscript -e "sapply(list.files('R', pattern='\\\\.R$', full.names=TRUE), source); testthat::test_dir('tests/testthat', $*)" 2>&1 | tee "tests/logs/snapshot_update_latest.log"
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
      echo "スナップショットテストが更新されました。"
    else
      echo "スナップショットテスト更新中にエラーが発生しました。詳細はログファイルを確認してください。"
    fi
    exit $exit_status
    ;;
  help | -h | --help)
    usage
    ;;
  *)
    echo "エラー: 不明なコマンド '$COMMAND'" >&2
    usage
    ;;
esac

exit 0 