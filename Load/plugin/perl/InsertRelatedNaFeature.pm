package PlasmoDBData::Load::Plugin::InsertRelatedNaFeature;

@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use GUS::PluginMgr::Plugin;
use FileHandle;

use ApiCommonData::Load::Util;

use GUS::Model::ApiDB::RelatedNaFeature;
use GUS::Model::ApiDB::ProfileSet;

my $argsDeclaration =
[

   fileArg({name           => 'interactionFile',
	    descr          => 'A pipe (|) delimeted file (no header row) containing interaction data between 2 source_ids',
	    reqd           => 1,
	    mustExist      => 1,
	    format         => 'PF14_0295|PF11_0097|9435.360',
	    constraintFunc => undef,
	    isList         => 0, }),

 stringArg({ descr => 'Name of the External Database',
	     name  => 'extDbName',
	     isList    => 0,
	     reqd  => 1,
	     constraintFunc => undef,
	   }),

 stringArg({ descr => 'Version of the External Database Release',
	     name  => 'extDbVersion',
	     isList    => 0,
	     reqd  => 1,
	     constraintFunc => undef,
	   }),

];

my $purpose = <<PURPOSE;
The purpose of this plugin is to relate an interaction between 2 source_ids.  n
PURPOSE

my $purposeBrief = <<PURPOSE_BRIEF;
The purpose of this plugin is to relate an interaction between 2 source_ids.  
PURPOSE_BRIEF

my $notes = <<NOTES;
NOTES

my $tablesAffected = <<TABLES_AFFECTED;
ApiDB::RelatedNaFeature
TABLES_AFFECTED

my $tablesDependedOn = <<TABLES_DEPENDED_ON;
Dots.NaFeature
TABLES_DEPENDED_ON

my $howToRestart = <<RESTART;
No Restart utilities for this plugin.
RESTART

my $failureCases = <<FAIL_CASES;
FAIL_CASES

my $documentation = { purpose          => $purpose,
		      purposeBrief     => $purposeBrief,
		      notes            => $notes,
		      tablesAffected   => $tablesAffected,
		      tablesDependedOn => $tablesDependedOn,
		      howToRestart     => $howToRestart,
		      failureCases     => $failureCases };

# ----------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({ requiredDbVersion => 3.5,
		      cvsRevision       => '$Revision$',
		      name              => ref($self),
		      argsDeclaration   => $argsDeclaration,
		      documentation     => $documentation});

  return $self;
}

# ======================================================================

sub run {
  my ($self) = @_;

  my $dbReleaseId = $self->getExtDbRlsId($self->getArgs()->{extDbName}, 
					 $self->getArgs()->{extDbVersion});

  open(FILE, $self->getArg('interactionFile')) || die "Could Not open File for reading: $!\n";

  my $line = 1;

  while(<FILE>) {
    chomp;

    my ($so, $st, $val) = split('\|', $_);

    my $naFeatureId = ApiCommonData::Load::Util::getGeneFeatureId($self, $so);
    my $assocNaFeatureId = ApiCommonData::Load::Util::getGeneFeatureId($self, $st);

    $self->log("WARNING", "No naFeatureId for Source_id $so.") if(!$naFeatureId);
    $self->log("WARNING", "No naFeatureId for Source_id $st.") if(!$assocNaFeatureId);

    next if(!$naFeatureId || !$assocNaFeatureId);

    my $interaction = GUS::Model::ApiDB::RelatedNaFeature->
	  new({ na_feature_id  => $naFeatureId,
                associated_na_feature_id => $assocNaFeatureId,
                external_database_release_id => $dbReleaseId,
                value => $val
          });

    my $otherInteraction = GUS::Model::ApiDB::RelatedNaFeature->
	  new({ associated_na_feature_id  => $naFeatureId,
                na_feature_id => $assocNaFeatureId,
                external_database_release_id => $dbReleaseId,
                value => $val
          });

    if($line % 1000 == 0) {
      $self->log("Processed $line Lines from Data File");
    }

    $interaction->submit();
    $otherInteraction->submit();

    $line++;
    $self->undefPointerCache();
  }
  close(FILE);

  return("Inserted $line rows into ApiDB::RelatedNaFeature");
}


1;

