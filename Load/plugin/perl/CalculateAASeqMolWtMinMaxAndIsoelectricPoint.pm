package ApiCommonData::Load::Plugin::CalculateAASeqMolWtMinMaxAndIsoelectricPoint;

use strict;
use warnings;

use GUS::PluginMgr::Plugin;
use base qw(GUS::PluginMgr::Plugin);

use GUS::Model::ApiDB::AaSequenceAttribute;
use Bio::Tools::SeqStats;
use Bio::Tools::pICalculator;
use Bio::Seq;

my $argsDeclaration =
  [
   stringArg({ name => 'extDbRlsName',
	       descr => 'External Database Release name of the AA sequences',
	       constraintFunc => undef,
	       isList => 0,
	       reqd => 1,
	     }),

   stringArg({ name => 'extDbRlsVer',
	       descr => 'External Database Release version of the AA sequences',
	       constraintFunc => undef,
	       isList => 0,
	       reqd => 1,
	     }),
   stringArg({ name => 'seqTable',
	       descr => 'where to find the target AA sequences in the form DoTs.tablename',
	       constraintFunc => undef,
	       isList => 0,
	       reqd => 1,
	     })
  ];


my $purposeBrief = <<PURPOSEBRIEF;
Calculates molecular weights MinMax and IsoelectricPoint of amino acid sequences.
PURPOSEBRIEF

my $purpose = <<PLUGIN_PURPOSE;
Calculates molecular weights  MinMax and IsoelectricPoint of amino acid sequences.
PLUGIN_PURPOSE

my $tablesAffected =
  [
   ['ApiDB.AASequenceAttribute' =>
    'min_molecular_weight,max_molecular_weight,isoelectric_point fields are updated if the entry exists, otherwise a new entry for the sequence is added with those fields filled in'
   ],
  ];

my $tablesDependedOn = [];

my $howToRestart = <<PLUGIN_RESTART;
PLUGIN_RESTART

my $failureCases = <<PLUGIN_FAILURE_CASES;
PLUGIN_FAILURE_CASES

my $notes = <<PLUGIN_NOTES;
PLUGIN_NOTES

my $documentation = { purposeBrief => $purposeBrief,
		      purpose => $purpose,
		      tablesAffected => $tablesAffected,
		      tablesDependedOn => $tablesDependedOn,
		      howToRestart => $howToRestart,
		      failureCases => $failureCases,
		      notes => $notes,
		    };

sub new {

  my $class = shift;
  $class = ref $class || $class;
  my $self = {};

  bless $self, $class;

  $self->initialize({ requiredDbVersion => 3.5,
		      cvsRevision =>  '',
		      name => ref($self),
		      argsDeclaration   => $argsDeclaration,
		      documentation     => $documentation
		    });
  return $self;
}


sub run {

  my ($self) = @_;

  my $extDbRlsName = $self->getArg("extDbRlsName");
  my $extDbRlsVer = $self->getArg("extDbRlsVer");

  my $extDbRlsId = $self->getExtDbRlsId($extDbRlsName, $extDbRlsVer);

  unless ($extDbRlsId) {
    die "No such External Database Release / Version:\n $extDbRlsName / $extDbRlsVer\n";
  }

  my $dbh = $self->getQueryHandle();

  my $sth = $dbh->prepare(<<EOSQL);

  SELECT aa_sequence_id, sequence
  FROM   @{[$self->getArg('seqTable')]}
  WHERE  external_database_release_id = ?

EOSQL

  $sth->execute($extDbRlsId);

  my $count = 0;

  my $pIcalc = Bio::Tools::pICalculator->new();

  while (my ($aaSeqId, $seq) = $sth->fetchrow_array()) {

    # J is valid IUPAC for leucine/isoleucine ambiguity but apparently
    # Bio::Tools::SeqStats didn't get the memo - J is not allowed.
    $seq =~ s/J/L/g;
    
    my $seq = Bio::Seq->new(-id => $aaSeqId,
				   -seq => $seq,
				   -alphabet => "protein",
				  );
    my ($minWt, $maxWt) =
      @{Bio::Tools::SeqStats->get_mol_wt($seq)};

    $pIcalc->seq($seq);

    my $isoelectricPoint = $pIcalc->iep();

    my $newSeqAttr =
      GUS::Model::ApiDB::AaSequenceAttribute->new({aa_sequence_id => $aaSeqId});

    $newSeqAttr->retrieveFromDB();

    $newSeqAttr->setMinMolecularWeight($minWt);

    $newSeqAttr->setMaxMolecularWeight($maxWt);

    $newSeqAttr->setIsoelectricPoint($isoelectricPoint);

    $newSeqAttr->submit();

    $count++;

    $self->undefPointerCache();

    if($count % 100 == 0) {
      $self->log("Inserted $count sequences.");
      $self->undefPointerCache();
    }

  }

  $self->log("Done inserted $count sequences");
}


sub undoTables {
  my ($self) = @_;

  return ('ApiDB.AASequenceAttribute',
	 );
}

1;
