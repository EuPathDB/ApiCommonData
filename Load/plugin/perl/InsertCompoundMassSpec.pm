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
        format         => 'Tab',
        constraintFunc => undef,
        isList         => 0, }),

    fileArg({name           => 'resultsFile',
        descr          => 'Name of file containing the resuls values.',
        reqd           => 1,
        mustExist      => 1,
        format         => 'Tab',
        constraintFunc => undef,
        isList         => 0, }),

    fileArg({name           => 'configFile',
        descr          => 'Name of config file, describes the profiles being loaded - this is generated by the plugin.',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab file with header',
        constraintFunc => undef,
        isList         => 0, }),

    stringArg({name => 'compoundType',
        descr => 'The compund identifier type that has been supplied with the data e.g. KEGG, InChIKey',
        constraintFunc=> undef,
        reqd  => 1,
        isList => 0
       }),

   stringArg({name => 'hasPeakMappingID',
       descr => 'y/n . Has a column that maps the rows in the peaks file to the data file.',
       constraintFunc=> undef,
       reqd  => 1,
       isList => 0
      }),

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

my $count = 0;

sub run {
  my ($self) = @_;

  # Hash of SQL queries for the different compound types e.g. KEGG, InChIKey, HMDB.
  # Cols are renamed - MYKEY: for the lookup. MYID: as the ID that needs to be returned.
  my $compoundTypeSQL = {};

  $compoundTypeSQL->{'KEGG'} = "select da.compound_id as MYID
                                 , da.accession_number as MYKEY
                                 from CHEBI.database_accession da
                                 where da.source = 'KEGG COMPOUND'";

  $compoundTypeSQL->{'InChIKey'} = "select c.id as MYID
                    , c.chebi_accession
                    , s.structure as MYKEY
                    from chebi.structures s
                    , CHEBI.compounds c
                    where s.type = 'InChIKey'
                    and c.id = s.compound_id";

  $compoundTypeSQL->{'HMDB'} = "select da.compound_id as MYID
                                 , da.accession_number as MYKEY
                                 from CHEBI.database_accession da
                                 where da.source = 'HMDB'";


  my $dbh = $self->getQueryHandle();
  my $compoundType = $self->getArg('compoundType');
  my $sqlQuery = $compoundTypeSQL->{$compoundType};
  my $compoundHash = $dbh->selectall_hashref($sqlQuery, 'MYKEY');
  #print STDERR Dumper $compoundHash;

  my $dir = $self->getArg('inputDir');
  my $peakFile = $self->getArg('peaksFile');
  my $peakFile = $dir . "/" . $peakFile;
  print STDERR "$peakFile\n";

  open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
  my $header = <PEAKS>;
  chomp $header;
  my @header = split(/\t/, $header);

  my ($external_database_release_id, $mass, $retention_time, $peak_id,
    $ms_polarity, $compound_id, $compound_peaks_id, $isotopomer,
    $user_compound_name);
  my ($lastMass, $lastRT, $lastPeakId);

  my $extDbSpec = $self->getArg('extDbSpec');
  $external_database_release_id = $self->getExtDbRlsId($extDbSpec);
  #print STDERR "Ross :$external_database_release_id";

  while(<PEAKS>){ # Could add all to a hash to speed up, not that slow to loop over twice though.
    my @peaksArray = split(/\t/, $_);
    $peak_id = $peaksArray[0];
  	$mass = $peaksArray[1];
  	$retention_time = $peaksArray[2];
  	$compound_id = $peaksArray[3];
    chomp $compound_id; # needs due to the new line char.
    #	$ms_polarity = $peaksArray[4];
    #	$isotopomer = $peaksArray[5];

    if (($lastPeakId == $peak_id) && ($lastMass == $mass) && ($lastRT == $retention_time)){
      #Mulplite compounds can map to one mass/rt pair.
      print STDERR "Mass: $mass - RT: $retention_time pair already in CompoundPeaks - skipping.\n"
    }
    else {
      $ms_polarity = "";
      $isotopomer = "test"; # leaving null for now.
      print STDERR  "Mass:", $mass, " RT:", $retention_time, "  Cpd ID:", $compound_id, " MS Pol:", $ms_polarity, "\n"; # - looks fine.
      ####### Load into CompoudPeaks ######
      # NOTE : Check that changing the format (csv->tab) does not change the Mass / RT float values.
        my $compoundPeaksRow = GUS::Model::ApiDB::CompoundPeaks->new({
          external_database_release_id=>$external_database_release_id,
          mass=>$mass,
          retention_time=>$retention_time,
          peak_id=>$peak_id,
          ms_polarity=>$ms_polarity
        });
      $compoundPeaksRow->submit();
    }
      $self->undefPointerCache();

      # If the next item is the same data this is not loaded, only one row is needed
      # to be the primary key to the other tables.
      $lastPeakId = $peaksArray[0];
      $lastMass = $peaksArray[1];
      $lastRT = $peaksArray[2];

  } #End of while(<PEAKS>)
    close(PEAKS);

    my $compoundPeaksSQL =
        "select cp.compound_peaks_id
          , cp.peak_id || '|' || cp.mass || '|' || cp.retention_time as KEY
          from ApiDB.CompoundPeaks cp
          where cp.external_database_release_id = '$external_database_release_id'"; # NOTE the precision of the data in the SQL table for mass and rt.

    my $peaksHash = $dbh->selectall_hashref($compoundPeaksSQL, 'KEY');
    #print STDERR Dumper $peaksHash;

    ###### Load into CompoundPeaksChebi ######
    open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
    my $header = <PEAKS>;
    chomp $header;
    my @header = split(/\t/, $header);

    while(<PEAKS>){
      my ($mass, $retention_time,
          $compound_id, $compound_peaks_id, $isotopomer);

      my @peaksArray = split(/\t/, $_);
      $peak_id = $peaksArray[0];
    	$mass = $peaksArray[1];
    	$retention_time = $peaksArray[2];
    	$compound_id = $peaksArray[3];
      chomp $compound_id; # needs due to the new line char.
      #	$ms_polarity = $peaksArray[4];
      #	$isotopomer = $peaksArray[5];

    my $compundLookup;
    if($compoundType eq 'InChIKey'){
      my $compundLookup = $compundLookup = 'InChIKey=' . $compound_id;
    }
    else{
      $compundLookup = $compound_id;
    }

    $compound_peaks_id = $peaksHash->{$peak_id . '|' .$mass . '|' . $retention_time}->{'COMPOUND_PEAKS_ID'};
    my $compoundIDLoad = $compoundHash->{$compundLookup}->{"MYID"};

    print STDERR "ChEBI ID:", $compoundIDLoad, "  CpdPeaksID:", $compound_peaks_id, "  Iso:", $isotopomer,"  User CPD ID:", $compound_id,  "\n";

    my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
      compound_id=>$compoundIDLoad,
      compound_peaks_id=>$compound_peaks_id,
      isotopomer=>$isotopomer,
      user_compound_name=>$compound_id
      });

    $compoundPeaksChebiRow->submit();
    $self->undefPointerCache();

    } #End of while(<PEAKS>)
    close(PEAKS);
  ###### END - Load into CompoundPeaksChebi ######

  # #print Dumper $testHash;
  # print STDERR "Count of no keys= $count. \n";
  #
   my $resultsFile = $self->getArg('resultsFile');

   my $args = {mainDirectory=>$dir, makePercentiles=>0, inputFile=>$resultsFile, profileSetName=>$self->getArg('studyName') };
  # #TODO Set an input for proper  profileSetName - this goes into Study.Study table.
   my $params;
  #
   my $resultsData = ApiCommonData::Load::MetaboliteProfiles->new($args, $params);
   $resultsData->munge();
   $self->SUPER::run();
  # #TODO  - need to rm insert_study_results_config.txt??

}


1;
