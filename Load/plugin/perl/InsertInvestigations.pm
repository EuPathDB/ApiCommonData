package ApiCommonData::Load::Plugin::InsertInvestigations;

@ISA = qw(GUS::PluginMgr::Plugin);
use GUS::PluginMgr::Plugin;
use strict;

use CBIL::ISA::Investigation;
use CBIL::ISA::InvestigationSimple;

use File::Basename;

use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::ProtocolApp;
use GUS::Model::Study::ProtocolAppParam;
use GUS::Model::Study::Input;
use GUS::Model::Study::Output;
use GUS::Model::Study::Protocol;
use GUS::Model::Study::ProtocolParam;
use GUS::Model::Study::Characteristic;
use GUS::Model::Study::StudyLink;
use GUS::Model::Study::Study;

use GUS::Model::SRes::OntologyTerm;

use CBIL::ISA::Investigation;
use CBIL::ISA::InvestigationSimple;

use Scalar::Util qw(blessed);
use POSIX qw/strftime/;
use File::Temp qw/ tempfile /;

use Data::Dumper;

my $argsDeclaration =
  [

   fileArg({name           => 'metaDataRoot',
            descr          => 'directory where to find directories of isa tab files',
            reqd           => 1,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),

   stringArg({name           => 'investigationBaseName',
            descr          => 'name of the investigation file',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),


   stringArg({name           => 'investigationSubset',
            descr          => 'Skip directory unless it is one of these',
            reqd           => 0,
            constraintFunc => undef,
            isList         => 1, }),

stringArg({name           => 'extDbRlsSpec',
            descr          => 'external database release spec',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),



   booleanArg({name => 'isSimpleConfiguration',
          descr => 'if true, use CBIL::ISA::InvestigationSimple',
          reqd => 1,
          constraintFunc => undef,
          isList => 0,
         }),


   booleanArg({name => 'skipDatasetLookup',
          descr => 'do not require existing nodes for datasets listed in isa files',
          reqd => 1,
          constraintFunc => undef,
          isList => 0,
         }),



   fileArg({name           => 'ontologyMappingFile',
            descr          => 'For InvestigationSimple Reader',
            reqd           => 0,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),

   fileArg({name           => 'valueMappingFile',
            descr          => 'For InvestigationSimple Reader',
            reqd           => 0,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),


   fileArg({name           => 'dateObfuscationFile',
            descr          => 'For InvestigationSimple Reader',
            reqd           => 0,
        mustExist      => 1,
        format         => '',
            constraintFunc => undef,
            isList         => 0, }),


   stringArg({name           => 'ontologyMappingOverrideFileBaseName',
            descr          => 'For InvestigationSimple Reader',
            reqd           => 0,
            constraintFunc => undef,
            isList         => 0, }),


   booleanArg({name => 'prefixProtocolNamesWithStudyIdentifier',
          descr => 'if true, prefix all protocol names with the study identifier before loading in database',
          reqd => 0,
          constraintFunc => undef,
          isList => 0,
         }),


  ];

my $documentation = { purpose          => "",
                      purposeBrief     => "",
                      notes            => "",
                      tablesAffected   => "",
                      tablesDependedOn => "",
                      howToRestart     => "",
                      failureCases     => "" };

# ----------------------------------------------------------------------
sub getIsReportMode { }

# ----------------------------------------------------------------------

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

# ======================================================================

sub run {
  my ($self) = @_;
  my $metaDataRoot = $self->getArg('metaDataRoot');
  my $investigationBaseName = $self->getArg('investigationBaseName');

  my $isReportMode = $self->getIsReportMode();

  my ($charFh, $charFile) = tempfile(SUFFIX => '.dat');

  my @investigationFiles;

  my $investigationSubset = $self->getArg('investigationSubset');
  if($investigationSubset) {
    @investigationFiles = map { "$metaDataRoot/$_/$investigationBaseName" } @$investigationSubset;
  }
  else {
    @investigationFiles = glob "$metaDataRoot/*/$investigationBaseName";
  }

  my $investigationCount;
  foreach my $investigationFile (@investigationFiles) {
    my $dirname = dirname $investigationFile;
    $self->log("Processing ISA Directory:  $dirname");

    # clear out the protocol app node hash
    $self->{_PROTOCOL_APP_NODE_MAP} = {};

    my $investigation;
    if($self->getArg('isSimpleConfiguration')) {
      my $valueMappingFile = $self->getArg('valueMappingFile');
      my $dateObfuscationFile = $self->getArg('dateObfuscationFile');

      my $ontologyMappingFile = $self->getArg('ontologyMappingFile');
      my $ontologyMappingOverrideFileBaseName = $self->getArg('ontologyMappingOverrideFileBaseName');
      my $overrideFile = $dirname . "/" . $ontologyMappingOverrideFileBaseName;

      $investigation = CBIL::ISA::InvestigationSimple->new($investigationFile, $ontologyMappingFile, $overrideFile, $valueMappingFile, undef, $isReportMode, $dateObfuscationFile);
    }
    else {
      $investigation = CBIL::ISA::Investigation->new($investigationBaseName, $dirname, "\t");
    }

    eval {
    $investigation->parseInvestigation();
    };
    if($@) {
      $self->logOrError($@);
      next;
    }

    my $investigationId = $investigation->getIdentifier();
    my $studies = $investigation->getStudies();

    my $hasDatasets;

    foreach my $study (@$studies) {
      my %isatabDatasets;

      my $studyAssays = $study->getStudyAssays();

      foreach my $studyAssay (@$studyAssays) {
        my $comments = $studyAssay->getComments();
        foreach my $comment (@$comments) {
          next unless($comment->getQualifier() eq 'dataset_names');
          my @datasetNames = split(/;/, $comment->getValue());
          foreach my $datasetName (@datasetNames) {
            $isatabDatasets{$datasetName}++;
          }
        }
      }

      my $datasetsMatchedInDbCount = $self->checkLoadedDatasets(\%isatabDatasets);

      if($datasetsMatchedInDbCount > 0) {
        $hasDatasets++;
      }
      $study->{_insert_investigations_datasets} = \%isatabDatasets;
    }

    if(!$hasDatasets && !$self->getArg('skipDatasetLookup')) {
      $self->log("Skipping Investigation $investigationId.  No matching datasets in database");
      next;
    }

    foreach my $study (@$studies) {

      while($study->hasMoreData()) {

        eval {
          $investigation->parseStudy($study);
          $investigation->dealWithAllOntologies();
        };
        if($@) {
          $self->logOrError($@);
          next;
        }

        my $isatabDatasets = $study->{_insert_investigations_datasets};

        $self->checkProtocolsAndSetIds($study->getProtocols(), $study);

        my $iOntologyTermAccessions = $investigation->getOntologyAccessionsHash();

        $self->checkOntologyTermsAndSetIds($iOntologyTermAccessions);

        my $investigationId = $self->loadInvestigation($investigation);


        $self->checkMaterialEntitiesHaveMaterialType($study->getNodes());


        $self->checkDatabaseNodesAreHandled($isatabDatasets, $study->getNodes());
        $self->checkDatabaseProtocolApplicationsAreHandledAndMark($isatabDatasets, $study->getEdges());
        $self->loadStudy($study,$investigationId, $charFh);
      }

      # clear out the protocol app node hash
      $self->{_PROTOCOL_APP_NODE_MAP} = {};
    }

    $investigationCount++;
  }

  my $errorCount = $self->{_has_errors};
  if($errorCount) {
    $self->error("FOUND $errorCount ERRORS!");
  }


  $self->loadCharacteristics($charFile);

  $self->logRowsInserted() if($self->getArg('commit'));

  return("Processed $investigationCount Investigations.");
}

sub countLines {
  my ($self, $charFile) = @_;
  open(FILE, "<", $charFile);
  my $count += tr/\n/\n/ while sysread(FILE, $_, 2 ** 16);
  close(FILE);
  return $count;
}

sub loadCharacteristics{
  my ($self, $charFile) = @_;
  my $configFile = "$charFile" . ".ctrl";
  my $logFile = "$charFile" . ".log";
  my @fields = (
    'CHARACTERISTIC_ID SEQUENCE(MAX,1)',
    'protocol_app_node_id',
    'qualifier_id',
    'unit_id',
    'value char(2000)',
    'ontology_term_id'
  );
  $self->writeConfigFile($configFile, $charFile, "Study.Characteristic", \@fields);

  my $login       = $self->getConfig->getDatabaseLogin();
  my $password    = $self->getConfig->getDatabasePassword();
  my $dbiDsn      = $self->getConfig->getDbiDsn();
  my ($dbi, $type, $db) = split(':', $dbiDsn);
  my $directMode = 'false';
  if ($self->countLines($charFile) > 100000){
      $directMode = 'true';
      $self->log("SQLLDR will use DIRECT path to load Characteristics\n");
  }
  if($self->getArg('commit')) {
      my $exitstatus = system("sqlldr $login/$password\@$db control=$configFile log=$logFile rows=1000 direct=$directMode");

      if($exitstatus != 0){
    die "ERROR: sqlldr returned exit status $exitstatus";
      }

      open(LOG, $logFile) or die "Cannot open log file $logFile: $!";

      while(<LOG>) {
    $self->log($_);
      }
      close LOG;

      unlink $logFile;
  }

  unlink $configFile;

  my $sequenceName = "Study.CHARACTERISTIC_sq";
  my $dbh = $self->getQueryHandle();
  my ($sequenceValue) = $dbh->selectrow_array("select ${sequenceName}.nextval from dual");
  my ($maxPrimaryKey) = $dbh->selectrow_array("select MAX(CHARACTERISTIC_ID) FROM Study.CHARACTERISTIC");
  my $sequenceDifference = $maxPrimaryKey - $sequenceValue;
  $self->log("Increasing CHARACTERISTIC_ID by $sequenceDifference\n");
  if($sequenceDifference > 0) {
    $dbh->do("alter sequence $sequenceName increment by $sequenceDifference");
    $dbh->do("select ${sequenceName}.nextval from dual");
    $dbh->do("alter sequence $sequenceName increment by 1");
  }

  return "Processed lines from data files";


}


sub lookupStudyLinks {
  my ($self, $studyId) = @_;

  my $dbh = $self->getQueryHandle();

  my %rv;

  my $sql = "select protocol_app_node_id from study.studylink where study_id = $studyId";

  my $sh = $dbh->prepare($sql);
  $sh->execute();
  while(my ($panId) = $sh->fetchrow_array()) {
    $rv{$panId}++;
  }

  return \%rv;
}


sub checkLoadedDatasets {
  my ($self, $isatabDatasets) = @_;

  my $dbh = $self->getQueryHandle();

  my $rv;

  foreach my $dataset (keys %$isatabDatasets) {
    my ($count) = $dbh->selectrow_array("select count(*) from apidb.datasource where name = '$dataset'");
    $rv++ if($count == 1);
  }

  return $rv;
}



sub checkMaterialEntitiesHaveMaterialType {
  my ($self, $nodes) = @_;

  foreach my $node (@$nodes) {
    my $value = $node->getValue();
    if($node->hasAttribute("Material Type")) {
      my $materialTypeOntologyTerm = $node->getMaterialType();
      $self->logOrError("Material Entitiy $value is required to have a [Material Type]");
    }
  }
}

sub checkProtocolsAndSetIds {
  my ($self, $protocols, $study) = @_;

  my $sql = "select name, protocol_id from study.protocol";

  my $dbh = $self->getQueryHandle();
  my $sh = $dbh->prepare($sql);
  $sh->execute();
  my %protocols;
  while(my ($protocol, $protocolId) = $sh->fetchrow_array()) {
    $protocols{$protocol} = $protocolId;
  }
  $sh->finish();

  foreach my $protocol (@$protocols) {
    my $protocolName = $protocol->getProtocolName();
    if ($self->getArg("prefixProtocolNamesWithStudyIdentifier")) {
      $protocolName = prefixProtocolName($protocolName, $study);
    }
    if($protocols{$protocolName}) {
      $protocol->{_PROTOCOL_ID} = $protocols{$protocolName};
    }
    else {
      $self->log("WARNING:  Protocol [$protocolName] Not found in the database ... adding") ;
    }
  }
}

sub loadStudy {
  my ($self, $study, $investigationId, $charFh) = @_;

  my $extDbRlsId = $self->{_external_database_release_id};

  my $identifier = $study->getIdentifier();
#  my $title = $study->getTitle();

  my $description = $study->getDescription();

  my $gusStudy = GUS::Model::Study::Study->new({name => $identifier, source_id => $identifier, investigation_id =>$investigationId, external_database_release_id=>$extDbRlsId});
  $gusStudy->submit() unless ($gusStudy->retrieveFromDB());

  $gusStudy->setDescription($description);

### DISABLE CONSTRAINTS
  my $panNameToIdMap = $self->loadNodes($study->getNodes(), $gusStudy, $charFh);

  my ($protocolParamsToIdMap, $protocolNamesToIdMap) = $self->loadProtocols($study->getProtocols(), $study);

  $self->loadEdges($study->getEdges, $panNameToIdMap, $protocolParamsToIdMap, $protocolNamesToIdMap, $study);
### ENABLE CONSTRAINTS
}


sub loadNodes {
  my ($self, $nodes, $gusStudy, $charFh) = @_;

  my %rv;

  my $gusStudyId = $gusStudy->getId();

  my $slPanIds = $self->lookupStudyLinks($gusStudyId);

  my $nodeCount = 0;
  $self->getDb()->manageTransaction(0, 'begin');

  foreach my $node (@$nodes) {
    my $pan;

    my @charsForLoader;

    my $studyLinksAlreadyExist;

    if(my $panId = $node->{_PROTOCOL_APP_NODE_ID}) {
      $pan = GUS::Model::Study::ProtocolAppNode->new({protocol_app_node_id => $panId});
      unless($pan->retrieveFromDB()) {
        $self->error("Could not retrieve ProtocolAppNode [$panId] w/ name " . $node->getValue());
      }

      if($slPanIds->{$panId}) {
        $studyLinksAlreadyExist = 1;
      }

    }
    else {
      $pan = GUS::Model::Study::ProtocolAppNode->new({name => $node->getValue()});
      my $isaClassName = ref($node);
      my($isaType) = $isaClassName =~ /\:\:(\w+)$/;
      $pan->setIsaType($isaType);

      if($node->hasAttribute("Description")) {
        $pan->setDescription($node->getDescription());
      }
    }

    unless($studyLinksAlreadyExist) {
      my $gusStudyLink = GUS::Model::Study::StudyLink->new();
      $gusStudyLink->setParent($gusStudy);
      $gusStudyLink->setParent($pan);

      my $gusInvestigationLink = GUS::Model::Study::StudyLink->new();
      $gusInvestigationLink->setStudyId($gusStudy->getInvestigationId());
      $gusInvestigationLink->setParent($pan);
    }

    if($node->hasAttribute("MaterialType")) {
      my $materialTypeOntologyTerm = $node->getMaterialType();
      my $gusOntologyTerm = $self->getOntologyTermGusObj($materialTypeOntologyTerm, 0);
      my $ontologyTermId = $gusOntologyTerm->getId();
      $pan->setTypeId($ontologyTermId); # CANNOT Set Parent because OntologyTerm Table has type and subtype.  Both have fk to Sres.ontologyterm

      my $characteristics = $node->getCharacteristics();

      foreach my $characteristic (@$characteristics) {
        if(lc $characteristic->getTermSourceRef() eq 'ncbitaxon') {
          my $taxonId = $self->{_ontology_term_to_identifiers}->{$characteristic->getTermSourceRef()}->{$characteristic->getTermAccessionNumber()};
          $pan->setTaxonId($taxonId);
        }

    #   my $gusChar = GUS::Model::Study::Characteristic->new();
    #   $gusChar->setParent($pan);

        my $charQualifierOntologyTerm = $self->getOntologyTermGusObj($characteristic, 1);
        my $charQualifierId = $charQualifierOntologyTerm->getId();

      # ALWAYS Set the qualifier_id

    #   $gusChar->setQualifierId($charQualifierOntologyTerm->getId()); # CANNOT SET Parent because ontology term id and Unit id.  both fk to sres.ontologyterm

        my $charUnitId;

        if($characteristic->getUnit()) {
          my $unitOntologyTerm = $self->getOntologyTermGusObj($characteristic->getUnit(), 0);
    #     $gusChar->setUnitId($unitOntologyTerm->getId());
          $charUnitId = $unitOntologyTerm->getId();
        }

        my ($charValue, $charOntologyTermId);

        if(lc $characteristic->getTermSourceRef() eq 'ncbitaxon') {
          my $value = $self->{_ontology_term_to_names}->{$characteristic->getTermSourceRef()}->{$characteristic->getTermAccessionNumber()};
    #     $gusChar->setValue($value);
          $charValue = $value;
        }
        elsif($characteristic->getTermAccessionNumber() && $characteristic->getTermSourceRef()) {
          my $valueOntologyTerm = $self->getOntologyTermGusObj($characteristic, 0);
    #     $gusChar->setOntologyTermId($valueOntologyTerm->getId());
              $charOntologyTermId = $valueOntologyTerm->getId();
        }
        else {
    #     $gusChar->setValue($characteristic->getTerm());
              $charValue = $characteristic->getTerm();
        }

        # strip off carriage return
        $charValue =~ s/\r//;


    #   print $charFh join("\t", ($pan->getId(),
        push @charsForLoader, [$charQualifierId, $charUnitId, $charValue, $charOntologyTermId];

      }
    }

    $pan->submit(undef, 1);

    # keep the cache up to date as we add new nodes
    $self->{_PROTOCOL_APP_NODE_MAP}->{$pan->getName()} = $pan->getId();

    $rv{$pan->getName()} = $pan->getId();

    foreach my $charForLoader(@charsForLoader) {
      print $charFh $pan->getId() . "\t" . join("\t", @$charForLoader) . "\n";
    }

    $self->undefPointerCache();

    if($nodeCount++ % 1000 == 0) {
      $self->getDb()->manageTransaction(0, 'commit');
      $self->getDb()->manageTransaction(0, 'begin');
    }

  }

  $self->getDb()->manageTransaction(0, 'commit');

  return \%rv;
}

sub getOntologyTermGusObj {
    my ($self, $ontologyTerm, $isCharQualifier) = @_;

    my $ontologyTermTerm = $ontologyTerm->getTerm();
    my $ontologyTermClass = blessed($ontologyTerm);
    my $ontologyTermAccessionNumber = $ontologyTerm->getTermAccessionNumber();
    my $ontologyTermSourceRef = $ontologyTerm->getTermSourceRef();

    $self->logDebug("OntologyTerm=$ontologyTermTerm\tClass=$ontologyTermClass\tAccession=$ontologyTermAccessionNumber\tSource=$ontologyTermSourceRef\n");

    my $ontologyTermId;
    if($ontologyTermClass eq 'CBIL::ISA::StudyAssayEntity::Characteristic' && $isCharQualifier) {
      my $qualifier = $ontologyTerm->getQualifier();
      $ontologyTermId = $self->{_ontology_term_to_identifiers}->{CHARACTERISTIC_QUALIFIER}->{$qualifier};
      $self->userError("No ontology entry found for qualifier [$qualifier]") unless($ontologyTermId);
    }
    elsif($ontologyTermAccessionNumber && $ontologyTermSourceRef) {
      $ontologyTermId = $self->{_ontology_term_to_identifiers}->{$ontologyTermSourceRef}->{$ontologyTermAccessionNumber};
      $self->userError("No ontology entry found for $ontologyTermSourceRef and $ontologyTermAccessionNumber") unless($ontologyTermId);
    }
    else {
      $self->logOrError("OntologyTerm of class $ontologyTermClass and value [$ontologyTermTerm] must provide accession&source OR a qualifier in the case of Characteristics must map to an ontologyterm");
    }


    if(my $gusObj = $self->{_gus_ontologyterm_objects}->{$ontologyTermId}) {
      return $gusObj;
    }

    my $gusOntologyTerm = GUS::Model::SRes::OntologyTerm->new({ontology_term_id => $ontologyTermId});
    unless($gusOntologyTerm->retrieveFromDB()) {
      $self->error("ERROR:  Found TaxonID ($ontologyTermId).  Was expecting OntologyTerm ID");
    }

    $self->{_gus_ontologyterm_objects}->{$ontologyTermId} = $gusOntologyTerm;
    return $gusOntologyTerm;
}


sub loadProtocols {
  my ($self, $protocols, $study) = @_;


  my $ppNameToId = {};
  my $pNameToId = {};

  foreach my $protocol (@$protocols) {
    my $protocolId = $protocol->{_PROTOCOL_ID};
    my $gusProtocol;

    my $protocolName = $protocol->getProtocolName();
    if ($self->getArg("prefixProtocolNamesWithStudyIdentifier")) {
      $protocolName = prefixProtocolName($protocolName, $study);
    }
    if($protocolId) {
      $gusProtocol = GUS::Model::Study::Protocol->new({protocol_id => $protocolId});
      unless($gusProtocol->retrieveFromDB()) {
        $self->error("Could not retrieve Study.Protocol w/ protoocl id [$protocolId]");
      }
    }
    else {
      my $protocolDescription = $protocol->getProtocolDescription();
      $gusProtocol = GUS::Model::Study::Protocol->new({name => $protocolName, description => $protocolDescription});

      if($protocol->getProtocolType()) {
        my $gusProtocolType = $self->getOntologyTermGusObj($protocol->getProtocolType(), 0);
        $gusProtocol->setParent($gusProtocolType);
      }
    }

    my @gusProtocolParams = $gusProtocol->getChildren("Study::ProtocolParam", 1);
    my $protocolParams = $protocol->getProtocolParameters();

#    next if (scalar (@$protocolParams) == 0);


    foreach my $protocolParam (@$protocolParams) {
      my $found;
      my $protocolParamSourceId = $protocolParam->getTermAccessionNumber();
      my $protocolParamTerm = $protocolParam->getTerm();

      unless ($self->{_protocol_param_source_id_to_name}->{$protocolParamSourceId}) {
        my $protocolParamOntologyTerm = GUS::Model::SRes::OntologyTerm->new({source_id=> $protocolParamSourceId, });
        unless($protocolParamOntologyTerm->retrieveFromDB()) {
          $self->error("Could not retrieve Sres.OntologyTerm for protocolParam $protocolParamSourceId");
        }
        $self->{_protocol_param_source_id_to_name}->{$protocolParamSourceId} = $protocolParamOntologyTerm->getName();
      }

      foreach my $gusProtocolParam (@gusProtocolParams) {
        if($gusProtocolParam->getName() eq $self->{_protocol_param_source_id_to_name}->{$protocolParamSourceId}) {
          $found = 1;
          last;
        }
      }

      unless($found) {
        my $gusProtocolParam = GUS::Model::Study::ProtocolParam->new({name => $self->{_protocol_param_source_id_to_name}->{$protocolParam->getTermAccessionNumber()}});
        $gusProtocolParam->setParent($gusProtocol);
      }
    }

    $gusProtocol->submit();
    $pNameToId->{$protocolName} = $gusProtocol->getId();

    foreach my $pp ($gusProtocol->getChildren("Study::ProtocolParam")) { # no need to retrieve here
      my $ppName = $pp->getName();
      my $ppId = $pp->getId();
      $ppNameToId->{$protocolName}->{$ppName} = $ppId;
    }
  }
  return($ppNameToId, $pNameToId);
}


sub loadEdges {
  my ($self, $edges, $panNameToIdMap, $protocolParamsToIdMap, $protocolNamesToIdMap, $study) = @_;


  my $edgeCount;
  $self->getDb()->manageTransaction(0, 'begin');

  foreach my $edge (@$edges) {
    my $databaseStatus = $edge->{_DATABASE_STATUS};
    my $protocolAppId = $edge->{_PROTOCOL_APP_ID};

    my $gusProtocolApp;
    my $protocolCount = 1;

    if($protocolAppId) {
      $gusProtocolApp = GUS::Model::Study::ProtocolApp->new({protocol_app_id => $protocolAppId});
      unless($gusProtocolApp->retrieveFromDB()) {
        $self->error("Could not retrieve Study.protocolApp w/ protocol_ap_id [$protocolAppId]");
      }
    }
    else {
      $gusProtocolApp = GUS::Model::Study::ProtocolApp->new();

      $protocolCount = scalar @{$edge->getProtocolApplications()};

      my $protocolName;

      my $gusProtocol;

      if($protocolCount > 1) {
        my @protocolNames = map { $_->getProtocol()->getProtocolName() } @{$edge->getProtocolApplications()};
	if ($self->getArg("prefixProtocolNamesWithStudyIdentifier")) {
	  @protocolNames = map { prefixProtocolName($_, $study) } @protocolNames;
	}
        $protocolName = join("; ", @protocolNames);
      }
      else {
        $protocolName = $edge->getProtocolApplications()->[0]->getProtocol()->getProtocolName();
      }

      my $gusProtocolId;
      if($gusProtocolId = $protocolNamesToIdMap->{$protocolName}) {
#        $gusProtocol = GUS::Model::Study::Protocol->new({protocol_id => $gusProtocolId});
#        unless($gusProtocol->retrieveFromDB()) {
#          $self->error("Could not retrieve protocol w/ protocol id of [$gusProtocolId]");
#        }
      }
      else {
        $gusProtocol = GUS::Model::Study::Protocol->new({name => $protocolName});
        $gusProtocol->retrieveFromDB(); # try to retrieve it

        $self->getDb()->manageTransaction(0, 'commit');
        $gusProtocol->submit();
        $self->getDb()->manageTransaction(0, 'begin');

        $gusProtocolId = $gusProtocol->getId();
        $protocolNamesToIdMap->{$protocolName} = $gusProtocolId;
      }

      $gusProtocolApp->setProtocolId($gusProtocolId);
    }

    if($databaseStatus) {
      $self->error("Edge DATABASE_STATUS set but missing protocol_app_id") unless($gusProtocolApp);
    }

    foreach my $output (@{$edge->getOutputs()}) {
      next if($databaseStatus);

      my $gusOutput = GUS::Model::Study::Output->new();

      my $outputName = $output->getValue();
      my $outputId = $panNameToIdMap->{$outputName};
      unless($outputId) {
        $self->error("No protocol app node id found for output $outputName");
      }
      $gusOutput->setProtocolAppNodeId($outputId);
      $gusProtocolApp->addToSubmitList($gusOutput);
      $gusOutput->setParent($gusProtocolApp);
    }

    foreach my $input (@{$edge->getInputs()}) {
      next if($databaseStatus eq 'FOUND_OUTPUTS_AND_INPUTS');

      my $gusInput = GUS::Model::Study::Input->new();

      my $inputName = $input->getValue();
      my $inputId = $panNameToIdMap->{$inputName};
      unless($inputId) {
        $self->error("No protocol app node id for input $inputName");
      }
      $gusInput->setProtocolAppNodeId($inputId);

      $gusInput->setParent($gusProtocolApp);
      $gusProtocolApp->addToSubmitList($gusInput);
    }

    my %existingProtocolAppParam;
    my @gusProtocolAppParams = $gusProtocolApp->getChildren("Study::ProtocolAppParam", 1); # go to the database and get all the children
    foreach my $gusProtocolAppParam (@gusProtocolAppParams) {
      my $gusProtocolParam = $gusProtocolAppParam->getParent("Study::ProtocolParam", 1);
      $existingProtocolAppParam{$gusProtocolParam->getName()} = 1;
    }

    # in the database we have one row in protocolapp w/ pointer to a protocol
    foreach my $protocolApp (@{$edge->getProtocolApplications()}) {
      my $protocol = $protocolApp->getProtocol();
      my $protocolName = $protocol->getProtocolName();
      if ($self->getArg("prefixProtocolNamesWithStudyIdentifier")) {
	$protocolName = prefixProtocolName($protocolName, $study);
      }

      foreach my $parameterValue (@{$protocolApp->getParameterValues()}) {

        my $ppValue = $parameterValue->getTerm();
        my $ppName = $self->{_protocol_param_source_id_to_name}->{$parameterValue->getQualifier()};

        next if($existingProtocolAppParam{$ppName}); #NOTE:  This is a bit easier because we don't deal w/ protocol series for existing protocolapps
        my $gusProtocolParamId = $protocolParamsToIdMap->{$protocolName}->{$ppName};
        unless($gusProtocolParamId) {
          $self->error("Could not find protocol param id for protocol [$protocolName] and protocolParam name [$ppName]");
        }

        my $gusProtocolAppParam = GUS::Model::Study::ProtocolAppParam->new({protocol_param_id => $gusProtocolParamId, value => $ppValue});
        $gusProtocolAppParam->setParent($gusProtocolApp);
      }
    }
    $gusProtocolApp->submit(undef, 1);
    $self->undefPointerCache();


    if($edgeCount++ % 1000 == 0) {
      $self->getDb()->manageTransaction(0, 'commit');
      $self->getDb()->manageTransaction(0, 'begin');
    }
  }

  $self->getDb()->manageTransaction(0, 'commit');
}



sub checkDatabaseProtocolApplicationsAreHandledAndMark {
  my ($self, $foundDatasets, $edges) = @_;


  my $sql = "select distinct * from (
select d.name dataset, p.name protocol, pa.PROTOCOL_APP_ID, pan.name, pan.protocol_app_node_id, 'input' as io
from study.protocolapp pa
   , study.protocol p
   , study.input i
   , study.protocolappnode pan
   , study.studylink sl
   , study.study s
   , study.study i
   , SRES.EXTERNALDATABASE d
   , sres.externaldatabaserelease r
where pa.PROTOCOL_ID = p.protocol_id
and pa.PROTOCOL_APP_ID = i.PROTOCOL_APP_ID
and i.PROTOCOL_APP_NODE_ID = pan.PROTOCOL_APP_NODE_ID
and pan.PROTOCOL_APP_NODE_ID = sl.PROTOCOL_APP_NODE_ID
and sl.STUDY_ID = s.study_id
and s.EXTERNAL_DATABASE_RELEASE_ID = r.EXTERNAL_DATABASE_RELEASE_ID
and r.EXTERNAL_DATABASE_ID = d.external_database_id
union
select d.name dataset, p.name protocol, pa.PROTOCOL_APP_ID, pan.name, pan.protocol_app_node_id, 'output' as io
from study.protocolapp pa
   , study.protocol p
   , study.Output i
   , study.protocolappnode pan
   , study.studylink sl
   , study.study s
   , study.study i
   , SRES.EXTERNALDATABASE d
   , sres.externaldatabaserelease r
where pa.PROTOCOL_ID = p.protocol_id
and pa.PROTOCOL_APP_ID = i.PROTOCOL_APP_ID
and i.PROTOCOL_APP_NODE_ID = pan.PROTOCOL_APP_NODE_ID
and pan.PROTOCOL_APP_NODE_ID = sl.PROTOCOL_APP_NODE_ID
and sl.STUDY_ID = s.study_id
and s.EXTERNAL_DATABASE_RELEASE_ID = r.EXTERNAL_DATABASE_RELEASE_ID
and r.EXTERNAL_DATABASE_ID = d.external_database_id
)
where dataset = ? ";

  my $dbh = $self->getQueryHandle();
  my $sh = $dbh->prepare($sql);

  my $databaseEdges = {};

  foreach my $datasetName(keys %$foundDatasets) {
    $sh->execute($datasetName);
    while(my ($dataset, $protocol, $protocolAppId, $pan, $panId, $io) = $sh->fetchrow_array()) {
      push @{$databaseEdges->{$protocol}->{$protocolAppId}->{$io}}, $pan;
    }
    $sh->finish();
  }

  foreach my $databaseProtocol (keys %$databaseEdges) {
    foreach my $protocolAppId (keys %{$databaseEdges->{$databaseProtocol}}) {

      next unless($databaseEdges->{$databaseProtocol}->{$protocolAppId}->{output});

      my @databaseOutputs = sort @{$databaseEdges->{$databaseProtocol}->{$protocolAppId}->{output}};

      my $found;

      foreach my $edge (@$edges) {
        my $protocolApps = $edge->getProtocolApplications();

        # Not in the business of matching protocol series.
        next if(scalar @$protocolApps > 1);
        my $protocolApp = $protocolApps->[0];

        next unless($databaseProtocol eq $protocolApp->getValue());

        my @outputs = sort map { $_->getValue()} @{$edge->getOutputs()};
        next unless(join(".", @outputs) eq join(".", @databaseOutputs));

        $found++;
        $edge->{_DATABASE_STATUS} = 'FOUND_OUTPUTS';
        $edge->{_PROTOCOL_APP_ID} = $protocolAppId;

        if($databaseEdges->{$databaseProtocol}->{$protocolAppId}->{input}) {
          my @databaseInputs = sort @{$databaseEdges->{$databaseProtocol}->{$protocolAppId}->{input}};
          my @inputs = sort map {$_->getValue()} @{$edge->getInputs()};

          if(join(".", @inputs) eq join(".", @databaseInputs)) {
            $edge->{_DATABASE_STATUS} = 'FOUND_OUTPUTS_AND_INPUTS';
          }
          else {


            $self->logOrError("ISATAB_ERROR:  Inputs found for ProtocolApp [$protocolApp] but they do not match the Inputs defined for this Edge in the ISA Tab File");
          }
        }
      }

#      $self->logOrError("ISATAB_ERROR:  ProtocolApp [$protocolAppId] could not be matched to Edges in the ISA Tab file") unless($found);
    }
  }
}


sub checkOntologyTermsAndSetIds {
  my ($self, $iOntologyTermAccessionsHash) = @_;

  my $sql = "select 'OntologyTerm', ot.source_id, ot.ontology_term_id id, name
from sres.ontologyterm ot
where ot.source_id = ?
and lower(ot.source_id) not like 'ncbitaxon%'
UNION
select 'NCBITaxon', 'NCBITaxon_' || t.ncbi_tax_id, t.taxon_id id, tn.name
from sres.taxon t, sres.taxonname tn
where 'NCBITaxon_' || t.ncbi_tax_id = ?
and lower(?) like  'ncbitaxon%'
and t.taxon_id = tn.taxon_id
and tn.name_class = 'scientific name'
";

  my $dbh = $self->getQueryHandle();
  my $sh = $dbh->prepare($sql);

  my $rv = {};
  my $oeToName = {};


  foreach my $os (keys %$iOntologyTermAccessionsHash) {

    foreach my $ota (keys %{$iOntologyTermAccessionsHash->{$os}}) {
      my $accessionOrName = basename $ota;
      $sh->execute($accessionOrName, $accessionOrName, $accessionOrName);
      my $count=0;
      my ($ontologyTermId, $ontologyTermName);
      while(my ($dName, $sourceId, $id, $name) = $sh->fetchrow_array()) {
        $ontologyTermId = $id;
        $ontologyTermName = $name;
    $count++;
      }
      $sh->finish();
      if($count == 1) {
        $rv->{$os}->{$ota} = $ontologyTermId;

        $oeToName->{$os}->{$ota} = $ontologyTermName;

      }
      else {
        $self->logOrError("ERROR:  OntologyTerms with Accession Or Name [$accessionOrName] were not found or were not found uniquely in the database");

      }
    }
  }

  $self->{_ontology_term_to_identifiers} = $rv;
  $self->{_ontology_term_to_names} = $oeToName;
}

sub checkDatabaseNodesAreHandled {
  my ($self, $foundDatasets, $nodes) = @_;

  unless(scalar keys %$foundDatasets > 0) {
    $self->logOrError("ISATAB_ERROR:  Required Comment[dataset_name] for assay not found");
  }

  my $sql = "select pan.name, pan.protocol_app_node_id
from SRES.EXTERNALDATABASE d
   , SRES.EXTERNALDATABASERELEASE r
   , study.study i
   , study.study ps
   , study.studylink sl
   , STUDY.PROTOCOLAPPNODE pan
where d.name = ?
 and d.EXTERNAL_DATABASE_ID = r.EXTERNAL_DATABASE_ID
 and r.EXTERNAL_DATABASE_RELEASE_ID = i.EXTERNAL_DATABASE_RELEASE_ID
 and i.STUDY_ID = ps.INVESTIGATION_ID
 and ps.study_id = sl.study_id
 and sl.PROTOCOL_APP_NODE_ID = pan.PROTOCOL_APP_NODE_ID
 UNION
select pan.name, pan.protocol_app_node_id
from SRES.EXTERNALDATABASE d
   , SRES.EXTERNALDATABASERELEASE r
   , study.study i
    , study.studylink sl
   , STUDY.PROTOCOLAPPNODE pan
where d.name = ?
 and d.EXTERNAL_DATABASE_ID = r.EXTERNAL_DATABASE_ID
 and r.EXTERNAL_DATABASE_RELEASE_ID = i.EXTERNAL_DATABASE_RELEASE_ID
 and i.STUDY_ID = sl.study_id
 and sl.PROTOCOL_APP_NODE_ID = pan.PROTOCOL_APP_NODE_ID";



  unless(scalar(keys(%{$self->{_PROTOCOL_APP_NODE_MAP}})) > 0) {
    my $dbh = $self->getQueryHandle();
    my $sh = $dbh->prepare($sql);

    my %studyNodes;

    foreach my $datasetName(keys %$foundDatasets) {
      $sh->execute($datasetName, $datasetName);

      while(my ($pan, $panId) = $sh->fetchrow_array()) {
        if($studyNodes{$datasetName}->{$pan}) {

          $self->logOrError("DATABASE_ERROR:  Existing ProtocolAppNode name $pan not unique w/in a study");
        }

        $studyNodes{$datasetName}->{$pan} = 1;

        $self->{_PROTOCOL_APP_NODE_MAP}->{$pan} = $panId;

      }
      $sh->finish();
    }
  }

  foreach my $node (@$nodes) {
    my $nodeName = $node->getValue();
    $node->{_PROTOCOL_APP_NODE_ID} = $self->{_PROTOCOL_APP_NODE_MAP}->{$nodeName};
  }

}

sub logOrError {
  my ($self, $msg) = @_;

  $self->{_has_errors}++;

  if($self->getArg('commit')) {
    $self->userError($msg);
  }
  else {
    $self->log($msg);
  }
}

sub loadInvestigation{
  my ($self, $study) = @_;

  my $extDbRlsSpec = $self->getArg('extDbRlsSpec');
  my $extDbRlsId = $self->getExtDbRlsId($extDbRlsSpec);

  $self->{_external_database_release_id} = $extDbRlsId;

  my $identifier = $study->getIdentifier();
 # my $title = $study->getTitle();

  my $description = $study->getDescription();

  my $gusStudy = GUS::Model::Study::Study->new({name => $identifier, description => $description, source_id => $identifier, external_database_release_id =>$extDbRlsId});
  $gusStudy->submit() unless($gusStudy->retrieveFromDB());
  return $gusStudy->getId();

}


sub writeConfigFile {
  my ($self, $configFile, $dataFile, $table, $fieldsArray) = @_;

  my $modDate = uc(strftime("%d-%b-%Y", localtime));
  my $fields = join(",\n", @$fieldsArray);
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

  open(CONFIG, "> $configFile") or die "Cannot open file $configFile For writing:$!";

  print CONFIG "LOAD DATA
INFILE '$dataFile'
APPEND
INTO TABLE Study.Characteristic
REENABLE DISABLED_CONSTRAINTS
FIELDS TERMINATED BY '\\t'
TRAILING NULLCOLS
(
$fields,
modification_date constant \"$modDate\",
user_read constant $userRead,
user_write constant $userWrite,
group_read constant $groupRead,
group_write constant $groupWrite,
other_read constant $otherRead,
other_write constant $otherWrite,
row_user_id constant $userId,
row_group_id constant $groupId,
row_project_id constant $projectId,
row_alg_invocation_id constant $algInvocationId
)\n";
  close CONFIG;
}

sub getConfig {
  my ($self) = @_;

  if (!$self->{config}) {
    my $gusConfigFile = $self->getArg('gusconfigfile');
     $self->{config} = GUS::Supported::GusConfig->new($gusConfigFile);
   }

  $self->{config};
}



sub undoTables {
  my ($self) = @_;

  return (
    'Study.Input',
    'Study.Output',
    'Study.Characteristic',
    'Study.StudyLink',
    'Study.ProtocolAppNode',
    'Study.ProtocolAppParam',
    'Study.ProtocolApp',
    'Study.ProtocolParam',
    'Study.Study',
     );
}


#
# helper function to prefix the protocolName with
# the study identifier, separated with a '|'
#
sub prefixProtocolName {
  my ($protocolName, $study) = @_;
  return join '|', $study->getIdentifier(), $protocolName;
}


1;

