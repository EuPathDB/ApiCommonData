package ApiCommonData::Load::WorkflowSteps::InsertGusTableWithXml;

@ISA = (GUS::Workflow::WorkflowStepInvoker);

use strict;
use GUS::Workflow::WorkflowStepInvoker;


sub run {
  my ($self, $test) = @_;

  my $xmlFile = $self->getParamValue('xmlFileRelativeToProjectHomeDir');

  my $gusTable = $self->getParamValue('gusTable');

  my $args = "--filename $xmlFile";

  self->runPlugin( "GUS::Supported::Plugin::LoadGusXml", $args);

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

sub getParamDeclaration {
  my @properties = 
    (
     ['xmlFile'],
     ['gusTable'],
    );
  return @properties;
}

sub getDocumentation {
}
