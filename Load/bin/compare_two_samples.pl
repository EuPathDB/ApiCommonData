#!/usr/bin/perl
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
                                                           
# Author: Elisabetta Manduchi
# Copyright University of Pennsylvania 2011

# Modified on 03/02/2011, by Ganesh Srinivasamoorthy to estimate only 
# the p values (and ignore the gene expression/fold change calculations)

# Uses fisher.R (same author/copyright)

# Returns 2 files: one for up-regulation in condition 1 vs condition 2,
# the other for down-regulation. In each file, genes are ranked in order
# of increasing p-values from the one-sided Fisher Exact Test and, for ties,
# decreasing fold change.
# Output files have the following columns: gene_id, RPKM condition 1,
# RPKM condition 2, adjusted ratio/inverse ratio, p-value. 
# Only genes with count>= minimum depth specified by user, are output.

# Assumes input files are generated by RUM 1.01.

use strict;
use IO::File;

if (scalar(@ARGV)==0) {
  die "Usage:\ncompare_counts_between_two_samples.pl <mapping_stats_file_1> <mapping_stats_file_2> <counts_file_1> <counts_file_2> <min_depth> <output_prefix> <Rscript_path> <min or max> <paired_end yes/no>\n";
}

my $Rcmd = `which R`;
chomp($Rcmd);
if ($Rcmd =~ /Not Found/) {
  die "R is needed to run this plug-in.\n";
}

my ($numMappers1, $numMappers2);
my $fh = IO::File->new("<$ARGV[0]") || die "Cannot open file $ARGV[0]\n";
my $startRead = 0;
my $value = 0;

while (my $line=<$fh>) {
  if (($line =~ /^TOTAL/) && $ARGV[8] eq 'yes'){ 
      $startRead = 1;
  } elsif (($line =~ /^TOTAL:\s+(\S+)\s+\(/) && ($ARGV[8] eq 'no')){
      $value = $1;
    last;
  }
  if (($line =~ /one of forward or reverse mapped:\s+(\S+)\s+\(/) && ($startRead == 1)){
      $value = $1;
    last;
  }
}

$fh->close();

$value =~ s/,//g;
$numMappers1 = $value;
STDOUT->print("n1=$numMappers1\n");


$fh = IO::File->new("<$ARGV[1]") || die "Cannot open file $ARGV[1]\n";

$startRead = 0;
while (my $line=<$fh>) {
  if (($line =~ /^TOTAL/) && $ARGV[8] eq 'yes'){ 
      $startRead = 1;
  } elsif (($line =~ /^TOTAL:\s+(\S+)\s+\(/) && ($ARGV[8] eq 'no')){
      $value = $1;
    last;
  }
  if (($line =~ /one of forward or reverse mapped:\s+(\S+)\s+\(/) && ($startRead == 1)){
      $value = $1;
    last;
  }
}  

$fh->close();

$value =~ s/,//g;
$numMappers2 = $value;
STDOUT->print("n2=$numMappers2\n");


my $data1;
$fh = IO::File->new("<$ARGV[2]") || die "Cannot open file $ARGV[2]\n";
while (my $line=<$fh>) {
  if ($line !~ /^transcript/) {
    next;
  }
  chomp($line);
  my @arr = split(/\t/, $line);
  if ($ARGV[7] eq 'min') {
    $data1->{$arr[6]}->{'count'} = $arr[2];
  }
  if ($ARGV[7] eq 'max') {
    $data1->{$arr[6]}->{'count'} = $arr[2] + $arr[3];
  }
}
$fh->close();

my $data2;
$fh = IO::File->new("<$ARGV[3]") || die "Cannot open file $ARGV[3]\n";
while (my $line=<$fh>) {
  if ($line !~ /^transcript/) {
    next;
  }
  chomp($line);
  my @arr = split(/\t/, $line);
  if ($ARGV[7] eq 'min') {
    $data2->{$arr[6]}->{'count'} = $arr[2];
  }
  if ($ARGV[7] eq 'max') {
    $data2->{$arr[6]}->{'count'} = $arr[2] + $arr[3];
  }
}
$fh->close();

$fh = IO::File->new(">counts.tmp");
foreach my $id (sort keys(%{$data1})) {
  $fh->print("$data1->{$id}->{'count'}\t$data2->{$id}->{'count'}\n");
}

STDOUT->print('Calling R ...');
my $Rscript = $ARGV[6] . "/fisher.R";
my $tmpOutFile = $ARGV[5] . ".tmp";
my $cmd = "echo 'inputFile=\"counts.tmp\";outputFile=\"$tmpOutFile\";n1=$numMappers1;n2=$numMappers2' | cat - $Rscript | $Rcmd --slave --no-save";  
system("$cmd");
if (!-e "$tmpOutFile" || `grep "Error" $tmpOutFile`) {
  die "R script failed.\n";
}
unlink('counts.tmp');

my %p;
$fh = IO::File->new("<$tmpOutFile");
my $i = 0;
my @ids = sort keys(%{$data1});
while (my $line=<$fh>) {
  chomp($line);
  $p{$ids[$i]} = $line;
  $i++;
}
$fh->close();
unlink("$tmpOutFile");

#my $avg1 = 0;
#my $geneCounter = 0;
#$fh = IO::File->new("<$ARGV[4]") || die "Cannot open file $ARGV[4]\n";
#while (my $line=<$fh>) {
#  chomp($line);
#  my ($id, $value) = split(/\t/, $line);
#  $data1->{$id}->{'expr'} = $value;
#  $avg1 += $value;
#  $geneCounter++;
#}
#$fh->close();
#$avg1 = $avg1/$geneCounter;
#STDOUT->print("AVG1=$avg1\n");

#my $avg2 = 0;
#$fh = IO::File->new("<$ARGV[5]") || die "Cannot open file $ARGV[5]\n";
#while (my $line=<$fh>) {
#  chomp($line);
#  my ($id, $value) = split(/\t/, $line);
#  $data2->{$id}->{'expr'} = $value;
#  $avg2 += $value;
#}
#$fh->close();
#$avg2 = $avg2/$geneCounter;
#STDOUT->print("AVG2=$avg2\n");

#my $adjustment = ($avg1+$avg2)/20;
#if($adjustment == 0) {
#    $adjustment = .0000001;
#}
#STDOUT->print("adjustment=$adjustment\n");

#my %ratio;
#foreach my $id (keys %{$data1}) {
#  $ratio{$id} = ($data1->{$id}->{'expr'}+$adjustment)/($data2->{$id}->{'expr'}+$adjustment);
#}

my $wfh1 = IO::File->new(">$ARGV[5]_pvalues.txt");
$wfh1->print("row_id\tpvalue_mant\tpvalue_exp\n");

foreach my $id (sort sortByFisherRatio keys %{$data1}) {
  if ($data1->{$id}->{'count'}>=$ARGV[4] || $data2->{$id}->{'count'}>=$ARGV[4]) {

    my @valueSplit = split(/e/,$p{$id});

    $valueSplit[1] = $valueSplit[1] ? $valueSplit[1]:0;

    my $string = "$id\t$valueSplit[0]\t$valueSplit[1]\n";

    $wfh1->print($string);
  }
}
$wfh1->close();

sub sortByFisherRatio {
  my $p1 = $p{$a};
  my $p2 = $p{$b};
   ($p1 <=> $p2);
}


