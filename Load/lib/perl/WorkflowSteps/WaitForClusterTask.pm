package ApiCommonData::Load::WorkflowSteps::WaitForClusterTask;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);
use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;

sub run {
  my ($self, $test) = @_;

  # get parameters
  my $taskDir = $self->getParamValue('taskDir');

  # get global properties
#  my $ = $self->getGlobalConfig('');

  # get step properties
#  my $ = $self->getConfig('');

  if ($test) {
  } else {
  }

}

sub getParamsDeclaration {
  return (
          'taskDir',
         );
}

sub getConfigDeclaration {
  return (
         # [name, default, description]
         # ['', '', ''],
         );
}

sub restart {
}

sub undo {

}

sub getDocumentation {
}
