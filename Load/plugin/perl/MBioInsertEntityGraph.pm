package ApiCommonData::Load::Plugin::MBioInsertEntityGraph;
@ISA = qw(GUS::PluginMgr::Plugin ApiCommonData::Load::Plugin::ParameterizedSchema ApiCommonData::Load::Plugin::InsertEntityGraph);

use GUS::PluginMgr::Plugin;
use ApiCommonData::Load::Plugin::ParameterizedSchema;
use ApiCommonData::Load::Plugin::InsertEntityGraph;
use strict;
use warnings;
use ApiCommonData::Load::MBioResultsDir;
use CBIL::ISA::InvestigationSimple;
use File::Basename;
use JSON;
use Carp;

my $argsDeclaration =
  [

   fileArg({name           => 'investigationFile',
            descr          => 'Investigation xml path',
            reqd           => 1,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),

   fileArg({name           => 'sampleDetailsFile',
            descr          => 'sample details file path',
            reqd           => 1,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),

   fileArg({name           => 'ontologyMappingFile',
            descr          => 'ontology mapping, xml or owl',
            reqd           => 1,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),

   fileArg({name           => 'mbioResultsDir',
            descr          => 'path to mbio results folder',
            reqd           => 1,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),

   stringArg({name           => 'mbioResultsFileExtensions',
            descr          => 'string eval for a hash',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),

   stringArg({name           => 'extDbRlsSpec',
            descr          => 'external database release spec',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),

   stringArg({name           => 'schema',
            descr          => 'schema',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),

   booleanArg({name           => 'dieOnFirstError',
            descr          => 'die on error if yes',
            reqd           => 0,
            constraintFunc => undef,
            isList         => 0, }),

   fileArg({name           => 'valueMappingFile',
            descr          => 'For InvestigationSimple Reader',
            reqd           => 0,
        mustExist      => 0,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),


   stringArg({name           => 'ontologyMappingOverrideFile',
            descr          => 'For InvestigationSimple Reader',
            reqd           => 0,
            constraintFunc => undef,
              isList         => 0, }),

    integerArg({  name           => 'userDatasetId',
	       descr          => 'For use with Schema=ApidbUserDatasets; this is the user_dataset_id',
	       reqd           => 0,
	       constraintFunc => undef,
	       isList         => 0 }),
      booleanArg({name => 'useOntologyTermTableForTaxonTerms',
          descr => 'should we use sres.ontologyterm instead of sres.taxonname',
          reqd => 0,
          constraintFunc => undef,
          isList => 0,
         }),


  ];

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({ requiredDbVersion => 4.0,
                      cvsRevision       => '$Revision$',
                      name              => ref($self),
                      argsDeclaration   => $argsDeclaration,
                      documentation     => $ApiCommonData::Load::Plugin::InsertEntityGraph::documentation});
  $self->{_require_tables} = \@ApiCommonData::Load::Plugin::InsertEntityGraph::REQUIRE_TABLES;
  $self->{_undo_tables} = \@ApiCommonData::Load::Plugin::InsertEntityGraph::UNDO_TABLES;
  return $self;
}

# ======================================================================

sub run {
  my ($self) = @_;
  $self->requireModelObjects();
  $self->resetUndoTables();

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  my $investigationFile = $self->getArg('investigationFile');
  my $namesPrefixForOwl = basename $self->getArg('sampleDetailsFile');
  my $ontologyMappingFile = $self->getArg('ontologyMappingFile');
  my $ontologyMappingOverrideFile = $self->getArg('ontologyMappingOverrideFile');
  unless( -e $ontologyMappingOverrideFile ){ $ontologyMappingOverrideFile = undef }
  my $valueMappingFile = $self->getArg('valueMappingFile');
  unless( -e $valueMappingFile ){ $valueMappingFile = undef }
  my $onError = $self->getArg('dieOnFirstError') ? sub {confess @_}: undef;
  my $isReporterMode = undef;
  my $dateObfuscationFile = undef;
  my $schema = $self->getArg('schema');
  my $mbioResultsDir = $self->getArg('mbioResultsDir');
  my $mbioResultsFileExtensions = $self->getArg('mbioResultsFileExtensions');
  if(-f $mbioResultsFileExtensions){
    open(FH, "<$mbioResultsFileExtensions");
    my @lines = <FH>;
    close(FH);
    chomp $_ for @lines;
    $mbioResultsFileExtensions = join(' ', @lines);
  }
  my $fileExtensions = eval $mbioResultsFileExtensions;
  $self->error("string eval of $mbioResultsFileExtensions failed: $@") if $@;
  $self->error("string eval of $mbioResultsFileExtensions failed: should return a hash") unless ref $fileExtensions eq 'HASH';
  my $getAddMoreData = ApiCommonData::Load::MBioResultsDir->new($mbioResultsDir, $fileExtensions)->toGetAddMoreData;
   
  my $doPruneStudies = 1;
  my $investigation = CBIL::ISA::InvestigationSimple->new($investigationFile, $ontologyMappingFile, $ontologyMappingOverrideFile, $valueMappingFile, $onError, $isReporterMode, $dateObfuscationFile, $getAddMoreData, $namesPrefixForOwl, $doPruneStudies);
  $investigation->setRowLimit(999999999); # Wojtek: work around a bug - entities must fit in batches and I don't know how to do that
  ApiCommonData::Load::Plugin::InsertEntityGraph::loadInvestigation($self,$investigation, $extDbRlsId, $schema); 

  $self->logRowsInserted() if($self->getArg('commit'));

}

1;
