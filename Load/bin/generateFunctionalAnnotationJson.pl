#!/usr/bin/perl

use strict;
use JSON;
use Getopt::Long;
use GUS::Model::SRes::Taxon;
use GUS::Model::SRes::TaxonName;
use GUS::Supported::GusConfig;


my ($genomeSummaryFile, $organismAbbrev, $gusConfigFile, $outputFileName, $outputFileDir, $help);

&GetOptions('organismAbbrev=s' => \$organismAbbrev,
            'gusConfigFile=s' => \$gusConfigFile,
            'outputFileName=s' => \$outputFileName,
            'outputFileDir=s' => \$outputFileDir,
            'help|h' => \$help
            );

&usage() if ($help);
&usage("Missing a Required Argument") unless (defined $organismAbbrev);


$gusConfigFile = "$ENV{GUS_HOME}/config/gus.config" unless ($gusConfigFile);
my $verbose;
my $gusconfig = GUS::Supported::GusConfig->new($gusConfigFile);

my $db = GUS::ObjRelP::DbiDatabase->new($gusconfig->getDbiDsn(),
                                        $gusconfig->getDatabaseLogin(),
                                        $gusconfig->getDatabasePassword(),
                                        $verbose,0,1,
                                        $gusconfig->getCoreSchemaName()
                                       );
my $dbh = $db->getQueryHandle();

#my $primaryExtDbRlsId = getExtDbRlsIdFormOrgAbbrev ($organismAbbrev);

my $outputFileName = $organismAbbrev . "_functional_annotation.json" unless($outputFileName);

if ($outputFileDir) {
  $outputFileName = "\./". $outputFileDir . "\/". $outputFileName;
}
open (OUT, ">$outputFileName") || die "cannot open $outputFileName file to write.\n";


## get all Ids hash
my ($geneHash, $transcriptHash, $translationHash) = getGeneTranscriptTranslation ($organismAbbrev);

## grep product info
my $products = getProductName ($organismAbbrev);

## get dbxrefs
my $dbxrefs = getDbxRefsAll ($organismAbbrev);



## main flow
my (@functAnnotInfos, $c);
foreach my $k (sort keys %{$geneHash}) {

  my %functAnnot = (
		 'object_type' => "gene",
		 'id' => $k,
		 );

  $functAnnot{xrefs} = \@{$dbxrefs->{$k}} if ($dbxrefs->{$k});

  push @functAnnotInfos, \%functAnnot;

  $c++;
#  last if ($c > 10);
}

$c = 0;
foreach my $k2 (sort keys %{$transcriptHash}) {
  my %functAnnot = (
		 'object_type' => "transcript",
		 'id' => $k2,
                 'description' => $products->{$k2}
		    );
  $functAnnot{xrefs} = \@{$dbxrefs->{$k2}} if ($dbxrefs->{$k2});

  push @functAnnotInfos, \%functAnnot;

  $c++;
#  last if ($c > 10);
}

$c = 0;
foreach my $k3 (sort keys %{$translationHash}) {
  my %functAnnot = (
		 'object_type' => "translation",
		 'id' => $k3,
		    );
  $functAnnot{xrefs} = \@{$dbxrefs->{$k3}} if ($dbxrefs->{$k3});

  push @functAnnotInfos, \%functAnnot;

  $c++;
#  last if ($c > 10);
}

my $json = encode_json(\@functAnnotInfos);

print OUT "$json\n";

close OUT;

$dbh->disconnect();


###########
sub getTranscriptsInfos {
  my ($extDbRlsId) = @_;

  my %transcriptInfos;

  my $sql = "select gf.SOURCE_ID, t.SOURCE_ID, t.name
             from dots.genefeature gf, dots.transcript t
             where gf.NA_FEATURE_ID=t.PARENT_ID
             and t.EXTERNAL_DATABASE_RELEASE_ID=$extDbRlsId";

  my $stmt = $dbh->prepareAndExecute($sql);

  while (my ($gSourceId, $tSourceId, $type)
	 = $stmt->fetchrow_array()) {

    my %transcriptInfo = (
			  'object_type' => "transcript",
			  'id' => $tSourceId,
			  'description' => $products->{$tSourceId}
			 );

    push @{$transcriptInfos{$gSourceId}}, \%transcriptInfo;

  }
  $stmt->finish();

  return \%transcriptInfos;
}

sub getProductName {
  my ($orgnaismAbbrev) = @_;

  my $extDbRlsId = getExtDbRlsIdFormOrgAbbrev ($organismAbbrev);

  ## only grep the preferred product name
  my $sql = "select t.SOURCE_ID, tp.product,
             tp.IS_PREFERRED, tp.PUBLICATION, tp.EVIDENCE_CODE, tp.WITH_FROM
             from dots.transcript t, ApiDB.TranscriptProduct tp
             where t.NA_FEATURE_ID=tp.NA_FEATURE_ID
             and tp.IS_PREFERRED = 1
             and t.EXTERNAL_DATABASE_RELEASE_ID=$extDbRlsId";

  my $stmt = $dbh->prepareAndExecute($sql);

  my %products;

  while (my ($tSourceId, $product, $isPreferred, $publication, $evidencdCode, $withFrom)
	 = $stmt->fetchrow_array()) {

    my %evidence = (
		   'isPreferred' => $isPreferred
		   );
    if ($publication) {
      $publication =~ s/PMID://;
      %evidence = (
		   'PMID' => $publication
		   );
    }
    if ($evidencdCode) {
      my $eviCodeName = getEvidenceCodeName ($evidencdCode);
      %evidence = (
		   'evidencdCode' => $eviCodeName
		   );
    }
    if ($withFrom) {
      %evidence = (
		   'withFrom' => $withFrom
		   );
    }

#    my $evidenceJson = encode_json(\%evidence);
#    print STDERR $evidenceJson. "\n";

#    my $productFull = $product . " " . $evidenceJson;

#    my $productHash = (
#		       'description' => $productFull
#		       );

#    push @{$products{$tSourceId}}, $productHash;

    $products{$tSourceId} = $product if ($isPreferred == 1);
  }

  $stmt->finish();

  return \%products;
}

sub getEvidenceCodeName {
  my ($eviCode) = @_;

  my $eviCodeName;

  my $sqll = "select NAME from SRES.ONTOLOGYTERM where ONTOLOGY_TERM_ID=$eviCode";

  my $stmtt = $dbh->prepareAndExecute($sqll);

  my($eviCodeName) = $stmtt->fetchrow_array();

  $stmtt->finish();

  return $eviCodeName;
}

sub getDbxRefsAll {
  my ($orgnaismAbbrev) = @_;

  my (%dbxrefs, $dbName);

  my $dbNameHash = getDbxrefsNameHash ($orgnaismAbbrev);

  foreach my $k (sort keys %{$dbNameHash}) {
    foreach my $extDbName (@{$dbNameHash->{$k}}) {
#      print STDERR "processing $extDbName ... \n";

      my $sql = "select nf.SOURCE_ID, df.PRIMARY_IDENTIFIER, ed.name
from dots.nafeature nf, DOTS.DBREFNAFEATURE dnf, SRES.DBREF df,
SRES.EXTERNALDATABASERELEASE edr, SRES.EXTERNALDATABASE ed
where nf.NA_FEATURE_ID=dnf.NA_FEATURE_ID and dnf.DB_REF_ID=df.DB_REF_ID 
and df.EXTERNAL_DATABASE_RELEASE_ID=edr.EXTERNAL_DATABASE_RELEASE_ID
and edr.EXTERNAL_DATABASE_ID=ed.EXTERNAL_DATABASE_ID
and ed.name like '$extDbName'";

      my $stmt = $dbh->prepareAndExecute($sql);

      while (my ($sourceId, $prmyId, $edName) = $stmt->fetchrow_array()) {

	if ($sourceId && $prmyId) {
	  my %xrefs = (
		       "id" => $prmyId,
		       "dbname" => $k
		      );

	  push @{$dbxrefs{$sourceId}}, \%xrefs;
	}
      }
      $stmt->finish();
    }
    $db->undefPointerCache();
  }

  return \%dbxrefs;
}

sub getDbxrefsNameHash {
  my ($abbrev) = @_;

  my (%nameHash, $dbName);

  $dbName = $abbrev . "_dbxref_gene2Entrez_RSRC";
  push @{$nameHash{"EntrezGene"}}, $dbName;

  $dbName = $abbrev . "_dbxref_gene2Uniprot_RSRC";
  push @{$nameHash{"Uniprot"}}, $dbName;
  $dbName = $abbrev . "_dbxref_uniprot_from_annotation_RSRC";
  push @{$nameHash{"Uniprot"}}, $dbName;

  $dbName = $abbrev . "_dbxref_gene2PubmedFromNcbi_RSRC";
  push @{$nameHash{"PubMed"}}, $dbName;
  $dbName = $abbrev . "_dbxref_pmid_from_annotation_RSRC";
  push @{$nameHash{"PubMed"}}, $dbName;

  $dbName = $abbrev . "_gbProteinId_NAFeature_aliases_RSRC";
  push @{$nameHash{"NCBI protein db"}}, $dbName;

  $dbName = $abbrev . "_dbxref_unity_GeneDB_RSRC";
  push @{$nameHash{"GeneDB"}}, $dbName;

  $dbName = $abbrev . "_dbxref_rfam_from_annotation_RSRC";
  push @{$nameHash{"Rfam"}}, $dbName;

  return \%nameHash;
}

sub getGeneTranscriptTranslation {
  my ($abbrev) = @_;

  my (%geneIds, %transcriptIds, %translationIds);

  my $extDbRlsId = getExtDbRlsIdFormOrgAbbrev ($abbrev);
  my $sql = "select g.source_id, t.source_id, aa.source_id from dots.genefeature g, dots.transcript t, dots.translatedaafeature aa
             where g.na_feature_id = t.parent_id and t.na_feature_id = aa.na_feature_id
             and g.EXTERNAL_DATABASE_RELEASE_ID=$extDbRlsId";

  my $stmt = $dbh->prepareAndExecute($sql);

  while (my ($geneId, $trcpIds, $trsltIds) = $stmt->fetchrow_array()) {
    $geneIds{$geneId} = $geneId;
    $transcriptIds{$trcpIds} = $trcpIds;
    $translationIds{$trsltIds} = $trsltIds;
  }

  return \%geneIds, \%transcriptIds, \%translationIds;
}

sub getExtDbRlsIdFormOrgAbbrev {
  my ($abbrev) = @_;

  my $extDb = $abbrev. "_primary_genome_RSRC";

  my $extDbRls = getExtDbRlsIdFromExtDbName ($extDb);

  return $extDbRls;
}

sub getExtDbRlsIdFromExtDbName {
  my ($extDbRlsName) = @_;

  my $sql = "select edr.external_database_release_id
             from sres.externaldatabaserelease edr, sres.externaldatabase ed
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
A script to generate functional_annotation.json file that required by EBI

Usage: perl bin/generateFunctionalAnnotationJson.pl --organismAbbrev pfal3D7 --gusConfigFile \$GUS_HOME/config/gus.config

where:
  --organismAbbrev: required, eg. pfal3D7
  --outputFileName: optional, default is organismAbbrev_genome.json
  --gusConfigFile: optional, default is \$GUS_HOME/config/gus.config

";
}
