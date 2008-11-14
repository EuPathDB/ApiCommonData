package ApiCommonData::Load::WorkflowSteps::FindNrdbXrefs;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);
use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;

sub run {
  my ($self, $test) = @_;

  # get parameters
  my $proteinsFile = $self->getParamValue('proteinsFile');
  my $nrdbFile = $self->getParamValue('nrdbFile');
  my $proteinsFileRegex = $self->getParamValue('proteinsFileRegex');
  my $nrdbFileRegex = $self->getParamValue('nrdbFileRegex');
  my $outputFile = $self->getParamValue('outputFile');

  my $localDataDir = $self->getLocalDataDir();

  my $cmd = "dbXRefBySeqIdentity --proteinFile '$localDataDir/$proteinsFile' --nrFile '$localDataDir/$nrdbFile' --outputFile '$localDataDir/$outputFile' --sourceIdRegex \"$nrdbFileRegex\" --protDeflnRegex \"$proteinsFileRegex\" ";
  if ($test) {
      self -> runCmd(0, "echo test > $localDataDir/$outputFile");
  } else {
      self -> runCmd($test,$cmd);
  }

}

sub getParamsDeclaration {
  return (
          'proteinsFile',
          'nrdbFile',
          'proteinsFileRegex',
          'nrdbFileRegex',
          'outputFile',
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
