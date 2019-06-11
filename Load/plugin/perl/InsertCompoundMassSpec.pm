package ApiCommonData::Load::Plugin::InsertCompoundMassSpec;
@ISA = qw(ApiCommonData::Load::Plugin::InsertStudyResults);

#use lib "$ENV{GUS_HOME}/lib/perl";
use ApiCommonData::Load::Plugin::InsertStudyResults;
use ApiCommonData::Load::MetaboliteProfiles;
use CBIL::TranscriptExpression::DataMunger::Profiles;
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
         }),

    # fileArg({name           => 'peaksFile',
    #     descr          => 'Name of file containing the compound peaks. Cols = PeakID, Mass, RT, CompoundID',
    #     reqd           => 1,
    #     mustExist      => 0,
    #     format         => 'Tab',
    #     constraintFunc => undef,
    #     isList         => 0,
    #   }),
    #
    # fileArg({name           => 'resultsFile',
    #     descr          => 'Name of file containing the resuls values. Cols = PeakID|Mass|RT (1 concatentated with '|' col), result1 .... resultX',
    #     reqd           => 1,
    #     mustExist      => 0,
    #     format         => 'Tab',
    #     constraintFunc => undef,
    #     isList         => 0,
    # #   }),
    #
    # fileArg({name           => 'mappingFile',
    #     descr          => 'Mapping file of samples -> groups.',
    #     reqd           => 1,
    #     mustExist      => 0,
    #     format         => 'Tab',
    #     constraintFunc => undef,
    # #     isList         => 0,
    # #   }),
    #
    fileArg({name           => 'configFile',
        descr          => 'Name of config file, describes the profiles being loaded - this is generated by the plugin.',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab file with header',
        constraintFunc => undef,
        isList         => 0
      }), # Needs to be here even though always the same as InsertStudyResults uses this value.

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

  ##NOTE - old query
  # $compoundTypeSQL->{'KEGG'} = "select da.compound_id as MYID
  #                                , da.accession_number as MYKEY
  #                                from CHEBI.database_accession da
  #                                where da.source = 'KEGG COMPOUND'";

  my $compoundInChIKeySQL = "select c.id as MYID
                    , c.chebi_accession
                    , s.structure as MYKEY
                    from chebi.structures s
                    , CHEBI.compounds c
                    where s.type = 'InChIKey'
                    and c.id = s.compound_id";

  my $compoundOtherSQL = "select da.compound_id as MYID
                                   , da.accession_number as MYKEY
                                   from CHEBI.database_accession da
                                   where da.source in (
                                   'KEGG DRUG'
                                   ,'ChEBI'
                                   ,'CiteXplore'
                                   ,'LIPID MAPS'
                                   ,'PDB'
                                   ,'SUBMITTER'
                                   ,'SMID'
                                   ,'KEGG COMPOUND'
                                   ,'Beilstein'
                                   ,'COMe'
                                   ,'RESID'
                                   ,'Patent'
                                   ,'KEGG GLYCAN'
                                   ,'KNApSAcK'
                                   ,'Chemical Ontology'
                                   ,'WebElements'
                                   ,'ChEMBL'
                                   ,'HMDB'
                                   ,'Gmelin'
                                   ,'YMDB'
                                   ,'Alan Wood' ||CHR(39)||'s Pesticides'
                                   ,'ChemIDplus'
                                   ,'NIST Chemistry WebBook'
                                   ,'Reaxys'
                                   ,'UM-BBD'
                                   ,'Wikipedia'
                                   ,'ECMDB'
                                   ,'PubChem'
                                   ,'PDBeChem'
                                   ,'MolBase'
                                   ,'DrugBank'
                                   ,'MetaCyc'
                                   ,'Chemspider'
                                   )";



  
  
  my $dbh = $self->getQueryHandle();

  ### InChIKey hash ###
  my $compoundInChIKeyHash = {};
  $compoundInChIKeyHash = $dbh->selectall_hashref($compoundInChIKeySQL, 'MYKEY');
  #print STDERR Dumper $compoundInChIKeyHash;

  ### Other Compound Hash ###
  my $otherCompoundHash = {};
  $otherCompoundHash = $dbh->selectall_hashref($compoundOtherSQL, 'MYKEY');
  #print STDERR Dumper $otherCompoundHash;

  my $dir = $self->getArg('inputDir');
  my $peakFile = 'peaks.tab';
  my $peakFile = $dir . "/" . $peakFile;
  print STDERR "$peakFile\n";

  ###### Load into CompoudPeaks ######
  open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
  my $header = <PEAKS>;
  chomp $header;
  my @header = split(/\t/, $header);

  my ($external_database_release_id, $mass, $retention_time, $peak_id,
    $ms_polarity, $compound_id, $InChIKey, $compound_peaks_id, $isotopomer,
    $user_compound_name, $is_preferred_compound);

  my $extDbSpec = $self->getArg('extDbSpec');
  $external_database_release_id = $self->getExtDbRlsId($extDbSpec);
  #print STDERR "Ross :$external_database_release_id";

  my $preferredCompounds = {};
  my $compoundHash = {};
  my ($compoundLookup, $chebiId);

  # Load into two hashes.
  # compoundHash stores the compounds with the associated data.
  # preferredCompounds stores the preferred status and the ChEBI IDs from our DB. 
  while(<PEAKS>){
    my @peaksArray = split(/\t/, $_);    
    my ($peak_id, $mass, $retention_time, $isotopomer, $ms_polarity, $compound_id, $InChIKey, $is_preferred_compound) = split(/\t/, $_);
    chomp $InChIKey;
    chomp $is_preferred_compound;

    my $chebiId; 	
    if (defined($InChIKey)) {$chebiId = $compoundInChIKeyHash->{'InChIKey='.$InChIKey}->{'MYID'};}
    else {$chebiId  = $otherCompoundHash->{$compoundLookup}->{'MYID'};}
	
    my $peakCompId = $chebiId . '|' . $peak_id; 

    $compoundHash->{$peak_id}->{$chebiId} = $InChIKey; #TODO will this work with more than one chebi ID in our DB. 
    $compoundHash->{$peak_id}->{'peak_data'} = [$mass, $retention_time, $isotopomer, $ms_polarity];

    if ( (defined($preferredCompounds->{$is_preferred_compound}->{$peakCompId})) 
    && !($peak_id ~~ $preferredCompounds->{$is_preferred_compound}->{$peakCompId}) )
    {
	    push $preferredCompounds->{$is_preferred_compound}->{$peakCompId}, $peak_id;
	  }
	  else{
	    $preferredCompounds->{$is_preferred_compound}->{$peakCompId} = [];
	    push $preferredCompounds->{$is_preferred_compound}->{$peakCompId}, $peak_id;
    }
  } #End of while(<PEAKS>)
  close(PEAKS);

#  print STDERR Dumper $compoundHash;  
#  print STDERR Dumper $preferredCompounds->{1};  ~

  # Loop over the entries in the compoundHash and load. 
  foreach my $peak(keys $compoundHash){
	  print STDERR "Peak: \n";
	  print STDERR Dumper $peak; 
  	my ($mass, $retention_time, $isotopomer, $ms_polarity, $InChIKey);

    $mass = $compoundHash->{$peak}->{'peak_data'}[0];
    $retention_time = $compoundHash->{$peak}->{'peak_data'}[1];
    $isotopomer = $compoundHash->{$peak}->{'peak_data'}[2];
    $ms_polarity = $compoundHash->{$peak}->{'peak_data'}[3]; 
    #print STDERR "$mass, $retention_time"; 

    my $compoundPeaksRow = GUS::Model::ApiDB::CompoundPeaks->new({
        external_database_release_id=>$external_database_release_id,
        mass=>$mass,
        retention_time=>$retention_time,
        peak_id=>$peak,
        ms_polarity=>$ms_polarity
        });
    # For a peak want to test if there is a preferred compound	
    foreach my $chebi(keys $compoundHash->{$peak}){
      my $peakCompId = $chebi . '|'. $peak;   

      $InChIKey = $compoundHash->{$peak}->{$chebi};

      if ( (defined($preferredCompounds->{1}->{$peakCompId}) 
        && (scalar(@{$preferredCompounds->{1}->{$peakCompId}}) == 1)) 
        && defined($compoundHash->{$peak}->{$peakCompId}->{1}) ){
      #print STDERR "LOAD: Pref peak $peak has cpd ($chebi)\n";
      
      my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
            compound_id=>$chebi,
              isotopomer=>$isotopomer,
              user_compound_name=>$InChIKey,
              is_preferred_compound=>'1'
          });
      $compoundPeaksChebiRow->setParent($compoundPeaksRow);
      $compoundPeaksRow->addToSubmitList($compoundPeaksChebiRow)
      }

            #TODO -  take out parent relationship to the peak - cpd and test the loading.
            #TODO - add in set parent to the chebi id -> chebi table. 
            #TODO - reverse the submit order of the objects - test to see if that is the issue. 

              # Redundant due to 1 pref peak having >1 ChEBI Id in our DB. 
          #	  elsif( (defined($preferredCompounds->{1}->{$peakCompId})) 
          #      && (scalar(@{$preferredCompounds->{1}->{$peakCompId}}) > 1) 
          #      && defined($compoundHash->{$peak}->{$peakCompId}->{1}) 
          #	  #&& !(defined($preferredCompounds->{1}->{''}))
          #	  ) 
          #	  {
          #        print STDERR "Peak $peak has >1 preferred compounds - exiting. \n";
          #        print STDERR Dumper $preferredCompounds->{1}->{$chebi}; 
          #	  }

        # If there is no pref compound load all the other compounds. 
        elsif( defined($preferredCompounds->{0}->{$peakCompId}) ){
      #	print STDERR "OTHER LOAD: $peak, $chebi \n"; 

        $mass = $compoundHash->{$peak}->{'peak_data'}[0];
        $retention_time = $compoundHash->{$peak}->{'peak_data'}[1];
        $isotopomer = $compoundHash->{$peak}->{'peak_data'}[2];
        $ms_polarity = $compoundHash->{$peak}->{'peak_data'}[3]; 
        $InChIKey = $compoundHash->{$peak}->{$chebi}; 
        #print STDERR "$mass, $retention_time"; 
      
      my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
              compound_id=>$chebi,
              isotopomer=>$isotopomer,
              user_compound_name=>$InChIKey,
              is_preferred_compound=>'0'
          });
        $compoundPeaksChebiRow->setParent($compoundPeaksRow);
        $compoundPeaksRow->addToSubmitList($compoundPeaksChebiRow)
        }
      
    } # End foreach $chebi
    $compoundPeaksRow->submit();
    $self->undefPointerCache()
  } # End foreach $peak
} # close sub new


	#make new peak GUS object 
    # for each chebi id:
      #if preferred:
        #make compound object
        #look up peak from preferred hash
        #check if already loaded
        #if not isotopomer, count how many are in array.  If not 1, decide how to handle this.
        #if loaded go to next compound without loading this one
        # if not, set parent compound->setParent(peak)
        #add compounds to peak object submit list
    #submit
    #undef pointer cache

    
    ####### END - Load into CompoudPeaks ######
#     if (($lastPeakId == $peak_id) && ($lastMass == $mass) && ($lastRT == $retention_time)){
# 			continue;
#       #print STDERR "Mass: $mass - RT: $retention_time pair already in CompoundPeaks - skipping.\n"
#     }
#     else {
# 			#print STDERR  "Mass:", $mass, " RT:", $retention_time, "  Cpd ID:", $compound_id, " MS Pol:", $ms_polarity, "\n";

#       # NOTE : Check that changing the format (csv->tab) does not change the Mass / RT float value.
#         my $compoundPeaksRow = GUS::Model::ApiDB::CompoundPeaks->new({
#           external_database_release_id=>$external_database_release_id,
#           mass=>$mass,
#           retention_time=>$retention_time,
#           peak_id=>$peak_id,
#           ms_polarity=>$ms_polarity
#         });
#       $compoundPeaksRow->submit();
#     }
#       $self->undefPointerCache();

#       $lastPeakId = $peaksArray[0];
#       $lastMass = $peaksArray[1];
#       $lastRT = $peaksArray[2];

#       if ($is_preferred_compound == 1){
#         print STDERR "Pref?", $is_preferred_compound;
#         $preferredCompounds->{$mass . "|" . $retention_time} = [$compound_id] ;
#       }




#     print STDERR Dumper $preferredCompounds;

#     # Hash of all the loaded compound peaks from above.
#     my $compoundPeaksSQL =
#         "select cp.compound_peaks_id
#           , cp.peak_id || '|' || cp.mass || '|' || cp.retention_time as KEY
#           from ApiDB.CompoundPeaks cp
#           where cp.external_database_release_id = '$external_database_release_id'"; # NOTE the precision of the data in the SQL table for mass and rt.

#     my $peaksHash = $dbh->selectall_hashref($compoundPeaksSQL, 'KEY');
#     #print STDERR Dumper $peaksHash;

#     ###### Load into CompoundPeaksChebi ######
#     open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
#     my $header = <PEAKS>;
#     chomp $header;
#     my @header = split(/\t/, $header);

# 	my $isPreferredCheck = @header[7]; 
#   my $preferredLoaded = {};
# 	my $compoundPeaksTest = {};
    
# 	while(<PEAKS>){
#     my ($mass, $retention_time,
#         $compound_id, $compound_peaks_id, $isotopomer, $is_preferred_compound);


#     my @peaksArray = split(/\t/, $_);
#     $peak_id = $peaksArray[0];
#     $mass = $peaksArray[1];
#     $retention_time = $peaksArray[2];
#     $isotopomer = $peaksArray[3];
#     $ms_polarity = $peaksArray[4];
#     $compound_id = $peaksArray[5];
#     chomp $compound_id;
#     $InChIKey = $peaksArray[6];
#     chomp $InChIKey;

#     if(defined($isPreferredCheck)){
#       $is_preferred_compound = $peaksArray[7];
#       print STDERR "#####  $isPreferredCheck"; 
#       chomp $is_preferred_compound;
#     }
#     else{$is_preferred_compound = 1;}   
#     #  print STDERR Dumper $preferredCompounds->{$mass . "|" . $retention_time};
#     #  print STDERR scalar(@{$preferredCompounds->{$mass . "|" . $retention_time}}), " ", $preferredCompounds->{$mass . "|" . $retention_time}[0], " ", $compound_id;

#     # Testing for a preferred compound. Will load only that for the peak.
#     # If more than one preferred in a peak (should not have this) it is skipped.
#     if (exists $preferredCompounds->{$mass . "|" . $retention_time} && scalar(@{$preferredCompounds->{$mass . "|" . $retention_time}}) > 1)
#     {print STDERR "More than 1 preferred compound in hash - skipping.\n"}
#     elsif(exists $preferredCompounds->{$mass . "|" . $retention_time} && $preferredCompounds->{$mass . "|" . $retention_time}[0] ne $compound_id)
#     {print STDERR "Not a preferred compound - skipping for this peak.\n"}
#     else{
#       my $compoundLookup = $compound_id;
#       my $InChILookup = 'InChIKey=' . $InChIKey;
#       my $compoundIDLoad;
#       # The hash below is testing for unique ChEBI IDs with peaks. e.g. ID ChEBI: X may be mapped to by >1 IDs from the provider data. In this
#       # instance the ChEBI ID is only loaded into the DB once at the first match - this stops the results being incorrect in the Model (queries/compoundQueries.xml ) where the ChEBI IDs are used to group the data (summing the abundance).
#       if(defined($compoundPeaksTest->{$peak_id})){;}
#       else{$compoundPeaksTest->{$peak_id} = {};}

#       #NOTE - for now only the $compound_id is being loaded into the table. The InChIKey, if there is one, is not.
#       # They are never seen so adding the col to the table to have both is not useful for the moment.
#       # To get a ChEBI ID the InChIKey is tested first, then the other compound ID.
#       # print STDERR "Values in hashes for $peak_id:\n";
#       # print STDERR Dumper $compoundInChIKeyHash->{$InChILookup};
#       # print STDERR Dumper $otherCompoundHash->{$compoundLookup};

#       if(defined($compoundInChIKeyHash->{'InChIKey=' . $InChIKey})){
#         # print STDERR "FOUND ---- InChI hash for $peak_id $InChIKey \n";
#         $compoundIDLoad = $compoundInChIKeyHash->{$InChILookup}->{'MYID'};
#         #	print STDERR "Inchi hash value :", Dumper $compoundInChIKeyHash->{'InChIKey=' . $InChIKey};
#         # print STDERR "1: $compoundIDLoad \n";
#       }
#       elsif(defined($otherCompoundHash->{$compoundLookup})){
#         $compoundIDLoad = $otherCompoundHash->{$compoundLookup}->{'MYID'};
#         #print STDERR "FOUND #### other hash for $peak_id $compoundLookup \n";
#         #print STDERR "Other hash value :", Dumper $otherCompoundHash->{$compoundLookup};
#         #print STDERR "2: $compoundIDLoad\n";
#       }
#       #else{;}

#       # If a compound ID has already been loaded as it is preferred, this will skip loading the compound ID for other peaks. 
#       # If the compound is an isotopomer it will be preferred (likely with these experiments) and in many peaks. This will load the range of isotopomers.
#       # This presumes that the isotopomers are only in the mass/rt range of the isotopomer and not ambiguosly elsewhere in another peak/s.
#       if (defined($preferredLoaded->{$compoundIDLoad})){print STDERR "Here 1\n";}
#       else{	  
#         if (defined($compoundPeaksTest->{$peak_id}->{$compoundIDLoad})){
#           print STDERR "$compoundIDLoad in hash\n";
#         }
#         else{
#           if ($compoundIDLoad eq ""){;}
#           # elsif(defined($isotopomer)){;} # Not adding isotopomer cpd ID to peak - peak test. Want that ID for all peaks. 
#           else{
#             $compoundPeaksTest->{$peak_id}->{$compoundIDLoad} = "Dummy value";
#             print STDERR "Here 2\n";
#           }
#           my $compoundPeak = GUS::Model::ApiDB::CompoundPeaks->new({peak_id=>$peak_id, });
#           $compundPeak->retrieveFromDb();

#           $compound_peaks_id = $peaksHash->{$peak_id . '|' .$mass . '|' . $retention_time}->{'COMPOUND_PEAKS_ID'};
#           #print STDERR $peak_id;
#           #print STDERR "\n TO LOAD : ChEBI ID:", $compoundIDLoad, "  CpdPeaksID:", $compound_peaks_id, "  Iso:", $isotopomer,"  User CPD ID:", $compound_id,  "\n";

#           # Adding to hash for testing if a preferred comp is already in DB - peak to peak check. 
#           if(defined($isotopomer)){;}
#           else{
#             if((defined($is_preferred_compound))){
#               $preferredLoaded->{$compoundIDLoad} = 1;
#             }
#           }
            
#           my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
#                 compound_id=>$compoundIDLoad,
#                 #compound_peaks_id=>$compound_peaks_id,
#                 isotopomer=>$isotopomer,
#                 user_compound_name=>$compound_id,
#                 is_preferred_compound=>$is_preferred_compound
#                 });

#           $compoundPeaksChebiRow->setParent($compoundPeak);
#           $compoundPeaksChebiRow->submit();
#         }
#         $self->undefPointerCache();
#         #print STDERR "Peak =  $peak_id\n";
#         #print STDERR Dumper $compoundPeaksTest->{$peak_id}
#       } # End preferredLoaded test.
#     }
#   } #End of while(<PEAKS>)
#   close(PEAKS);
#     ###### END - Load into CompoundPeaksChebi ######

#     ###### Load into CompoundMassSpecResults ######
#   my $resultsFile = 'data.tab';
#   my $profileSetName = $self->getArg('studyName') . $self->getExtDbRlsId($self->getArg('extDbSpec'));
#   my $params;

#   # ####### Loading of the raw data ##  - Not used, not loaded for now. #######
#   # my $args = {mainDirectory=>$dir, makePercentiles=>0, inputFile=>$resultsFile, profileSetName=>$profileSetName};
#   # # NOTE Setting profileSetName as studyName + compoundType for now.

#   # my $resultsData = ApiCommonData::Load::MetaboliteProfiles->new($args, $params);
#   # $resultsData->munge();
#   # $self->SUPER::run();
#   # system('mv insert_study_results_config.txt results_insert_study_results_config.txt');
#   # # renamed as the munge method appends to the config file.
#   # system("mv $dir/.$resultsFile/ $dir/.resultsFile_$resultsFile/");
#   # ####### END -  Loading of the raw data #######

#   my $mappingFile = 'mapping.tab';

#   my $meanRScript =
#         "
#         library(data.table)
#         library(matrixStats)

#         # input data.
#         print('1 here')
#         data <- read.csv('$dir/data.tab', sep='\\t', header=TRUE, check.names=FALSE)  # make sure check.names is not needed.
#         print('2 here')
#         data = data.table(data)
#         # output data.tables.
#         output <-data.table(data[,1])
#         sd_output <-data.table(data[,1])

#         # For storing file header and new col names.
#         colnames(output)<- ' '
#         colnames(sd_output)<- ' '
#         header = ''
#         sd_header = ''

#         # Mapping file that gives sample groupings
#         mapping <- read.csv('$dir/mapping.tab', sep='\\t', header=TRUE, check.names=FALSE)
#         mapping = data.table(mapping)
#         # Takes the col inputs of samples, groups and renames to conform with the rest of the script. 
#         names(mapping)[1] <- 'sample'
#         names(mapping)[2] <- 'group'
#         # Output dir for sd.
#         dir.create('$dir/.sd')

#         # add in data col for sample names
#         groups = unique(mapping[['group']])

#         for(i in groups){
#             # Get each sample by groups from mapping, calculate row means.
#             newData <- mapping[group ==i]
#             newData = data.table(newData)
#             samples = as.vector(newData[['sample']])
#             newResults = data[, samples, with=FALSE]
#             newResults[,'mean'] <- rowMeans(newResults, na.rm=TRUE)
#             mean <- newResults[, 'mean']

#             # New column names for samples. Table header -  needs to be like this for munge input (no index header value).
#             new_col_name = paste(i, 'mean', sep='_')
#             new_col_name_sd = paste(i, 'SD', sep='_')
#             header = paste(header, new_col_name, sep='\\t')
#             sd_header = paste(sd_header, i, sep='\\t') # need name to be as munge output???

#             # Drop mean to work out SD by rows.
#             newResults[,'mean':=NULL]
#             newResults = cbind(newResults, transform(newResults, SD=rowSds(as.matrix(newResults), na.rm=TRUE)))

#             # Add to output data.tables and rename cols with relevant sample names.
#             output = cbind(output, mean[, 'mean'])
#             setnames(output, 'mean', new_col_name)

#             sd_output = cbind(sd_output, newResults[, 'SD'])
#             #setnames(sd_output, 'SD', new_col_name_sd)
#             print(sd_output)

#             # Write the SD files to a dir with the names as the munge method outputs.
#             sd_out = paste('$dir/.sd', gsub(' ', '_', i),  sep='/')
#             print(sd_out)
#             write.table(sd_header, file=sd_out, col.names=FALSE, row.names=FALSE, quote=FALSE)
#             write.table(sd_output, file=sd_out, sep='\\t', append=TRUE, na='0',  col.names=FALSE, row.names=FALSE, quote=FALSE)
#             # Drop the sample SD now the file has been written
#             sd_output[,'SD':=NULL]
#             sd_header = ''
#         }

#         # Writing header first, see above comment about munge method.
#         write.table(header, file='$dir/mean.tab', col.names=FALSE, row.names=FALSE, quote=FALSE)
#         write.table(output, file='$dir/mean.tab', sep='\\t', append=TRUE, na='0',  col.names=FALSE, row.names=FALSE, quote=FALSE)
#         "
#   ;

#   open(my $fh, '>', "$dir/mean.R");
#   print $fh "$meanRScript";
#   close $fh;
#   my $command = "Rscript $dir/mean.R";
#   system($command);
#   #system("rm $dir/mean.R");
#   # This is set by the R script.
#   my $meanFile = 'mean.tab';

#   my $meanArgs = {mainDirectory=>$dir, makePercentiles=>1, inputFile=>$meanFile, profileSetName=>$profileSetName};
#   my $meanData = ApiCommonData::Load::MetaboliteProfiles->new($meanArgs, $params);
#   $meanData->munge();

#   # take munge output and combine with standard error.

#   my $combineRScript = "
#       library(data.table)

#       # take percetile data -> table # Not needed - in the munge output.
#       #percentile <-read.csv('mean.tab.pct', sep='\\t', header=TRUE, check.names=FALSE)
#       #percentile = data.table(percentile)
#       #print(percentile)

#       # take each of the samples from mapping
#       mapping <- read.csv('$dir/mapping.tab', sep='\\t', header=TRUE, check.names=FALSE)
#       mapping = data.table(mapping)
#       names(mapping)[1] <- 'sample'
#       names(mapping)[2] <- 'group'
#       #print(mapping)
#       groups = unique(mapping[['group']])

#       # get file for mean of group via mapping file
#       for(i in groups){
#               #print(i) # has no hashes.
#               # Read munge output for sample. )
#               file = paste('$dir/.mean.tab',  paste(gsub(' ',  '_', i ), '_mean', sep='' ), sep='/')
#               data <- read.csv(file, sep='\\t', header=TRUE, check.names=FALSE)
#               data = data.table(data)
#               setnames(data, 1, 'idx')
#               #print(data)

#               # Read sd data.
#               sd <-read.csv(paste('$dir/.sd', gsub(' ', '_', i), sep='/') ,header=TRUE, sep='\t')
#               sd = data.table(sd)
#               setnames(sd, 1, 'idx')
#               setnames(sd, 2, 'sd')
#               sd[,'sd'] = round(x = sd[,'sd'],digits = 2)
#               #print(sd)

#               # Join on index with sd table.
#               merged = merge(data, sd, by='idx')
#               #setnames(sd, 3, 'percentile')
#               #setnames(sd, 2, 'standard_error')
#               setcolorder(merged, c(1, 3, 4, 2))
#               # Overite munge output.
#               write.table(merged, file=file, sep='\\t', row.names=FALSE, quote=FALSE)
#       }
#   ";

#   open(my $fh, '>', "$dir/combine.R");
#   print $fh "$combineRScript";
#   close $fh;
#   my $combineCommand = "Rscript $dir/combine.R";
#   system($combineCommand);

#   $self->SUPER::run();
#   system("mv $dir/.mean.tab/ $dir/.means_$resultsFile/");
#   system('mv insert_study_results_config.txt mean_insert_study_results_config.txt');
#   ###### END - Load into CompoundMassSpecResults -  using InsertStudyResults.pm ######

# # rm statements for developing
# system("rm $dir/insert_study_results_config.txt");
# #system("rm -r $dir/.means_$resultsFile/");
# #system("rm -r $dir/.sd");
# #system("rm -r $dir/mean.tab");



sub undoTables {
  my ($self) = @_;
  # For GUS::Community::Plugin::Undo - this is getting the tables to remove from
  # in the plugin InsertStudyResults.
  # This sub has to be here to call the sub in InsertStudyResults.
  $self->SUPER::undoTables();
}

1;
