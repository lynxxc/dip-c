'''
Seurat & Signac 
Code primarily follows https://stuartlab.org/signac/articles/pbmc_multiomic.html and https://satijalab.org/seurat/articles/integration_introduction.html
'''

library(Signac)
library(Seurat)
library(EnsDb.Hsapiens.v86)
library(BSgenome.Hsapiens.UCSC.hg38)
library(dplyr)
library(ggplot2)

# Re-analysis of published data --------------------------------------------------------------------------------------------------------
seurat_object <- readRDS("published_data/kozareva_2021/sn035.rds") 

# example plot marker genes 
FeaturePlot(seurat_object, features = "FOXP2", coord.fixed = TRUE, pt.size = 1, cols = CustomPalette(low = rgb(0.85,0.85,0.85), high = rgb(1,0,0)))


# Defualt seurat pipeline for individual samples ----------------------------------------------------------------------------------------
set.seed(1234)
counts <- Read10X_h5("/path/to/filtered_feature_bc_matrix.h5")
fragpath <- "/path/toatac_fragments.tsv.gz"
annotation <- GetGRangesFromEnsDb(ensdb = EnsDb.Hsapiens.v86)
seqlevelsStyle(annotation) <- "UCSC"

seurat_object <- CreateSeuratObject(
  counts = counts$`Gene Expression`,
  assay = "RNA"
)
seurat_object[["ATAC"]] <- CreateChromatinAssay(
  counts = counts$Peaks,
  sep = c(":", "-"),
  fragments = fragpath,
  annotation = annotation
)

DefaultAssay(seurat_object) <- "ATAC"
seurat_object <- NucleosomeSignal(seurat_object)
seurat_object <- TSSEnrichment(seurat_object)

seurat_object <- subset(
  x = seurat_object
,
  subset = nCount_ATAC < 100000 &
    nCount_RNA < 25000 &
    nCount_ATAC > 1000 &
    nCount_RNA > 500 &
    nucleosome_signal < 2 &
    TSS.enrichment > 1
)

peaks <- CallPeaks(seurat_object, macs2.path = "/path/to/macs2")
# remove peaks on nonstandard chromosomes and in genomic blacklist regions
peaks <- keepStandardChromosomes(peaks, pruning.mode = "coarse")
peaks <- subsetByOverlaps(x = peaks, ranges = blacklist_hg38_unified, invert = TRUE)

# quantify counts in each peak
macs2_counts <- FeatureMatrix(
  fragments = Fragments(seurat_object
),
  features = peaks,
  cells = colnames(seurat_object
)
)
# create a new assay using the MACS2 peak set and add it to the Seurat object
seurat_object[["peaks"]] <- CreateChromatinAssay(
  counts = macs2_counts,
  fragments = fragpath,
  annotation = annotation
)

DefaultAssay(seurat_object) <- "RNA"
seurat_object <- SCTransform(seurat_object)
seurat_object <- RunPCA(seurat_object)

DefaultAssay(seurat_object) <- "peaks"
seurat_object <- FindTopFeatures(seurat_object, min.cutoff = 5)
seurat_object <- RunTFIDF(seurat_object)
seurat_object <- RunSVD(seurat_object)
# build a joint UMAP visualization
seurat_object <- RunUMAP(
  object = seurat_object
,
  nn.name = "weighted.nn",
  assay = "RNA",
  verbose = TRUE
)
seurat_object <- FindMultiModalNeighbors(
  object = seurat_object
,
  reduction.list = list("pca", "lsi"),
  dims.list = list(1:50, 2:40),
  modality.weight.name = "RNA.weight",
  verbose = TRUE
)
saveRDS(seurat_object, file = "/path/to/sample.rds")

# Creating a combined Seurat object --------------------------------------------------------------------------------------------------

# example with 3 samples 
hcb.0_1yo <- readRDS(file = "/path/to/first-sample.rds")
hcb.0_2yo <- readRDS(file = "/path/to/second-sample.rds")
hcb.0_4yo <- readRDS(file = "/path/to/third-sample.rds")

hcb.0_1yo <- AddMetaData(hcb.0_1yo, metadata = "0.1a", col.name= "age")
hcb.0_2yo <- AddMetaData(hcb.0_2yo, metadata = "0.2", col.name= "age")
hcb.0_4yo  <- AddMetaData(hcb.0_4yo, metadata = "0.4", col.name= "age")

hcb.combined = merge(hcb.0_1yo, y = c(hcb.0_2yo, hcb.0_4yo), add.cell.ids = c("01a", "02", "04"), project = "hcb.combined")

saveRDS(hcb.combined, file = "~/research/multiome/seurat/combined/human-cerebellum-combined.rds")
