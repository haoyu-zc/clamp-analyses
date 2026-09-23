args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Expected one output path")

suppressPackageStartupMessages({
  library(org.Hs.eg.db)
  library(GO.db)
  library(AnnotationDbi)
})

if (as.character(packageVersion("org.Hs.eg.db")) != "3.20.0") {
  stop("org.Hs.eg.db 3.20.0 is required")
}
if (as.character(packageVersion("GO.db")) != "3.20.0") {
  stop("GO.db 3.20.0 is required")
}

terms <- AnnotationDbi::Term(GO.db::GOTERM)
ontology <- AnnotationDbi::Ontology(GO.db::GOTERM)
bp_ids <- sort(names(ontology)[ontology == "BP"])

sets <- suppressMessages(AnnotationDbi::mapIds(
  org.Hs.eg.db,
  keys = bp_ids,
  column = "SYMBOL",
  keytype = "GOALL",
  multiVals = "list"
))

out <- file(args[[1]], "w")
for (id in names(sets)) {
  genes <- unique(sets[[id]])
  genes <- genes[!is.na(genes)]
  if (!length(genes)) next
  writeLines(paste(c(id, unname(terms[id]), genes), collapse = "\t"), out)
}
close(out)
