package ApiCommonData::Load::IsolateVocabulary::Reporter;
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
  # GUS4_STATUS | dots.gene                      | manual | unreviewed
die 'This file has broken or unreviewed GUS4_STATUS rules.  Please remove this line when all are fixed or absent';
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^

use strict;
use Carp;

use ApiCommonData::Load::IsolateVocabulary::Utils;

sub getSqlTerms {$_[0]->{_sql_terms}}

sub getVocabTerms {$_[0]->{_vocabTerms}}

sub getXmlMapTerms {$_[0]->{_xml_map_terms}}
sub setXmlMapTerms {$_[0]->{_xml_map_terms} = $_[1]}

sub getGusConfigFile {$_[0]->{gusConfigFile}}
sub setGusConfigFile {$_[0]->{gusConfigFile} = $_[1]}

sub disconnect {$_[0]->{dbh}->disconnect()}

sub getDbh {$_[0]->{dbh}}
sub setDbh {$_[0]->{dbh} = $_[1]}

sub new {
  my ($class, $gusConfigFile, $xmlMapTerms, $sqlTerms, $type, $vocabTerms) = @_;

  unless(ApiCommonData::Load::IsolateVocabulary::Utils::isValidType($type)) {
    croak "Type $type is not supported";
  }

  my $args = {_sql_terms => $sqlTerms,
              _xml_map_terms => $xmlMapTerms,
              _type => $type,
	      _vocabTerms => $vocabTerms
             };


  my $self = bless $args, $class;
  $self->setGusConfigFile($gusConfigFile);

  my $dbh = ApiCommonData::Load::IsolateVocabulary::Utils::createDbh($gusConfigFile);

  $self->setDbh($dbh);
  $self->setXmlMapTerms($xmlMapTerms);

  return $self;
}

sub report {
  my ($self) = @_;

  my $type = $_[0]->{_type};

  my $hadErrors;

  my $dbh = $self->getDbh();

  my $xmlMapTerms = $self->getXmlMapTerms();

  # Check XML terms have all needed attributes
  foreach my $xmlTerm (@$xmlMapTerms) {
    unless($xmlTerm->isValid()) {
      print STDERR "had error\n";
      $hadErrors = 1;
    }
  }

  # ensure the (assignment) terms in the mapping file are present in ontology
  my $check = $self->checkOntology($dbh);

  # make hash lookup for xml terms
  my $xmlTermsHash = $self->makeHashFromTerms();

  my $sqlTerms = $self->getSqlTerms();

  # Check all Sql terms are handled
  foreach my $vocabTerm (@{$sqlTerms}) {
    next if($vocabTerm->getAlreadyMaps());

    my $term = $vocabTerm->getTerm();
    my $table = $vocabTerm->getTable();

    unless($xmlTermsHash->{$term}->{$table}) {
      print STDERR "No Mapping Info for Vocab Term:  $term\n";
      $self->getXml($term, $type, $table);
      $hadErrors = 1;
    }
  }


  if($hadErrors || $check) {
    print STDERR "Please Correct Errors and rerun.  Terms can either be added to an ontology or add an xml map to link term to existing ontology\n";
  }
  else {
    print STDERR "All New Ontology Terms either map to existing term or are handled in the xml map!\n";
  }

}

sub makeHashFromTerms {
  my ($self) = @_;

  my $xmlTerms = $self->getXmlMapTerms();

  my %hash;

  foreach my $vocabTerm (@{$xmlTerms}) {

    my $term = $vocabTerm->getTerm();
    my $table = $vocabTerm->getTable();

    $hash{$term}->{$table} = 1;
  }

  return \%hash;
}


sub getXml {
  my ($self, $value, $type, $table) = @_;
  my $typeInTable = $type;

  # change typeInTable appropriately
  if ($table eq 'OntologyEntry') {
    $typeInTable = 'GeographicLocation' if ($type eq 'geographic_location');
    $typeInTable = 'BioSourceType' if ($type eq 'isolation_source');
    $typeInTable = 'Host' if ($type eq 'specific_host');
  } else {
    $typeInTable = 'country' if ($type eq 'geographic_location');
  }

  # parse out country name from geographic_location, and put in the reporter XML
  my ($country, $x ) =('','');
  if ($type eq 'geographic_location') {
    ($country, $x ) = split (/:/, $value);
  }

  my $str = <<END;
  <initial table=\"$table\" field=\"$typeInTable">
   <original>$value<\/original>
    <maps>
      <row type=\"$type\" value=\"$country\" \/>
    <\/maps>
  <\/initial>
END

print STDOUT $str;

}


sub isIncluded {
  my ($self, $a, $v) = @_;

  unless($a) {
    return 0;
  }
  foreach(@$a) {
    return 1 if $v eq $_;
  }
  return 0;
}

sub checkOntology {
  my ($self) = @_;

  my $allOntology = $self->getVocabTerms();
  my $fails = 0;

  foreach my $term (@{$self->getXmlMapTerms}) {
    my $mapTerm = $term->getMapTerm();
    my $mapType = $term->getType();
    my $origterm = $term->getTerm();

    unless($allOntology->{$mapType}->{$mapTerm}) {
      $fails++;
      print STDOUT "MISSING FROM VOCABULARY FILE: $mapTerm\t\t$mapType\n";
    }
  }
  print STDOUT "\n\n";
  return $fails;
}

1;
