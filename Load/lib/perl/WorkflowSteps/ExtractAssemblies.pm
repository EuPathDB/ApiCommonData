package ApiCommonData::Load::WorkflowSteps::ExtractAssemblies;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);

use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;

sub run {
  my ($self, $test) = @_;

  my $ncbiTaxonId = $self->getParamValue('ncbiTaxonId');
  my $outputFile = $self->getParamValue('outputFile');

  my $taxonId = $self->getTaxonId($test,$ncbiTaxonId);

  my $sql = "select na_sequence_id,description,'('||number_of_contained_sequences||' sequences)','length='||length,sequence from dots.Assembly where taxon_id = $taxonId";

  my $localDataDir = $self->getLocalDataDir();

  my $cmd = "gusExtractSequences --outputFile $localDataDir/$outputFile --verbose --idSQL \"$sql\"";

  if ($test){
      self->runCmd(0, "echo test > $localDataDir/$outputFile");
  }
  self->runCmd($test, $cmd);

}

sub getParamsDeclaration {
  return ('ncbiTaxonId',
	  'outputFile',
	 );
}

sub getConfigDeclaration {
  return (
	  # [name, default, description]
	 );
}

sub getDocumentation {
}

sub restart {
}

sub undo {

}

