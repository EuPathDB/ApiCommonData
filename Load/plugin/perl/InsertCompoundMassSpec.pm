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

    fileArg({name           => 'peaksFile',
        descr          => 'Name of file containing the compound peaks. Cols = PeakID, Mass, RT, CompoundID',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab',
        constraintFunc => undef,
        isList         => 0,
      }),

    fileArg({name           => 'resultsFile',
        descr          => 'Name of file containing the resuls values. Cols = PeakID|Mass|RT (1 concatentated with '|' col), result1 .... resultX',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab',
        constraintFunc => undef,
        isList         => 0,
      }),

    fileArg({name           => 'mappingFile',
        descr          => 'Mapping file of samples -> groups.',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab',
        constraintFunc => undef,
        isList         => 0,
      }),

    fileArg({name           => 'configFile',
        descr          => 'Name of config file, describes the profiles being loaded - this is generated by the plugin.',
        reqd           => 1,
        mustExist      => 0,
        format         => 'Tab file with header',
        constraintFunc => undef,
        isList         => 0
      }),

    # stringArg({name => 'compoundType',
    #     descr => 'The compund identifier (CompoundID - peaksFile) type that has been supplied with the data e.g. KEGG, InChIKey',
    #     constraintFunc=> undef,
    #     reqd  => 1,
    #     isList => 0
    #    }),

   # stringArg({name => 'hasPeakMappingID',
   #     descr => 'y/n . Has a column (PeakID) that maps the rows in the resultsFile to the peaksFile.',
   #     constraintFunc=> undef,
   #     reqd  => 1,
   #     isList => 0
   #    }),

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
  my $peakFile = $self->getArg('peaksFile');
  my $peakFile = $dir . "/" . $peakFile;
  print STDERR "$peakFile\n";

  ####### Load into CompoudPeaks ######
  open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
  my $header = <PEAKS>;
  chomp $header;
  my @header = split(/\t/, $header);

  my ($external_database_release_id, $mass, $retention_time, $peak_id,
    $ms_polarity, $compound_id, $InChIKey, $compound_peaks_id, $isotopomer,
    $user_compound_name);

    # Mulplite compounds can map to one mass/rt pair.
    # If the next item is the same data this is not loaded, only one row is needed
    # to be the primary key to the other tables.
    # The below are used to test and bypass.
  my ($lastMass, $lastRT, $lastPeakId);

  my $extDbSpec = $self->getArg('extDbSpec');
  $external_database_release_id = $self->getExtDbRlsId($extDbSpec);
  #print STDERR "Ross :$external_database_release_id";

  while(<PEAKS>){
    my @peaksArray = split(/\t/, $_);
    $peak_id = $peaksArray[0];
  	$mass = $peaksArray[1];
  	$retention_time = $peaksArray[2];
    $isotopomer = $peaksArray[3];
    $ms_polarity = $peaksArray[4];
  	$compound_id = $peaksArray[5];
    chomp $compound_id;
	$InChIKey = $peaksArray[6];
	chomp $InChIKey; 
	
     # Not using for the moment. Setting in elsif below.

    if (($lastPeakId == $peak_id) && ($lastMass == $mass) && ($lastRT == $retention_time)){

			#print STDERR "Mass: $mass - RT: $retention_time pair already in CompoundPeaks - skipping.\n"
    }
    else {
			#print STDERR  "Mass:", $mass, " RT:", $retention_time, "  Cpd ID:", $compound_id, " MS Pol:", $ms_polarity, "\n";

      # NOTE : Check that changing the format (csv->tab) does not change the Mass / RT float value.
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

      $lastPeakId = $peaksArray[0];
      $lastMass = $peaksArray[1];
      $lastRT = $peaksArray[2];

  } #End of while(<PEAKS>)
    close(PEAKS);
    ####### END - Load into CompoudPeaks ######

    # Hash of all the loaded compound peaks from above.
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
      $isotopomer = $peaksArray[3];
      $ms_polarity = $peaksArray[4];
      $compound_id = $peaksArray[5];
      chomp $compound_id;
      $InChIKey = $peaksArray[6];
      chomp $InChIKey; 
      
	  my $compoundLookup = $compound_id;
	  my $InChILookup = 'InChIKey=' . $InChIKey; 
	  my $compoundIDLoad;

	#NOTE - for noow only the $compound_id is being loaded into the table. The InChIKey, if there is one, is not.
# They are never seen so adding the col to the table to have both is not useful for the moment. 
# To get a ChEBI ID the InChIKey is tested first, the the other compound ID. 
	# print STDERR "Values in hashes for $peak_id:\n";
	# print STDERR Dumper $compoundInChIKeyHash->{$InChILookup};
	# print STDERR Dumper $otherCompoundHash->{$compoundLookup};
	
	
	
	  if(defined($compoundInChIKeyHash->{'InChIKey=' . $InChIKey})){
	    #print STDERR "FOUND ---- InChI hash for $peak_id $InChIKey \n";
        $compoundIDLoad = $compoundInChIKeyHash->{$InChILookup}->{'MYID'};
		#	print STDERR "Inchi hash value :", Dumper $compoundInChIKeyHash->{'InChIKey=' . $InChIKey};
		#print STDERR "1: $compoundIDLoad \n"; 
	  }
      elsif(defined($otherCompoundHash->{$compoundLookup})){
        $compoundIDLoad = $otherCompoundHash->{$compoundLookup}->{'MYID'};
		#print STDERR "FOUND #### other hash for $peak_id $compoundLookup \n";
		#print STDERR "Other hash value :", Dumper $otherCompoundHash->{$compoundLookup};
		#print STDERR "2: $compoundIDLoad\n"; 
      }
      else{;}
	 
      $compound_peaks_id = $peaksHash->{$peak_id . '|' .$mass . '|' . $retention_time}->{'COMPOUND_PEAKS_ID'};
	  
	  #print STDERR "\n TO LOAD : ChEBI ID:", $compoundIDLoad, "  CpdPeaksID:", $compound_peaks_id, "  Iso:", $isotopomer,"  User CPD ID:", $compound_id,  "\n \n\n\n\n";

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

    ###### Load into CompoundMassSpecResults ######
  my $resultsFile = $self->getArg('resultsFile');
  my $profileSetName = $self->getArg('studyName') . $self->getExtDbRlsId($self->getArg('extDbSpec'));
  my $args = {mainDirectory=>$dir, makePercentiles=>0, inputFile=>$resultsFile, profileSetName=>$profileSetName};
  # NOTE Setting profileSetName as studyName + compoundType for now.
  my $params;
  my $resultsData = ApiCommonData::Load::MetaboliteProfiles->new($args, $params);
  $resultsData->munge();
  $self->SUPER::run();
  system('mv insert_study_results_config.txt results_insert_study_results_config.txt');
  # renamed as the munge method appends to the config file.
  system("mv $dir/.$resultsFile/ $dir/.resultsFile_$resultsFile/");

  my $mappingFile = $self->getArg('mappingFile');

  my $meanRScript =
  "library(data.table)

data <- read.csv('$resultsFile', sep='\\t', header=TRUE, check.names=FALSE)
data = data.table(data)
output <-data.table(data[,1])#(V1=NA)
colnames(output)<- ' '
header = ''
mapping <- read.csv('$mappingFile', sep='\\t', header=TRUE)
mapping = data.table(mapping)
colnames(mapping)[1]<-'sample'
colnames(mapping)[2]<-'group'

groups = unique(mapping[['group']])

for(i in groups){
#   print(i)
    newData <- mapping[group ==i]
    newData = data.table(newData)
    samples = as.vector(newData[['sample']])
    newResults = data[, samples, with=FALSE]
    newResults[,'mean'] <- rowMeans(newResults, na.rm=TRUE)
    mean <- newResults[, 'mean']
    new_col_name = paste(i, 'mean')
    header = paste(header, new_col_name, sep='\\t')
#   print(mean)
    output = cbind(output, mean[, 'mean'])
    setnames(output, 'mean', new_col_name)
}

write.table(header, file='mean.tab', col.names=FALSE, row.names=FALSE, quote=FALSE)
write.table(output, file='mean.tab', sep='\\t', append=TRUE, na="0", col.names=FALSE, row.names=FALSE, quote=FALSE)"
;

# NEED underscores for names.
  open(my $fh, '>', "$dir/mean.R");
  print $fh "$meanRScript";
  close $fh;
  my $command = "Rscript $dir/mean.R";
  system($command);
  system("rm $dir/mean.R");
  # This is set by the R script.
  my $meanFile = 'mean.tab';

  my $meanArgs = {mainDirectory=>$dir, makePercentiles=>0, inputFile=>$meanFile, profileSetName=>$profileSetName};
  my $meanData = ApiCommonData::Load::MetaboliteProfiles->new($meanArgs, $params);
  $meanData->munge();

  $self->SUPER::run();
  system("mv $dir/.mean.tab/ $dir/.means_$resultsFile/");
  system('mv insert_study_results_config.txt mean_insert_study_results_config.txt');
  ###### END - Load into CompoundMassSpecResults -  using InsertStudyResults.pm ######
}

sub undoTables {
  my ($self) = @_;
  # For GUS::Community::Plugin::Undo - this is getting the tables to remove from
  # in the plugin InsertStudyResults.
  # This sub has to be here to call the sub in InsertStudyResults.
  $self->SUPER::undoTables();
}

1;
