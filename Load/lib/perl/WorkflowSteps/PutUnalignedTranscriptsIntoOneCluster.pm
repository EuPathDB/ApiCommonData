package ApiCommonData::Load::WorkflowSteps::PutUnalignedTranscriptsIntoOneCluster;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);

use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;


## to do
## API $self->getTaxonId($ncbiTaxId) 
## API $self->getTaxonIdList($taxonId,$taxonHierarchy)


sub run {
  my ($self, $test) = @_;

  my $outputFile = $self->getParamValue('outputFile');

  my $inputFile = $self->getParamValue('inputFile');

  my $queryTaxonId = $self->getTaxonId($self->getParamValue('queryNcbiTaxonId'));

  my $subjectTaxonId = $self->getTaxonId($self->getParamValue('subjectNcbiTaxonId'));

  my $taxonIdList = $self->getTaxonIdList($queryTaxonId,$self->getParamValue('useTaxonHierarchy'));
  
  my $repeatMaskErrFile = $self->getParamValue('repeatMaskErrFile');

  my $cmd = "getSourceIds --inputFile $inputFile --outputFile $outputFile --blockFile $repeatMaskErrFile";

  if ($test){
      self->runCmd(0,'echo hello > $outputFile');
  }else{
      self->runCmd($test,$cmd);      
  }
}


sub restart {
}

sub undo {

}

sub getConfigDeclaration {
  my @properties = 
    (
     # [name, default, description]
    );
  return @properties;
}

sub getConfigDeclaration {
  my @properties = 
    (
     ['inputFile'],
     ['outputFile'],
     ['queryNcbiTaxonId'],
     ['subjectNcbiTaxonId'],
     ['useTaxonHierarchy'],
     ['repeatMaskErrFile'],
    );
  return @properties;
}

sub getDocumentation {
}
