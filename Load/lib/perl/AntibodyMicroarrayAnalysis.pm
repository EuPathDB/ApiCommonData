package ApiCommonData::Load::AntibodyMicroarrayAnalysis;
use base qw(CBIL::TranscriptExpression::DataMunger::NoSampleConfigurationProfiles);

sub getProtocol {
  return "Antibody Microarray";
}

1;

