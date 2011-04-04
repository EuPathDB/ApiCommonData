#!/usr/bin/perl

use strict;
use lib "$ENV{GUS_HOME}/lib/perl";
use CBIL::Util::PropertySet;
use Getopt::Long;
use DBI;
use DBD::Oracle;

my ($help, $fn, $gusConfigFile);

&GetOptions('help|h' => \$help,
            'file=s' => \$fn,
            'gus_config_file=s' => \$gusConfigFile,
            );

#============================================

$gusConfigFile = $ENV{GUS_HOME} . "/config/gus.config" unless($gusConfigFile);

unless(-e $gusConfigFile && -e $fn) {
  print STDERR "usage --file continents_file [--gus_config_file]\n";
  exit;
}

my @properties = ();
my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

my $u = $gusconfig->{props}->{databaseLogin};
my $pw = $gusconfig->{props}->{databasePassword};
my $dsn = $gusconfig->{props}->{dbiDsn};

my $dbh = DBI->connect($dsn, $u, $pw) or die DBI::errstr;
$dbh->{RaiseError} = 1;
$dbh->{AutoCommit} = 0;

open(FILE, $fn) or die "Cannot open file $fn for reading:$!";


$dbh->do("delete apidb.isolatevocabulary");

my $sql = "insert into apidb.isolatevocabulary (isolate_vocabulary_id, term, parent, type) values (ApiDB.IsolateVocabulary_sq.nextval,?,?,?)";
my $sh = $dbh->prepare($sql);

while(<FILE>) {
  chomp;

  next unless $_;
  my ($term, $parent, $type) = split(/\t/, $_);

  $sh->execute($term, $parent, $type);
}

close FILE;

$sh->finish();
$dbh->disconnect;

1;
