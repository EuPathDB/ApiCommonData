package ApiCommonData::Load::SpecialCaseQualifierHandlers;

use strict;

use GUS::Supported::SpecialCaseQualifierHandlers;
use GUS::Model::DoTS::Transcript;
use GUS::Model::DoTS::TranslatedAAFeature;
use GUS::Model::DoTS::TranslatedAASequence;
use GUS::Model::DoTS::AALocation;
use GUS::Supported::Plugin::InsertSequenceFeaturesUndo;
use GUS::Model::DoTS::AASequenceEnzymeClass;
use GUS::Model::DoTS::NAFeatureComment;
use ApiCommonData::Load::Util;

# this is the list of so terms that this file uses.  we have them here so we
# can check them at start up time.
my $soTerms = ({"pseudogene" => 1,
		"pseudogenic_transcript" => 1,
		"SECIS_element" => 1,
		"stop_codon_redefinition_as_selenocysteine" => 1,
	       });


sub new {
  my ($class) = @_;
  my $self = {};

  bless($self, $class);

  $self->{standardSCQH} = GUS::Supported::SpecialCaseQualifierHandlers->new();
  return $self;
}

sub setPlugin{
  my ($self, $plugin) = @_;
  $self->{plugin} = $plugin;

}

sub initUndo{
  my ($self, $algoInvocIds, $dbh) = @_;

  $self->{'algInvocationIds'} = $algoInvocIds;
  $self->{'dbh'} = $dbh;
  $self->{standardSCQH}->initUndo($algoInvocIds, $dbh);
}

sub undoAll{
  my ($self, $algoInvocIds, $dbh) = @_;

  $self->initUndo($algoInvocIds, $dbh);

  $self->_undoFunction();
  $self->_undoProduct();
  $self->_undoGene();
  $self->_undoECNumber();
  $self->_undoAnticodon();
  $self->_undoProvidedTranslation();
  $self->_undoMiscSignalNote();
  $self->_undoSourceIdAndTranscriptSeq();
  $self->_undoDbXRef();
  $self->_undoGapLength();
  $self->_undoNote();
  $self->_undoPseudo();
  $self->_undoTranscriptProteinId();
  $self->_undoTranscriptTranslExcept();
  $self->_undoProvidedOrfTranslation();
}


######### Set source_id and, while here, exon start/stop and transcript seq ###

# 1. Loop through Transcripts... Set the Sequence for its splicedNaSequence
# 2. Find the Min CDS Start and Max CDS END and set translation(Start|Stop) for 
#    the translatedAAFeature
# 3. No Splicing of the Exons occurs!!!
sub sourceIdAndTranscriptSeq {
  my ($self, $tag, $bioperlFeature, $geneFeature) = @_;

  # first set source id, and propogate it to the transcript and aa seq
  my @tagValues = $bioperlFeature->get_tag_values($tag);
  $geneFeature->setSourceId($tagValues[0]);

  my @transcripts = $geneFeature->getChildren("DoTS::Transcript");
  my $count = 0;
  foreach my $transcript (@transcripts) {
    $count++;
    $transcript->setSourceId("$tagValues[0]-$count");
    my $translatedAAFeat = $transcript->getChild('DoTS::TranslatedAAFeature');
    if ($translatedAAFeat) {
      $translatedAAFeat->setSourceId("$tagValues[0]-$count");
      my $aaSeq = $translatedAAFeat->getParent('DoTS::TranslatedAASequence');
      if ($aaSeq) {
	$aaSeq->setSourceId("$tagValues[0]-$count");
      }
    }
  }


  # second, initialize isPseudo
  if (!defined($geneFeature->getIsPseudo())) {
    $geneFeature->setIsPseudo(0);
  }

  # now do the exons and transcript seq
  foreach my $transcript ($geneFeature->getChildren('DoTS::Transcript')) {

    my ($transcriptMin, $transcriptMax, @exons, $isReversed);

    foreach my $rnaExon ($transcript->getChildren('DoTS::RNAFeatureExon')) {
      my $exon = $rnaExon->getParent('DoTS::ExonFeature');
      my $naLoc = $exon->getChild('DoTS::NALocation');

      $isReversed = $naLoc->getIsReversed();

      my $exonStart = $isReversed ? $naLoc->getEndMax : $naLoc->getStartMin();
      my $exonStop = $isReversed ? $naLoc->getStartMin : $naLoc->getEndMax();

      $transcriptMin = $naLoc->getStartMin if($naLoc->getStartMin < $transcriptMin || !$transcriptMin);
      $transcriptMax = $naLoc->getEndMax if($naLoc->getEndMax > $transcriptMax || !$transcriptMax);

      # This works until there are alternaltive spliced transcripts...
      $exon->setCodingStart($exonStart);
      $exon->setCodingEnd($exonStop);

      push(@exons, $exon);
    }

    if($bioperlFeature->primary_tag() eq "coding_gene"){
      my $translatedAaFeature = $transcript->getChild('DoTS::TranslatedAAFeature');

      if($isReversed) {
	$translatedAaFeature->setTranslationStart($transcriptMax);
	$translatedAaFeature->setTranslationStop($transcriptMin);
      }
      else {
	$translatedAaFeature->setTranslationStart($transcriptMin);
	$translatedAaFeature->setTranslationStop($transcriptMax);
      }
    }

    my $transcriptCodingSequence = ApiCommonData::Load::Util::getCodingSequenceFromExons(\@exons);
    my $splicedNaSeq = $transcript->getParent('DoTS::SplicedNASequence');
    $splicedNaSeq->setSequence($transcriptCodingSequence);
  }
  return [];
}

sub _undoSourceIdAndTranscriptSeq {
  my ($self) = @_;

}

################ Translation#############################

sub setProvidedTranslation {
  my ($self, $tag, $bioperlFeature, $geneFeature) = @_;

  my ($aaSequence) = $bioperlFeature->get_tag_values($tag);

  my $transcript = $geneFeature->getChild("DoTS::Transcript");

  my $translatedAaFeature = $transcript->getChild('DoTS::TranslatedAAFeature');
  my $translatedAaSequence = $translatedAaFeature->getParent('DoTS::TranslatedAASequence');

  $translatedAaSequence->setSequence($aaSequence);

  return [];
}

sub _undoProvidedTranslation{
  my ($self) = @_;

}

################ Product ################################

# only keep the first /product qualifier
# cascade product name to transcript, translation and AA sequence:
sub product {
  my ($self, $tag, $bioperlFeature, $geneFeature) = @_;

  my @tagValues = $bioperlFeature->get_tag_values($tag);
  $geneFeature->setProduct($tagValues[0]);

  # cascade product name to transcript, translation and AA sequence:
  my @transcripts = $geneFeature->getChildren("DoTS::Transcript");
  foreach my $transcript (@transcripts) {
    $transcript->setProduct($tagValues[0]);
    my $translatedAAFeat = $transcript->getChild('DoTS::TranslatedAAFeature');
    if ($translatedAAFeat) {
      $translatedAAFeat->setDescription($tagValues[0]);
      my $aaSeq = $translatedAAFeat->getParent('DoTS::TranslatedAASequence');
      if ($aaSeq) {
	$aaSeq->setDescription($tagValues[0]);
      }
    }
  }

  return [];
}

# nothing special to do
sub _undoProduct{
  my ($self) = @_;

}


################ Gene ###############################3
# we wrap these methods so that we don't call the standard SCQH directly, to
# have finer control over the order of undoing
sub gene {
  my ($self, $tag, $bioperlFeature, $feature) = @_;
  return $self->{standardSCQH}->gene($tag, $bioperlFeature, $feature);
}

sub _undoGene{
  my ($self) = @_;
  return $self->{standardSCQH}->_undoGene();
}

################ dbXRef ###############################

sub dbXRef {
  my ($self, $tag, $bioperlFeature, $feature) = @_;
  return $self->{standardSCQH}->dbXRef($tag, $bioperlFeature, $feature);
}

sub _undoDbXRef{
  my ($self) = @_;
  return $self->{standardSCQH}->_undoDbXRef();
}


################ Gap Length ###############################

sub gapLength {
  my ($self, $tag, $bioperlFeature, $feature) = @_;
  return $self->{standardSCQH}->gapLength($tag, $bioperlFeature, $feature);
}

sub _undoGapLength{
  my ($self) = @_;
  return $self->{standardSCQH}->_undoGapLength();
}


################ Note ########################################

sub note {
  my ($self, $tag, $bioperlFeature, $feature) = @_;
  return $self->{standardSCQH}->note($tag, $bioperlFeature, $feature);
}

sub _undoNote{
  my ($self) = @_;
  return $self->{standardSCQH}->_undoNote();
}

############### Pseudo  ###############################

sub setPseudo {
  my ($self, $tag, $bioperlFeature, $feature) = @_;

  my $transcript = &getGeneTranscript($self->{plugin}, $feature);

  $feature->setIsPseudo(1);
  $transcript->setIsPseudo(1);

#  $feature->setSequenceOntologyId($self->_getSOPrimaryKey("pseudogene"));
#  $transcript->setSequenceOntologyId($self->_getSOPrimaryKey("pseudogenic_transcript"));

  return [];
}

sub _undoPseudo{
    my ($self) = @_;
}

############### transl_except  ###############################

sub transcriptTranslExcept {
  my ($self, $tag, $bioperlFeature, $geneFeature) = @_;
  my $transcript = $geneFeature->getChild("DoTS::Transcript");
  my ($transl_except) = $bioperlFeature->get_tag_values($tag);
  $transcript->setTranslExcept($transl_except);
  return [];
}

sub _undoTranscriptTranslExcept {}

################ EC Number ###############################

# attach EC number to translated aa seq.
sub ECNumber {
  my ($self, $tag, $bioperlFeature, $feature) = @_;

  my $aaSeq = &getGeneAASeq($self->{plugin},$feature);

  foreach my $tagValue ($bioperlFeature->get_tag_values($tag)) {
    if ($tagValue eq ""){
      next;
    }
    $tagValue =~ s/^EC: //;
    $tagValue =~ s/\_/\-/;
    my $ecId = $self->_getECNumPrimaryKey($tagValue);
    die "Invalid Enzyme Class '$tagValue'" unless $ecId;
    my $args = {enzyme_class_id => $ecId,
		evidence_code => 'Annotation Center'};
    my $aaSeqEC = GUS::Model::DoTS::AASequenceEnzymeClass->new($args);
    $aaSeq->addChild($aaSeqEC);
  }

#  $aaSeq->submit();

  return [];
}

sub _getECNumPrimaryKey {
  my ($self, $ECNum) = @_;

  if (!$self->{ECNumPKs}) {
    my $rls_id = $self->{plugin}->getExternalDbRlsIdByTag("enzyme");
    $self->{plugin}->userError("Plugin argument --handlerExternalDbs must provide a tag 'enzyme' with External Db info for the Enzyme Database") unless $rls_id;

    my $dbh = $self->{plugin}->getQueryHandle();
    my $sql = <<EOSQL;

  SELECT EC_number, enzyme_class_id
  FROM   sres.EnzymeClass
  WHERE  external_database_release_id = ?

EOSQL

    my $stmt = $dbh->prepare($sql); $stmt->execute($rls_id);
    while (my ($ecnum, $pk) = $stmt->fetchrow_array()){
      $self->{ECNumPKs}->{$ecnum} = $pk;
    }
  }

  return $self->{ECNumPKs}->{$ECNum};
}

# nothing special to do
sub _undoECNumber{
  my ($self) = @_;
  $self->_deleteFromTable('DoTS.AASequenceEnzymeClass');
}

################ anticodon ########################################
sub anticodon {
  my ($self, $tag, $bioperlFeature, $feature) = @_;

  my @tags = $bioperlFeature->get_tag_values($tag);
  die "Feature has more than one /anticodon\n" if scalar(@tags) != 1;

  my $transcript = &getGeneTranscript($self->{plugin}, $feature);
  $transcript->setAnticodon($tags[0]);
  return [];
}

sub _undoAnticodon{
  my ($self) = @_;
}

################# transcript's protein ID ######################################
sub transcriptProteinId {
  my ($self, $tag, $bioperlFeature, $feature) = @_;

  my ($proteinId) = $bioperlFeature->get_tag_values($tag);

  my $transcript = $feature->getChild("DoTS::Transcript");

  $transcript->setProteinId($proteinId);

  my $translatedAAFeat = $transcript->getChild('DoTS::TranslatedAAFeature');
  if ($translatedAAFeat) {
    my $aaSeq = $translatedAAFeat->getParent('DoTS::TranslatedAASequence');
    $aaSeq->setSecondaryIdentifier($proteinId) if ($aaSeq);
  }

  return [];
}

sub _undoTranscriptProteinId{
  my ($self) = @_;
}
################ Function ################################

sub function {
  my ($self, $tag, $bioperlFeature, $feature) = @_;

  my @tagValues = $bioperlFeature->get_tag_values($tag);
  $feature->setFunction(join(' | ', @tagValues));

  return [];
}

sub _undoFunction{
  my ($self) = @_;

}


################### open reading frame translation  #################
################ Translation#############################

sub setProvidedOrfTranslation {
  my ($self, $tag, $bioperlFeature, $orfFeature) = @_;

  my ($aaSequence) = $bioperlFeature->get_tag_values($tag);

  my $translatedAaFeature = $orfFeature->getChild('DoTS::TranslatedAAFeature');
  my $translatedAaSequence = $translatedAaFeature->getParent('DoTS::TranslatedAASequence');

  $translatedAaSequence->setSequence($aaSequence);

  return [];
}

sub _undoProvidedOrfTranslation{
  my ($self) = @_;

}

################## static methods to be used by this and other S.C.Q.H.s ######

sub getGeneAASeq {
  my ($plugin, $gusGeneFeature) = @_;

  my $transcript = &getGeneTranscript($plugin,$gusGeneFeature);

  my $translatedAAFeat = $transcript->getChild("DoTS::TranslatedAaFeature");

  my $aaSeq = $translatedAAFeat->getParent("DoTS::TranslatedAaSequence");

  return $aaSeq;
}

# given a gus feature, confirm that it is a gene, and, get its transcript
# note: assumes the gene has only one transcript (for now)
sub getGeneTranscript {
  my ($plugin, $gusGeneFeature) = @_;

  my $transcript = $gusGeneFeature->getChild("DoTS::Transcript");
  $transcript || $plugin->error("Can't find transcript for feature with na_feature_id = " . $gusGeneFeature->getId());
  return $transcript;
}


###################  misc_signal /note  #################

sub miscSignalNote {
  my ($self, $tag, $bioperlFeature, $feature) = @_;

  my @notes;
  foreach my $tagValue ($bioperlFeature->get_tag_values($tag)) {
    if ($tagValue eq 'TGA slenocysteine codon') {
      my $soId = $self->_getSOPrimaryKey('stop_codon_redefinition_as_selenocysteine');
      $feature->setSequenceOntologyId($soId);
    } elsif ($tagValue eq 'SECIS element') {
      my $id = $self->_getSOPrimaryKey('SECIS_element');
      $feature->setSequenceOntologyId($id);
    }

    my $arg = {comment_string => substr($tagValue, 0, 4000)};
    push(@notes, GUS::Model::DoTS::NAFeatureComment->new($arg));

  }
  return \@notes;
}

sub _undoMiscSignalNote{
  my ($self) = @_;
  $self->_deleteFromTable('DoTS.NAFeatureComment');
}

#################################################################

sub _getSOPrimaryKey {
  my ($self, $soTerm) = @_;
  die "using so term '$soTerm' which not declared at the top of this file" unless $soTerms->{$soTerm};

  return $self->{plugin}->getSOPrimaryKey($soTerm);
}

sub _deleteFromTable{
   my ($self, $tableName) = @_;

  &GUS::Supported::Plugin::InsertSequenceFeaturesUndo::deleteFromTable($tableName, $self->{'algInvocationIds'}, $self->{'dbh'});
}

1;
