package ApiCommonData::Load::Plugin::UpdateHtsSnpsFromSeqVars;
@ISA = qw(GUS::PluginMgr::Plugin);



use strict;

use GUS::PluginMgr::Plugin;

use GUS::Model::SRes::SequenceOntology;
use GUS::Model::SRes::ExternalDatabase;
use GUS::Model::SRes::ExternalDatabaseRelease;

use GUS::Model::DoTS::SeqVariation;
use GUS::Model::DoTS::NALocation;
use GUS::Model::DoTS::SnpFeature;
use GUS::Model::DoTS::Transcript;

use Error qw (:try);

use Bio::Seq;
use Bio::Tools::GFF;
use CBIL::Bio::SequenceUtils;

use Benchmark;

use Data::Dumper;


$| = 1;

# ---------------------------------------------------------------------------
# Load Arguments
# ---------------------------------------------------------------------------

sub getArgumentsDeclaration{
  my $argsDeclaration =
    [
     stringArg({name => 'snpExternalDatabaseName',
		descr => 'sres.externaldatabase.name for SNP source',
		constraintFunc => undef,
		reqd => 0,
		isList => 0
	       }),
     stringArg({name => 'organism',
		descr => 'Organism string indicated in SnpFeature.reference_organism',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),
     integerArg({name => 'restart',
		descr => 'for restarting use number from last processed row number in STDOUT',
	        constraintFunc => undef,
	        reqd => 0,
	        isList => 0
	    }),
     integerArg({name => 'testNum',
		descr => 'for testing plugin will stop after this number',
	        constraintFunc => undef,
	        reqd => 0,
	        isList => 0
	    }),
    ];
  return $argsDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = "Updates the HTS SnpFeatures for a specific organism based on the information contained in the dots.sequencevariations ... should be run after all strains loaded";

  my $purpose = "Updates the HTS SnpFeatures for a specific organism based on the information contained in the dots.sequencevariations ... should be run after all strains loaded";

  my $tablesAffected = [['DoTS::SnpFeature', 'one row updated per SNP']];

  my $tablesDependedOn = [['SRes::SequenceOntology',  'SequenceOntology term equal to SNP required']];

  my $howToRestart = "Use restart option and last processed row number from STDOUT file.";

  my $failureCases = "";

  my $notes = "";

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases,notes=>$notes};

  return $documentation;
}

# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {na_sequences => []
             };
  bless($self,$class);

  my $documentation = &getDocumentation();
  my $argumentDeclaration = &getArgumentsDeclaration();


  $self->initialize({requiredDbVersion => 3.6,
		     cvsRevision => '$Revision$',
                     name => ref($self),
                     revisionNotes => '',
                     argsDeclaration => $argumentDeclaration,
                     documentation => $documentation});

  return $self;
}

# ----------------------------------------------------------------------
# run method to do the work
# ----------------------------------------------------------------------

sub run {
  my ($self) = @_;


  my $dbh = $self->getDbHandle();
  $dbh->{'LongReadLen'} = 10_000_000;

  $dbh = $self->getQueryHandle();
  $dbh->{'LongReadLen'} = 10_000_000;

  ##set so doesn't update the algorithminvocation of updated objects
  $self->getDb()->setDoNotUpdateAlgoInvoId(1);

  ##we aren't using the version tables anymore given the workflow so set so doesn't version .. .more efficient
  $self->getDb()->setGlobalNoVersion(1);

  ##prepare statement to get info for each SNPfeature
  my $sumSQL = <<SQL;
select sv.allele,sv.product,
        count(*) as total
from DoTS.SnpFeature sf, DoTS.SeqVariation sv
where sf.na_feature_id = ?
and sv.parent_id = sf.na_feature_id
group by sv.allele,sf.is_coding,sv.product
order by count(*) desc
SQL

my $sumStmt = $dbh->prepare($sumSQL);

##now loop through SNPs and update
  my $dbName = $self->getArg('snpExternalDatabaseName') ? $self->getArg('snpExternalDatabaseName') : "InsertSnps.pm NGS SNPs INTERNAL";
  my $referenceOrganism = $self->getArg('organism');
  my $snpSQL = <<EOSQL;
select sf.na_feature_id
from dots.snpfeature sf, SRES.externaldatabase d, SRES.externaldatabaserelease rel, sres.sequenceontology so
where d.name = '$dbName'
and rel.external_database_id = d.external_database_id
and sf.external_database_release_id = rel.external_database_release_id
and sf.organism = '$referenceOrganism'
and sf.sequence_ontology_id = so.sequence_ontology_id
and so.term_name = 'SNP'
EOSQL

  my $snpStmt = $self->getQueryHandle()->prepare($snpSQL);
  $self->log("executing query to get SNP features to update");
  $snpStmt->execute();
  my $ctSnps = 0;
  my $restarting = $self->getArg('restart');
  my $testNumber = $self->getArg('testNum');

  my @snpIds;
  my $ctRows = 0;
  while(my $row = $snpStmt->fetchrow_hashref('NAME_lc')){
    $ctRows++;
    next if $restarting && $restarting > $ctRows;
    push(@snpIds,$row->{na_feature_id});
    last if $testNumber && $ctRows >= $testNumber;
  }
  $self->log("returned ".scalar(@snpIds)." SNPs to update");
  $self->getDb()->manageTransaction(0,'begin');
  $self->log("Starting to update SNP features");
  foreach my $snpId (@snpIds){
    $ctSnps++;
#    $self->updateSnp(undef,$snpId);  ##will use seqvariation objects
    $self->updateSnp($sumStmt,$snpId); ##will use sumQuery ... seems more efficient as expected.
    $self->manageTransAndCache($ctSnps) if $ctSnps % 100 == 0;
  }
  $self->getDb()->manageTransaction(0,'commit');
  $self->log("Updated $ctSnps SnpFeatures");
}

sub updateSnp {
  my($self,$stmt,$row) = @_;
  my $snp = GUS::Model::DoTS::SnpFeature->new({'na_feature_id' => $row});
  $snp->retrieveFromDB();

## use following block for generating from the summary query
  $stmt->execute($snp->getId());
  my $majorRow = $stmt->fetchrow_hashref('NAME_lc');
  my $minorRow = $stmt->fetchrow_hashref('NAME_lc');
  my ($otherCt,$otherIsNS,$otherStr,$otherStrRC) = $self->getRemainingMinorAlleles($stmt);
  my $hasNonSyn = ($otherIsNS || $self->getHasSyn($majorRow,$minorRow)) ? 1 : 0;
  $snp->setHasNonsynonymousAllele($hasNonSyn) unless $snp->getHasNonsynonymousAllele() == $hasNonSyn;
  $snp->setMinorAlleleCount($minorRow->{total} + $otherCt) unless $snp->getMinorAlleleCount() == $minorRow->{total};
  $snp->setMajorAlleleCount($majorRow->{total}) unless $snp->getMajorAlleleCount() == $majorRow->{total};
  $snp->setMinorAllele($minorRow->{allele}) unless $snp->getMinorAllele() eq $minorRow->{allele};


  $snp->setMinorProduct($minorRow->{product}) unless $snp->getMinorProduct() eq $minorRow->{product};
  $snp->setMajorAllele($majorRow->{allele}) unless $snp->getMajorAllele() eq $majorRow->{allele};
  $snp->setMajorProduct($majorRow->{product}) unless $snp->getMajorProduct eq $majorRow->{product};


#  my $strains = "$majorRow->{strains} $minorRow->{strains}".($otherCt ? " $otherStr" : "");
#  $snp->setStrains($strains) unless $snp->getStrains() eq $strains;
#  my $revStrains = "$majorRow->{strains_revcomp} $minorRow->{strains_revcomp}".($otherCt ? " $otherStrRC" : "");
#  $snp->setStrainsRevcomp() unless $snp->getStrainsRevcomp() eq $revStrains;

## use following if want to update from objects but less efficient
#    $snp->retrieveChildrenFromDB('GUS::Model::DoTS::SeqVariation');
#    $self->_makeSnpFeatureDescriptionFromSeqVars($snp);
#    $self->_addMajorMinorInfo($snp);
  
  $snp->submit(1,1);
}

sub getHasSyn {
  my($self,$maj,$min) = @_;
  return $maj->{phenotype} eq 'non-synonymous' || $min->{phenotype} eq 'non-synonymous';
}

sub getRemainingMinorAlleles {
  my($self,$stmt) = @_;
  my $tot = 0;
  my $ns = 0;
  my @strains;
  my @strainsRC;
  while(my $row = $stmt->fetchrow_hashref('NAME_lc')){
    $tot += $row->{total};
    $ns = 1 if $row->{phenotype} eq 'non-synonymous';
    push(@strains,$row->{strains});
    push(@strainsRC,$row->{strains_revcomp});
  }
  return ($tot,$ns,join(" ",@strains),join(" ",@strainsRC));
}

##commit / start transaction and undef the cache ...
sub manageTransAndCache {
  my($self,$ct) = @_;
  $self->getDb()->manageTransaction(0,'commit');
  $self->getDb()->manageTransaction(0,'begin');
  $self->undefPointerCache();
  $self->log("Updated $ct SnpFeatures") if $ct % 1000 == 0;
}


# sub _addMajorMinorInfo {
#   my ($self, $snpFeature) = @_;

#   my @seqVars = $snpFeature->getChildren('GUS::Model::DoTS::SeqVariation');
#   my $sourceId = $snpFeature->getSourceId();

#   my $referenceAllele = $snpFeature->getReferenceNa();
#   my $referenceProduct = $snpFeature->getReferenceAa();

#   my (%alleles, %products);

#   foreach my $seqVar (@seqVars) {
#     my $allele = $seqVar->getAllele();
#     my $product = $seqVar->getProduct();

#     $alleles{$allele}++;
#     $products{$allele} = $product if($product);
#   }

#   my %counts;
#   foreach(keys %alleles) {
#     my $count = $alleles{$_};
#     $counts{$count} = 1;
#   }

#   my (@sortedAlleleKeys, $nullAllele);
#   foreach my $allele (sort {$alleles{$b} <=> $alleles{$a}} keys %alleles){
#     if($allele eq "") {
#       $nullAllele = 1;
#     }
#     else {
#       push(@sortedAlleleKeys, $allele) ;
#     }
#   }

#   my $numbers = scalar(keys %counts);

#   if(scalar(@sortedAlleleKeys) == 1 && !$nullAllele) {
#     $self->log("WARNING","No Variation for source_id [$sourceId]");
#   }

#   my $majorAllele = @sortedAlleleKeys[0];
#   my $minorAllele = @sortedAlleleKeys[1];

#   if($numbers == 1) {
#     if($minorAllele eq $referenceAllele) {
#       $minorAllele = $majorAllele;
#       $majorAllele = $referenceAllele;
#     }
#     else {   
#       $majorAllele = $referenceAllele;
#     }
#   }
#   if($numbers == 2) {
#     $minorAllele = $referenceAllele
#       unless($majorAllele eq $referenceAllele || $minorAllele eq $referenceAllele);
#   } 

#   my $majorAlleleCount = $alleles{$majorAllele};
#   my $minorAlleleCount = $alleles{$minorAllele};

#   my $majorProduct = $products{$majorAllele};
#   my $minorProduct = $products{$minorAllele};

#   $snpFeature->setMajorAllele($majorAllele);
#   $snpFeature->setMajorAlleleCount($majorAlleleCount);
#   $snpFeature->setMajorProduct($majorProduct);
#   $snpFeature->setMinorAllele($minorAllele);
#   $snpFeature->setMinorAlleleCount($minorAlleleCount);
#   $snpFeature->setMinorProduct($minorProduct);

#   return($snpFeature);
# }


# ----------------------------------------------------------------------

#sub _makeSnpFeatureDescriptionFromSeqVars {
#  my ($self, $snpFeature) = @_;
#
#  my @seqVars = $snpFeature->getChildren('GUS::Model::DoTS::SeqVariation');
#
#  my (@strains, @strainsRevComp);
#
#  foreach my $seqVar (@seqVars) {
#    my $strain = $seqVar->getStrain();
#    my $allele = $seqVar->getAllele();
#    my $product = $seqVar->getProduct();
#
#    $strain =~ s/\s//g;
#    $allele =~ s/\s//g;
#    $product =~ s/\s//g;
#
#    my $revCompAllele = CBIL::Bio::SequenceUtils::reverseComplementSequence($allele);
#
#    push(@strains, "\"$strain\:$allele".($product ? "\:$product\"" : '"'));
#    push(@strainsRevComp, "\"$strain\:$revCompAllele".($product ? "\:$product\"" : '"'));
#  }
#
#  my $strains = join(' ', @strains);
#  my $strainsRevComp = join(' ', @strainsRevComp);
#
#  $snpFeature->setStrains(join(' ', @strains));
#  $snpFeature->setStrainsRevcomp(join(' ', @strainsRevComp));
#
#  return($snpFeature);
#}


# ----------------------------------------------------------------------

sub getSoId {
  my ($self, $termName) = @_;

  my $so = GUS::Model::SRes::SequenceOntology->new({'term_name'=>$termName});

  if (!$so->retrieveFromDB()) {
    $self->error("No row has been added for term_name = $termName in the sres.sequenceontology table\n");
  }

  my $soId = $so->getId();

  return $soId;

}

sub undoTables {
  my ($self) = @_;

  return (
         );
}

1;
