#!/usr/bin/perl
use strict;
use lib "$ENV{GUS_HOME}/lib/perl";
use Getopt::Long;
use GUS::ObjRelP::DbiDatabase;
use GUS::Supported::GusConfig;

my $gusConfigFile;
my $organism;
my $path;

&GetOptions( "gusConfigFile=s" => \$gusConfigFile,
             "organism=s"      => \$organism,
             "path=s"          => \$path );

die "usage: getValueFromTable --gusConfigFile [\$GUS_CONFIG_FILE] --organism \"Plasmodium falciparum 3D7\" --path \"absolute path for outputs\" \n" unless $gusConfigFile && $organism && $path;

my $gusconfig = GUS::Supported::GusConfig->new($gusConfigFile);
my @chrs;

my $db = GUS::ObjRelP::DbiDatabase->new($gusconfig->getDbiDsn(),
                                        $gusconfig->getDatabaseLogin(),
                                        $gusconfig->getDatabasePassword(),
                                        0,0,1,
                                        $gusconfig->getCoreSchemaName());


my $dbh = $db->getQueryHandle();

$dbh->{LongReadLen} = 512 * 512 * 1024;
$dbh->{LongTruncOk} = 0;    ### We're happy to truncate any excess

my @chrs = &printGeneticElement($dbh, $organism, $path);

foreach(@chrs) {
  &printFasta($dbh, $_, $path);
  &printPF($dbh, $_, $path);
}

sub printFasta {
  my ($dbh, $chr, $path)  = @_;
  my $sql = "select sequence from ApidbTuning.NASequence where source_id = '$chr'"; 
  my $sth = $dbh->prepareAndExecute($sql);
  while(my ($seq) = $sth->fetchrow_array) {
    $seq =~ s/(.{1,60})/$1\n/g;
    open (FSA, ">$path/$chr.fsa");
    print FSA ">$chr\n";
    print FSA $seq;
    close FSA;
  }
  $sth->finish;
}

sub printGeneticElement {
  my ($dbh, $organism, $path) = @_;

  my $sql = "select distinct ga.CHROMOSOME, ga.SEQUENCE_ID from ApidbTuning.GeneAttributes ga where ga.organism = '$organism' and ga.chromosome is not null order by ga.chromosome";

  my $sth = $dbh->prepareAndExecute($sql);

  open(OUT, '>genetic-elements.dat');
  while(my ($chr, $name, $seq) = $sth->fetchrow_array()){
    push @chrs, $name;
    print OUT <<EOL;
ID\t$name
NAME\tChromosome $chr
TYPE\t:CHRSM
CIRCULAR?\tN
ANNOT-FILE\t$path/$name.pf
SEQ-FILE\t$path/$name.fsa
//
EOL
  }
  close OUT;
  $sth->finish;
  return @chrs;
}

sub printPF {
  my ($dbh, $chr, $path)  = @_;
  open PF, ">$path/$chr.pf";

  my $sql =<<EOL;
SELECT ga.source_id ,
       ga.na_sequence_id ,
       fl.start_min ,
       fl.end_max ,
       ga.product , 
       ga.so_term_name, 
       ga.is_deprecated,
       ga.organism, 
       ga.is_pseudo,
       ga.gene_type,
       ga.ec_numbers,
       ga.name
FROM   ApidbTuning.GeneAttributes ga, 
       ApidbTuning.FeatureLocation fl
WHERE  fl.na_feature_id = ga.na_feature_id
   AND ga.sequence_id = '$chr'
ORDER BY fl.start_min
EOL

  my $sth = $dbh->prepareAndExecute($sql);

  while(my $arr = $sth->fetchrow_arrayref()){
     my($id, $na_seq_id, $start, $end, $product, $so, $deprecated, $organism, $pseudo, $genetype, $ec_number, $name) = @$arr;
     
     my $product_type = 'P';

     if($genetype =~ /rRNA encoding/i) {
       $product_type = 'RRNA';
     } elsif($genetype =~ /tRNA encoding/i) {
       $product_type = 'TRNA';
     } elsif($genetype =~ /non protein coding/i) {
       $product_type = 'P';
     } elsif($genetype =~ /snRNA encoding/i) {
       $product_type = 'MISC-RNA';
     } elsif($genetype =~ /protein coding/i) {
       $product_type = 'P';
     } elsif($genetype =~ /snoRNA encoding/i) {
       $product_type = 'MISC-RNA';
     }

     $product_type = 'PSEUDO' if $pseudo;

     $ec_number =~ s/\(.+\)//;
     $ec_number =~ s/\s+$//g;

     my $pf = "ID\t$id\n";

$pf = "NAME\t$id\n"; 
$pf .= "STARTBASE\t$start\n";
$pf .= "ENDBASE\t$end\n";
$pf .= "FUNCTION\t$product\n" if $product;
$pf .= "PRODUCT-TYPE\t$product_type\n";
$pf .= "EC\t$ec_number\n" if $ec_number;
#$pf .= "GO:\t$so\n" if $so;
$pf .= "//\n";

    print PF $pf;
  }
  close PF;
  $sth->finish;
}

$dbh->disconnect;
