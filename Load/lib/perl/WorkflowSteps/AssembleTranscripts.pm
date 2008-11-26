package ApiCommonData::Load::WorkflowSteps::AssembleTranscripts;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);

use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;


## to do
## API $self->runCmdInBackground 

sub run {
  my ($self, $test) = @_;

  my $inputFile = $self->getParamValue('inputFile');
  my $outputDir = $self->getParamValue('outputDir');
  my $ncbiTaxonId = $self->getParamValue('ncbiTaxonId');
  my $reassemble = $self->getParamValue('reassemble') eq "yes" ? "--reassemble" :"";
  my $cap4Dir = $self->getConfig('cap4Dir');

  my $taxonId = $self->getTaxonIdFromNcbiTaxId($test,$ncbiTaxonId);
  my $workingDir = $self->runCmd(0,"pwd");

  &splitClusterFile($self,$test,$inputFile);

  &runAssemblePlugin($self, $test,"big",$inputFile,$outputDir, $reassemble, $taxonId, $cap4Dir); 

  $self->runCmd(0,"sleep 10");

  &runAssemblePlugin($self,$test,"small",$inputFile,$outputDir, $reassemble, $taxonId, $cap4Dir); 

  $self->runCmd($test,"chdir $workingDir") || die "Can't chdir to $workingDir";

}


sub splitClusterFile{

  my ($self,$test,$inputFile) = @_;

  my $cmd = "splitClusterFile $inputFile";

  if ($test){
      $self->runCmd(0,"echo hello > $inputFile.small");
      $self->runCmd(0,"echo hello > $inputFile.big");
  }else{
      $self->runCmd($test,$cmd);
  }

}

sub runAssemblePlugin{

  my ($self,$test,$suffix, $inputFile,$outputDir, $reassemble, $taxonId, $cap4Dir) = @_;

  my $args = "--clusterfile $inputFile.$suffix $reassemble --taxon_id $taxonId --cap4Dir $cap4Dir";
  
  my $pluginCmd = "ga DoTS::DotsBuild::Plugin::UpdateDotsAssembliesWithCap4 --commit $args --comment '$args'";

  my $cmd = "runUpdateAssembliesPlugin --clusterFile $inputFile.$suffix --pluginCmd \"$pluginCmd\"";

  my $assemDir = "$outputDir/$suffix";

  $self->runCmd($test,"chdir $assemDir") || die "Can't chdir to $assemDir";

  $self->runCmdInBackground($test,$cmd);
}

sub restart {
}

sub undo {

}

sub getConfigDeclaration {
  my @properties = 
    (
     # [name, default, description]
     ['cap4Dir', "", ""],
    );
  return @properties;
}

sub getParamDeclaration {
  my @properties = 
    (
     ['outputDir',
      'inputFile',
      'ncbiTaxonId',
      'reassemble',
     ]
    );
  return @properties;
}

sub getDocumentation {
}
