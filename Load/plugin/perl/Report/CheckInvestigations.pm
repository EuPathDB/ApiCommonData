package ApiCommonData::Load::Plugin::Report::CheckInvestigations;

@ISA = qw(ApiCommonData::Load::Plugin::InsertInvestigations);
use ApiCommonData::Load::Plugin::InsertInvestigations;
use strict;

# I don't load anything.  I am a reporter
sub loadStudy {}

1;
