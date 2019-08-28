#!/usr/bin/perl

use strict;
use lib "$ENV{GUS_HOME}/lib/perl/";

use DBI;
use DBD::Oracle;
use Getopt::Long;

use CBIL::Util::PropertySet;
use GUS::Community::GeneModelLocations;

use Bio::Tools::GFF;


my ($help, $gusConfigFile, $extDbRlsId, $outputFile, $orgAbbrev);
&GetOptions('help|h' => \$help,
            'gusConfigFile=s' => \$gusConfigFile,
            'orgAbbrev=s' => \$orgAbbrev,
            'extDbRlsId=s' => \$extDbRlsId,
            'outputFile=s' => \$outputFile,
    );


if(!$gusConfigFile) {
  $gusConfigFile = $ENV{GUS_HOME} . "/config/gus.config";
}

&usage("Missing a required argument.") unless (defined $orgAbbrev || $extDbRlsId);

my @properties;
my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

my $dbiDsn = $gusconfig->{props}->{dbiDsn};
my $dbiUser = $gusconfig->{props}->{databaseLogin};
my $dbiPswd = $gusconfig->{props}->{databasePassword};

my $dbh = DBI->connect($dbiDsn, $dbiUser, $dbiPswd) or die DBI->errstr;
$dbh->{RaiseError} = 1;
$dbh->{AutoCommit} = 0;
$dbh->{LongTruncOk} = 1;


if (!$extDbRlsId) {
  $extDbRlsId = getExtDbRlsIdForAnnot ($orgAbbrev);
}


open(GFF, "> $outputFile") or die "Cannot open file $outputFile For writing: $!";

my $geneAnnotations = {};
my $transcriptAnnotations = {};
my $ncbiTaxId;
my $sequenceLengths = {};

my $sql = "select gf.NAME, t.NAME, ns.SOURCE_ID as seq_source_id, ns.LENGTH, gf.SOURCE_ID as gene_source_id, 
t.SOURCE_ID as transcript_source_id, ta.NCBI_TAX_ID, t.is_pseudo, t.TRANSL_TABLE, t.ANTICODON
from DOTS.EXTERNALNASEQUENCE ns, DOTS.GENEFEATURE gf, DOTS.TRANSCRIPT t, SRES.TAXON ta
where ns.NA_SEQUENCE_ID=gf.NA_SEQUENCE_ID and gf.NA_FEATURE_ID=t.PARENT_ID
and ns.TAXON_ID=ta.TAXON_ID
and gf.EXTERNAL_DATABASE_RELEASE_ID= ?
";


my $sh = $dbh->prepare($sql);
$sh->execute($extDbRlsId);
while(my ($geneSoTermName, $soTermName, $sequenceSourceId, $sequenceLength, $geneSourceId, $transcriptSourceId, $ncbi, $isPseudo, $translTable, $anticodon ) = $sh->fetchrow_array()) {
  $ncbiTaxId = $ncbi if($ncbi);

  $geneAnnotations->{$geneSourceId} = {
                                       ncbi_tax_id => $ncbiTaxId,
  };

  $transcriptAnnotations->{$transcriptSourceId} = {
                                   so_term_name => $soTermName,
                                   is_pseudo => $isPseudo,
                                   transl_table => $translTable,
                                   anticodon => $anticodon,
#                                   translation => $translation,
  };

  $sequenceLengths->{$sequenceSourceId} = $sequenceLength;
}

my $geneModelLocations = GUS::Community::GeneModelLocations->new($dbh, $extDbRlsId, 1);


print GFF "##gff-version 3\n";
#print GFF "##species http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=$ncbiTaxId\n" if($ncbiTaxId);

foreach(sort keys %$sequenceLengths) {
  my $length = $sequenceLengths->{$_};

  print GFF "##sequence-region $_ 1 $length\n";
}

my $date = HTTP::Date::time2iso();
print GFF "#created $date\n";


foreach my $geneSourceId (@{$geneModelLocations->getAllGeneIds()}) {
  my $features = $geneModelLocations->bioperlFeaturesFromGeneSourceId($geneSourceId);

  foreach my $feature (@$features) {
    $feature->source_tag("EuPathDB");
    foreach my $extraTag ("NA_FEATURE_ID", "NA_SEQUENCE_ID", "PARENT_NA_FEATURE_ID", "AA_FEATURE_ID", "AA_SEQUENCE_ID", "GENE_NA_FEATURE_ID", "SEQUENCE_IS_PIECE") {
      $feature->remove_tag($extraTag) if($feature->has_tag($extraTag));
    }

    foreach($feature->get_all_tags()) {
      if($_ eq 'ID') { }
      elsif($_ eq 'PARENT') {

        my ($parent) = $feature->remove_tag($_);

        my @parents = split(",", $parent);
        foreach(@parents) {
          $feature->add_tag_value('Parent', $_);
        }
      }
      else {
        $feature->add_tag_value(lc($_), $feature->remove_tag($_));
      }

    }


    if($feature->primary_tag eq 'gene') {
#      $feature->add_tag_value("description", $geneAnnotations->{$geneSourceId}->{gene_product});
    }

    if($feature->primary_tag eq 'transcript') {


      my ($transcriptId) = $feature->get_tag_values("ID");

      my $soTermName = $transcriptAnnotations->{$transcriptId}->{so_term_name};
      my $isPseudo = $transcriptAnnotations->{$transcriptId}->{is_pseudo};
      my $translTable = $transcriptAnnotations->{$transcriptId}->{transl_table};
      my $anticodon = $transcriptAnnotations->{$transcriptId}->{anticodon};
#      my $translation = $transcriptAnnotations->{$transcriptId}->{translation};

      $feature->primary_tag($soTermName);
      $feature->add_tag_value("is_pseudo", $isPseudo) if($isPseudo);
      $feature->add_tag_value("transl_table", $translTable) if($translTable);
      $feature->add_tag_value("anticodon", $anticodon) if($anticodon);
#      $feature->add_tag_value("translation", $translation) if($translation);

    }


    if($feature->primary_tag eq 'utr3prime') {
      $feature->primary_tag('three_prime_UTR');
    }
    if($feature->primary_tag eq 'utr5prime') {
      $feature->primary_tag('five_prime_UTR');
    }


    unless($feature->primary_tag eq 'CDS') {
      $feature->frame('.');
    }



    $feature->gff_format(Bio::Tools::GFF->new(-gff_version => 3)); 
    print GFF $feature->gff_string . "\n";
  }
}

$dbh->disconnect();
close GFF;

1;

sub usage {
  die
"
Usage: 

where
  --orgAbbrev:  required, organims abbreviation
  --extDbRlsId: optional, the externalDatabaseRleaseId that have database name like '*_primary_genome_RSRC'
  --outputFile: required, the ouput file and/or dir
  --gusConfigFile: optional, use the current GUS_HOME gusConfigFile if not specify
";
}
