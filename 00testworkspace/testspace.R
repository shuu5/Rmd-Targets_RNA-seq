library(tidyverse)
library(pheatmap)
# data/stomach_TCGA_GTEx/のcounts.csvとclinical.csvを読み込む
counts <- read_csv("data/stomach_TCGA_GTEx/counts.csv")
clinical <- read_csv("data/stomach_TCGA_GTEx/clinical.csv")

# countsの最初の数行を表示
print(head(counts))

# heatmapを作成
# countsはtibbleであるため、matrixに変換
# 行ごとの分散を計算し、分散が大きい上位100遺伝子を抽出
counts_matrix <- counts %>%
  # 数値列のみを選択して行分散を計算し、元のデータに列として追加
  # NAがある場合に備えて na.rm = TRUE を追加
  mutate(variance = apply(select(., where(is.numeric)), 1, var, na.rm = TRUE)) %>%
  # 分散の降順で並び替え
  arrange(desc(variance)) %>%
  # 上位100行を選択
  slice_head(n = 100) %>%
  # 計算に使用した分散列を削除
  select(-variance) %>%
  # gene_id列を行名に設定
  column_to_rownames(var = "gene_id") %>%
  # matrixに変換
  as.matrix()

# edgeRパッケージを読み込む (インストールされていない場合はインストールが必要)
# if (!requireNamespace("edgeR", quietly = TRUE)) BiocManager::install("edgeR")
library(edgeR)

# DGEListオブジェクトを作成
dge <- DGEList(counts = counts_matrix)

# TMM正規化係数を計算
dge <- calcNormFactors(dge, method = "TMM")

# CPM値を計算 (log=FALSEがデフォルトですが、明示的に示すこともできます)
cpm_matrix <- cpm(dge, log = FALSE)

# log変換
cpm_matrix_log <- log2(cpm_matrix + 1)

# heatmapを作成 (正規化後のデータを使用する場合)
# scalingを有効かして
pheatmap(cpm_matrix_log, scale = "row") # 必要に応じてこちらの行を有効化

# 元のカウントデータでheatmapを作成する場合
pheatmap(counts_matrix)


