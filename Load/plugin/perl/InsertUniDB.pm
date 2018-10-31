package ApiCommonData::Load::Plugin::InsertUniDB;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use GUS::PluginMgr::Plugin;

use DBI;
use DBD::Oracle;

use GUS::Model::ApiDB::DATABASETABLEMAPPING;

use File::Temp qw/ tempfile /;

use Data::Dumper;

use POSIX qw(mkfifo);

use Fcntl;

my $END_OF_RECORD_DELIMITER = "#EOR#\n";
my $END_OF_COLUMN_DELIMITER = "#EOC#\t";

my $START_OF_LOB_DELIMITER = "<startlob>";
my $END_OF_LOB_DELIMITER = "<endlob>";

my $MAPPING_TABLE_NAME = "ApiDB.DatabaseTableMapping";
my $PROJECT_INFO_TABLE = "Core.ProjectInfo";
my $TABLE_INFO_TABLE = "Core.TableInfo";

my $PLACEHOLDER_STRING = "PLACEHOLDER_STRING";

# CLOB data in here requires some hand holding
my $NA_SEQUENCE_TABLE_NAME = "DoTS.NASequenceImp";

my %GLOBAL_UNIQUE_FIELDS = ("GUS::Model::Core::ProjectInfo" => ["name", "release"],
                            "GUS::Model::Core::TableInfo" => ["name", "database_id"],
                            "GUS::Model::Core::DatabaseInfo" => ["name"],
                            "GUS::Model::Core::DatabaseVersion" => ["version"],
                            "GUS::Model::Core::GroupInfo" => ["name"],
                            "GUS::Model::Core::UserInfo" => ["login"],
                            "GUS::Model::Core::UserProject" => ["user_id", "project_id"],
                            "GUS::Model::Core::UserGroup" => ["user_id", "group_id"],
                            "GUS::Model::Core::Algorithm" => ["name"],
                            "GUS::Model::Core::AlgorithmImplementation" => ["executable", "cvs_revision"], 
                            "GUS::Model::DoTS::AASequenceImp" => ["source_id", "external_database_release_id"],
                            "GUS::Model::DoTS::BLATAlignmentQuality" => ["name"],
                            "GUS::Model::SRes::ExternalDatabase" => ["name"],
                            "GUS::Model::SRes::ExternalDatabaseRelease" => ["external_database_id", "version"],
                            "GUS::Model::SRes::OntologyTerm" => ["source_id", "name", "external_database_release_id"],
                            "GUS::Model::SRes::OntologySynonym" => ["ontology_term_id", "ontology_synonym"],
                            "GUS::Model::SRes::OntologyRelationship" => ["subject_term_id", "object_term_id", "predicate_term_id", "external_database_release_id"],
                            "GUS::Model::SRes::OntologyTermType" => ["name"],
                            "GUS::Model::SRes::EnzymeClass" => ["ec_number"],
                            "GUS::Model::SRes::Taxon" => ["ncbi_tax_id"],
                            "GUS::Model::SRes::TaxonName" => ["taxon_id", "name"],
                            "GUS::Model::SRes::EnzymeClassAttribute" => ["enzyme_class_id", "attribute_value"],
                            "GUS::Model::SRes::GeneticCode" => ["name"],
                            "GUS::Model::SRes::DbRef" => ["primary_identifier", "secondary_identifier", "external_database_release_id"],
                            "GUS::Model::ApiDB::GoSubset" => ["go_subset_term", "ontology_term_id", "external_database_release_id"],
                            "GUS::Model::ApiDB::IsolateGPS" => ["gazetteer_id"],
                            "GUS::Model::ApiDB::EcNumberGenus" => ["ec_number", "genus"],
                            "GUS::Model::ApiDB::Datasource" => ["name"],
                            "GUS::Model::Study::Protocol" => ["name"],
                            "GUS::Model::Study::ProtocolParam" => ["protocol_id", "name"],
    );


my $HOUSEKEEPING_FIELDS = ['modification_date',
                           'user_read',
                           'user_write',
                           'group_read',
                           'group_write',
                           'other_read',
                           'other_write',
                           'row_user_id',
                           'row_group_id',
                           'row_alg_invocation_id',
                           'row_project_id',
    ];



# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
  my $argsDeclaration  =
    [
   fileArg({name           => 'logDir',
            descr          => 'directory where to log sqlldr output',
            reqd           => 1,
            mustExist      => 1,
            format         => '',
            constraintFunc => undef,
            isList         => 0, }),

     stringArg ({ name => 'database',
                  descr => 'gus oracle instance name (plas-inc), directory or files or possibly mysql database depending on the table_reader below',
                  constraintFunc => undef,
                  reqd => 0,
                  isList => 0 
                }),

     stringArg ({ name => 'table_reader',
                  descr => 'perl class which will serve out full rows to this plugin.  Example ApiCommonData::Load::GUSTableReader',
                  constraintFunc => undef,
                  reqd => 1,
                  isList => 0 
                }),


     stringArg ({ name => 'pk_table_reader',
                  descr => 'perl class which will serve out primary_keys to this plugin for undo context.  Example ApiCommonData::Load::GUSPrimaryKeyTableReader',
                  constraintFunc => undef,
                  reqd => 0,
                  isList => 0 
                }),


     booleanArg({
       name            =>  'skipUndo', 
       descr           =>  'skip undo method if set',
       reqd            =>  0,
       isList          =>  0
                }),


     booleanArg({
       name            =>  'rebuildIndexsAndEnableConstraintsOnly', 
       descr           =>  'if true, only rebuild indexes and reenable R/P constraints',
       reqd            =>  0,
       isList          =>  0
                }),


    ];

  return $argsDeclaration;
}


# ----------------------------------------------------------
# Documentation
# ----------------------------------------------------------

sub getDocumentation {

  my $description = <<DESCR;
Plugin to load UniDB Database
DESCR

  my $purpose = <<PURPOSE;
Plugin to load UniDB Database
PURPOSE

  my $purposeBrief = <<PURPOSEBRIEF;
Plugin to load UniDB Database
PURPOSEBRIEF

  my $notes = <<NOTES;
NOTES

  my $tablesAffected = <<AFFECT;
The whole shebang
AFFECT

  my $tablesDependedOn = <<TABD;
TABD

  my $howToRestart = <<RESTART;
Can be restarted
RESTART

  my $failureCases = <<FAIL;
Run again
FAIL

  my $documentation = { purpose          => $purpose,
                        purposeBrief     => $purposeBrief,
                        tablesAffected   => $tablesAffected,
                        tablesDependedOn => $tablesDependedOn,
                        howToRestart     => $howToRestart,
                        failureCases     => $failureCases,
                        notes            => $notes
                      };

  return ($documentation);
}


sub getActiveForkedProcesses {
  my ($self) = @_;

  return $self->{_active_forked_processes} || [];
}

sub addActiveForkedProcess {
  my ($self, $pid) = @_;

  push @{$self->{_active_forked_processes}}, $pid;
}

sub resetActiveForkedProcesses {
  my ($self) = @_;

  $self->{_active_forked_processes} = [];
}


sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);

  my $documentation = &getDocumentation();

  my $args = &getArgsDeclaration();

  my $configuration = { requiredDbVersion => 4.0,
#                        cvsRevision => '$Revision$',
		      cvsRevision       => '$Revision$',
                        name => ref($self),
                        argsDeclaration => $args,
                        documentation => $documentation
                      };

  $self->initialize($configuration);

  return $self;
}

sub error {
  my ($self, $msg) = @_;
  print STDERR "\nERROR: $msg\n";

  foreach my $pid (@{$self->getActiveForkedProcesses()}) {
    kill(9, $pid); 
  }

  $self->SUPER::error($msg);
}


sub makeReaderObj {
  my ($database, $readerClass) = @_;

  eval "require $readerClass";
  die $@ if $@;  

  my $reader = eval {
    $readerClass->new($database);
  };
  die $@ if $@;

  return $reader;
}


sub rebuildIndexesAndEnableConstraints {
  my ($self, $tableInfo) = @_;

  my $fullTableName = $tableInfo->{fullTableName};
  my $abbreviatedTablePeriod = &getAbbreviatedTableName($fullTableName, ".");

  $self->log("Rebuilding Indexes on Table $abbreviatedTablePeriod");

  my ($owner, $tableName) = split(/\./, uc($abbreviatedTablePeriod));

  $self->rebuildIndexes($owner, $tableName);

  $self->log("Enabling Constraints on Table $abbreviatedTablePeriod");

  $self->enablePrimaryKeyConstraint($owner, $tableName);
  $self->enableUniqueConstraints($owner, $tableName);
  $self->enableReferentialConstraints($owner, $tableName);
}


sub rebuildIndexes {
  my ($self, $owner, $tableName) = @_;

  my $sql = "select index_name from all_indexes where upper(owner) = '$owner' and upper(table_name) = '$tableName' and upper(status) = 'UNUSABLE'";

  my $alterSql = "alter index ${owner}.${PLACEHOLDER_STRING} rebuild nologging";

  $self->doConstraintsSql($sql, $alterSql);


}

sub enablePrimaryKeyConstraint {
  my ($self, $owner, $tableName) = @_;

  my $sql = "select constraint_name from all_constraints where upper(owner) = '$owner' and upper(table_name) = '$tableName' and upper(CONSTRAINT_TYPE) = 'P'  and upper(status) = 'DISABLED'";

  my $alterSql = "alter table ${owner}.${tableName} enable constraint $PLACEHOLDER_STRING";

  $self->doConstraintsSql($sql, $alterSql);
}

sub enableUniqueConstraints {
  my ($self, $owner, $tableName) = @_;

  my $sql = "select constraint_name from all_constraints where upper(owner) = '$owner' and upper(table_name) = '$tableName' and upper(CONSTRAINT_TYPE) = 'U'  and upper(status) = 'DISABLED'";

  my $alterSql = "alter table ${owner}.${tableName} enable constraint $PLACEHOLDER_STRING";

  $self->doConstraintsSql($sql, $alterSql);
}



sub enableReferentialConstraints {
  my ($self, $owner, $tableName) = @_;

  my $sql = "select constraint_name from all_constraints where upper(owner) = '$owner' and upper(table_name) = '$tableName' and upper(CONSTRAINT_TYPE) = 'R'  and upper(status) = 'DISABLED'";

  my $alterSql = "alter table ${owner}.${tableName} enable constraint $PLACEHOLDER_STRING";

  $self->doConstraintsSql($sql, $alterSql);
}

sub disableReferentialConstraintsFromTable {
  my ($self, $tableNamePeriod) = @_;

  my ($owner, $tableName) = split(/\./, uc($tableNamePeriod));

  my $sql = "select constraint_name from all_constraints where upper(owner) = '$owner' and upper(table_name) = '$tableName' and upper(CONSTRAINT_TYPE) = 'R'";

  my $alterSql = "alter table $tableNamePeriod disable constraint $PLACEHOLDER_STRING";

  $self->doConstraintsSql($sql, $alterSql);
}

sub doConstraintsSql {
  my ($self, $constraintSelect, $doSql) = @_;

  my $dbh = $self->getQueryHandle();  

  my $sh = $dbh->prepare($constraintSelect) or die $dbh->errstr;
  $sh->execute() or die $dbh->errstr;

  while(my ($constraintName) = $sh->fetchrow_array()) {
    my $tmpSql = $doSql;

    $tmpSql =~ s/$PLACEHOLDER_STRING/$constraintName/;

    $self->log("Running SQL:  $tmpSql");

    $dbh->do($tmpSql) or die $dbh->errstr;
  }
  $sh->finish();
}

sub run {
  my $self = shift;

  chdir $self->getArg('logDir');

  my $dbh = $self->getDbHandle();
  $dbh->do("alter session set nls_date_format = 'yyyy-mm-dd hh24:mi:ss'") or $self->error($dbh->errstr);

  my $database = $self->getArg('database');
  my $tableReaderClass = $self->getArg('table_reader');

  my $tableReader = &makeReaderObj($database, $tableReaderClass);


  $tableReader->connectDatabase();


  $self->log("Getting Table Dependencies and Ordering Tables by Foreign Keys...");

  my $tableInfo = $self->getAllTableInfo($tableReader);

  my $initialTableCount = scalar(keys(%$tableInfo));
  
  my $orderedTables = [];
  $self->orderTablesByRelations($tableInfo, $orderedTables);


  my $orderedTableCount = scalar @$orderedTables;

  unless($initialTableCount == $orderedTableCount) {
    $self->error("Expected $initialTableCount tables but found $orderedTableCount upon Ordering");
  }

  if($self->getArg('rebuildIndexsAndEnableConstraintsOnly')) {
    foreach my $tableName (@$orderedTables) {
      $self->rebuildIndexesAndEnableConstraints($tableInfo->{$tableName});
    }
    return("Rebuilt all indexes and updated disabled constraints.");
  }

  unless($self->getArg('skipUndo')) {
    my $pkTableReaderClass = $self->getArg('pk_table_reader');
    my $pkTableReader = &makeReaderObj($database, $pkTableReaderClass);
    $pkTableReader->connectDatabase();

    foreach my $tableName (reverse @$orderedTables) {
      $self->undoTable($database, $tableName, $tableInfo->{$tableName}, $pkTableReader);
    }

    $pkTableReader->disconnectDatabase();
  }

  foreach my $tableName (@$orderedTables) {
    $self->loadTable($database, $tableName, $tableInfo->{$tableName}, $tableReader);
  }

  $tableReader->disconnectDatabase();
}

sub hasRowsToDelete {
  my ($self, $database, $tableReader, $tableInfo, $maxPkOrig) = @_;

  my $tableName = $tableInfo->{fullTableName};
  my $primaryKeyColumn = $tableInfo->{primaryKey};
  my $abbreviatedTable = &getAbbreviatedTableName($tableName, "::");

  my $countAlreadyMapped = $self->queryForCountMappedOrigPk($database, $abbreviatedTable);


  # count from input db where pk <= maxPkValue already mapped
  my $inputTableRowCount = $tableReader->getTableCount($tableName, $primaryKeyColumn, $maxPkOrig);

  if($inputTableRowCount == $countAlreadyMapped) {
    return 0;
  }
  return 1;
}


sub loadPrimaryKeyTableForUndo {
  my ($self, $tableInfo, $primaryKeyTableName, $tableReader, $maxPkOrig, $dbh) = @_;

  my $tableName = $tableInfo->{fullTableName};
  my $abbreviatedTablePeriod = &getAbbreviatedTableName($tableName, ".");
  my $primaryKeyColumn = $tableInfo->{primaryKey};

  my $eorLiteral = $END_OF_RECORD_DELIMITER;
  $eorLiteral =~ s/\n/\\n/;

  my $attributeInfo = $tableInfo->{attributeInfo};    

  my ($pkInfo) = grep { lc($_->{'col'}) eq lc($primaryKeyColumn) } @$attributeInfo;
  my $prec = $pkInfo->{'prec'};

  $dbh->do("create table $primaryKeyTableName ($primaryKeyColumn number($prec), primary key($primaryKeyColumn))")  or die $dbh->errstr;;

  my ($sqlldrUndoFh, $sqlldrUndoFn) = tempfile("sqlldrUndoXXXX", UNLINK => 0, SUFFIX => '.ctl');
  my $sqlldrUndoInfileFn = "${abbreviatedTablePeriod}_pk.dat";

  print $sqlldrUndoFh "LOAD DATA
CHARACTERSET UTF8 LENGTH SEMANTICS CHAR
INFILE '$sqlldrUndoInfileFn' \"str '$eorLiteral'\" 
APPEND
INTO TABLE primarykey
REENABLE DISABLED_CONSTRAINTS
($primaryKeyColumn CHAR($prec))
    ";

    $self->error("Could not create named pipe for sqlloader undo file") unless(mkfifo($sqlldrUndoInfileFn, 0700));

    my $login       = $self->getConfig->getDatabaseLogin();
    my $password    = $self->getConfig->getDatabasePassword();
    my $dbiDsn      = $self->getConfig->getDbiDsn();
    my ($dbi, $type, $db) = split(':', $dbiDsn);

    my $sqlldrUndoProcessString = "sqlldr $login/$password\@$db control=$sqlldrUndoFn rows=100000 bindsize=512000 log=${sqlldrUndoFn}.log discardmax=0 errors=0 >/dev/null 2>&1 |";
    my $pid = open(my $sqlldrUndoProcess, $sqlldrUndoProcessString) or die "Cannot open pipe for sqlldr process:  $!";
    $self->addActiveForkedProcess($pid);
    open(my $sqlldrUndoInfileFh, ">$sqlldrUndoInfileFn") or die "Could not open named pipe $sqlldrUndoInfileFn for writing: $!";

    $tableReader->prepareTable($tableName, undef, $primaryKeyColumn, $maxPkOrig);
    
    while(my $row = $tableReader->nextRowAsHashref($tableInfo)) {
      my $origPrimaryKey = $row->{lc($primaryKeyColumn)};
      print $sqlldrUndoInfileFh $origPrimaryKey . $END_OF_RECORD_DELIMITER; # note the special line terminator
    }

    close $sqlldrUndoInfileFh;
    close $sqlldrUndoProcess;
    $self->error("sqlldr process failed!") if($?);
    unlink($sqlldrUndoFn,$sqlldrUndoInfileFn);
}

sub deleteFromTable {
  my ($self, $dbh, $deleteSql, $tableName) = @_;
  my $chunkSize = 100000;
  $deleteSql = $deleteSql . " and rownum <= $chunkSize";

  my $deleteStmt = $dbh->prepare($deleteSql) or die $dbh->errstr;
  my $rowsDeleted = 0;
    
  while (1) {
    my $rtnVal = $deleteStmt->execute() or die $dbh->errstr;
    $rowsDeleted += $rtnVal;
    $self->log("Deleted $rowsDeleted rows from $tableName");
    $dbh->commit() || $self->error("Committing deletions from $tableName failed: " . $self->{dbh}->errstr());
    last if $rtnVal < $chunkSize;
  }

  return $rowsDeleted;
}



sub undoTable {
  my ($self, $database, $tableName, $tableInfo, $tableReader) = @_;

  my $abbreviatedTable = &getAbbreviatedTableName($tableName, "::");
  my $abbreviatedTablePeriod = &getAbbreviatedTableName($tableName, ".");

  my $primaryKeyColumn = $tableInfo->{primaryKey};

  $self->log("Begin Undo for $abbreviatedTable from database $database");

  my $maxPkOrig = $self->queryForMaxMappedOrigPk($database, $abbreviatedTable);

  unless($self->hasRowsToDelete($database, $tableReader, $tableInfo, $maxPkOrig)) {
    $self->log("No rows to delete for $abbreviatedTable from database $database");
    return;
  }

  $self->resetActiveForkedProcesses();

  # TODO:  what is the state of the indexeson the  primary table? Will they matter when deleting?

  my $dbh = $self->getDbHandle();

  my $primaryKeyTableName = "primarykey";
  $self->loadPrimaryKeyTableForUndo($tableInfo, $primaryKeyTableName, $tableReader, $maxPkOrig, $dbh);

  my $deleteMapSql = "delete from $MAPPING_TABLE_NAME
             where database_orig = '$database'
             and table_name = '$abbreviatedTable'
             and primary_key_orig not in (select $primaryKeyColumn from $primaryKeyTableName)";


  # TODO:  Should not delete global row if other rows point to it

  my $deleteSql = "delete from $abbreviatedTablePeriod
        where $primaryKeyColumn not in (select primary_key 
                                        from $MAPPING_TABLE_NAME
                                        where database_orig = '$database' 
                                        and table_name = '$abbreviatedTable')
        ";

  $self->deleteFromTable($dbh, $deleteMapSql, $MAPPING_TABLE_NAME);  
  $self->deleteFromTable($dbh, $deleteSql, $abbreviatedTable);  

  $dbh->do("drop table $primaryKeyTableName") or die $dbh->errstr;;
}

sub getDatabaseTableMappingSql {
  my ($database, $tableNames) = @_;

  my $tableNamesString = join(",", map { "'" . &getAbbreviatedTableName($_, '::') . "'" } @$tableNames);

  my $sql = "select database_orig
                  , table_name
                  , primary_key_orig
                  , primary_key 
             from $MAPPING_TABLE_NAME
             where database_orig = '$database'
             and table_name in ($tableNamesString)
";

  return $sql;
}


sub addToIdMappings {
  my ($self, $database, $idMappings, $tableNames, $keepIds) = @_;

  my $sql = &getDatabaseTableMappingSql($database, $tableNames);
  
  my $dbh = $self->getDbHandle(); # this is the one which is inserting rows
  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my ($databaseOrig, $tableName, $pkOrig, $pk) = $sh->fetchrow_array()) {
    if(!defined($keepIds) || $keepIds->{$pkOrig}) {
      $tableName = "GUS::Model::$tableName";
      $idMappings->{$tableName}->{$pkOrig} = $pk;
    }
  }
  $sh->finish();

  return $idMappings;
}


sub getIdMappings {
  my ($self, $database, $tableName, $tableInfo, $tableReader) = @_;

  my $idMappings = {};

  my $abbreviatedTableColumn = &getAbbreviatedTableName($tableName, "::");
  $self->log("Begin ID Lookup for $abbreviatedTableColumn from database $database");

  foreach my $pr (@{$tableInfo->{parentRelations}}) {
    my $field = $pr->[1];

    $self->log("Getting Distinct Values for foreign key $field from $database");

    my @tableNames;

    my $keepIds = $tableReader->getDistinctValuesForTableFields($tableName, [$field], 0);

    if(ref($pr->[0]) eq 'ARRAY') {
      push @tableNames, @{$pr->[0]};
    }
    else {
      push @tableNames, $pr->[0];
    }

    $self->addToIdMappings($database, $idMappings, \@tableNames, $keepIds);
  }

  $self->addToIdMappings($database, $idMappings, [$tableName], undef);

  $self->log("Finished ID Lookup for $abbreviatedTableColumn from database $database");

  return $idMappings;
}

sub mapRow {
  my ($self, $row, $idMappings, $tableInfo, $origPrimaryKey) = @_;

  my @setToPk;

  my %mappedRow = %$row;

  foreach my $rel (@{$tableInfo->{parentRelations}}) {
    my $parentTable = $rel->[0];
    my $field = $rel->[1];
    my $parentField = $rel->[2];

    my $softKeyTableField = $rel->[3];
    my $softKeyTableMap = $rel->[4];

    my $origId = $mappedRow{lc($field)};

    next unless($origId); # no mappings for null values

    # Handle "Soft Keys"
    if($softKeyTableField) {
      my $softKeyTableId = $row->{lc($softKeyTableField)};
      $parentTable = $softKeyTableMap->{$softKeyTableId};
    }


    my $mappedId = $idMappings->{$parentTable}->{$origId};

    unless($mappedId) {
      if($tableInfo->{fullTableName} eq $parentTable && $origId eq $origPrimaryKey) {
        push @setToPk, lc($field);
      }
      else {
        $self->error("Could not map foreign key value $origId from $parentTable");        
      }
    }


    $mappedRow{lc($field)} = $mappedId;
  }

  return \%mappedRow, \@setToPk;
}


sub queryForMaxMappedOrigPk {
  my ($self, $database, $tableName) = @_;

  return $self->pkOrigFunctions($database, $tableName, "max");
}

sub queryForCountMappedOrigPk {
  my ($self, $database, $tableName) = @_;

  return $self->pkOrigFunctions($database, $tableName, "count");
}


sub pkOrigFunctions {
  my ($self, $database, $tableName, $function) = @_;

  my $sql = "select ${function}(primary_key_orig) 
             from $MAPPING_TABLE_NAME
             where database_orig = '$database' 
             and table_name = '$tableName'";

  my $dbh = $self->getQueryHandle();  

  my $sh = $dbh->prepare($sql);
  $sh->execute();

  my ($val) = $sh->fetchrow_array();

  unless($val) {
    return 0;
  }

  return $val;
}


sub queryForMaxPK {
  my ($self, $tableName, $primaryKey) = @_;

  my $sql = "select max($primaryKey) from $tableName";

  my $dbh = $self->getQueryHandle();  

  my $sh = $dbh->prepare($sql);
  $sh->execute();

  my ($max) = $sh->fetchrow_array();

  unless($max) {
    return 0;
  }

  return $max;
}


sub writeConfigFile {
  my ($self, $configFh, $tableInfo, $tableName, $datFileName, $tableReader, $hasRowProjectId) = @_;

  my $fullTableName = $tableInfo->{fullTableName};

  my $eorLiteral = $END_OF_RECORD_DELIMITER;
  $eorLiteral =~ s/\n/\\n/;

  my $eocLiteral = $END_OF_COLUMN_DELIMITER;
  $eocLiteral =~ s/\t/\\t/;

  my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
  my @abbr = qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC);
  my $modDate = sprintf('%2d-%s-%02d', $mday, $abbr[$mon], ($year+1900) % 100);

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

  my $attributeList = $tableInfo->{attributeList};
  my $attributeInfo = $tableInfo->{attributeInfo};

  
  my $rowProjectId = ($tableName eq $PROJECT_INFO_TABLE || $tableName eq $MAPPING_TABLE_NAME) ? " constant $projectId" : "";

  my $datatypeMap = {'user_read' => " constant $userRead", 
                     'user_write' => " constant $userWrite", 
                     'group_read' => " constant $groupRead", 
                     'group_write' => " constant $groupWrite", 
                     'other_read' => " constant $otherRead", 
                     'other_write' => " constant $otherWrite", 
                     'row_user_id' => " constant $userId", 
                     'row_group_id' => " constant $groupId", 
                     'row_alg_invocation_id' => " constant $algInvocationId",
                     'row_project_id' => $rowProjectId,
  };

  if($tableName eq $MAPPING_TABLE_NAME) {
    $attributeList = ["database_orig",
                      "table_name",
                      "primary_key_orig",
                      "primary_key",
                      'modification_date',
        ];

    push @$attributeList, "global_natural_key" if($GLOBAL_UNIQUE_FIELDS{$fullTableName});

    push @$attributeList, keys %$datatypeMap;

    $datatypeMap->{'database_orig'} = " CHAR(10)";
    $datatypeMap->{'global_natural_key'} = " CHAR(2500)";
    $datatypeMap->{'table_name'} = " CHAR(35)";
    $datatypeMap->{'primary_key_orig'} = " INTEGER EXTERNAL(20)";
    $datatypeMap->{'primary_key'} = " INTEGER EXTERNAL(20)";
  }
  else {
    foreach my $att (@$attributeInfo) {
      my $col = lc($att->{'col'});

      unless($datatypeMap->{$col}) {
        my $prec = $att->{'prec'};
        my $precString = $prec ? "($prec)" : "";
        my $length = $att->{'length'};
        my $type = $att->{'type'};

        if($type eq 'NUMBER') {
          $datatypeMap->{$col} = " CHAR";
        }
        elsif($type eq 'CHAR' || $type eq 'VARCHAR2') {
          $datatypeMap->{$col} = " CHAR($length)";
        }
        elsif($type eq 'DATE') {
          $datatypeMap->{$col} = " DATE 'yyyy-mm-dd hh24:mi:ss'";
        }
        elsif($type eq 'FLOAT') {
          $datatypeMap->{$col} = " CHAR(255)";
        }

        elsif($type eq 'BLOB' || $type eq 'CLOB') {
          my $charLength = $tableReader->getMaxLobLength($fullTableName, $col);
          $charLength = 1 unless($charLength);
          $datatypeMap->{$col} = " CHAR($charLength) ENCLOSED BY '$START_OF_LOB_DELIMITER' AND '$END_OF_LOB_DELIMITER'";
        }

        else {
          $self->error("$type columns not currently supported by this plugin for loading with sqlloader");
        }
      }
    }
  }

  $datatypeMap->{'modification_date'} = " constant \"$modDate\"";

  my @fields = map { lc($_) . $datatypeMap->{lc($_)}  } grep { $_ ne 'row_project_id'} @$attributeList;

  if($hasRowProjectId) {
    push @fields, "row_project_id " . $datatypeMap->{row_project_id}; #ensure row_project_id is last
  }

  if($tableName eq $MAPPING_TABLE_NAME) {
    push @fields, "database_table_mapping_id SEQUENCE(MAX,1)";
  }

  my $fieldsString = join(",\n", @fields);


  my $unrecoverable = $tableName eq $MAPPING_TABLE_NAME ? "" : "UNRECOVERABLE\n";

  # need to reenable constraints for core tables or the plugin won't fire up
  my $reenableDisabledConstraints = "";
  if($tableName =~ /GUS::Model::Core::Algorithm/ || $tableName eq $MAPPING_TABLE_NAME) {
    $reenableDisabledConstraints = "REENABLE DISABLED_CONSTRAINTS\n";
  }

  print $configFh "${unrecoverable}LOAD DATA
CHARACTERSET UTF8 LENGTH SEMANTICS CHAR
INFILE '$datFileName' \"str '$eorLiteral'\" 
APPEND
INTO TABLE $tableName
${reenableDisabledConstraints}FIELDS TERMINATED BY '$eocLiteral'
TRAILING NULLCOLS
($fieldsString
)
";

}




sub loadTable {
  my ($self, $database, $tableName, $tableInfo, $tableReader) = @_;

  # New GUS Table ApiDB does not use
  next if $tableName =~ /SnpLinkage/;
  next if $tableName =~ /ApiDB::GeneGff/; #TODO:  what is different about this table?? some issue with the content of the clob

  $self->resetActiveForkedProcesses();

  my $abbreviatedTableColumn = &getAbbreviatedTableName($tableName, "::");
  my $abbreviatedTablePeriod = &getAbbreviatedTableName($tableName, ".");

  my $loadDatWithSqlldr = $abbreviatedTablePeriod eq $NA_SEQUENCE_TABLE_NAME ? 0 : 1;

  # try to reuse all rows from these tables
  # some of these will have rows populated by the installer so globalMapping query is different
  my $isGlobalTable = $tableName =~ /GUS::Model::Core::(\w+)Info/ || 
      $tableName =~ /GUS::Model::Core::Algorithm/ || 
      $tableName eq 'GUS::Model::Study::Protocol' || 
      $tableName eq 'GUS::Model::Study::ProtocolParam';

  my $hasRowProjectId = 1;
  if($abbreviatedTablePeriod eq 'ApiDB.Snp' || $abbreviatedTablePeriod eq 'ApiDB.SequenceVariation') {
    $hasRowProjectId = 0;
  }

  my $login       = $self->getConfig->getDatabaseLogin();
  my $password    = $self->getConfig->getDatabasePassword();
  my $dbiDsn      = $self->getConfig->getDbiDsn();

  my ($dbi, $type, $db) = split(':', $dbiDsn);

  $self->log("Begin Loading table $abbreviatedTableColumn from database $database");

  my $rowCount = 0;
  my $primaryKeyColumn = $tableInfo->{primaryKey};
  my $isSelfReferencing = $tableInfo->{isSelfReferencing};
  my %lobColumns = map { lc($_) => 1 } @{$tableInfo->{lobColumns}};

  my ($hasNewDatRows, $hasNewMapRows);

  my ($sqlldrDatFh, $sqlldrDatFn, $sqlldrDatInfileFh, $sqlldrDatInfileFn, $sqlldrDatProcess, $sqlldrDatProcessString);
  my ($sqlldrMapFh, $sqlldrMapFn, $sqlldrMapInfileFh, $sqlldrMapInfileFn, $sqlldrMapProcess, $sqlldrMapProcessString);
  if($loadDatWithSqlldr) {
    ($sqlldrDatFh, $sqlldrDatFn) = tempfile("sqlldrDatXXXX", UNLINK => 0, SUFFIX => '.ctl');
    $sqlldrDatInfileFn = "${abbreviatedTablePeriod}.dat";
    $self->error("Could not create named pipe for sqlloader dat file") unless(mkfifo($sqlldrDatInfileFn, 0700));

    my $skipIndexMaintenance = $tableName =~ /GUS::Model::Core::Algorithm/ ? "false" : "true";
    $sqlldrDatProcessString = "sqlldr $login/$password\@$db control=$sqlldrDatFn streamsize=512000 direct=TRUE skip_index_maintenance=$skipIndexMaintenance log=${sqlldrDatFn}.log discardmax=0 errors=0 >/dev/null 2>&1 |";

  }
  else {
    $self->disableReferentialConstraintsFromTable($NA_SEQUENCE_TABLE_NAME);

    $self->getDb()->manageTransaction(0, 'begin');
    eval "require $tableName";
    $self->error($@) if $@;
  }

  ($sqlldrMapFh, $sqlldrMapFn) = tempfile("sqlldrMapXXXX", UNLINK => 0, SUFFIX => '.ctl');
  $sqlldrMapInfileFn = "${abbreviatedTablePeriod}_map.dat";
  $self->writeConfigFile($sqlldrMapFh, $tableInfo, $MAPPING_TABLE_NAME, $sqlldrMapInfileFn, $tableReader, $hasRowProjectId);
  $self->error("Could not create named pipe for sqlloader map file") unless(mkfifo($sqlldrMapInfileFn, 0700));
  $sqlldrMapProcessString = "sqlldr $login/$password\@$db control=$sqlldrMapFn rows=10000 bindsize=512000 log=${sqlldrMapFn}.log discardmax=0 errors=0 >/dev/null 2>&1 |";

  my $alreadyMappedMaxOrigPk = $self->queryForMaxMappedOrigPk($database, $abbreviatedTableColumn);

  my $maxPrimaryKey = $self->queryForMaxPK($abbreviatedTablePeriod, $primaryKeyColumn);

  $tableReader->prepareTable($tableName, $isSelfReferencing, $primaryKeyColumn, $alreadyMappedMaxOrigPk);

  my ($idMappings, $globalLookup);

  $self->log("Will skip rows with a $primaryKeyColumn <= $alreadyMappedMaxOrigPk");

  my %housekeepingFieldsHash = map { $_ => 1 } @$HOUSEKEEPING_FIELDS;

  my @attributeList = map { lc($_) } @{$tableInfo->{attributeList}};

  while(my $row = $tableReader->nextRowAsHashref($tableInfo)) {
    my $origPrimaryKey = $row->{lc($primaryKeyColumn)};

    next if($origPrimaryKey <= $alreadyMappedMaxOrigPk); # restart OR new data (TODO: won't work for "skipped" datasets)
    next if($tableReader->skipRow($row));

    # first time we see data
    unless($idMappings) {
      $idMappings = $self->getIdMappings($database, $tableName, $tableInfo, $tableReader);
      $globalLookup = $self->globalLookupForTable($primaryKeyColumn, $tableName, $database, $isGlobalTable);
    }


    my ($mappedRow, $fieldsToSetToPk) = $self->mapRow($row, $idMappings, $tableInfo, $origPrimaryKey);

    my $primaryKey;

    my $isGlobal = $tableReader->isRowGlobal($mappedRow) || $isGlobalTable;

    if($isGlobal) {
      $primaryKey = $self->lookupPrimaryKey($tableName, $mappedRow, $globalLookup);

      unless($primaryKey) {
        $self->log("No lookup Found for GLOBAL row $origPrimaryKey in table $abbreviatedTableColumn...adding row") if($self->getArg("debug"));
      }

      if($primaryKey && !$idMappings->{$tableName}->{$origPrimaryKey}) {

        unless($hasNewMapRows) {
          my $pid = open($sqlldrMapProcess, $sqlldrMapProcessString) or die "Cannot open pipe for sqlldr process:  $!";
          $self->addActiveForkedProcess($pid);
          open($sqlldrMapInfileFh, ">$sqlldrMapInfileFn") or die "Could not open named pipe $sqlldrMapInfileFn for writing: $!";
        }

        $hasNewMapRows = 1;
        my @mappingRow = ($database, $abbreviatedTableColumn, $origPrimaryKey, $primaryKey, undef);
        print $sqlldrMapInfileFh join($END_OF_COLUMN_DELIMITER, @mappingRow) . $END_OF_RECORD_DELIMITER ; # note the special line terminator

        $idMappings->{$tableName}->{$origPrimaryKey} = $primaryKey
      }
    }

    if(!$primaryKey && $abbreviatedTablePeriod ne $TABLE_INFO_TABLE) {
      unless($hasNewMapRows) {
        my $pid = open($sqlldrMapProcess, $sqlldrMapProcessString) or die "Cannot open pipe for sqlldr process:  $!";
        $self->addActiveForkedProcess($pid);
        open($sqlldrMapInfileFh, ">$sqlldrMapInfileFn") or die "Could not open named pipe $sqlldrMapInfileFn for writing: $!";
      }


      if($loadDatWithSqlldr) {
        unless($hasNewDatRows) {
          $self->writeConfigFile($sqlldrDatFh, $tableInfo, $abbreviatedTablePeriod, $sqlldrDatInfileFn, $tableReader, $hasRowProjectId);
          my $pid = open($sqlldrDatProcess, $sqlldrDatProcessString) or die "Cannot open pipe for sqlldr process:  $!";
          $self->addActiveForkedProcess($pid);
          open($sqlldrDatInfileFh, ">$sqlldrDatInfileFn") or die "Could not open named pipe $sqlldrDatInfileFn for writing: $!";
        }
      }

      $hasNewDatRows = 1;
      $hasNewMapRows = 1;
      $rowCount++;

      if($loadDatWithSqlldr) {
        $primaryKey = ++$maxPrimaryKey;
        $mappedRow->{lc($primaryKeyColumn)} = $primaryKey;

        # If the table is self referencing AND the fk is to the same row
        foreach my $ancestorField (@$fieldsToSetToPk) {
          $mappedRow->{lc($ancestorField)} = $primaryKey;
        }

        my @columns = map { $lobColumns{$_} ? $START_OF_LOB_DELIMITER . $mappedRow->{$_} . $END_OF_LOB_DELIMITER : $mappedRow->{$_} } grep { !$housekeepingFieldsHash{$_} } @attributeList;


        if($hasRowProjectId && $abbreviatedTablePeriod ne $PROJECT_INFO_TABLE) {
          $self->error("Could not map row") unless $mappedRow->{row_project_id};
          push @columns, $mappedRow->{row_project_id};
        }
      
        print $sqlldrDatInfileFh join($END_OF_COLUMN_DELIMITER, @columns) . $END_OF_RECORD_DELIMITER; # note the special line terminator
      }
      else { # Load with GUS Objects
        $mappedRow->{lc($primaryKeyColumn)} = undef;
        $mappedRow->{row_user_id} = undef;
        $mappedRow->{row_group_id} = undef;
        $mappedRow->{row_project_id} = undef if($abbreviatedTablePeriod eq $PROJECT_INFO_TABLE); #Important that we keep the project id for everything except projectinfo
        $mappedRow->{row_alg_invocation_id} = undef;

        my $gusRow = eval {
          $tableName->new($mappedRow);
        };
        die $@ if $@;

        $gusRow->submit(undef, 1);
        
        $primaryKey = $gusRow->get(lc($primaryKeyColumn));        

        # If the table is self referencing AND the fk is to the same row (seems unlikely to ever happen here)
        foreach my $ancestorField (@$fieldsToSetToPk) {
          $gusRow->set($ancestorField, $primaryKey);
          $gusRow->submit(undef, 1);
        }

        if($rowCount % 2000 == 0) {
          $self->getDb()->manageTransaction(0, 'commit');
          $self->getDb()->manageTransaction(0, 'begin');
        }
        $self->undefPointerCache();
      }

      # self referencing tables will need mappings for loaded rows
      $idMappings->{$tableName}->{$origPrimaryKey} = $primaryKey if($isSelfReferencing);
      
      # update the globalMapp for newly added rows
      my $globalNaturalKey;
      if($isGlobal) {
        my $globalUniqueFields = $GLOBAL_UNIQUE_FIELDS{$tableName};
        
        my @globalUniqueValues = map { lc($mappedRow->{lc($_)}) } @$globalUniqueFields;
        $globalNaturalKey = join("_", @globalUniqueValues);
        $globalLookup->{$globalNaturalKey} = $primaryKey;
      }
      
      my @mappingRow = ($database, $abbreviatedTableColumn, $origPrimaryKey, $primaryKey);
      push @mappingRow, $globalNaturalKey;
      print $sqlldrMapInfileFh join($END_OF_COLUMN_DELIMITER, @mappingRow) . $END_OF_RECORD_DELIMITER; # note the special line terminator

      if($rowCount % 100000 == 0) {
        $self->log("Processed $rowCount from $abbreviatedTableColumn");
      }
    }
  }

  $self->log("Finished Reading data from $abbreviatedTableColumn");

  $tableReader->finishTable();

  if($hasNewMapRows) {
    close $sqlldrMapInfileFh;
    close $sqlldrMapProcess;
    $self->error("sqlldr process failed!") if($?);
  }
  unlink($sqlldrMapFn,$sqlldrMapInfileFn);

  if($loadDatWithSqlldr) {
    if($hasNewDatRows) {
      close $sqlldrDatInfileFh;
      close $sqlldrDatProcess;
      if($?) {
        $self->error("sqlldr process for databasemapping failed!");
      }
    }
    unlink($sqlldrDatFn,$sqlldrDatInfileFn);

    # update the sequence
    my $sequenceName = "${abbreviatedTablePeriod}_sq";
    my $dbh = $self->getQueryHandle();  
    my ($sequenceValue) = $dbh->selectrow_array("select ${sequenceName}.nextval from dual"); 
    my $sequenceDifference = $maxPrimaryKey - $sequenceValue;
    if($sequenceDifference > 0) {
      $dbh->do("alter sequence $sequenceName increment by $sequenceDifference");
      $dbh->do("select ${sequenceName}.nextval from dual");
      $dbh->do("alter sequence $sequenceName increment by 1");
    }
  }
  else {
    $self->getDb()->manageTransaction(0, 'commit');
  }

  $self->log("Finished Loading $rowCount Rows into table $abbreviatedTableColumn from database $database");
}

sub getAbbreviatedTableName {
  my ($fullTableName, $del) = @_;

  $fullTableName =~ /GUS::Model::(.+)::(.+)/i;
  return $1 . $del . $2;
}

sub lookupPrimaryKey {
  my ($self, $tableName, $row, $globalLookup) = @_;

  # Load all alg invocations
  if($tableName eq "GUS::Model::Core::AlgorithmInvocation") {
      return undef;
  }

  unless($GLOBAL_UNIQUE_FIELDS{$tableName}) {
    $self->error("Table $tableName requires fields for Global Lookup");
  }

  my $fields = $GLOBAL_UNIQUE_FIELDS{$tableName};

  my @values = map { lc($row->{lc($_)}) } @$fields;
  my $key = join("_", @values);

  return $globalLookup->{$key};
}


sub globalLookupForTable  {
  my ($self, $primaryKeyColumn, $tableName, $database, $isGlobalTable) = @_;

  my $dbh = $self->getQueryHandle();  

  my $fields = $GLOBAL_UNIQUE_FIELDS{$tableName};

  return unless($fields);

  my $abbreviatedTableColumn = &getAbbreviatedTableName($tableName, "::");
  $self->log("Preparing Global Lookup for table $abbreviatedTableColumn from database $database");

  my $sql;
  if($isGlobalTable) {
    my $fieldsString = join(",", map { $_ } @$fields);
    $tableName = &getAbbreviatedTableName($tableName, ".");

    $sql = "select $primaryKeyColumn, $fieldsString from $tableName";
  }
  else {
    $tableName = &getAbbreviatedTableName($tableName, "::");
    $sql = "select primary_key, global_natural_key from apidb.DatabaseTableMapping where table_name = '$tableName' and global_natural_key is not null";
  }

  my $sh = $dbh->prepare($sql);
  $sh->execute();
  my %lookup;

  my $rowCount = 0;
  while(my ($pk, @a) = $sh->fetchrow_array()) {

    my @values = map { lc($_) } @a;
    my $key = join("_", @values);

    $lookup{$key} = $pk;
    $rowCount++
  }
  $sh->finish();

  
  unless($rowCount == scalar(keys(%lookup))) {
      $self->log("The GLOBAL UNIQUE FIELDS for table $tableName resulted in nonunique key when concatenated... choosing one");
  }

  $self->log("Finished caching Global Lookup for table $abbreviatedTableColumn from database $database");

  return \%lookup;
}


sub orderTablesByRelations {
  my ($self, $tableInfo, $orderedTables) = @_;

  my $seenTables = {};

  foreach my $tableName (keys %$tableInfo) {
    $self->orderTable($tableName, $tableInfo, $seenTables, $orderedTables);
  }
}



sub orderTable {
  my ($self, $tableName, $tableInfo, $seenTables, $orderedTables) = @_;

  return if($seenTables->{$tableName});

  next unless($tableInfo->{$tableName});

  my @parentsList;
  foreach my $pr (@{$tableInfo->{$tableName}->{parentRelations}}) {
    if(ref($pr->[0]) eq 'ARRAY') {
      push @parentsList, @{$pr->[0]};
    }
    else {
      push @parentsList, $pr->[0];
    }
  }

  # sequencevariation has a foreign key (nasequence_id,location) to apidb.snp but parentRelations only has the fk to NASequenceImp
  if($tableName eq "GUS::Model::ApiDB::SequenceVariation") {
    push @parentsList, "GUS::Model::ApiDB::Snp";
  }

  foreach my $parentTableName (@parentsList) {
    # foreignKey to own table
    unless($parentTableName eq $tableName) {
      $self->orderTable($parentTableName, $tableInfo, $seenTables, $orderedTables);
    }
  }

  push @$orderedTables, $tableName;
  $seenTables->{$tableName} = 1;
}

sub getTableRelationsSql {
  return "select ti.name as table_name
                  , di.name as database_name
                  , ti. primary_key_column
             from (-- everything but version and userdataset schemas
                   select  t.* 
                   from core.tableinfo t, core.databaseinfo d
                   where lower(t.table_type) != 'version'
                    and t.DATABASE_ID = d.DATABASE_ID
                    and d.name not in ('UserDatasets', 'ApidbUserDatasets', 'chEBI', 'hmdb')
                    and t.name not in ('AlgorithmParam', 'AlgorithmParamKey', 'AlgorithmParamKeyType')
                   minus
                   -- minus Views on tables
                   select * from core.tableinfo where view_on_table_id is not null
                  ) ti, core.databaseinfo di
            where ti.database_id = di.database_id
";
}


sub getAllTableInfo {
  my ($self, $tableReader) = @_;

  my %allTableInfo;

  my $dbh = $self->getQueryHandle();

  my $sql = &getTableRelationsSql();

  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my ($table, $schema, $primaryKey) = $sh->fetchrow_array()) {
    next if($table eq 'DATABASETABLEMAPPING'); # Do not sync the mapping table

    my $fullTableName = "GUS::Model::${schema}::${table}";
    my $packageName = "${fullTableName}_Table";
    eval "require $packageName";
    die $@ if $@;  

    my $dbiTable = eval {
      $packageName->new();
    };
    die $@ if $@;

    my $parentRelations = $dbiTable->getParentRelations();

    my @lobColumns;

    my $attributeInfo = $dbiTable->getAttributeInfo();

    foreach my $att (@{$dbiTable->getAttributeInfo()}) {
      if(uc($att->{type}) eq "CLOB" || uc($att->{type}) eq "BLOB") {
        push @lobColumns, $att->{col};
      }
    }

    my @parentRelationsNoHousekeeping;

    my $isSelfReferencing;

    foreach my $parentRelation (@$parentRelations) {
      my $parentTable = $parentRelation->[0];
      my $field = $parentRelation->[1];
      my $parentField = $parentRelation->[2];

      if($parentTable eq $fullTableName) {
        $isSelfReferencing = 1;
      }


      if(&getAbbreviatedTableName($parentTable, ".") eq $TABLE_INFO_TABLE) {
        my $softKeyTablesHash = $tableReader->getDistinctTablesForTableIdField($field, "${schema}.${table}");
        my @softKeyTables = values %$softKeyTablesHash;

        if(scalar @softKeyTables > 0) {
          my $rowIdField = $self->getRowIdFieldForTableIdField($fullTableName, $field, $dbiTable);
          if($rowIdField) {
            push @parentRelationsNoHousekeeping, [\@softKeyTables, $rowIdField, undef, $field, $softKeyTablesHash];
          }
        }
      }

      # NASequenceImp has circular foreign key to sequence piece. we never use
      # should work now. has been fixed in gus schema
      #if($fullTableName eq "GUS::Model::DoTS::NASequenceImp" &&
      #   $parentTable eq "GUS::Model::DoTS::SequencePiece") {
      #  next;
      #}

      if($fullTableName eq "GUS::Model::ApiDB::SequenceVariation" && (lc($field) eq 'location' || lc($parentField) eq 'location')) {
        next;
      }

      if($fullTableName eq "GUS::Model::ApiDB::SequenceVariation" && lc($field) eq 'ref_na_sequence_id') {
        $parentRelation->[0] = 'GUS::Model::DoTS::NASequenceImp';
      }

      # important for us to retain row_project_id
      unless($field eq "row_alg_invocation_id" || $field eq "row_user_id" || $field eq "row_group_id" || (&getAbbreviatedTableName($fullTableName, '.') eq $PROJECT_INFO_TABLE && $field eq "row_project_id")) {
        push @parentRelationsNoHousekeeping, $parentRelation;
      }
    }

    $allTableInfo{$fullTableName}->{attributeInfo} = $attributeInfo;
    $allTableInfo{$fullTableName}->{lobColumns} = \@lobColumns;

    $allTableInfo{$fullTableName}->{isSelfReferencing} = $isSelfReferencing;
    $allTableInfo{$fullTableName}->{parentRelations} = \@parentRelationsNoHousekeeping;

    $allTableInfo{$fullTableName}->{fullTableName} = $fullTableName;

    # TODO:  confirm that this is 1:1 with table
    $allTableInfo{$fullTableName}->{primaryKey} = $dbiTable->getPrimaryKey();

    $allTableInfo{$fullTableName}->{attributeList} = $dbiTable->getAttributeList();
  }

  return \%allTableInfo;
}

sub getRowIdFieldForTableIdField {
  my ($self, $table, $field, $tableObject) = @_;;

  my $skips = {'GUS::Model::Core::DatabaseDocumentation' =>  {'table_id' => 1} ,
               'GUS::Model::DoTS::BLATAlignment' => { 'query_table_id' => 1, 'target_table_id' => 1 },
               'GUS::Model::ApiDB::BLATProteinAlignment' => { 'query_table_id' => 1, 'target_table_id' => 1 },
               'GUS::Model::Study::Characteristic' => { 'table_id' => 1 },
               'GUS::Model::Core::TableInfo' => {'superclass_table_id' => 1, 'view_on_table_id' => 1},
               'GUS::Model::Core::TableCategory' => { 'table_id' => 1 },
  };

  my $map = { 'GUS::Model::DoTS::IndexWordSimLink' => {'similarity_table_id' => 'best_similarity_id'},
              'GUS::Model::DoTS::BestSimilarityPair' => {'paired_source_table_id' => 'paired_sequence_id',
                                                         'source_table_id' => 'sequence_id' },
              'GUS::Model::DoTS::Complementation' => { 'table_id' => 'entry_id'},
              'GUS::Model::DoTS::SequenceSequenceGroup' => { 'source_table_id' => 'sequence_id'},
              'GUS::Model::Model::NetworkRelEvidence' => { 'fact_table_id' => 'fact_row_id' },
              'GUS::Model::DoTS::MergeSplit' => { 'table_id' => 'old_id' },
              'GUS::Model::DoTS::ProjectLink' => { 'table_id' => 'id'}

  };

  return undef if($skips->{$table}->{$field});

  if(my $mappedRowField = $map->{$table}->{$field}) {
    return $mappedRowField;
  }


  my $attributeNames = $tableObject->getAttributeList();

  if($field eq 'table_id' && &foundValueInArray('row_id', $attributeNames)) {
    return 'row_id';
  }

  my $substr = $field;

  $substr =~ s/table_//;

  if(&foundValueInArray($substr, $attributeNames)) {
    return $substr;
  }

  $self->error("Could not map column $field for table $table");
}


sub foundValueInArray {
  my ($value, $array) = @_;

  foreach(@$array) {
    if($_ eq $value) {
      return 1;
    }
  }
  return 0;
}


sub getConfig {
  my ($self) = @_;

  if (!$self->{config}) {
    my $gusConfigFile = $self->getArg('gusconfigfile');
     $self->{config} = GUS::Supported::GusConfig->new($gusConfigFile);
   }

  $self->{config};
}

1;
