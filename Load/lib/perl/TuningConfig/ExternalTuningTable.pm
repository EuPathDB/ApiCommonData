package ApiCommonData::Load::TuningConfig::ExternalTuningTable;

# @ISA = qw( ApiCommonData::Load::TuningConfig::Table );

use strict;
use ApiCommonData::Load::TuningConfig::Log;

sub new {
    my ($class,
	$name,      # name of database table
        $dblink,
        $dbh,       # database handle
        $doUpdate)  # are we updating, not just checking, the db?
	= @_;

    my $self = {};

    bless($self, $class);
    $self->{name} = $name;
    $self->{dbh} = $dbh;

    if ($dblink) {
      $dblink = '@' . $dblink;
    }
    $self->{dblink} = $dblink;

    # get the timestamp
    my $sql = <<SQL;
       select to_char(timestamp, 'yyyy-mm-dd hh24:mi:ss')
       from apidb.TuningTable$dblink
       where name = '$self->{name}'
SQL
    my $stmt = $dbh->prepare($sql);
    $stmt->execute()
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
    my ($timestamp) = $stmt->fetchrow_array();
    $stmt->finish();

    if (!defined $timestamp) {
      $self->{exists} = 0;
      ApiCommonData::Load::TuningConfig::Log::addErrorLog("No TuningTable record for $self->{name}" . "\@$dblink");
    } else {
      $self->{exists} = 1;
    };

    $self->{timestamp} = $timestamp;
    return $self;
}

sub getTimestamp {
    my ($self) = @_;

    return $self->{timestamp};
}

sub getName {
  my ($self) = @_;

  return $self->{name};
}

sub exists {
  my ($self) = @_;

  return $self->{exists};
}


1;
