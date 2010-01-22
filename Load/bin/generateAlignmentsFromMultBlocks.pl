#!/usr/bin/perl

# 0      1       2       3               4       5       6               7               8
# qName	tName	strand	blockCount	qStarts	tStarts	blockSizes	misMatches	genomeMatches

# bowtie
#  0         1       2          3                            4                5     6               7
# query_id  strand  target_id  target_start(offset from 0)  query_sequence   ???   genomeMatches   misMatch string
#7_14_2008:1:2:117:568   +       Tb927_03_v4     927217  TTTTGGTTGCGCACCTACAAATTGCCAACTCAGAAC    IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII   9 

use strict;
use Getopt::Long;

my $filename;
my $maxGenomeMatch = 1;
my $maxBlockCount = 2;
my $sample;
my $mappingFile;
my $fileType;
my $extdbrelid;


&GetOptions("filename|f=s" => \$filename, 
            "maxGenomeMatch|m=i"=> \$maxGenomeMatch,
            "maxBlockCount|b=i"=> \$maxBlockCount,
            "sample|e=s"=> \$sample,
            "mappingFile|mf=s"=> \$mappingFile,
            "fileType|ft=s"=> \$fileType,
            "ext_db_rel_id|eid=i"=> \$extdbrelid,
            );

die "usage: generateAlignmentsFromMultBlocks.pl 
             --filename|f <filename> 
             --maxGenomeMatch|m <matchesToGenome[1]> 
             --maxBlockCount <maxBlocks[1]> 
             --sample <sample name (reqired)> 
             --type <type of analysis (unique|multiple|provider)> 
             --mappingFile|mf <filename of source_id\tna_sequence_id mapping> 
             --ext_db_rel_id|eid <external_database_release_id for this experiment> 
             --fileType|ft <(blat|bowtie)>\n" unless $sample && $fileType =~ /(blat|bowtie)/i;

my %map;
if($mappingFile){
  open(M,"$mappingFile") || die "unable to open $filename\n";
  while(<M>){
    chomp;
    my@tmp = split("\t",$_);
    next unless scalar(@tmp) == 2;
    $map{$tmp[0]} = $tmp[1];
  }
  close M;
}

my $ct = 0;
my $data = {};
my %dis;

#print "\t$extdbrelid\tsample\tsequence_id\tquery_id\tstrand\tstart_a\tend_a\tstart_b\tend_b\tintron_size\tgenomeMatches\n";

open(F,"$filename") || die "unable to open $filename\n";
while(<F>){
  chomp;
  my @line = split("\t",$_);
  if($fileType =~ /blat/i){
    next $line[3] > $maxBlockCount;
    next if $line[8] > $maxGenomeMatch;
    my @s = split(",",$line[6]);
    my @ts = split(",",$line[5]);
    my $d = $ts[1]-($ts[0] + $s[0]);
    #  next unless $d > 20;
    $dis{$d}++;
    my $newId = $mappingFile ? $map{$line[1]} : $line[1];
    if(!$newId){
      print STDERR "unable to map $line[1]\n";
      next;
    }
    push(@{$data->{$newId}},[$newId,$line[0],$line[2],$ts[0]+1,$ts[0]+$s[0],($ts[1] ? $ts[1]+1 : undef),($ts[1] ? $ts[1]+$s[1] : undef),($ts[1] ? $ts[1]+1 - ($ts[0]+$s[0]) : undef),$line[8]]);
  }elsif($fileType =~ /bowtie/i){
    next if $line[6]+1 > $maxGenomeMatch;
    my $newId = $mappingFile ? $map{$line[2]} : $line[2];
    if(!$newId){
      print STDERR "unable to map $line[2]\n";
      next;
    }
    push(@{$data->{$newId}},[$newId,$line[0],$line[1],$line[3]+1,$line[3]+length($line[4]), undef, undef, undef,$line[6]+1]);
  }
}

#foreach my $d (sort {$a <=> $b}keys%dis){
#  print "$d: $dis{$d}\n";
#}

foreach my $val (values %{$data}){
  foreach my $h (sort {$a->[2] <=> $b->[2]} @{$val}){
    print "\t$extdbrelid\t$sample\t",join("\t",@{$h}),"\n";
  }
}
