#!/usr/bin/perl

use strict;
use lib "$ENV{GUS_HOME}/lib/perl/";

use DBI;
use DBD::Oracle;
use Getopt::Long;

use CBIL::Util::PropertySet;
use GUS::ObjRelP::DbiDbHandle;
use GUS::Community::GeneModelLocations;

use Bio::Tools::GFF;


my ($help, $gusConfigFile, $extDbRlsId, $outputFile, $orgAbbrev, $outputFileDir, $ifSeparateParents);
&GetOptions('help|h' => \$help,
            'gusConfigFile=s' => \$gusConfigFile,
            'orgAbbrev=s' => \$orgAbbrev,
            'extDbRlsId=s' => \$extDbRlsId,
            'outputFile=s' => \$outputFile,
            'ifSeparateParents=s' => \$ifSeparateParents,
            'outputFileDir=s' => \$outputFileDir
    );

&usage("Missing a required argument.") unless (defined $orgAbbrev);

if(!$gusConfigFile) {
  $gusConfigFile = $ENV{GUS_HOME} . "/config/gus.config";
}

if (!$outputFile) {
  $outputFile = $orgAbbrev . ".gff3";
}

if ($outputFileDir) {
  $outputFile = "\./" . $outputFileDir. "\/".$outputFile;
}

if (!$ifSeparateParents) {
  $ifSeparateParents = "No";
}

my @properties;
my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

my $dbiDsn = $gusconfig->{props}->{dbiDsn};
my $dbiUser = $gusconfig->{props}->{databaseLogin};
my $dbiPswd = $gusconfig->{props}->{databasePassword};

my $dbh = GUS::ObjRelP::DbiDbHandle->new($dbiDsn, $dbiUser, $dbiPswd);
$dbh->{RaiseError} = 1;
$dbh->{AutoCommit} = 0;
$dbh->{LongTruncOk} = 1;


if (!$extDbRlsId) {
  $extDbRlsId = getExtDbRlsIdFormOrgAbbrev ($orgAbbrev);
}


open(GFF, "> $outputFile") or die "Cannot open file $outputFile For writing: $!";

my $geneAnnotations = {};
my $transcriptAnnotations = {};
my $ncbiTaxId;
my $sequenceLengths = {};
my $gene2TranscriptHash = {};

my $sql = "select gf.NAME, t.NAME, ns.SOURCE_ID as seq_source_id, ns.LENGTH, gf.SOURCE_ID as gene_source_id, 
t.SOURCE_ID as transcript_source_id, ta.NCBI_TAX_ID, t.is_pseudo, t.TRANSL_TABLE, t.ANTICODON, t.TRANSL_EXCEPT
from DOTS.EXTERNALNASEQUENCE ns, DOTS.GENEFEATURE gf, DOTS.TRANSCRIPT t, SRES.TAXON ta
where ns.NA_SEQUENCE_ID=gf.NA_SEQUENCE_ID and gf.NA_FEATURE_ID=t.PARENT_ID
and ns.TAXON_ID=ta.TAXON_ID
and gf.EXTERNAL_DATABASE_RELEASE_ID= ?
";


my $sh = $dbh->prepare($sql);
$sh->execute($extDbRlsId);

while(my ($geneSoTermName, $soTermName, $sequenceSourceId, $sequenceLength, $geneSourceId, $transcriptSourceId, $ncbi, $isPseudo, $translTable, $anticodon, $translExcept ) = $sh->fetchrow_array()) {
  $ncbiTaxId = $ncbi if($ncbi);

  $geneAnnotations->{$geneSourceId} = {
                                       ncbi_tax_id => $ncbiTaxId,
                                       so_term_name => $geneSoTermName,
                                       eupathdb_id => $geneSourceId,
                                       ebi_id => 'null',    # a place holder for EBI unique ID
  };

  $transcriptAnnotations->{$transcriptSourceId} = {
                                   so_term_name => $soTermName,
                                   is_pseudo => $isPseudo,
                                   transl_table => $translTable,
                                   transl_except => $translExcept,
                                   anticodon => $anticodon,
                                   eupathdb_id => $transcriptSourceId,
                                   ebi_id => 'null',    # a place holder for EBI unique ID
#                                   translation => $translation,
  };

  ## GUS is using lncRNA, which should be lnc_RNA in gene ontology
  $geneAnnotations->{$geneSourceId}->{so_term_name} = "lnc_RNA" if ($geneAnnotations->{$geneSourceId}->{so_term_name} eq "lncRNA");
  $transcriptAnnotations->{$transcriptSourceId}->{so_term_name} = "lnc_RNA" if ($transcriptAnnotations->{$transcriptSourceId}->{so_term_name} eq "lncRNA");

  $sequenceLengths->{$sequenceSourceId} = $sequenceLength;
  push @{$gene2TranscriptHash->{$geneSourceId}}, $transcriptAnnotations->{$transcriptSourceId};
}

my $geneModelLocations = GUS::Community::GeneModelLocations->new($dbh, $extDbRlsId, 1);


print GFF "##gff-version 3\n";
#print GFF "##species http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=$ncbiTaxId\n" if($ncbiTaxId);

foreach(sort keys %$sequenceLengths) {
  my $length = $sequenceLengths->{$_};

#  print GFF "##sequence-region $_ 1 $length\n";   ## sequence query from dots.externalNaFeature table are not top level
}

my $date = HTTP::Date::time2iso();
print GFF "#created $date\n";


foreach my $geneSourceId (sort @{$geneModelLocations->getAllGeneIds()}) {
  my $features = $geneModelLocations->bioperlFeaturesFromGeneSourceId($geneSourceId);

  foreach my $feature (@$features) {
    $feature->source_tag("EuPathDB");
    foreach my $extraTag ("NA_FEATURE_ID", "NA_SEQUENCE_ID", "PARENT_NA_FEATURE_ID", "AA_FEATURE_ID", "AA_SEQUENCE_ID", "GENE_NA_FEATURE_ID", "EBI_BIOTYPE", "GENE_EBI_BIOTYPE", "SEQUENCE_IS_PIECE") {
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

    # change protein_coding_gene, *RNA_gene to gene
    if ($feature->primary_tag eq 'protein_coding_gene'
	|| $feature->primary_tag =~ /RNA_gene$/ ) {
      $feature->primary_tag('gene');
    }


    if($feature->primary_tag eq 'gene') {
#      $feature->add_tag_value("description", $geneAnnotations->{$geneSourceId}->{gene_product});

#      $feature->add_tag_value("eupathdb_id", $geneAnnotations->{$geneSourceId}->{eupathdb_id});
#      $feature->add_tag_value("ebi_id", $geneAnnotations->{$geneSourceId}->{ebi_id});
    }

    if($feature->primary_tag eq 'transcript') {


      my ($transcriptId) = $feature->get_tag_values("ID");

      my $soTermName = $transcriptAnnotations->{$transcriptId}->{so_term_name};
      my $isPseudo = $transcriptAnnotations->{$transcriptId}->{is_pseudo};
      my $translTable = $transcriptAnnotations->{$transcriptId}->{transl_table};
      my $translExcept = $transcriptAnnotations->{$transcriptId}->{transl_except};
      my $anticodon = $transcriptAnnotations->{$transcriptId}->{anticodon};
#      my $translation = $transcriptAnnotations->{$transcriptId}->{translation};

      $feature->primary_tag($soTermName);
#      $feature->add_tag_value("eupathdb_id", $transcriptAnnotations->{$transcriptId}->{eupathdb_id});
#      $feature->add_tag_value("ebi_id", $transcriptAnnotations->{$transcriptId}->{ebi_id});
      $feature->add_tag_value("is_pseudo", $isPseudo) if($isPseudo);
      $feature->add_tag_value("transl_table", $translTable) if($translTable);
      $feature->add_tag_value("transl_except", $translExcept) if($translExcept);
      $feature->add_tag_value("anticodon", $anticodon) if($anticodon);
#      $feature->add_tag_value("translation", $translation) if($translation);

    }

    my $bioType = getBioTypeAndUpdatePrimaryTag(\$feature, $geneSourceId);
    $feature->add_tag_value ("biotype", $bioType) if ($bioType);

    if($feature->primary_tag eq 'utr3prime') {
      $feature->primary_tag('three_prime_UTR');
    }
    if($feature->primary_tag eq 'utr5prime') {
      $feature->primary_tag('five_prime_UTR');
    }


    unless($feature->primary_tag eq 'CDS') {
      $feature->frame('.');
    }

#    print STDERR "$feature->primary_tag\n" if ($feature->primary_tag ne "gene" 
#					       || $feature->primary_tag =~ /RNA$/
#					       || $feature->primary_tag ne "CDS"
#					       || $feature->primary_tag ne "pseudogene"
#					       || $feature->primary_tag ne "pseudogenic_transcript"
#					       || $feature->primary_tag ne "pseudogenic_exon"
#					       || $feature->primary_tag ne "exon");

    ## separate features if there are more than one parent
    if ($ifSeparateParents =~ /^y/i) {
      if ($feature->has_tag("Parent") && scalar ($feature->get_tag_values("Parent")) > 1 ) {

	my @parents = $feature->get_tag_values("Parent");

	my $c = 0;
	foreach my $pant (@parents) {
	  $c++;
	  $feature->remove_tag("Parent");
	  $feature->add_tag_value('Parent', $pant);
	  if ($feature->has_tag("ID")) {
	    my ($nid) = $feature->remove_tag("ID");
	    $nid =~ s/\.\d//;
	    $nid .= ".$c";
	    $feature->add_tag_value("ID", $nid);
	  }

	  $feature->gff_format(Bio::Tools::GFF->new(-gff_version => 3));
	  print GFF $feature->gff_string . "\n";
	}
      } else {
	$feature->gff_format(Bio::Tools::GFF->new(-gff_version => 3));
	print GFF $feature->gff_string . "\n";
      }
    } else {
      $feature->gff_format(Bio::Tools::GFF->new(-gff_version => 3));
      print GFF $feature->gff_string . "\n";
    }
  }
}

## get info of transposable_element
my $tes = getTransposableElement($dbh, $extDbRlsId);
foreach my $k (sort keys %{$tes}) {
  foreach my $i (0..$#{$tes->{$k}}) {
    ($i == $#{$tes->{$k}}) ? print GFF "$tes->{$k}[$i]\n" : print GFF "$tes->{$k}[$i]\t";
  }
}

$dbh->disconnect();
close GFF;

1;

############
sub getTransposableElement {
  my ($dbh, $extDbRlsId) = @_;
  my %elements;

  my $sql = "
            select te.SOURCE_ID, ot.name, ns.SOURCE_ID, nl.START_MIN, nl.END_MAX, nl.IS_REVERSED
            from DOTS.TRANSPOSABLEELEMENT te, DOTS.EXTERNALNASEQUENCE ns, dots.nalocation nl, SRES.ONTOLOGYTERM ot
            where te.NA_FEATURE_ID=nl.NA_FEATURE_ID and te.NA_SEQUENCE_ID=ns.NA_SEQUENCE_ID and te.SEQUENCE_ONTOLOGY_ID=ot.ONTOLOGY_TERM_ID
            and ot.name like 'transposable_element' and te.EXTERNAL_DATABASE_RELEASE_ID=$extDbRlsId
           ";

  my $stmt = $dbh->prepare($sql);
  $stmt->execute();
  while (my ($eSourceId, $eProduct, $sSourceId, $start, $end, $std) = $stmt->fetchrow_array()) {
    if ($eSourceId) {

      my $strand = ($std == 0) ? "+" : "-";

      $eSourceId .= ".2" if ($elements{$eSourceId}); ## temp fix for id
      $eSourceId =~ s/TEG/TE/ if ($eSourceId eq "TVAG_TEG_DS113326_1");
      next if ($eSourceId eq "TVAG_TE_DS113443_3"); ## skip TVAG_TE_DS113443_3 because it has been annotated at a wrong sequence

      my $idColumn = "ID=$eSourceId";
      $idColumn .= ";biotype=transposable_element";

      push (@{$elements{$eSourceId}}, $sSourceId, 'EuPathDB', 'transposable_element', $start, $end, '.', $strand, '.', $idColumn);
    }
  }
  $stmt->finish();

  foreach my $k (sort keys %elements) {
    foreach my $i (0..$#{$elements{$k}}) {
#      ($i == $#{$elements{$k}}) ? print STDERR "$elements{$k}[$i]\n" : print STDERR "$elements{$k}[$i]\t";
    }
  }

  return \%elements;
}

sub getBioTypeAndUpdatePrimaryTag {
  my ($feat, $geneSourceId) = @_;
  my $bioType;

  my ($id) = $$feat->get_tag_values("ID");
  my $type = $$feat->primary_tag;
#  print STDERR "processing $type, '$id'......\n";

  ## for those primary_tag = transcript, assign with gene soTerm
  if ($$feat->primary_tag eq "transcript") {
    my ($parentID) = $$feat->get_tag_values('Parent');
    my $transcriptType = $geneAnnotations->{$parentID}->{so_term_name};
    if ($transcriptType eq "coding_gene" || $transcriptType eq "protein_coding") {
      $transcriptType = "mRNA";
    } elsif ($transcriptType eq "pseudogene") {
      $transcriptType = "pseudogenic_transcript";
    } else {
      $transcriptType =~ s/\_gene$//;
      $transcriptType =~ s/\_encoding$//;
    }
    $$feat->primary_tag($transcriptType);
  }

  if ($$feat->primary_tag eq "gene") {
    $bioType = $geneAnnotations->{$id}->{so_term_name};
    my $isPseudoString = "";
    foreach my $transcriptHash (@{$gene2TranscriptHash->{$id}}) {
      if ($transcriptHash->{so_term_name} eq "mRNA" || $transcriptHash->{so_term_name} eq "transcript") {

#	## this will assign gene as pseudogene when partial of transcripts are pseudo-, which is incorrect
#	if ($transcriptHash->{is_pseudo} == 1) {
#	  $bioType = "pseudogene";
#	  $$feat->primary_tag("pseudogene");
#	}
	my $isP = ($transcriptHash->{is_pseudo} == 1) ? 1 : 0;
	$isPseudoString .= $isP;
      }
    }
    if ($isPseudoString =~ /^1+$/) {
      $bioType = "pseudogene";
      $$feat->primary_tag("pseudogene");
    }

    $bioType = "protein_coding" if ($bioType eq "coding_gene");
    $bioType =~ s/\_gene$/\_encoding/i;

  } elsif ($$feat->primary_tag =~ /RNA$/ || $$feat->primary_tag =~ /transcript$/i) {
    $bioType = $transcriptAnnotations->{$id}->{so_term_name};
    if ($$feat->has_tag("is_pseudo") && ($$feat->get_tag_values("is_pseudo")) == 1) {
      if ($$feat->primary_tag =~ /tRNA/) {
	$bioType = "pseudogenic_tRNA";
	$$feat->primary_tag("pseudogenic_tRNA");
      } elsif ($$feat->primary_tag =~ /rRNA/) {
	$bioType = "pseudogenic_rRNA";
	$$feat->primary_tag("pseudogenic_rRNA");
      } else {
	$bioType = "pseudogenic_transcript";
	$$feat->primary_tag("pseudogenic_transcript");
      }
    }

  } elsif ($$feat->primary_tag eq "exon" ) {
    my @parentIDs = $$feat->get_tag_values('Parent');
    foreach my $parentID (@parentIDs) {
      if ($transcriptAnnotations->{$parentID}->{is_pseudo} == 1) {
	$bioType = "pseudogenic_exon";
	$$feat->primary_tag("pseudogenic_exon");
      } else {
	$bioType = $$feat->primary_tag;
      }
    }
  } else {
    ## do not need it for CDS and others
  }
  return $bioType;
}

sub getExtDbRlsIdFormOrgAbbrev {
  my ($abbrev) = @_;

  my $extDb = $abbrev. "_primary_genome_RSRC";

  my $extDbRls = getExtDbRlsIdFromExtDbName ($extDb);

  return $extDbRls;
}

sub getExtDbRlsIdFromExtDbName {
  my ($extDbRlsName) = @_;

#  my $dbh = $self->getQueryHandle();

  my $sql = "select edr.external_database_release_id from sres.externaldatabaserelease edr, sres.externaldatabase ed
             where ed.name = '$extDbRlsName'
             and edr.external_database_id = ed.external_database_id";
  my $stmt = $dbh->prepareAndExecute($sql);
  my @rlsIdArray;

  while ( my($extDbRlsId) = $stmt->fetchrow_array()) {
      push @rlsIdArray, $extDbRlsId;
    }

  die "No extDbRlsId found for '$extDbRlsName'" unless(scalar(@rlsIdArray) > 0);

  die "trying to find unique extDbRlsId for '$extDbRlsName', but more than one found" if(scalar(@rlsIdArray) > 1);

  return @rlsIdArray[0];

}


sub usage {
  die
"
Usage: 

where
  --orgAbbrev:  required, organims abbreviation
  --extDbRlsId: optional, the externalDatabaseRleaseId that have database name like '*_primary_genome_RSRC'
  --outputFile: optional, the ouput file and/or dir
  --outputFileDir: optional, the ouput file dir that holds all output file
  --gusConfigFile: optional, use the current GUS_HOME gusConfigFile if not specify
  --ifSeparateParents: optional, Yes|No, default is No
";
}
