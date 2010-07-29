package ApiCommonData::Load::Plugin::InsertIsolateVocabMapping;
@ISA = qw(GUS::PluginMgr::Plugin);
 
use strict;

use FileHandle;
use GUS::PluginMgr::Plugin;
use ApiCommonData::Load::IsolateVocabulary::Reader::SqlReader;
use ApiCommonData::Load::IsolateVocabulary::Reader::XmlReader;
use ApiCommonData::Load::IsolateVocabulary::InsertMappedValues;



$| = 1;


my $argsDeclaration =
[

   fileArg({name => 'productXmlFile',
	    descr => 'xml file with corrections to product mappings',
	    reqd => 0,
	    mustExist => 1,
	    format => '',
	    constraintFunc => undef,
	    isList => 0,
	   }),

   fileArg({name => 'geographicXmlFile',
	    descr => 'xml file with corrections to geographic location mappings',
	    reqd => 0,
	    mustExist => 1,
	    format => '',
	    constraintFunc => undef,
	    isList => 0,
	   }),

   fileArg({name => 'sourceXmlFile',
	    descr => 'xml file with corrections to isolation source mappings',
	    reqd => 0,
	    mustExist => 1,
	    format => '',
	    constraintFunc => undef,
	    isList => 0,
	   }),

   fileArg({name => 'hostXmlFile',
	    descr => 'xml file with corrections to specific host mappings',
	    reqd => 0,
	    mustExist => 1,
	    format => '',
	    constraintFunc => undef,
	    isList => 0,
	   }),

 ];


my $purposeBrief = <<PURPOSEBRIEF;
Insert mappings between isolates and controlled vocabularies.
PURPOSEBRIEF

my $purpose = <<PLUGIN_PURPOSE;
Insert mappings between isolates and controlled vocabularies for four fields: host, geographic loc, source, and product.  The first three are mapped by finding matches between those fields in the isolate sequence (provided with the isolates from the original provider) and values in the vocabularly already loaded into the database.  the xml files provide mappings for the case in which the isolate feature fields do not map into the vocabulary, ie, corrected mappings.  in the case of product, all mappings are provided by the xml file, as they are based on blast hits to sequence in the database, and the original provider did not have that information.  
PLUGIN_PURPOSE

my $tablesAffected = [
['ApiDB.IsolateMapping', 'One row is added to this table for each vocab term mapped to an isolate']
];

my $tablesDependedOn = ['ApiDB.IsolateFeature', 'ApiDB.IsolateSource', 'ApiDB.ExternalNaSequence'];

my $howToRestart = <<PLUGIN_RESTART;
This plugin cannot be restarted.
PLUGIN_RESTART

my $failureCases = <<PLUGIN_FAILURE_CASES;
unknown
PLUGIN_FAILURE_CASES

my $notes = <<PLUGIN_NOTES;

PLUGIN_NOTES

my $documentation = {purposeBrief => $purposeBrief,
		     purpose => $purpose,
		     tablesAffected => $tablesAffected,
		     tablesDependedOn => $tablesDependedOn,
		     howToRestart => $howToRestart,
		     failureCases => $failureCases,
		     notes => $notes
		    };


sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->initialize({requiredDbVersion => 3.5,
		       cvsRevision =>  '$Revision: 3413 $',
		       name => ref($self),
		       argsDeclaration   => $argsDeclaration,
		       documentation     => $documentation
		      });

    return $self;
}

sub run {
    my ($self) = @_;

    my $sourceXmlFile = $self->getArg('sourceXmlFile');
    my $productXmlFile = $self->getArg('productXmlFile');
    my $locationXmlFile = $self->getArg('geographicXmlFile');
    my $hostXmlFile = $self->getArg('hostXmlFile');

    my $count;
    $count += $self->insert($sourceXmlFile, 'isolation_source') if $sourceXmlFile;
    $count += $self->insert($productXmlFile, 'product') if $productXmlFile;
    $count += $self->insert($locationXmlFile, 'geographic_location') if $locationXmlFile;
    $count += $self->insert($hostXmlFile, 'specific_host') if $hostXmlFile;
    return "Inserted $count rows into IsolateMapping";
}

sub insert {
    my ($self, $xmlFile, $type) = @_;
    my $xmlReader = ApiCommonData::Load::IsolateVocabulary::Reader::XmlReader->new($xmlFile);
    my $xmlTerms = $xmlReader->extract();

    my $sqlReader = ApiCommonData::Load::IsolateVocabulary::Reader::SqlReader->new($self->getDbHandle(), $type);
    my $sqlTerms = $sqlReader->extract();


    my $inserter = ApiCommonData::Load::IsolateVocabulary::InsertMappedValues->new($self, $self->getDbHandle(), $type, $xmlTerms, $sqlTerms);
    my ($count, $msg) = $inserter->insert();
    $self->log("$type: $msg");
    return $count;
}


sub undoTables {
  my ($self) = @_;

  return ('ApiDB.IsolateMapping',
         );
}

1;
