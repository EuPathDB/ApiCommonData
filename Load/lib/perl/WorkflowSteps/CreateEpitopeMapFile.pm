package ApiCommonData::Load::WorkflowSteps::CreateEpitopeMapFile;

@ISA = (ApiCommonData::Load::WorkflowSteps::WorkflowStep);

use strict;
use ApiCommonData::Load::WorkflowSteps::WorkflowStep;

sub run {
    my ($self, $test) = @_;

    my $ncbiBlastPath = $self->getConfig('ncbiBlastPath');
    my $inputDirRelativeToDownloadsDir = $self->getParamValue('inputDirRelativeToDownloadsDir');
    my $proteinsFile = $self->getParamValue('proteinsFile');
    my $blastDbDir = $self->getParamValue('blastDbDir');
    my $organismTwoLetterAbbrev = $self->getParamValue('organismTwoLetterAbbrev');
    my $outputDir = $self->getParamValue('outputDir');

    my $localDataDir = $self->getLocalDataDir();

    my $cmd = "createEpitopeMappingFile  --ncbiBlastPath $ncbiBlastPath --inputDir $localDataDir/$inputDirRelativeToDownloadsDir --queryDir $proteinsFile --outputDir $localDataDir/$outputDir --blastDatabase $blastDbDir";
       $cmd .= " --speciesKey $organismTwoLetterAbbrev" if ($organismTwoLetterAbbrev);

    $self->runCmd($test,$cmd);
}



sub getParamsDeclaration {
    return ('inputDirRelativeToDownloadsDir',
            'blastDbDir',
            'organismTwoLetterAbbrev',
            'proteinsFile',
            'outputDir'
           );
}


sub getConfigDeclaration {
    return (
            # [name, default, description]
              ['ncbiBlastPath', "", ""]
           );
}

sub getDocumentation {
}

sub restart {
}

sub undo {
}
