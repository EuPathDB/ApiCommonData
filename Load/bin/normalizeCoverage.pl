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
  # GUS4_STATUS | dots.gene                      | manual | reviewed
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^

use strict;
use Getopt::Long;
use lib "$ENV{GUS_HOME}/lib/perl";
use CBIL::Util::Utils;
use List::Util qw(min max);
use ApiCommonData::Load::AnalysisConfigRepeatFinder qw(displayAndBaseName);
use File::Basename;
use CBIL::TranscriptExpression::SplitBamUniqueNonUnique qw(splitBamUniqueNonUnique);
use Data::Dumper;
# this script loops through each experiment output directory and sums the score under each experiment. 
# Use sum_score / max_sum_core as normalization ratio and update coverage file 
#
#  ... Su_strand_specific/analyze_lateTroph/master/mainresult
#  ... Su_strand_specific/analyze_schizont/master/mainresult
#  ... Su_strand_specific/analyze_gametocyteII/master/mainresult
#  ... Su_strand_specific/analyze_gametocyteV/master/mainresult

my %hash;

my ($inputDir, $strandSpecific, $topLevelSeqSizeFile, $isPairedEnd); 

&GetOptions("inputDir=s"            => \$inputDir,
            "topLevelSeqSizeFile=s" => \$topLevelSeqSizeFile,
            "strandSpecific!"       => \$strandSpecific,
	    "isPairedEnd!" => \$isPairedEnd
 );

my $usage =<<endOfUsage;
Usage:
  normalizeCoverage.pl --inputDir input_diretory --topLevelSeqSizeFile chrosome_size_file --strandSpecific --isPairedEnd

    intpuDir: top level directory, e.g. /eupath/data/EuPathDB/workflows/PlasmoDB/bigwig/data/pfal3D7/organismSpecificTopLevel/Su_strand_specific
    topLevelSeqSizeFile: chromosome size text file e.g. /eupath/data/EuPathDB/workflows/PlasmoDB/bigwig/data/pfal3D7/organismSpecificTopLevel/topLevelSeqSizes.txt
    strandSpecific: required if the experiement is strand specific
  isPairedEnd: required if the experiment is paired end 
endOfUsage

die $usage unless -e $inputDir;
die $usage unless -e $topLevelSeqSizeFile;

opendir(DIR, $inputDir);
my @ds = readdir(DIR);

# pull display name and base name for any with replciation
my $analysis_config_display;
my $samplesHash;
foreach my $analysis_config (glob "$inputDir/*/final/analysisConfig.xml") {
    $samplesHash = displayAndBaseName($analysis_config);	

}    

my %dealingWithReps;

my $mappingStatsBasename = "mappingStats.txt";

foreach my $old_dir (glob "$inputDir/analyze_*_combined") {
	my $cmd = "rm -r $old_dir";
#	print Dumper "command is $cmd\n";
	&runCmd($cmd);
	print Dumper "trying to delete folder $old_dir\n";
}
   
foreach my $exp_dir (glob "$inputDir/analyze_*/master/mainresult") {
	my $mappingStats = "$exp_dir/$mappingStatsBasename";
	if(-e $mappingStats) {
	    my $statsString = `cat $mappingStats`;
	    if($statsString =~ /DONE STATS/) {
		next;
	    }
	    else {
		print "data set $exp_dir has not been split on unique non unique mapping. doing this now ...\n";
		my $splitExpDir = splitBamUniqueNonUnique($exp_dir, $strandSpecific, $isPairedEnd, "$exp_dir/results_sorted.bam");
	    }
	}
	else {
	    print "data set $exp_dir has not been split on unique non unique mapping. doing this now ...\n";
	    my $splitExpDir = splitBamUniqueNonUnique($exp_dir, $strandSpecific, $isPairedEnd, "$exp_dir/results_sorted.bam");
	}
}

foreach my $groupKey (keys %$samplesHash) {
  my @samples = @{$samplesHash->{$groupKey}->{samples}};
  my @mappingStatsFiles = map {"$inputDir/analyze_${_}/master/mainresult"} @samples;

  if(scalar @mappingStatsFiles > 1) {
    push @{$dealingWithReps{$groupKey}}, @mappingStatsFiles;
  }
  else {
    $hash{$mappingStatsFiles[0]} = &getCountHash($mappingStatsFiles[0], $mappingStatsBasename);
  }
}
#print Dumper %$samplesHash;

#print Dumper "rep hash is \n";
#print Dumper %dealingWithReps;
 
foreach my $expWithReps (keys %dealingWithReps) {
    my $count = 0;
    my %scoreHash;
    my $exp_dir = "$inputDir/analyze_$expWithReps"."_combined";
    my $cmd = "mkdir $exp_dir";
     &runCmd($cmd);
     my $cmd = "mkdir $exp_dir/master";
     &runCmd($cmd);
     my $cmd = "mkdir $exp_dir/master/mainresult";
     &runCmd($cmd);
    $exp_dir = "$exp_dir/master/mainresult";
    my $listOfUniqueRepBwFiles;
    my $listOfNonUniqueRepBwFiles;
    my $listOfUniqueFirstStrandFiles;
    my $listOfUniqueSecondStrandFiles;
    my $listOfNonUniqueFirstStrandFiles;
    my $listOfNonUniqueSecondStrandFiles;
    my @FileSets;
    &makeMappingFile($dealingWithReps{$expWithReps}, $exp_dir, $mappingStatsBasename);
#need to add here dealing with the stand etc.     
    foreach my $replicateDir (@{$dealingWithReps{$expWithReps}}) {
 	foreach	my $file_to_open (glob "$replicateDir/*.bed") {
 	    my $baseBed = basename $file_to_open;
 	    my $bwFile = $baseBed;
 	    $bwFile =~ s/\.bed$/.bw/;
	    &runCmd("bedGraphToBigWig $replicateDir/$baseBed $topLevelSeqSizeFile $replicateDir/$bwFile"); 
	    if ($baseBed =~ /^unique/) {
		if ($baseBed =~/firststrand/)  {
		    $listOfUniqueFirstStrandFiles.= "$replicateDir/$bwFile ";
		}
		elsif ($baseBed =~/secondstrand/) {
		    $listOfUniqueSecondStrandFiles.= "$replicateDir/$bwFile ";
		}
		else{
		    $listOfUniqueRepBwFiles.= "$replicateDir/$bwFile ";
		}
	    }
	    elsif ($baseBed =~ /^non_unique/) {
		if ($baseBed =~/firststrand/)  {
		    $listOfNonUniqueFirstStrandFiles.= "$replicateDir/$bwFile ";
		}
		elsif ($baseBed =~/secondstrand/) {
		    $listOfNonUniqueSecondStrandFiles.= "$replicateDir/$bwFile ";
		}
		else{
		    $listOfNonUniqueRepBwFiles.= "$replicateDir/$bwFile ";
		}
		
	
	    }
 	}
	
    }
    push @FileSets , ($listOfUniqueFirstStrandFiles, $listOfUniqueSecondStrandFiles, $listOfUniqueRepBwFiles, $listOfNonUniqueFirstStrandFiles, $listOfNonUniqueSecondStrandFiles, $listOfNonUniqueRepBwFiles);
 #   print Dumper @FileSets;
    
    foreach my $set (@FileSets) {
	next unless (defined $set);
	my @temps = split  " ", $set;
	my $fileToUse = $temps[0];
#	print Dumper $fileToUse;
	my $base = basename $fileToUse;
	$base =~ s/\.bw//;
	my $cmd = "bigWigMerge -max $set $exp_dir/${base}CombinedReps.bed";
#	print Dumper "command now for the reps is $cmd\n";
	&runCmd($cmd);
  #  my $cmd = "bigWigMerge -max $listOfNonUniqueRepBwFiles $exp_dir/non_uniqueCombinedReps.bed";
  #  &runCmd($cmd);
    }
	$hash{$exp_dir} = &getCountHash($exp_dir, $mappingStatsBasename);
}



update_coverage(\%hash);

merge_normalized_coverage(\%hash);

sub merge_normalized_coverage {
    my $hash = shift;
    while(my ($k, $v) = each %$hash) {  # $k is exp directory; %v is sum_coverage
 	my $dir = "$k/normalized";
 	if(!-e "$dir/final") {
 	    &runCmd("mkdir $k/normalized/final");
 	}
	
 	my @bedFiles = glob "$k/normalized/*.bed";
	
 	foreach my $bedFile (@bedFiles) {
 	    my $baseBed = basename $bedFile;
 	    my $bwFile = $baseBed;
 	    $bwFile =~ s/\.bed$/.bw/;
	    
 	    &runCmd("bedGraphToBigWig $k/normalized/$baseBed $topLevelSeqSizeFile $k/normalized/final/$bwFile"); 
 	}
     }
 }

# # updates coverage file - score * normalization_ratio
# # save updated coverage file to the new 'normalized' directory
sub update_coverage {
    my $hash = shift;
    my %hash2 = %$hash;

    foreach my $k (keys %hash2) {  # $k is exp directory; $v is sum_coverage  
	my @sorted = sort {$a <=> $b } values %{$hash2{$k}};
	my $max_sum_coverage = pop @sorted;
	opendir(D, $k);
	my @fs = readdir(D);
	
	my $cmd = "mkdir $k/normalized";
	if(!-e "$k/normalized") {
	    &runCmd($cmd);
	}
	
	my $out_dir = "$k/normalized";
	
	foreach my $f (@fs) {
	    next if $f !~ /\.bed/i;
	    open(F, "$k/$f");
	    open OUT, ">$out_dir/$f";
	    my $outputFile = $f;
	    my $bamfile = $f;
	    $bamfile =~ s/\.bed$/.bam/;
	    print Dumper "trying to match $bamfile in $k";
	    $outputFile =~ s/\.bed$/_unlogged.bed/;
	    open OUTUNLOGGED, ">$out_dir/$outputFile";
	    print Dumper %hash2;
	    my $coverage = $hash2{$k}{$bamfile};

	    <F>;
	    while(<F>) {
		my($chr, $start, $stop, $score) = split /\t/, $_;
		
		next unless ($chr && $start && $stop && $score);
		
		my $normalized_score = $score == 0 ? 0 : sprintf ("%.2f", ($score * $max_sum_coverage / $coverage ));
		print OUTUNLOGGED "$chr\t$start\t$stop\t$normalized_score\n";
		my $normalized_score_logged = sprintf ("%.2f", ((log($normalized_score))/(log(2))));
		print OUT "$chr\t$start\t$stop\t$normalized_score_logged\n";
		
	    }
	    close F;
	    close OUT;
	    close OUTUNLOGGED;
	}
    }
}

sub getCountHash {
    
    my %hash;
    my $d = shift;
    my $f = shift;
    open my $IN, "$d/$f" or die "cant find mapping file $d/$f\n\n\n";
    while(my $line = <$IN>) {
	chomp $line;
	if ($line =~ /file/) {
	    next;
	}
	elsif ($line =~ /^\s*$/) {
	    next;
	}
	elsif ($line =~ /DONE STATS/) {
	    next;
	}
	else {
	    my($file, $coverage, $percentage, $count) = split /\t/, $line;
	    my $shortfile = basename $file;
	    $hash{$shortfile} = $count;
	}
    }
    return \%hash;
}


sub makeMappingFile{
    my ($repFiles, $comboDir, $mappingStatsBase) = @_;

    my $countReps = 0;
    my %totals;
    foreach my $rep (@$repFiles) {
            $countReps ++;
            open(R, "$rep/$mappingStatsBase") or die "Cannot open file $rep/$mappingStatsBase for reading:$!";;
            <R>;
            while(<R>) {
        	chomp $_;
        	if ($_ =~ /file/) {
        	    next;
        	}
        	elsif ($_ =~ /^\s*$/) {
        	    next;
        	}
        	elsif ($_ =~ /DONE STATS/) {
        	    next;
        	}
        	else {
        	    my($file, $coverage, $percentage, $count) = split /\t/, $_;
        	    my $shortname = basename $file;
        	    if (exists $totals{$shortname}) {
        		@{$totals{$shortname}}[0] += $coverage;
        		@{$totals{$shortname}}[1] += $percentage;
        		@{$totals{$shortname}}[2] += $count;
        	    }
        	    else {
        		@{$totals{$shortname}} = ($coverage, $percentage, $count);
        	    }
		    
        	}
            }


    }
    my $mapping = $comboDir."/mappingStats.txt";
    open (M, ">$mapping") or die "Could not open file $mapping for writing: $!";;
    print M "file\tcoverage\tpercentageMapped\treadsMapped\n";

    foreach my $key (keys %totals) {
        my $finalFile = $key;
        $finalFile =~ s/_results_sorted.bam/_results_sortedCombinedReps.bam/;
	$finalFile =~ s/results.bam/resultsCombinedReps.bam/;
        my $finalCoverage= ($totals{$key}->[0] / $countReps);
        my $finalPercentage= ($totals{$key}->[1]/ $countReps);
        my $finalCount = ($totals{$key}->[2] / $countReps) ;
        print M "$finalFile\t$finalCoverage\t$finalPercentage\t$finalCount\n";
	
    }
    close M;
    return "finished";
}
