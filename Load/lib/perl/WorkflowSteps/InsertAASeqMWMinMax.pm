package ApiCommonData::Load::WorkflowSteps::InsertAASeqMWMinMax;

@ISA = (GUS::Workflow::WorkflowStepInvoker);

use strict;
use GUS::Workflow::WorkflowStepInvoker;


sub run {
  my ($self, $test) = @_;

  my $extDbRlsSpec = $self->getParamValue('genomeExtDbRlsSpec');

  my ($extDbName, $extDbRlsVer);

  if ($extDbRlsSpec =~ /(.+)\|(.+)/) {

      $extDbName = $1;

      $extDbRlsVer= $2

    } else {

      die "Database specifier '$extDbRlsSpec' is not in 'name|version' format";
  }

  my $table = $self->getParamValue('table');

  my $args = "--extDbRlsName '$extDbName' --extDbRlsVer '$extDbRlsVer' --seqTable $table";

  $self->runPlugin("GUS::Supported::Plugin::CalculateAASeqMolWtMinMax",$args);

}

sub restart {
}

sub undo {

}

sub getConfigDeclaration {
  my @properties = 
    (
    );
  return @properties;
}

sub getConfigDeclaration {
  my @properties = 
    (
     ['genomeExtDbRlsSpec'],
     ['table'],
    );
  return @properties;
}

sub getDocumentation {
}
