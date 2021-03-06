#' pfam domain annotation and summarization.
#' @description Summarizes amino acid positions and annotates them with pfam domain information.
#' @param maf an \code{\link{MAF}} object generated by \code{\link{read.maf}}
#' @param AACol manually specify column name for amino acid changes. Default looks for field 'AAChange'
#' @param summarizeBy Summarize domains by amino acid position or conversions. Can be "AAPos" or "AAChange"
#' @param top How many top mutated domains to label in the scatter plot. Defaults to 5.
#' @param domainsToLabel Default NULL. Exclusive with top argument.
#' @param varClass which variants to consider for summarization. Can be nonSyn, Syn or all. Default nonSyn.
#' @param baseName If given writes the results to output file. Default NULL.
#' @param width width of the file to be saved.
#' @param height height of the file to be saved.
#' @param labelSize font size for labels. Default 1.
#' @return returns a list two tables summarized by amino acid positions and domains respectively. Also plots top 5 most mutated domains as scatter plot.
#' @examples
#' laml.maf <- system.file("extdata", "tcga_laml.maf.gz", package = "maftools")
#' laml <- read.maf(maf = laml.maf)
#' pfamDomains(maf = laml, AACol = 'Protein_Change')
#' @export


pfamDomains = function(maf = NULL, AACol = NULL, summarizeBy = 'AAPos', top = 5, domainsToLabel = NULL, baseName = NULL, varClass = 'nonSyn', width = 5, height = 5, labelSize = 1){


  summarizeBy.opts = c('AAPos', 'AAChange')

  if(!summarizeBy %in% summarizeBy.opts){
    stop('summarizeBy can only be either AAPos or AAChange')
  }

  if(length(summarizeBy) > 1){
    stop('summarizeBy can only be either AAPos or AAChange')
  }

  varClas.opts = c('nonSyn', 'Syn', 'all')

  if(!varClass %in% varClas.opts){
    stop('varClas can only be either nonSyn, Syn or all')
  }

  if(length(varClass) > 1){
    stop('varClas can only be either nonSyn, Syn or all')
  }

  gs = getGeneSummary(maf)

  if(varClass == 'Syn'){
    mut = maf@maf.silent
  }else if(varClass == 'all'){
    mut = subsetMaf(maf = maf, fields = AACol, includeSyn = TRUE, mafObj = FALSE, query = "Variant_Type != 'CNV'")
  }else{
    mut = subsetMaf(maf = maf, fields = AACol, includeSyn = FALSE, mafObj = FALSE, query = "Variant_Type != 'CNV'")
  }

  mut = mut[!Variant_Type %in% 'CNV']

  #Protein domain source.
  gff = system.file('extdata', 'protein_domains.RDs', package = 'maftools')
  gff = readRDS(file = gff)
  data.table::setDT(x = gff)

  if(is.null(AACol)){
    pchange = c('HGVSp_Short', 'Protein_Change', 'AAChange')
    if(pchange[pchange %in% colnames(mut)] > 0){
      pchange = suppressWarnings(pchange[pchange %in% colnames(mut)][1])
      message(paste0("Assuming protein change information are stored under column ", pchange,". Use argument AACol to override if necessary."))
      colnames(mut)[which(colnames(mut) == pchange)] = 'AAChange'
    }else{
      message('Available fields:')
      print(colnames(mut))
      stop('AAChange field not found in MAF. Use argument AACol to manually specifiy field name containing protein changes.')
    }
  }else{
    colnames(mut)[which(colnames(mut) == AACol)] = 'AAChange'
  }

  prot.dat = mut[,.(Hugo_Symbol, Variant_Type, Variant_Classification, AAChange)]

  #prot.dat = prot.dat[Variant_Classification != 'Splice_Site']
  #Remove 'p.'
  prot.spl = strsplit(x = as.character(prot.dat$AAChange), split = '.', fixed = TRUE)
  prot.conv = sapply(sapply(prot.spl, function(x) x[length(x)]), '[', 1)

  prot.dat[,conv := prot.conv]
  if(nrow(prot.dat[conv %in% c("", NA)]) > 0){
    warning(paste('Removed', nrow(prot.dat[conv %in% c(NA, "")]),
                  'mutations for which AA position was not available', sep = ' '), immediate. = TRUE)
    #print(prot.dat[is.na(prot.dat$pos),])
    prot.dat = prot.dat[!conv %in% c(NA, "")]
  }
  pos = gsub(pattern = '[[:alpha:]]', replacement = '', x = prot.dat$conv)
  pos = gsub(pattern = '\\*$', replacement = '', x = pos) #Remove * if nonsense mutation ends with *
  pos = gsub(pattern = '^\\*', replacement = '', x = pos)
  pos = gsub(pattern = '\\*.*', replacement = '', x = pos) #Remove * followed by position e.g, p.C229Lfs*18
  #return(pos)
  pos = as.numeric(sapply(strsplit(x = pos, split = '_', fixed = TRUE), '[[', 1))
  prot.dat[,pos := pos]
  prot.dat = prot.dat[!is.na(pos)]
  #return(prot.dat)

  if(summarizeBy == 'AAPos'){
    prot.sum = prot.dat[,.N, by = .(Hugo_Symbol, Variant_Classification ,pos)]
    prot.sum = merge(prot.sum, gs[,.(Hugo_Symbol ,total)], by = 'Hugo_Symbol')
    prot.sum = prot.sum[order(N, decreasing = TRUE)]
    prot.sum[,fraction := N/total]
    prot.sum = data.table::data.table(HGNC = prot.sum[,Hugo_Symbol], Start = prot.sum[,pos], End = prot.sum[,pos],
                          Variant_Classification = prot.sum[,Variant_Classification],
                          N = prot.sum[,N], total = prot.sum[,total], fraction = prot.sum[,fraction])
  }else{
    prot.sum = prot.dat[,.N, by = .(Hugo_Symbol, Variant_Classification ,AAChange, pos)]
    prot.sum = merge(prot.sum, gs[,.(Hugo_Symbol ,total)], by = 'Hugo_Symbol')
    prot.sum = prot.sum[order(N, decreasing = TRUE)]
    prot.sum[,fraction := N/total]
    prot.sum = data.table::data.table(HGNC = prot.sum[,Hugo_Symbol], Start = prot.sum[,pos], End = prot.sum[,pos],
                          Variant_Classification = prot.sum[,Variant_Classification], AAChange = prot.sum[,AAChange],
                          N = prot.sum[,N], total = prot.sum[,total], fraction = prot.sum[,fraction])
  }

  gff = gff[,.(HGNC, Start, End, Label, pfam, Description)]
  data.table::setkey(gff, HGNC, Start, End)
  #return(list(prot.sum, gff))
  gff.idx = data.table::foverlaps(prot.sum, gff, type="within", which=TRUE, nomatch = NA, mult = 'first')

  prot.sum[, idx:=gff.idx]

  prot.sum.na = prot.sum[is.na(prot.sum[,idx])]
  prot.sum.na[,Label := NA]
  prot.sum.na[,pfam := NA]
  prot.sum.na[,Description := NA]
  if('AAChange' %in% colnames(prot.sum.na)){
    prot.sum.na = prot.sum.na[,.(HGNC, Start, Variant_Classification, AAChange, N, total, fraction, Label, pfam, Description)]
  }else{
    prot.sum.na = prot.sum.na[,.(HGNC, Start, Variant_Classification, N, total, fraction, Label, pfam, Description)]
  }


  prot.sum = prot.sum[!is.na(prot.sum[,idx])]
  prot.sum = cbind(prot.sum, gff[prot.sum[,idx]])
  if('AAChange' %in% colnames(prot.sum)){
    prot.sum = prot.sum[,.(HGNC, Start, Variant_Classification, AAChange, N, total, fraction, Label, pfam, Description)]
    prot.sum = rbind(prot.sum, prot.sum.na)
    colnames(prot.sum)[c(2, 8)] = c('AAPos', 'DomainLabel')
  }else{
    prot.sum = prot.sum[,.(HGNC, Start, Variant_Classification, N, total, fraction, Label, pfam, Description)]
    prot.sum = rbind(prot.sum, prot.sum.na)
    colnames(prot.sum)[c(2, 7)] = c('AAPos', 'DomainLabel')
  }

  #domain.sum = prot.sum[,.N, DomainLabel]
  domain.sum = prot.sum[, .(nMut = sum(N)),by= DomainLabel]
  domain.sum = domain.sum[order(nMut, decreasing = TRUE)]

  nGeneDomain = prot.sum[,.(nGenes = length(unique(HGNC))), by = DomainLabel]
  nGeneDomain = nGeneDomain[order(nGenes, decreasing = TRUE)]

  domainSum = merge(domain.sum, nGeneDomain, by = 'DomainLabel')
  colnames(domainSum)[2] = 'nMuts'
  domainSum = domainSum[complete.cases(domainSum)]

  ggfd = gff[!duplicated(gff$Label)]
  domainSum = merge(x = domainSum, y = ggfd[,.(Label, pfam, Description)], by.x = 'DomainLabel', by.y = 'Label', all.x = TRUE)

  domainSum = domainSum[order(nMuts, decreasing = TRUE)]

  if(!is.null(domainsToLabel)){
    lab_dat = domainSum[DomainLabel %in% domainsToLabel]
  }else{
    lab_dat = domainSum[1:top]
  }

  if(!is.null(baseName)){
    write.table(x = prot.sum, file = paste(baseName, '_AAPos_summary.txt',sep= ''), quote = FALSE, row.names = FALSE, sep = '\t')
    write.table(x = domainSum, file = paste(baseName, '_domainSummary.txt',sep= ''), quote = FALSE, row.names = FALSE, sep = '\t')
    pdf(file = paste(baseName, '_domainSummary.pdf',sep= ''), width = width, height = height, paper = "special", bg = "white")
  }

  par(mar = c(4, 4, 2, 2))
  xx = bubble_plot(plot_dat = domainSum, lab_dat = lab_dat, x_var = "nMuts", y_var = "nGenes",
              bubble_var = "nGenes", text_var = "DomainLabel", text_size = labelSize, return_dat = FALSE)
  #return(xx)
  mtext(text = "# mutations", side = 1, line = 2.5, cex = 1.2)
  mtext(text = "# genes", side = 2, line = 2.5, cex = 1.2)

  if(!is.null(baseName)){
    dev.off()
  }

  return(list(proteinSummary = prot.sum, domainSummary = domainSum))
}
