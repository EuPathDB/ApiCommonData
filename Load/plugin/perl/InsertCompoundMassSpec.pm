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
  # my $sqlQuery = "select c.id
  #                   , c.chebi_accession
  #                   , s.structure
  #                   from chebi.structures s
  #                   , CHEBI.compounds c
  #                   where s.type = 'InChIKey'
  #                   and c.id = s.compound_id";

  my $compoundHash = $dbh->selectall_hashref($sqlQuery, 'MYKEY');
  #print STDERR Dumper $compoundHash;

  # my $testHash = {};
  # $testHash->{"CompoundMissing"} = 0;
  # $testHash->{"AllMissing"} = 0;

  my $dir = $self->getArg('inputDir');
  my $peakFile = $self->getArg('peaksFile');
  #print STDERR "$peakFile :Ross \n";
  my $peakFile = $dir . "/" . $peakFile;
  print STDERR $peakFile;

  open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
  my $header = <PEAKS>;
  chomp $header;
  my @header = split(/\t/, $header);

  my ($external_database_release_id, $mass, $retention_time,
    $ms_polarity, $compound_id, $compound_peaks_id, $isotopomer,
    $user_compound_name);
  my ($lastMass, $lastRT);


  while(<PEAKS>){
    my @peaksArray = split(/\t/, $_);
  	$mass = $peaksArray[0];
  	$retention_time = $peaksArray[1];
  	$compound_id = $peaksArray[2];
    chomp $compound_id; # needs due to the new line char.
    #	$ms_polarity = $peaksArray[4];
    #	$isotopomer = $peaksArray[5];

    if (($lastMass == $mass) && ($lastRT == $retention_time)){
      #Mulplite compounds can map to one mass/rt pair.
      print STDERR "Mass: $mass - RT: $retention_time pair already in CompoundPeaks - skipping.\n"
    }
    else {
      print STDERR  "Mass:", $mass, " RT:", $retention_time, "  Cpd ID:", $compound_id, " MS Pol:", $ms_polarity, "\n"; # - looks fine.

      my $extDbSpec = $self->getArg('extDbSpec');
      $external_database_release_id = $self->getExtDbRlsId($extDbSpec);
      #print STDERR "Ross :$external_database_release_id";
      $ms_polarity = "";
      $isotopomer = "test"; # leaving null for now.

      ####### Load into CompoudPeaks ######
      # NOTE : Check that changing the format (csv->tab) does not change the Mass / RT float values.
        my $compoundPeaksRow = GUS::Model::ApiDB::CompoundPeaks->new({
          external_database_release_id=>$external_database_release_id,
          mass=>$mass,
          retention_time=>$retention_time,
          ms_polarity=>$ms_polarity
        });
        $compoundPeaksRow->submit();

      } # end of else mass/rt test.

        # ###### Load into CompoundPeaksChebi ######
        # my $compundLookup;
        # if($compoundType eq 'InChIKey'){
        #   my $compundLookup = $compundLookup = 'InChIKey=' . $compound_id;
        # }
        # else{
        #   $compundLookup = $compound_id;
        # }
        #
        # my $compoundIDLoad = $compoundHash->{$compundLookup}->{"MYID"};
        # #print STDERR $compoundIDLoad;
        #
        # if(!$compoundIDLoad){
        #   print STDERR "No key: $compundLookup\n";
        #   $count = $count+1;
        # }
        #
        # # Should move this outside and get data as a hash.
        # my @compoundPeaksSQL = $self->sqlAsArray(Sql=>
      	# 	  "SELECT cp.compound_peaks_id
      	# 	   FROM APIDB.CompoundPeaks cp
      	# 	   WHERE cp.mass = '$mass'
      	# 		 and cp.retention_time= '$retention_time'
        #      and cp.external_database_release_id = '$external_database_release_id'"); # NOTE the precision of the data in the SQL table for mass and rt.
        #
        # my $compound_peaks_id = @compoundPeaksSQL[0];
        # # print STDERR "c:", $compoundIDLoad, " cp:", $compound_peaks_id, " iso:", $isotopomer,  "\n";
        #
        # my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
        #   compound_id=>$compoundIDLoad,
        #   compound_peaks_id=>$compound_peaks_id,
        #   isotopomer=>$isotopomer,
        #   user_compound_name=>$compound_id
        #   });
        #
        # #$compoundPeaksChebiRow->submit();
        # ###### END - Load into CompoundPeaksChebi ######


        $self->undefPointerCache();
        $lastMass = $peaksArray[1];
        $lastRT = $peaksArray[2];

  } #End of while(<PEAKS>)

  # #print Dumper $testHash;
  # print STDERR "Count of no keys= $count. \n";
  #
  # my $resultsFile = $self->getArg('resultsFile');
  #
  # my $args = {mainDirectory=>$dir, makePercentiles=>0, inputFile=>$resultsFile, profileSetName=>'RossMetaTest' };
  # #TODO Set an input for proper  profileSetName - this goes into Study.Study table.
  # my $params;
  #
  # my $resultsData = ApiCommonData::Load::MetaboliteProfiles->new($args, $params);
  # $resultsData->munge();
  # $self->SUPER::run();
  # #TODO  - need to rm insert_study_results_config.txt??

}


1;
