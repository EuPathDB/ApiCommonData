package ApiCommonData::Load::Plugin::InsertDataSource;
@ISA = qw( GUS::PluginMgr::Plugin);

use strict;

use GUS::PluginMgr::Plugin;
use lib "$ENV{GUS_HOME}/lib/perl";
use use GUS::Model::ApiDB::DataSource;
use Data::Dumper;


my $purposeBrief = <<PURPOSEBRIEF;
Insert Data Sources from a resource.xml file
PURPOSEBRIEF

my $purpose = <<PLUGIN_PURPOSE;
Insert Data Sources from a resource.xml file
PLUGIN_PURPOSE

my $tablesAffected =
	[['ApiDB.DataSource', ''],
];

my $tablesDependedOn = [];


my $howToRestart = <<PLUGIN_RESTART;
There is no restart method.
PLUGIN_RESTART

my $failureCases = <<PLUGIN_FAILURE_CASES;
There are no known failure cases.
PLUGIN_FAILURE_CASES

my $notes = <<PLUGIN_NOTES;
PLUGIN_NOTES

my $documentation = { purpose=>$purpose,
		      purposeBrief=>$purposeBrief,
		      tablesAffected=>$tablesAffected,
		      tablesDependedOn=>$tablesDependedOn,
		      howToRestart=>$howToRestart,
		      failureCases=>$failureCases,
		      notes=>$notes
		    };


my $argsDeclaration = 
  [
   stringArg({name => 'dataSourceName',
	      descr => 'name of the data source.',
	      reqd => 1,
	      constraintFunc => undef,
	      isList => 0,
	     }),
   stringArg({name => 'version',
	      descr => 'the version of the data source.',
	      reqd => 1,
	      constraintFunc => undef,
	      isList => 0,
	     }),
   stringArg({name => 'organismAbbrev',
	      descr => 'the organismAbbrev of the data source.  Omit if global scope',
	      reqd => 0,
	      constraintFunc => undef,
	      isList => 0,
	     }),

   booleanArg({name => 'isSpeciesScope',
	      descr => 'true if the dataset applies to the species.',
	      reqd => 1,
	      constraintFunc => undef,
	      isList => 0,
	     }),

  ];


sub new {
    my ($class) = @_;
    my $self = {};
    bless($self,$class); 


    $self->initialize({requiredDbVersion => 3.6,
		       cvsRevision => '$Revision: 21749 $', # cvs fills this in!
		       name => ref($self),
		       argsDeclaration => $argsDeclaration,
		       documentation => $documentation
		      });

    return $self;
}

sub run {
    my ($self) = @_; 

    
    my $objArgs = {
	name   => $dataSourceName,
	version  => $version,
        organismAbbrev => $organismAbbrev
    };
    $objArgs->{isSpeciesScope} = $isSpeciesScope if $organismAbbrev;

    my $datasource = use GUS::Model::ApiDB::DataSource->new($objArgs);
    $datasource->submit();
    return "Inserted data source $dataSourceName";
}

sub undoTables {
  my ($self) = @_;

  return ('ApiDB.DataSource');
}



1;
