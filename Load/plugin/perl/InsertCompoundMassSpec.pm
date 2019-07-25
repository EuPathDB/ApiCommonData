package ApiCommonData::Load::Plugin::InsertCompoundMassSpec;
@ISA = qw(ApiCommonData::Load::Plugin::InsertStudyResults);

use lib "$ENV{GUS_HOME}/lib/perl";
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

sub run {
  my ($self) = @_;

  # Hash of SQL queries for the different compound types e.g. KEGG, InChIKey, HMDB.
  # Cols are renamed - MYKEY: for the lookup. MYID: as the ID that needs to be returned.

  my $compoundInChIKeySQL = 
    "select replace (s.structure, 'InChIKey=', '') as MYKEY
    , c.chebi_accession
    , c.id as MYID 
    from chebi.structures s
    , CHEBI.compounds c
    where s.type = 'InChIKey'
    and c.id = s.compound_id                    
  ";

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
                                   )                                   
                        UNION
                          select  
                            c.id  as MYID,
                            c.chebi_accession as MYKEY
                            from 
                            chebi.compounds c";
  
  my $dbh = $self->getQueryHandle();

  ### InChIKey hash ###
  my $compoundInChIKeyHash = {};
  my $compoundInChIKeyArray = [];
  $compoundInChIKeyArray = $dbh->selectall_arrayref($compoundInChIKeySQL); 

  # This has is needed are there are multiple ChEBI IDs for an InChIKey. I need to return all the ChEBI IDs for the data to
  # be properly represented. 
  foreach my $item (@{$compoundInChIKeyArray}) {
    my @inChI = split(/-/, @{$item}[0]);  
    $compoundInChIKeyHash->{@inChI[0]}->{@inChI[1]}->{@inChI[2]}->{@{$item}[2]}->{'InChIKey'} = @{$item}[0];
    $compoundInChIKeyHash->{@inChI[0]}->{@inChI[1]}->{@inChI[2]}->{@{$item}[2]}->{'ChEBI'} = @{$item}[2];  
  }

  ### Other Compound Hash ###
  my $otherCompoundHash = {};
  $otherCompoundHash = $dbh->selectall_hashref($compoundOtherSQL, 'MYKEY');

  my $dir = $self->getArg('inputDir');
  my $peakFile = 'peaks.tab';
  my $peakFile = $dir . "/" . $peakFile;

  ###### Read peaks.tab into hash ######
  open(PEAKS, $peakFile) or $self->("Could not open $peakFile for reading: $!");
  my $header = <PEAKS>;
  chomp $header;
  my @header = split(/\t/, $header);

  my ($external_database_release_id, $mass, $retention_time, $peak_id,
    $ms_polarity, $compound_id, $InChIKey, $compound_peaks_id, $isotopomer,
    $user_compound_name, $is_preferred_compound);

  my $extDbSpec = $self->getArg('extDbSpec');
  $external_database_release_id = $self->getExtDbRlsId($extDbSpec);

  my $preferredCompounds = {};
  my $compoundHash = {};

  # Load into two hashes.
  # compoundHash stores the compounds with the associated data.
  # preferredCompounds stores the preferred status and the ChEBI IDs from our DB. 
  while(<PEAKS>){
    my @peaksArray = split(/\t/, $_);    
    my ($peak_id, $mass, $retention_time, $isotopomer, $ms_polarity, $compound_id, $InChIKey, $is_preferred_compound) = split(/\t/, $_);
    chomp $InChIKey;
    chomp $is_preferred_compound;

    if ($is_preferred_compound eq  '' ){
      $is_preferred_compound = '1';
    }

    my $chebiIdArray = [];   	
  
    if ( defined($InChIKey) && !($InChIKey eq '' ) ) {
      my @keys = split(/-/, $InChIKey);

      if ( defined($compoundInChIKeyHash->{@keys[0]}->{@keys[1]}->{@keys[2]}) ){      
        foreach my $chebiSearched (keys $compoundInChIKeyHash->{@keys[0]}->{@keys[1]}->{@keys[2]}){        
          push @{$chebiIdArray}, $chebiSearched; 
        }  
      }
    }
    else {
      if ( defined($otherCompoundHash->{$compound_id}->{'MYID'}) ){
        push @{$chebiIdArray}, $otherCompoundHash->{$compound_id}->{'MYID'};
      }
    } 
     
    if( scalar@{$chebiIdArray} == 0 ){
      $compoundHash->{$peak_id}->{$is_preferred_compound};
      $compoundHash->{$peak_id}->{'peak_data'} = [$mass, $retention_time, $isotopomer, $ms_polarity]; # Need to set this for the peaks with no chebi ID hits. 
    }

    foreach my $chebiId (@{$chebiIdArray}){
      my $peakCompId = $chebiId . '|' . $peak_id; 

      if( !(defined($compoundHash->{$peak_id}->{$is_preferred_compound}->{$chebiId})) ){ 
        $compoundHash->{$peak_id}->{$is_preferred_compound}->{$chebiId} = [];
        push $compoundHash->{$peak_id}->{$is_preferred_compound}->{$chebiId}, $InChIKey; }
      else{push $compoundHash->{$peak_id}->{$is_preferred_compound}->{$chebiId}, $InChIKey; } 
      #TODO will this work with more than one chebi ID in our DB. 
      # Or no chebi ID in the DB but more than one ID in the data.
      $compoundHash->{$peak_id}->{'peak_data'} = [$mass, $retention_time, $isotopomer, $ms_polarity];

      if ( (defined($preferredCompounds->{$is_preferred_compound}->{$chebiId}->{$peak_id})) 
      && !($peak_id ~~ $preferredCompounds->{$is_preferred_compound}->{$chebiId}->{$peak_id}) ){
        push $preferredCompounds->{$is_preferred_compound}->{$chebiId}->{$peak_id}, $peak_id;
      }
      else{
        $preferredCompounds->{$is_preferred_compound}->{$chebiId}->{$peak_id} = [];
        push $preferredCompounds->{$is_preferred_compound}->{$chebiId}->{$peak_id}, $peak_id;
      }
    } 
  } 
  close(PEAKS);

  ###### Load into CompoundPeaks & CompoundPeaksChebi ######
  foreach my $peak(keys $compoundHash){

    my ($mass, $retention_time, $isotopomer, $ms_polarity, $InChIKey);
    $mass = $compoundHash->{$peak}->{'peak_data'}[0];
    $retention_time = $compoundHash->{$peak}->{'peak_data'}[1];
    $isotopomer = $compoundHash->{$peak}->{'peak_data'}[2];
    $ms_polarity = $compoundHash->{$peak}->{'peak_data'}[3];     

    my $compoundPeaksRow = GUS::Model::ApiDB::CompoundPeaks->new({
        external_database_release_id=>$external_database_release_id,
        mass=>$mass,
        retention_time=>$retention_time,
        peak_id=>$peak,
        ms_polarity=>$ms_polarity
        });
        
    # For a peak want to test if there is a preferred compound	
    foreach my $pref(keys $compoundHash->{$peak}){
      foreach my $chebi (keys $compoundHash->{$peak}->{$pref}){
        my $peakCompId = $chebi . '|'. $peak;        
        if ($chebi eq 'peak_data'){
          ;
        }    
        elsif ( $pref eq '1'           
          && (defined($preferredCompounds->{'1'}->{$chebi}->{$peak})) 
        ){ 
          foreach my $cpd (@{$compoundHash->{$peak}->{'1'}->{$chebi}}){    
            my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
                compound_id=>$chebi,
                isotopomer=>$isotopomer,
                user_compound_name=>$cpd, # TODO This needs to be updated from the chebI ID to the user cpd names???
                is_preferred_compound=>'1'
              });
            $compoundPeaksChebiRow->setParent($compoundPeaksRow);
            $compoundPeaksRow->addToSubmitList($compoundPeaksChebiRow);
          }
        }
          #TODO - add in set parent to the chebi id -> chebi table. 
         # If there is no pref compound load all the other compounds. 
        elsif( $pref eq '0'
          && !(defined($compoundHash->{$peak}->{'1'}))
          && defined($preferredCompounds->{'0'}->{$chebi}->{$peak})
          && !(defined($preferredCompounds->{'1'}->{$chebi})) ){ # cpd 58161 #TODO test only no pref are added
          $mass = $compoundHash->{$peak}->{'peak_data'}[0];
          $retention_time = $compoundHash->{$peak}->{'peak_data'}[1];
          $isotopomer = $compoundHash->{$peak}->{'peak_data'}[2];
          $ms_polarity = $compoundHash->{$peak}->{'peak_data'}[3]; 

          ### Loads only one compound per chebi id. 
          my $compoundPeaksChebiRow = GUS::Model::ApiDB::CompoundPeaksChebi->new({
              compound_id=>$chebi,
              isotopomer=>$isotopomer,
              user_compound_name=>@{$compoundHash->{$peak}->{'0'}->{$chebi}}[0],
              is_preferred_compound=>'0'
            });

          $compoundPeaksChebiRow->setParent($compoundPeaksRow);
          $compoundPeaksRow->addToSubmitList($compoundPeaksChebiRow);
          
        }
      } 
    } 
    $compoundPeaksRow->submit();
    $self->undefPointerCache();
  } 

  ###### Load into CompoundMassSpecResults ######
  my $resultsFile = 'data.tab';
  my $profileSetName = $self->getArg('studyName') . $self->getExtDbRlsId($self->getArg('extDbSpec'));
  my $params;

  my $mappingFile = 'mapping.tab';

  my $meanRScript =
        "
        library(data.table)
        library(matrixStats)

        # input data.
        data <- read.csv('$dir/data.tab', sep='\\t', header=TRUE, check.names=FALSE)  # make sure check.names is not needed.
        data = data.table(data)
        output <-data.table(data[,1])
        sd_output <-data.table(data[,1])

        # For storing file header and new col names.
        colnames(output)<- ' '
        colnames(sd_output)<- ' '
        header = ''
        sd_header = ''

        # Mapping file that gives sample groupings
        mapping <- read.csv('$dir/mapping.tab', sep='\\t', header=TRUE, check.names=FALSE)
        mapping = data.table(mapping)
        # Takes the col inputs of samples, groups and renames to conform with the rest of the script. 
        names(mapping)[1] <- 'sample'
        names(mapping)[2] <- 'group'
        # Output dir for sd.
        dir.create('$dir/.sd')

        # add in data col for sample names
        groups = unique(mapping[['group']])

        for(i in groups){
            # Get each sample by groups from mapping, calculate row means.
            newData <- mapping[group ==i]
            newData = data.table(newData)
            samples = as.vector(newData[['sample']])
            newResults = data[, samples, with=FALSE]
            newResults[,'mean'] <- rowMeans(newResults, na.rm=TRUE)
            mean <- newResults[, 'mean']

            # New column names for samples. Table header -  needs to be like this for munge input (no index header value).
            new_col_name = paste(i, 'mean', sep='_')
            new_col_name_sd = paste(i, 'SD', sep='_')
            header = paste(header, new_col_name, sep='\\t')
            sd_header = paste(sd_header, i, sep='\\t') # need name to be as munge output???

            # Drop mean to work out SD by rows.
            newResults[,'mean':=NULL]
            newResults = cbind(newResults, transform(newResults, SD=rowSds(as.matrix(newResults), na.rm=TRUE)))

            # Add to output data.tables and rename cols with relevant sample names.
            output = cbind(output, mean[, 'mean'])
            setnames(output, 'mean', new_col_name)

            sd_output = cbind(sd_output, newResults[, 'SD'])

            # Write the SD files to a dir with the names as the munge method outputs.
            sd_out = paste('$dir/.sd', gsub(' ', '_', i),  sep='/')
            write.table(sd_header, file=sd_out, col.names=FALSE, row.names=FALSE, quote=FALSE)
            write.table(sd_output, file=sd_out, sep='\\t', append=TRUE, na='0',  col.names=FALSE, row.names=FALSE, quote=FALSE)
            # Drop the sample SD now the file has been written
            sd_output[,'SD':=NULL]
            sd_header = ''
        }

        # Writing header first, see above comment about munge method.
        write.table(header, file='$dir/mean.tab', col.names=FALSE, row.names=FALSE, quote=FALSE)
        write.table(output, file='$dir/mean.tab', sep='\\t', append=TRUE, na='0',  col.names=FALSE, row.names=FALSE, quote=FALSE)
        "
  ;

  open(my $fh, '>', "$dir/mean.R");
  print $fh "$meanRScript";
  close $fh;
  my $command = "Rscript $dir/mean.R";
  system($command);
  my $meanFile = 'mean.tab';

  my $meanArgs = {mainDirectory=>$dir, makePercentiles=>1, inputFile=>$meanFile, profileSetName=>$profileSetName};
  my $meanData = ApiCommonData::Load::MetaboliteProfiles->new($meanArgs, $params);
  $meanData->munge();

  # take munge output and combine with standard error.
  my $combineRScript = "
      library(data.table)

      # take percetile data -> table # Not needed - in the munge output.

      # take each of the samples from mapping
      mapping <- read.csv('$dir/mapping.tab', sep='\\t', header=TRUE, check.names=FALSE)
      mapping = data.table(mapping)
      names(mapping)[1] <- 'sample'
      names(mapping)[2] <- 'group'
      groups = unique(mapping[['group']])

      # get file for mean of group via mapping file
      for(i in groups){
              # Read munge output for sample. )
              file = paste('$dir/.mean.tab',  paste(gsub(' ',  '_', i ), '_mean', sep='' ), sep='/')
              data <- read.csv(file, sep='\\t', header=TRUE, check.names=FALSE)
              data = data.table(data)
              setnames(data, 1, 'idx')

              # Read sd data.
              sd <-read.csv(paste('$dir/.sd', gsub(' ', '_', i), sep='/') ,header=TRUE, sep='\t')
              sd = data.table(sd)
              setnames(sd, 1, 'idx')
              setnames(sd, 2, 'sd')
              sd[,'sd'] = round(x = sd[,'sd'],digits = 2)

              # Join on index with sd table.
              merged = merge(data, sd, by='idx')
              setcolorder(merged, c(1, 3, 4, 2))
              # Overite munge output.
              write.table(merged, file=file, sep='\\t', row.names=FALSE, quote=FALSE)
      }
  ";

  open(my $fh, '>', "$dir/combine.R");
  print $fh "$combineRScript";
  close $fh;
  my $combineCommand = "Rscript $dir/combine.R";
  system($combineCommand);

  $self->SUPER::run();
  system("mv $dir/.mean.tab/ $dir/.means_$resultsFile/");
  system('mv insert_study_results_config.txt mean_insert_study_results_config.txt');

}

sub undoTables {
  my ($self) = @_;
  # For GUS::Community::Plugin::Undo - this is getting the tables to remove from
  # in the plugin InsertStudyResults.
  # This sub has to be here to call the sub in InsertStudyResults.
  $self->SUPER::undoTables();
}

1;
