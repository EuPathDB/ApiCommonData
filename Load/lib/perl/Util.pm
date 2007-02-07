package ApiCommonData::Load::Util;

use strict;

use GUS::Model::DoTS::TranslatedAAFeature;
use GUS::Model::DoTS::TranslatedAASequence;

# return null if not found:  be sure to check handle that condition!!
sub getNASequenceId {
  my ($plugin, $sourceId) = @_;

  if (!$plugin->{sourceIdFeatureIdMap}) {
    $plugin->{sourceIdFeatureIdMap} = {};
    my $sql = "
SELECT source_id, na_sequence_id
FROM Dots.SplicedNASequence
";
    my $stmt = $plugin->prepareAndExecute($sql);
    while ( my($sourceId, $na_sequence_id) = $stmt->fetchrow_array()) {
      $plugin->{sourceIdFeatureIdMap}->{$sourceId} = $na_sequence_id;
    }
  }
  return $plugin->{sourceIdFeatureIdMap}->{$sourceId};
}



# return null if not found:  be sure to check handle that condition!!
sub getGeneFeatureId {
  my ($plugin, $sourceId) = @_;

  if (!$plugin->{sourceIdFeatureIdMap}) {

    $plugin->{sourceIdFeatureIdMap} = {};

    my $sql = "
SELECT source_id, na_feature_id
FROM Dots.GeneFeature
UNION
SELECT g.name, gf.na_feature_id
FROM Dots.GeneFeature gf, Dots.NAFeatureNAGene nfng, Dots.NAGene g
WHERE nfng.na_feature_id = gf.na_feature_id
AND nfng.na_gene_id = g.na_gene_id
";
    my $stmt = $plugin->prepareAndExecute($sql);
    while ( my($sourceId, $na_feature_id) = $stmt->fetchrow_array()) {
      $plugin->{sourceIdFeatureIdMap}->{$sourceId} = $na_feature_id;
    }
  }

  return $plugin->{sourceIdFeatureIdMap}->{$sourceId};
}

# return null if not found:  be sure to check handle that condition!!
sub getAAFeatureId {
  my ($plugin, $sourceId) = @_;

  if (!$plugin->{sourceIdFeatureIdMap}) {

    $plugin->{sourceIdFeatureIdMap} = {};

    my $sql = "
SELECT source_id, aa_feature_id
FROM Dots.AAFeature
";
    my $stmt = $plugin->prepareAndExecute($sql);
    while ( my($sourceId, $na_feature_id) = $stmt->fetchrow_array()) {
      $plugin->{sourceIdFeatureIdMap}->{$sourceId} = $na_feature_id;
    }
  }

  return $plugin->{sourceIdFeatureIdMap}->{$sourceId};
}

sub getAASeqIdFromFeatId {
  my ($featId) = shift;

  my $gusTAAF = GUS::Model::DoTS::TranslatedAAFeature->new( { 'na_feature_id' => $featId, } );

  $gusTAAF->retrieveFromDB()
    or die "no translated aa sequence: $featId";

  my $gusAASeq = $gusTAAF->getAaSequenceId();

  return $gusAASeq;
}


# get an aa seq id from a source_id or source_id alias.
sub getAASeqIdFromGeneId {
  my ($plugin, $geneId) = @_;

  my $featId = getGeneFeatureId($plugin, $geneId);
  return getAASeqIdFromFeatId($featId);
}


sub getAASeqIdFromCaselessSourceId {
  my ($plugin, $sourceId) = @_;

  $sourceId = uc($sourceId);

  my $sql = "SELECT aa_sequence_id
               FROM DoTS.TranslatedAASequence
               Where upper(source_id) = \'$sourceId\'";

  my $recordSet = $plugin->prepareAndExecute($sql);
  my($aaSeqId) = $recordSet->fetchrow_array(); 
  return $aaSeqId;
}


sub getGeneFeatureIdFromSourceId {
  my $featureId = shift;

  my $gusGF = GUS::Model::DoTS::GeneFeature->new( { 'source_id' => $featureId, } );

  $gusGF->retrieveFromDB() ||
    die "no translated aa sequence: $featureId";

  my $gusAASeq = $gusGF->getId();

  return $gusAASeq;
}

sub getCodingSequenceFromExons {
  my ($gusExons) = @_;

  die "No Exons found" unless(scalar(@$gusExons) > 0);

  foreach (@$gusExons) {
    die "Expected DoTS Exon... found " . ref($_)
      unless(UNIVERSAL::isa($_, 'GUS::Model::DoTS::ExonFeature'));
  }

  # this code gets the feature locations of the exons and puts them in order
  my @exons = map { $_->[0] }
    sort { $a->[3] ? $b->[1] <=> $a->[1] : $a->[1] <=> $b->[1] }
      map { [ $_, $_->getFeatureLocation ]}
	@$gusExons;

  my $codingSequence;

  for my $exon (@exons) {
    my $chunk = $exon->getFeatureSequence();

    my ($exonStart, $exonEnd, $exonIsReversed) = $exon->getFeatureLocation();

    my $codingStart = $exon->getCodingStart();
    my $codingEnd = $exon->getCodingEnd();

    next unless ($codingStart && $codingEnd);

    my $trim5 = $exonIsReversed ? $exonEnd - $codingStart : $codingStart - $exonStart;
    substr($chunk, 0, $trim5, "") if $trim5 > 0;

    my $trim3 = $exonIsReversed ? $codingEnd - $exonStart : $exonEnd - $codingEnd;
    substr($chunk, -$trim3, $trim3, "") if $trim3 > 0;

    $codingSequence .= $chunk;
  }

  return($codingSequence);
}



1;


