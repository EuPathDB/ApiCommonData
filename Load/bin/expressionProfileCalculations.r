# Command line arguments for R are not fun... so to make this easy create the args
#vvvvvvvvvvvvvvvvvvvvvvvvv GUS4_STATUS vvvvvvvvvvvvvvvvvvvvvvvvv
  # GUS4_STATUS | SRes.OntologyTerm              | auto   | absent
  # GUS4_STATUS | SRes.SequenceOntology          | auto   | absent
  # GUS4_STATUS | Study.OntologyEntry            | auto   | absent
  # GUS4_STATUS | SRes.GOTerm                    | auto   | absent
  # GUS4_STATUS | Dots.RNAFeatureExon            | auto   | absent
  # GUS4_STATUS | RAD.SageTag                    | auto   | absent
  # GUS4_STATUS | RAD.Analysis                   | auto   | absent
  # GUS4_STATUS | ApiDB.Profile                  | auto   | absent
  # GUS4_STATUS | Study.Study                    | auto   | absent
  # GUS4_STATUS | Dots.Isolate                   | auto   | absent
  # GUS4_STATUS | DeprecatedTables               | auto   | absent
  # GUS4_STATUS | Pathway                        | auto   | absent
  # GUS4_STATUS | DoTS.SequenceVariation         | auto   | absent
  # GUS4_STATUS | RNASeq Junctions               | auto   | absent
  # GUS4_STATUS | Simple Rename                  | auto   | absent
  # GUS4_STATUS | ApiDB Tuning Gene              | auto   | absent
  # GUS4_STATUS | Rethink                        | auto   | absent
  # GUS4_STATUS | dots.gene                      | manual | unreviewed
die 'This file has broken or unreviewed GUS4_STATUS rules.  Please remove this line when all are fixed or absent';
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^
# by prepending them to this script directly before the R call:  
# [bash]$ echo 'arg1 = "value";arg2="someValue"' |cat - script.r | R --no-save

# Variables inputFile and outputFile are required

# Simple Script to calculate the mean, standard deviation, standard error, rank, and percentile from a file

# The input file should be a tab del file with the first column being an identifier and NO HEADER !!!
# All columns after the first are considered to be data
# NA values are ignored

input=read.table(file=inputFile, header=FALSE, sep="\t");

meanV = vector(mode="numeric");
stdevV = vector(mode="numeric");
stderrV = vector(mode="numeric");
rankV = vector(mode="numeric");
percentileV = vector(mode="numeric");

for(i in 1:nrow(input)) {

  # count the non NA Values in THIS ROW
  numberOfElements = ncol(input) - sum(is.na(input[i, 2:ncol(input)])) - 1;

  values = as.vector(input[i, 2:ncol(input)], mode="numeric");

  meanV[i] = mean(values, na.rm=TRUE)
  
  if(numberOfElements > 1) {
    stdevV[i] = sd(values, na.rm=TRUE)
    stderrV[i] = stdevV[i] / sqrt(numberOfElements);
  }
  else {
    stdevV[i] = NA;
    stderrV[i] = NA;
  }
}

rankV=rank(meanV, na.last="keep");

n = sum(!is.na(rankV)) + 1;

for(i in 1:length(rankV)) {
  percentileV[i] = (100 * rankV[i]) / n;
}

rm(i, n, numberOfElements, values);


headers = c("row_id", "mean", "std_dev", "std_err", "percentile");
dat = cbind(input[,1], meanV, stdevV, stderrV, percentileV);
colnames(dat) = headers;

write.table(dat, file=outputFile, quote=FALSE, sep="\t", row.names=FALSE)

saveFile = paste(inputFile, ".RData", sep="");
saveHistory = paste(inputFile, ".RHistory", sep="");

save.image(saveFile);

