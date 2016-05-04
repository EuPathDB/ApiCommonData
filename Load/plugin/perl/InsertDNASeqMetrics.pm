package ApiCommonData::Load::Plugin::InsertDNASeqMetrics;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;
use CBIL::Util::Disp;
use CBIL::Util::Utils;
use GUS::PluginMgr::Plugin;
use GUS::Supported::Util;

use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;
use GUS::Model::Study::Characteristic;
use GUS::Model::Study::Protocol;
#use GUS::Model::Study::ProtocolParam;
use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::ProtocolApp;
#use GUS::Model::Study::ProtocolAppParam;
use GUS::Model::Study::Input;
use GUS::Model::Study::Output;
use GUS::Model::SRes::OntologyTerm;

use ApiCommonData::Load::DnaSeqMetrics;

use Data::Dumper;

my $argsDeclaration = [
    
    fileArg({name   => 'analysisDir',
        descr    => 'Directory containing bam file',
        reqd    => 1,
        mustExist   => 1,
        format  =>  'Path to dir',
        constraintFunc  => undef,
        isList  => 0,
        }),

    stringArg({name => 'studyName',
          descr => 'Name of the Study;  Will be added if it does not already exist',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),

    stringArg({name => 'assayName',
          descr => 'Name for the DNAseq assay',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),

    stringArg({name => 'sampleExtDbSpec',
          descr => 'External database release for sample',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),

    stringArg({name => 'seqVariationNodeName',
          descr => 'Sequence variation node name',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),

    stringArg({name => 'protocolName',
          descr => 'Protocol name',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),
];
#TODO fill these out
my $purpose = <<PURPOSE;
Insert quality metrics (average coverage and percentage mapped reads) from DNAseq datasets
PURPOSE

my $purposeBrief = <<PURPOSE_BRIEF;
Insert quality metrics from DNAseq datasets
PURPOSE_BRIEF

my $notes = <<NOTES;
NOTES

my $tablesAffected = <<TABLES_AFFECTED;
Study.StudyLink
Study.Characteristic
Study.Protocol
Study.ProtocolAppNode
Study.ProtocolApp
Study.Input
Study.Output
Sres.OntologyTerm
TABLES_AFFECTED

my $tablesDependedOn = <<TABLES_DEPENDED_ON;
Study.Study
TABLES_DEPENDED_ON

my $howToRestart = <<RESTART;
This plugin cannot be restarted
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

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({ requiredDbVersion => 4.0,
		      cvsRevision       => '$Revision$',
		      name              => ref($self),
		      argsDeclaration   => $argsDeclaration,
		      documentation     => $documentation});

  return $self;
}

sub run {
    my ($self) = @_;

    my $analysisDir = $self->getArg('analysisDir');
    my $bamFile = "$analysisDir/result.bam";
    my $coverage = sprintf (<%.2f>, ApiCommonData::Load::DnaSeqMetrics::getCoverage($analysisDir, $bamFile));
    my $mappedReadPercentage = sprintf (<%.4f>, ApiCommonData::Load::DnaSeqMetrics::getMappedReads($bamFile));
 
    my $studyName = $self->getArg('studyName');
    my $gusStudy = GUS::Model::Study::Study->new({name => $studyName});
    unless($gusStudy->retrieveFromDB()) {
        $self->userError("Study $studyName does not exist");
    }


    my $seqVariationNodeName = $self->getArg('seqVariationNodeName');
    my $sampleExtDbSpec = $self->getArg('sampleExtDbSpec');
    my $sampleExtDbRlsId = $self->getExtDbRlsId($sampleExtDbSpec);
    my $variationProtocolAppNode = GUS::Model::Study::ProtocolAppNode->new({name => $seqVariationNodeName,
                                                                   external_database_release_id => $sampleExtDbRlsId});
    unless($variationProtocolAppNode->retrieveFromDB()) {
        $self->userError("Protocol app node with name $seqVariationNodeName does not exist");
    }

    my $variationProtocolName = $self->getArg('protocolName');
    my $gusVariationProtocol = GUS::Model::Study::Protocol->new({name => $variationProtocolName});
    $gusVariationProtocol->retrieveFromDB();


    my $assayName = $self->getArg('assayName');
    my $assayProtocolAppNode = GUS::Model::Study::ProtocolAppNode->new({name => $assayName,
                                                                        external_database_release_id => $sampleExtDbRlsId});
   
    my $studyLink = GUS::Model::Study::StudyLink->new();
    $studyLink->setParent($gusStudy);
    $studyLink->setParent($assayProtocolAppNode);
    $study->addToSubmitList($studyLink);

    # for now using random hard coded source_id for this - there must be a better way?!
    my $coverageOntologyTerm = GUS::Model::SRes::OntologyTerm->new({name => 'average mapping coverage',
                                                                    source_id => 'EuPathUserDefined_00501'});
    unless($coverageOntologyTerm->retrieveFromDB()) {
        $coverageOntologyTerm->submit();
        $self->undefPointerCache();
    }
    my $coverageOntologyTermId = $coverageOntologyTerm->getId();

    my $coverageCharacteristic = GUS::Model::Study::Characteristic->new({value => $coverage});
    $coverageCharacteristic->setQualifierId($coverageOntologyTermId);
    $coverageCharacteristic->setParent($assayProtocolAppNode);


    my $mappedReadOntologyTerm = GUS::Model::SRes::OntologyTerm->new({name => 'proportion mapped reads',
                                                                      source_id => 'EuPathUserDefined_00502'});
    unless($mappedReadOntologyTerm->retrieveFromDB()) {
        $mappedReadOntologyTerm->submit();
        $self->undefPointerCache();
    }
    my $mappedReadOntologyTermId = $mappedReadOntologyTerm->getId();

    my $mappedReadCharacteristic = GUS::Model::Study::Characteristic->new({value => $mappedReadPercentage});
    $mappedReadCharacteristic->setQualifierId($mappedReadOntologyTermId);
    $mappedReadCharacteristic->setParent($assayProtocolAppNode);


    my $studyProtocolApp = GUS::Model::Study::ProtocolApp->new();
    $studyProtocolApp->setParent($gusVariationProtocol);


    my $studyInput = GUS::Model::Study::Input->new();
    $studyInput->setParent($studyProtocolApp);
    $studyInput->setParent($assayProtocolAppNode);


    my $studyOutput = GUS::Model::Study::Output->new();
    $studyOutput->setParent($studyProtocolApp);
    $studyOutput->setParent($variationProtocolAppNode);

    #TODO
    #submit - figure out how this would work.  probably assay node.
    $gusStudy->addToSubmitList($studyProtocolApp);
    $gusStudy->submit();
    
}


sub undoTables {
  my ($self) = @_;

  return ( 
    'Study.Input',
    'Study.Output',
    'Study.StudyLink',
    'Study.ProtocolAppNode',
    'Study.ProtocolApp',
    'Study.Characteristic',
    'Study.Protocol',
     );
}


1;
