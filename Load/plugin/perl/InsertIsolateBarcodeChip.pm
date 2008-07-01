package ApiCommonData::Load::Plugin::InsertIsolateBarcodeChip;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use lib "$ENV{GUS_HOME}/lib/perl";
use GUS::PluginMgr::Plugin;
use GUS::Model::DoTS::ExternalNASequence;
use GUS::Model::DoTS::NALocation;
use GUS::Model::DoTS::IsolateSource;
use GUS::Model::DoTS::IsolateFeature;

use Data::Dumper;

my $purposeBrief = <<PURPOSEBRIEF;
Insert Molecular Barcode data from a tab file (converted from Excel format).
PURPOSEBRIEF

my $purpose = <<PURPOSE;
Insert Molecular Barcode data from a tab file (converted from Excel format).
PURPOSE

my $tablesAffected = [
  ['DoTS.IsolateSource', 'One row per barcode - strain, origin, source, sequence'],
  ['DoTS.IsolateFeature', 'One row or more per inserted IsolateSource, name, chr, major/minor allele'],
  ['DoTS.ExternalNASequence', 'One row inserted per barcode .IsolateSource row'] 
];

my $tablesDependedOn = [];

my $howToRestart = "There is currently no restart method.";

my $failureCases = "There are no know failure cases.";

my $notes = <<PLUGIN_NOTES;
Here are the tab file columns:
  Strain
  Origin
  Source
  Barcode
  SNPS
  snp_id A T C ...

  Example SNP id: Pf_01_000101502 indicates SNP on contig 1 position 101502.
PLUGIN_NOTES

my $documentation = { purpose          => $purpose,
                      purposeBrief     => $purposeBrief,
                      tablesAffected   => $tablesAffected,
                      tablesDependedOn => $tablesDependedOn,
                      howToRestart     => $howToRestart,
                      failureCases     => $failureCases,
                      notes            => $notes
                    };

my $argsDeclaration = 
  [
    stringArg({name           => 'extDbName',
               descr          => 'the external database name to tag the data with.',
               reqd           => 1,
               constraintFunc => undef,
               isList         => 0,
             }),
    stringArg({name           => 'extDbRlsVer',
               descr          => 'the version of the external database to tag the data with.',
               reqd           => 1,
               constraintFunc => undef,
               isList         => 0,
             }),
    booleanArg({name    => 'tolerateMissingIds',
                descr   => "don't fail if an input sourceId is not found in database",
                reqd    => 0,
                default => 0
              }),
    fileArg({ name           => 'inputFile',
              descr          => 'file containing the data',
              constraintFunc => undef,
              reqd           => 1,
              mustExist      => 1,
              isList         => 0,
              format         =>'Tab-delimited.  See ApiDB.MassSpecSummary for columns'
           }), 
   ];

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class); 

  $self->initialize({requiredDbVersion => 3.5,
                     cvsRevision => '$Revision: 2 $', # cvs fills this in!
                     name => ref($self),
                     argsDeclaration => $argsDeclaration,
                     documentation => $documentation
                   });
  return $self;
}

sub run {
  my ($self) = @_;
  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbName'),
                                        $self->getArg('extDbRlsVer'));

  die "Couldn't find external_database_release_id" unless $extDbRlsId;

  my $inputFile = $self->getArg('inputFile');

  open(FILE, $inputFile) || $self->error("couldn't open file '$inputFile' for reading");

  my $count = 0;
  my @snpFeats;
  my $flag = 0;
  my %metaHash;
  my @snps;

  while(<FILE>) {
    chomp;
    next if /^\s*$/;

    $flag = 0 and next if /^#MetaData/i;

    if($flag == 0) {
      $flag = 1 and next if /^#SNPS/i;
      my($k, @others) = split /\t/, $_;
      $metaHash{$k} = \@others;
    } else {
      my @snp = split /\t/, $_;
      map { s/\s+$// } @snp;  # trim off extra end spaces
      push @snps, \@snp;
    }
  } # end file

  my $size = @{$metaHash{Strain}};
  for(my $i = 0; $i < $size; $i++) {
    my $strain = $metaHash{Strain}->[$i];
    my $origin = $metaHash{Origin}->[$i];
    my $source = $metaHash{Source}->[$i];
    my $barcode = $metaHash{Barcode}->[$i];

    print "$strain |$origin | $source |$barcode\n";

    my $objArgs = {
                    strain                       => $strain,
                    name                         => $strain,  
                    isolate                      => $strain,
                    country                      => $origin,
                    collected_by                 => $source,
                    external_database_release_id => $extDbRlsId,
                  };

    my $isolateSource = GUS::Model::DoTS::IsolateSource->new($objArgs);

    # foreach barcode nucleotide, find SNP ID#, major and minor allele

    my $isolateFeature = $self->processIsolateFeature(\@snps, $i+1);

    foreach(@$isolateFeature) {
      my ($snp_id, $allele) = @$_;

      # sample snp_id: Pf_02_000842803
      my ($species, $chr, $location) = split /_/, $snp_id;
      $chr =~ s/^0+//;
      $chr = 'MAL' . $chr;
      $location =~ s/^0+//;

      print "++ $species | $chr | $location\n";

      my $featArgs = { allele                       => $allele,
                       name                         => $snp_id,
                       map                          => $location, # na_location.. later
                       external_database_release_id => $extDbRlsId,
                     };

      my $isolateFeature = GUS::Model::DoTS::IsolateFeature->new($featArgs);

      my $naLoc = GUS::Model::DoTS::NALocation->new({'start_min'     => $location,
                                                     'start_max'     => $location,
                                                     'end_min'       => $location,
                                                     'end_max'       => $location,
                                                     'location_type' => 'EXACT'  
                                                    });
      $isolateFeature->addChild($naLoc);
      $isolateSource->addChild($isolateFeature);

    }

    my $extNASeq = $self->buildSequence($barcode, $extDbRlsId);

    $extNASeq->addChild($isolateSource);

    $extNASeq->submit();
    $count++;
    $self->log("processed $count") if ($count % 1000) == 0;

  }

  return "Inserted $count rows.";
}

sub buildSequence {
  my ($self, $seq, $extDbRlsId) = @_;

  my $extNASeq = GUS::Model::DoTS::ExternalNASequence->new();

  $extNASeq->setExternalDatabaseReleaseId($extDbRlsId);
  $extNASeq->setSequence($seq);

  return $extNASeq;
}

sub processIsolateFeature {
  my ($self, $snps, $index) = @_;

  my @isolateFeature;

  foreach my $s (@$snps) {
    #print "?? $s | @$s | $index\n";
    push @isolateFeature, [$s->[0], $s->[$index]];
  }

  return \@isolateFeature;
}

sub undoTables {
  my ($self) = @_;
  return ('ApiDB.IsolateSource');
}

1;
