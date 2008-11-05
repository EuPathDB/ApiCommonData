package ApiCommonData::Load::WorkflowSteps::RunSignalP;

@ISA = (GUS::Workflow::WorkflowStepInvoker);

use strict;
use GUS::Workflow::WorkflowStepInvoker;


sub run {
  my ($self, $test) = @_;

  my $proteinsFile = $self->getParamValue('proteinsFile');

  my $outputFile = $self->getConfig('outputFile');

  my $options = $self->getConfig('options');

  my $binPath = $self->getConfig('path');

  my $cmd = "runSignalP --binPath $binPath  --options '$options' --seqFile $proteinsFile --outFile $outputFile";

  if ($test){

      $self->runCmd(0,"test>$outputFile");

  }else{

      $self->runCmd($test,$cmd);

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
     ['proteinsFile', "", ""],
     ['outputFile', "", ""],
     ['options', "", ""],
    );
  return @properties;
}

sub getDocumentation {
}
