#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;

use Getopt::Long;

my ($convFile, $externFile, $outFile, $setFile, $test);

GetOptions("c|conversionFile=s" => \$convFile, "x|externalOwl=s" => \$externFile, "s|settingsFile=s" => \$setFile, "o|outputFile=s" => \$outFile, "t|test!" => \$test);


my $basename = basename($convFile, '.csv');
if (-e $convFile){ symlink($convFile, basename($convFile)); }
$basename =~ s/_conversion//;
my ($subProject) = split(/_/, $outFile);
$outFile ||= sprintf("%s.owl", $basename);
my $outDir = dirname($outFile) || ".";

$outDir .= "/"; 

#my $cmdline = "java -jar $ENV{PROJECT_HOME}/ApiCommonData/Load/ontology/script/OWLconverter.jar -settingFilename %s";
my $cmdline = "java -jar $ENV{HOME}/bin/OWLmaker.jar -settingFilename %s";
$setFile ||= sprintf("%s/%s_settings.txt", $outDir, $basename);

# params: conversion.csv, external .owl,  owl basename, owl basename

my $settingsTemplate = <<TEMPLATE_END;
path	
input file	%s
output file	%s.owl
ontology IRI	http://purl.obolibrary.org/obo/%s/%s.owl
IRI base	http://purl.obolibrary.org/obo/
prefix	EUPATH
start ID	1
external ontology file	%s
term position	3
term IRI position	2
term parent position	10
term parent IRI position	9
annotation property	variable|EUPATH_0000755
annotation property	displayOrder|EUPATH_0000274
annotation property	dataFile|EUPATH_0001001
annotation property	definition|IAO_0000115
annotation property	category|EUPATH_0001002
annotation property	codebookDescription|EUPATH_0001003
annotation property	codebookValues|EUPATH_0001004
annotation property	termType|EUPATH_0001005
annotation property	repeated|EUPATH_0001011
annotation property	is_temporal|EUPATH_0001015
annotation property	mergeKey|EUPATH_0001016
annotation property	dataSet|EUPATH_0001010
annotation property	replaces|EUPATH_0001006
annotation property	unitLabel|EUPATH_0001008
annotation property	unitIRI|EUPATH_0001009
annotation property	is_featured|EUPATH_0001012
annotation property	hidden|EUPATH_0001013
annotation property	scale|EUPATH_0001014
annotation property	defaultDisplayRangeMin|EUPATH_0001017
annotation property	defaultDisplayRangeMax|EUPATH_0001018
annotation property	defaultBinWidth|EUPATH_0001019
annotation property	forceStringType|EUPATH_0001020
TEMPLATE_END

unless (-e $setFile ){
  open(SF, ">$setFile") or die "$!\n";
  printf SF ($settingsTemplate, $convFile, $outFile, $subProject, $outFile, $externFile || "");
  close(SF);
}

printf STDERR ($cmdline . "\n", $setFile);
unless($test){
  system(sprintf($cmdline, $setFile)) == 0 or die "Failed: $?";
  #unlink($setFile);
}


