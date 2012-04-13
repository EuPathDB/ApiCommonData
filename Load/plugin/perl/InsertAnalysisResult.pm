package ApiCommonData::Load::Plugin::InsertAnalysisResult;
@ISA = qw(GUS::PluginMgr::Plugin);


use strict;

use GUS::Supported::GusConfig;
use GUS::PluginMgr::Plugin;

use GUS::Model::Study::OntologyEntry;
use GUS::Model::RAD::Analysis;
use GUS::Model::RAD::AnalysisInput;

use GUS::Model::RAD::Protocol;
use GUS::Model::RAD::AnalysisParam;
use GUS::Model::RAD::ProtocolParam;

use GUS::Model::RAD::LogicalGroup;
use GUS::Model::RAD::LogicalGroupLink;
use GUS::Supported::Util;

$| = 1;

# ---------------------------------------------------------------------------
# Load Arguments
# ---------------------------------------------------------------------------

sub getArgumentsDeclaration{
  my $argsDeclaration =
    [

     booleanArg ({name => 'useSqlLdr',
                  descr => 'Set this to use sqlldr instead of objects.  Only implemented for DataTransformationResult',
                  reqd => 0,
                  default => 0
                 }),

     fileArg({name           => 'inputDir',
              descr          => 'Directory in which to find input files',
              reqd           => 1,
              mustExist      => 1,
              format         => '',
              constraintFunc => undef,
              isList         => 0, 
             }),

     fileArg({ name           => 'configFile',
               descr          => 'tab-delimited file with differential expression stats',
               reqd           => 1,
               mustExist      => 1,
               format         => '',
               constraintFunc => undef,
               isList         => 0,
             }),

     enumArg({ descr          => 'View of analysisResultImp',
               name           => 'analysisResultView',
               isList         => 0,
               reqd           => 1,
               constraintFunc => undef,
               enum           => "DataTransformationResult,DifferentialExpression,ExpressionProfile",
             }),

     enumArg({ descr          => 'View of naFeatureImp',
               name           => 'naFeatureView',
               isList         => 0,
               reqd           => 1,
               constraintFunc => undef,
               enum           => "ArrayElementFeature,GeneFeature,BindingSiteFeature", 
             }),

    ];
  return $argsDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = "Inserts Rad.Analysis and Rad.AnalysisResultImp View.  Creates the associated Rad.Protocol if it doesn't exist";

  my $purpose = "Inserts Rad.Analysis and Rad.AnalysisResultImp View.  Creates the associated Rad.Protocol if it doesn't exist";

  my $tablesAffected = [['RAD::Analysis', 'One Row to Identify this experiment'],['RAD::AnalysisResultImp', 'one row per line in the data file'],['RAD::Protocol', 'Will Create generic row if the specified protocol does not already exist']];

  my $tablesDependedOn = [['Study::OntologyEntry',  'new protocols will be assigned unknown_protocol_type'],
                          ['DoTS::GeneFeature', 'The id in the data file must ge an existing Gene Feature']];

  my $howToRestart = "No restart";

  my $failureCases = "";

  my $notes = "The first column in the data file specifies the Dots.GeneFeature SourceId.  Subsequent columns are view specific. (ex:  fold_change for DifferentialExpression OR float_value for DataTransformationResult).  The Config file has the following columns (no header):file analysis_name protocol_name protocol_type(OPTOINAL)";

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases,notes=>$notes};

  return $documentation;
}

#--------------------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {na_sequences => []
             };
  bless($self,$class);

  my $documentation = &getDocumentation();
  my $argumentDeclaration = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 3.6,
		             cvsRevision => '$Revision$',
                     name => ref($self),
                     revisionNotes => '',
                     argsDeclaration => $argumentDeclaration,
                     documentation => $documentation});

  return $self;
}

#--------------------------------------------------------------------------------

sub run {
  my ($self) = @_;

  my $config = $self->readConfig();

  my $totalLines;

  my $analysisResultView = $self->getArg('analysisResultView');
  my $naFeatureView = $self->getArg('naFeatureView');
  my $useSqlLdr = $self->getArg('useSqlLdr');

  if($analysisResultView ne 'DataTransformationResult' && $useSqlLdr) {
    $self->userError("DataTransformationResult is the only anlalysisResultVeiw currently supported with sqlldr");
  }

  my $class = "GUS::Model::RAD::$analysisResultView";
  eval "require $class";

  my $configHeader = shift @$config;

  $self->validateHeader($configHeader);

  foreach my $configRow (@$config) {
    my $dataFile = $configRow->[0];
    my $analysisName = $configRow->[1];
    my $protocolName = $configRow->[2];
    my $protocolType = $configRow->[3];
    my $profileSetName = $configRow->[4];
    my $profileElements = $configRow->[5];

    my $logicalGroup = $self->makeLogicalGroup($profileElements, $analysisName, $profileSetName);

    my $protocol = $self->getProtocol($protocolName, $protocolType, $configHeader);

    my $analysis = $self->createAnalysis($protocol, $analysisName, $configHeader, $configRow, $logicalGroup);

    my $count = $self->processDataFile($analysis, $dataFile, $class, $naFeatureView, $useSqlLdr);

    $self->log("File Finished.  $count lines processed");

    $totalLines = $totalLines + $count;
  }

  my $totalInserts = $self->getTotalInserts();

  return "Processed $totalLines lines from data files and $totalInserts Total Inserts";
}

#--------------------------------------------------------------------------------

sub validateHeader {
  my ($self, $header) = @_;

  my @expected = ('datafile', 'analysisname', 'protocolname', 'protocoltype','profilesetname','profileelementnames');

  for(my $i = 0; $i < scalar @expected; $i++) {
    my $value = $header->[$i];
    $value =~ s/\s//g;

    my $e = $expected[$i];

    unless($value =~ /$e/i) {
      $self->userError("Config file missing missing expected Column: $e");
    }
  }
  return 1;
}


#--------------------------------------------------------------------------------

sub makeLogicalGroup {
  my ($self, $profileElements, $analysisName, $profileSetName) = @_;

  return unless($profileElements && $profileSetName);

  my ($tableId) = $self->sqlAsArray( Sql => "select table_id from core.tableinfo where name = 'ProfileElementName'" );

  my $logicalGroupName = "$analysisName INPUTS";
  my $logicalGroup = GUS::Model::RAD::LogicalGroup->new({name => $logicalGroupName});

  my ($profileSetId) = $self->sqlAsArray( Sql => "select profile_set_id from apidb.profileset where name = '$profileSetName'" );

  my @profileElements = split(';', $profileElements);

  foreach my $pe (@profileElements) {
    my ($profileElementNameId) = $self->sqlAsArray( Sql => "select profile_element_name_id from apidb.profileelementname where profile_set_id = $profileSetId and name = '$pe'" );

    unless($profileElementNameId) {
      $self->userError("No row in apidb.profileelementname for profile set [$profileSetName] and Name [$pe]");
    }

    my $link = GUS::Model::RAD::LogicalGroupLink->new({table_id => $tableId, row_id => $profileElementNameId});
    $link->setParent($logicalGroup);
    $link->submit();
  }
  return $logicalGroup;
}



#--------------------------------------------------------------------------------

sub readConfig {
  my ($self) = @_;

  my $fn = $self->getArg('configFile');

  open(CONFIG, "$fn") or $self->error("Cannot open file $fn for reading: $!");

  my @rv;

  while(<CONFIG>) {
    chomp;

    next unless($_);
    next if /^#/;

    my @a = split(/\t/, $_);

    push @rv, \@a;
  }

  close CONFIG;

  return \@rv;
}


#--------------------------------------------------------------------------------

sub processDataFile {
  my ($self, $analysis, $fn, $class, $naFeatureView, $useSqlLdr) = @_;

  my $inputDir = $self->getArg('inputDir');

  open(FILE, "$inputDir/$fn") or $self->error("Cannot open file $inputDir/$fn for reading: $!");

  my $tableId = $self->getTableId($naFeatureView);

  my $header = <FILE>;
  chomp $header;

  my @headers = split(/\t/, $header);

  my $count;

  # the sqlldr requires us to write a data file
  if($useSqlLdr) {
    my $sqlLdrFn = "$inputDir/$fn" . ".dat";
    open(OUT, "> $sqlLdrFn") or die "Cannot open file $sqlLdrFn for writing:$!";
  }
    
  $analysis->submit();
  
  while(<FILE>) {
    chomp;

    $count++;
    if($count % 500 == 0) {
      $self->undefPointerCache();
      $self->log("Processed $count rows from $fn");
    }

    my @row = split(/\t/, $_);

    $self->userError("The number of columns in the data file didn't match the number of columns in the header for row $count") unless(scalar @row == scalar @headers);

    my $sourceId = $row[0];

    my $naFeatureIdArrayRef = $self->getNaFeatureId($sourceId, $naFeatureView);
    next unless $naFeatureIdArrayRef;

    foreach my $naFeatureId (@$naFeatureIdArrayRef) {

      my $hashRef = {table_id => $tableId,
                     row_id => $naFeatureId
                    };

      for(my $i = 1; $i < scalar @headers; $i++) {
        my $key = $headers[$i];
        my $value = $row[$i];

        $hashRef->{$key} = $value;
      }

      if($useSqlLdr) {
        $self->writeSqlLdrInput($hashRef, $analysis, \*OUT);
      }
      else {

        my $analysisResult = eval {
          $class->new($hashRef);
        };

        $self->error($@) if $@;

        $analysisResult->setParent($analysis);
        
	$analysisResult->submit();
      }
    }
  }
  close FILE;

  if($useSqlLdr) {
    close OUT;
    my $sqlLdrFn = "$inputDir/$fn" . ".dat";

    my $configFile = $sqlLdrFn;
    my $logFile = $sqlLdrFn;

    $configFile =~ s/.dat$/.ctrl/;
    $logFile =~ s/.dat$/.log/;

    $self->writeConfigFile($configFile, $sqlLdrFn);
    my $login       = $self->getConfig->getDatabaseLogin();
    my $password    = $self->getConfig->getDatabasePassword();
    my $dbiDsn      = $self->getConfig->getDbiDsn();

    my ($dbi, $type, $db) = split(':', $dbiDsn);

    system("sqlldr $login/$password\@$db control=$configFile log=$logFile") if($self->getArg('commit'));
  }


  return $count;
}

#--------------------------------------------------------------------------------

sub getNaFeatureId {
  my ($self, $sourceId, $naFeatureView) = @_;

  my @naFeatures;

  if ($naFeatureView eq 'GeneFeature'){
      my $naFeatureId =  GUS::Supported::Util::getGeneFeatureId($self, $sourceId);

      push @naFeatures, $naFeatureId;
  }else{
      my $naFeatureIds =  GUS::Supported::Util::getNaFeatureIdsFromSourceId($self, $sourceId, $naFeatureView);

      @naFeatures = @$naFeatureIds;
  }

  if(scalar @naFeatures > 1) {
    $self->log("WARN:  Several NAFeatures are found for source_id $sourceId. Loading multiple rows.");
  }
  return \@naFeatures;

}

#--------------------------------------------------------------------------------

sub getTableId {
  my ($self, $naFeatureView) =  @_;

  my @tableIds = $self->sqlAsArray( Sql => "select table_id from core.tableinfo where name = '$naFeatureView'" );

  if(scalar @tableIds != 1) {
    $self->error("Core::TableInfo not found for $naFeatureView");
  }
  return $tableIds[0];
}

#--------------------------------------------------------------------------------

sub createAnalysis {
  my ($self, $protocol, $analysisName,$configHeader, $configRow, $logicalGroup) = @_;

  my $analysis = GUS::Model::RAD::Analysis->new({name => $analysisName});
  my @protocolParamList =$protocol->getChildren('RAD::ProtocolParam',1);

  for(my $i = 6; $i < scalar @$configRow; $i++){
      next unless ($configRow->[$i]);
      my $analysisParamValue=$configRow->[$i]; 
      my $analysisParam = GUS::Model::RAD::AnalysisParam->new({value => $analysisParamValue});
      $analysisParam->setParent($analysis); 
      my $protocolParamName = $configHeader->[$i];
      foreach (@protocolParamList){
	  if ($_->getName() eq $protocolParamName){
	      $analysisParam->setParent($_); 
          }
       }
  }
  $analysis->setParent($protocol);

  if($logicalGroup) {
    my $ai = GUS::Model::RAD::AnalysisInput->new({});

    $ai->setParent($analysis);
    $ai->setParent($logicalGroup);
  }

  return $analysis;
}

#--------------------------------------------------------------------------------

sub getProtocol {
  my ($self, $protocolName, $protocolType, $configHeader) = @_;

  my $protocol = GUS::Model::RAD::Protocol->new({name => $protocolName });

  unless($protocol->retrieveFromDB()) {
    my $protocolTypeId = $self->getProtocolTypeId($protocolType);
    # Can't set parent because there are many fk to Study::OntologyEntry
    $protocol->setProtocolTypeId($protocolTypeId);
  }
  
  my $protocolId = $protocol->getId(); 

  for(my $i = 6; $i < scalar @$configHeader; $i++){
      my $protocolParamName = $configHeader->[$i]; 
      my $protocolParam = GUS::Model::RAD::ProtocolParam->new({protocol_id => $protocolId,
                                                          name => $protocolParamName}); 
      $protocolParam->setParent($protocol); 
      $protocolParam->submit() unless $protocolParam->retrieveFromDB();

  }
  return $protocol;
}


#--------------------------------------------------------------------------------

sub getProtocolTypeId {
  my ($self, $protocolType) = @_;

  $protocolType = 'unknown_protocol_type' unless($protocolType);
  my $category = 'ExperimentalProtocolType';

  my $oe = GUS::Model::Study::OntologyEntry->new({value => $protocolType,
                                                  category => $category,
                                                 });

  unless($oe->retrieveFromDB()) {
    $self->error("Could not retrieve Study::OntologyEntry for value $protocolType");
  }

  return $oe->getId();
}

#--------------------------------------------------------------------------------

sub writeSqlLdrInput { 
  my ($self, $hashRef, $analysis, $fh) = @_;

  my $subclassView = 'DataTransformationResult';

  my $analysisId = $analysis->getId();
  my $modDate = $analysis->getModificationDate();

  my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
  my @abbr = qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC);
  $modDate = sprintf('%2d-%s-%02d', $mday, $abbr[$mon], ($year+1900) % 100);

  my $database = $self->getDb();

  my $projectId = $database->getDefaultProjectId();
  my $userId = $database->getDefaultUserId();
  my $groupId = $database->getDefaultGroupId();
  my $algInvocationId = $database->getDefaultAlgoInvoId();
  my $userRead = $database->getDefaultUserRead();
  my $userWrite = $database->getDefaultUserWrite();
  my $groupRead = $database->getDefaultGroupRead();
  my $groupWrite = $database->getDefaultGroupWrite();
  my $otherRead = $database->getDefaultOtherRead();
  my $otherWrite = $database->getDefaultOtherWrite();

  my $tableId = $hashRef->{table_id};
  my $rowId = $hashRef->{row_id};
  my $floatValue = $hashRef->{float_value};
  my $intValue = $hashRef->{int_value};


  unless(defined($floatValue)) {
    $self->userError("Float value must be specified for DatatransformationResult when sqlldr is used");
  }

  my @a = ($subclassView, $analysisId, $tableId, $rowId, $floatValue, $intValue,$modDate, $userRead, $userWrite, $groupRead, $groupWrite, $otherRead, $otherWrite, $userId, $groupId, $projectId, $algInvocationId);

  print $fh join("\t", @a) . "\n";
}


sub getConfig {
  my ($self) = @_;

  if (!$self->{config}) {
    my $gusConfigFile = $self->getArg('gusconfigfile');
     $self->{config} = GUS::Supported::GusConfig->new($gusConfigFile);
   }

  $self->{config};
}

sub writeConfigFile {
  my ($self, $configFile, $sqlLdrFn) = @_;

  open(CONFIG, "> $configFile") or die "Cannot open file $configFile For writing:$!";

  print CONFIG "LOAD DATA
INFILE '$sqlLdrFn'
APPEND
INTO TABLE Rad.AnalysisResultImp
FIELDS TERMINATED BY '\\t'
TRAILING NULLCOLS
(subclass_view char, 
analysis_id integer external,
table_id integer external, 
row_id integer external, 
float1 decimal external, 
NUMBER1 integer external,
modification_date date, 
user_read integer external, 
user_write integer external, 
group_read integer external, 
group_write integer external, 
other_read integer external, 
other_write integer external, 
row_user_id integer external, 
row_group_id integer external, 
row_project_id integer external, 
row_alg_invocation_id integer external, 
analysis_result_id \"rad.analysisresultimp_sq.nextval\"
)
";

close CONFIG;
}

sub undoTables {
  my ($self) = @_;

  return ('RAD.AnalysisInput','RAD.AnalysisResultImp', 'RAD.AnalysisParam', 'RAD.ProtocolParam', 'RAD.Analysis', 'RAD.Protocol','RAD.LogicalGroupLink','RAD.LogicalGroup');
}

1;

