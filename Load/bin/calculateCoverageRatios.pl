#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;


   
# get parameter values
my $experimentDir;
my $outputDir;
my $chromSizesFile;

&GetOptions("experimentDir|e=s" => \$experimentDir,
            "outputDir|o=s" => \$outputDir,
            "chromSizesFile|c=s" => \$chromSizesFile);

# extract information from a bedFile of binned coverage
sub bedExtract {
    my $bedFile = "@_";
    open (BED, "$bedFile") or die "Cannot open $bedFile\n$!\n";
    my @bedLines;
    while (<BED>) {
        my ($chr, $start, $end, $mapped) = split(/\t/,$_);
        push (@bedLines, [$chr, $start, $end, $mapped]);
    }
    close (BED);
    return \@bedLines 
}

# Extract the name of the sample from the name of the bedfile
sub bedName {
    my $bedFile = "@_";
    my $fileName = (split(/\/([^\/]+)$/, $bedFile))[1];
    my $sampleName = (split(/\./, $fileName))[0];
    return $sampleName
}

# Get all bedfiles in dir
my @bedFiles = `ls $experimentDir/*.bed`;

#Determine which one is the ref for the expt (should have 'ref' in filename)
# TODO - this needs to exit if there is >1 ref file too
my $index = 0;
my $refFile;
$index ++ until index($bedFiles[$index], 'ref') != -1 or $index == scalar @bedFiles -1;
#Check that you have found ref and not just reached end of array
if (index($bedFiles[$index], 'ref') != -1) {
    #Set reference file and remove from array
    $refFile = $bedFiles[$index];
    splice(@bedFiles, $index, 1);
}else{
    die "There is no reference file";
}

# Calculate coverage ratio for each sample in comparison to the reference
my $refCoverage = bedExtract($refFile);
my $refName = bedName($refFile);
foreach my $compFile (@bedFiles){
    my $compCoverage = bedExtract($compFile);
    my $compName = bedName($compFile);
    my $count = 0;
    my $outputFile = $outputDir."/".$refName."_".$compName.".bed.tmp";
    open (OUT, ">$outputFile") or die "Cannot write output file\n$!\n";
    foreach my $ref (@{$refCoverage}){
        my ($refChr, $refStart, $refEnd, $refMapped) = @{$ref};
        my ($compChr, $compStart, $compEnd, $compMapped) = @{@{$compCoverage}[$count]};
        ++$count;
        if ($refChr eq $compChr && $refStart == $compStart && $refEnd ==$compEnd){
            my $mapRatio = $compMapped/$refMapped unless ($refMapped == 0 || $compMapped == 0);
            if (defined($mapRatio)){
                printf OUT "%s\t%d\t%d\t%g\n", $refChr, $refStart, $refEnd, $mapRatio;
            }
        }else{
            die "Elements in reference and comparison arrays are not in the same order\n";
        }
    }
    close (OUT);
    # sort bedGraph File
    my $sortedOutput = $outputDir."/".$refName."_".$compName.".bed";
    system ("sort -k1,1 -k2,2n $outputFile > $sortedOutput");
    # convert to bigwig
    my $bigWig = $outputDir."/".$refName."_".$compName.".bw";
    system ("bedGraphToBigWig $sortedOutput $chromSizesFile $bigWig");
    # remove unsorted bedGraph
    system ("rm -f $outputFile");
}
exit;

