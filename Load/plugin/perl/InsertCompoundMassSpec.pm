package ApiCommonData::Load::Plugin::InsertCompoundMassSpec;
@ISA = qw(ApiCommonData::Load::Plugin::InsertStudyResults);

#use lib "$ENV{GUS_HOME}/lib/perl";
use ApiCommonData::Load::Plugin::InsertStudyResults;
use ApiCommonData::Load::MetaboliteProfiles;
use GUS::Model::ApiDB::CompoundPeaksChebi;
use GUS::Model::ApiDB::CompoundPeaks;
use GUS::PluginMgr::Plugin;
use Data::Dumper;


use strict;

my $argsDeclaration =
[
    fileArg({name           => 'inputDir',
        descr          => 'Directory in which to find input files',
        reqd           => 1,
        mustExist      => 1,
        format         => '',
        constraintFunc => undef,
        isList         => 0, }),

    stringArg({name => 'extDbSpec',
          descr => 'External database from whence this data came|version',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),

    stringArg({name => 'studyName',
          descr => 'Name of the Study;  Will be added if it does not already exist',
          constraintFunc=> undef,
          reqd  => 1,
          isList => 0
         }),   # Need this?

    fileArg({name           => 'peaksFile',
        descr          => 'Name of file containing the compound peaks.',
        reqd           => 1,
        mustExist      => 1,
        format         => '',
        constraintFunc => undef,
        isList         => 0, }),

    fileArg({name           => 'resultsFile',
        descr          => 'Name of file containing the resuls values.',
        reqd           => 1,
        mustExist      => 1,
        format         => '',
        constraintFunc => undef,
        isList         => 0, }),

    fileArg({name           => 'configFile',
        descr          => 'Name of config File, describes the profiles being loaded',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab file with header',
        constraintFunc => undef,
        isList         => 0, }),
];

my $purpose = <<PURPOSE;
To load metabolomics datasets -  compounds mapping to mass spec data.
PURPOSE

my $purposeBrief = <<PURPOSE_BRIEF;
To load metabolomics datasets -  compounds mapping to mass spec data.
PURPOSE_BRIEF

my $notes = <<NOTES;
NOTES

my $tablesAffected = <<TABLES_AFFECTED;
TABLES_AFFECTED

my $tablesDependedOn = <<TABLES_DEPENDED_ON;
TABLES_DEPENDED_ON

my $howToRestart = <<RESTART;
There are no restart facilities for this plugin
RESTART

my $failureCases = <<FAIL_CASES;
FAIL_CASES

my $documentation = {purpose   => $purpose,
              purposeBrief     => $purposeBrief,
              notes            => $notes,
              tablesAffected   => $tablesAffected,
              tablesDependedOn => $tablesDependedOn,
              howToRestart     => $howToRestart,
              failureCases     => $failureCases };

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({ requiredDbVersion => 4.0,
              cvsRevision       => '$Revision$',
              name              => ref($self),
              argsDeclaration   => $argsDeclaration,
              documentation     => $documentation});

  return $self;
}

sub run {
  my ($self) = @_;

  my $testHash = {};
  $testHash->{"CompoundMissing"} = 0;
  $testHash->{"AllMissing"} = 0;

  my $dir = $self->getArg('inputDir');
  my $peakFile = $self->getArg('peaksFile');
  #print STDERR "$peakFile :Ross \n";
  my $peakFile = $dir . "/" . $peakFile;
  print STDERR $peakFile;

  open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
  my $header = <PEAKS>;
  chomp $header;
  my @header = split(/\t/, $header);

  my ($external_database_release_id, $peak_id, $mass, $retention_time, $ms_polarity, $compound_id, $compound_peaks_id, $isotopomer);
  my ($lastMass, $lastRT);

  my $allPresent = 1;

  while(<PEAKS>){
    if (($lastMass != $mass) && ($lastRT != $retention_time)){
      if ($allPresent == 1){
        $allPresent = 1;
      }
    }

    my @peaksArray = split(/\t/, $_);
  	$peak_id = $peaksArray[0];
  	$mass = $peaksArray[1];
  	$retention_time = $peaksArray[2];
  	$compound_id = $peaksArray[3];
    chomp $compound_id; # needs due to the new line char.
    #	$ms_polarity = $peaksArray[4];
    #	$isotopomer = $peaksArray[5];

    if (($lastMass == $mass) && ($lastRT == $retention_time)){
      #Mulplite compounds can map to one mass/rt pair.
      #print STDERR "Mass: $mass - RT: $retention_time pair already in CompoundPeaks - skipping.\n"
    }
    else {
      #print STDERR $peak_id, " ",  $mass, " ", $retention_time, " ", $compound_id, " ", $ms_polarity, "\n"; # - looks fine.

      my $extDbSpec = $self->getArg('extDbSpec');
      $external_database_release_id = $self->getExtDbRlsId($extDbSpec);
      #print STDERR "Ross :$external_database_release_id";
      $ms_polarity = "";
      $isotopomer = "test"; # leaving null for now.

      # Load into CompoudPeaks #NOTE - may want to take out peak_id #### NOTE ###
      # NOTE : Check that changing the format (csv->tab) does not change the Mass / RT float values.
        my $compoundPeaksRow = GUS::Model::ApiDB::CompoundPeaks->new({
          external_database_release_id=>$external_database_release_id,
          peak_number=>$peak_id, mass=>$mass,
          retention_time=>$retention_time,
          ms_polarity=>$ms_polarity
        });
        #$compoundPeaksRow->submit(); .

      } # end of else mass/rt test.
        # Load into CompoundPeaksChebi
        my $compundLookup = 'InChIKey=' . $compound_id;

        # This look up takes time.
        my @compoundSQL = $self->sqlAsArray(Sql=> "select c.id
                                                  , c.chebi_accession
                                                  , s.structure
                                                  from chebi.structures s
                                                  , CHEBI.compounds c
                                                  where s.type = 'InChIKey'
                                                  and c.id = s.compound_id
                                                  and to_char(s.structure) = '$compundLookup'
                                                  "); # OBSIPTVJSOCDLZ-UHFFFAOYSA-N -  not in tables. Others also.

        my $compoundIDLoad = @compoundSQL[0];

        if (!$compoundIDLoad) {
          $testHash->{"CompoundMissing"} =  $testHash->{"CompoundMissing"} +1;
          $allPresent = 0;
          # if (($lastMass == $mass) && ($lastRT == $retention_time)){
          #   $allPresent = 0;
          # }
          #if(($lastMass != $mass) && ($lastRT != $retention_time)){
            if ($allPresent = 0){
              $testHash->{"AllMissing"} =  $testHash->{"AllMissing"} +1;
              $allPresent = 1;
            }
          #}
        }

        # Loaded some test data into apidb.compoundpeaks on rm23697

        # my @compoundPeaksSQL = $self->sqlAsArray(Sql=>
      	# 	  "SELECT cp.compound_peaks_id
      	# 	   FROM APIDB.CompoundPeaks cp
      	# 	   WHERE cp.mass = '$mass'
      	# 		 and cp.retention_time= '$retention_time'
        #      and cp.external_database_release_id = '$external_database_release_id'"); # NOTE the precision of the data in the SQL table for mass and rt.
        #
        # my $compound_peaks_id = @compoundPeaksSQL[0];
        # print STDERR "c:", $compoundIDLoad, " cp:", $compound_peaks_id, " iso:", $isotopomer,  "\n";
        #
        # my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
        #   compound_id=>$compoundIDLoad,
        #   compound_peaks_id=>$compound_peaks_id,
        #   isotopomer=>$isotopomer
        #   });

        #$compoundPeaksChebiRow->submit();
        $self->undefPointerCache();
        $lastMass = $peaksArray[1];
        $lastRT = $peaksArray[2];

  } #End of while(<PEAKS>)

  print Dumper $testHash;

  # my $resultsFile = $self->getArg('resultsFile');
  #
  # my $args = {mainDirectory=>$dir, makePercentiles=>0, inputFile=>$resultsFile, profileSetName=>'RossMetaTest' };
  # #TODO What should profileSetName be?
  # my $params;
  #
  # my $resultsData = ApiCommonData::Load::MetaboliteProfiles->new($args, $params);
  # $resultsData->munge();
  # $self->SUPER::run();
  # #TODO  - need to rm insert_study_results_config.txt??

}


1;
