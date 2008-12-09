package ApiCommonData::Load::WorkflowSteps::ExtractNaSeqs;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);

use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;

sub run {
  my ($self, $test) = @_;

  my $table = $self->getParamValue('table');
  my $extDbRlsSpec = $self->getParamValue('extDbRlsSpec');
  my $alternateDefline = $self->getParamValue('alternateDefline');
  my $outputFile = $self->getParamValue('outputFile');
  my $separateFastaFiles = $self->getParamValue('separateFastaFiles');
  my $outputDirForSeparateFiles = $self->getParamValue('outputDirForSeparateFiles');

  my $dbRlsId = $self->getExtDbRlsId($test, $extDbRlsSpec);

  my $deflineSelect = $alternateDefline?
    $alternateDefline :
      "source_id, description, 'length='||length";

  my $sql = "SELECT $deflineSelect, sequence
             FROM dots.$table
             WHERE external_database_release_id = $dbRlsId";

  my $localDataDir = $self->getLocalDataDir();

  my $cmd;
  if ($separateFastaFiles eq 'true') {
    $cmd = "gusExtractIndividualSequences --outputDir $localDataDir/$outputDirForSeparateFiles --idSQL \"$sql\" --verbose";

    if ($test) {
      $self->runCmd(0,"mkdir -p $localDataDir/$outputDirForSeparateFiles");
    }

  } else {
    $cmd = "gusExtractSequences --outputFile $localDataDir/$outputFile --idSQL \"$sql\" --verbose";

    if ($test) {
      $self->runCmd(0,"echo test > $localDataDir/$outputFile");
    }
  }
  $self->runCmd($test,$cmd);

}

sub getParamsDeclaration {
  return (
	  'table',
	  'extDbRlsSpec',
	  'alternateDefline',
	  'separateFastaFiles',
	  'outputFile',
	  'outputDirForSeparateFiles',
	 );
}

sub getConfigDeclaration {
  return (
	  # [name, default, description]
	 );
}

sub restart {
}

sub undo {

}

sub getDocumentation {
}
