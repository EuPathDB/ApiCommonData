package ApiCommonData::Load::IsolateVocabulary::Reader::VocabSqlReader;
use base qw(ApiCommonData::Load::IsolateVocabulary::Reader);

use strict;

use Carp;

sub new {
  my ($class, $dbh) = @_;

  my $args = {};

  my $self = bless $args, $class; 

  $self->setDbh($dbh);

  return $self;
}

sub extract {
  my ($self) = @_;

  my $dbh = $self->getDbh();

  my $sql = "select term, parent, type from apidb.isolatevocabulary";
  my $sh = $dbh->prepare($sql);
  $sh->execute();

  my $vocab;

  while(my ($term, $parent, $type) = $sh->fetchrow_array()) {
    die "duplicate ($type, $term) in vocab file line $.\n" if $vocab->{$type}->{$term};
    $vocab->{$type}->{$term} = 1;
  }

  $sh->finish();

  return $vocab;
}


1;
