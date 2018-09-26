package ApiCommonData::Load::GUSTableReader;
use base qw(ApiCommonData::Load::UniDBTableReader);

use strict;

use DBI;
use DBD::Oracle;

use Data::Dumper;

use GUS::Supported::GusConfig;

sub setDatabaseHandle { $_[0]->{_database_handle} = $_[1] }
sub getDatabaseHandle { $_[0]->{_database_handle} }

sub setStatementHandle { $_[0]->{_statement_handle} = $_[1] }
sub getStatementHandle { $_[0]->{_statement_handle} }

sub getTableNameFromPackageName {
  my ($fullTableName) = @_;

  $fullTableName =~ /GUS::Model::(.+)::(.+)/i;
  return $1 . "." . $2;
}


sub readClob {
  my ($self, $lobLocator) = @_;

  my $dbh = $self->getDatabaseHandle();

  my $chunkSize = 1034;   # Arbitrary chunk size, for example
  my $offset = 1;   # Offsets start at 1, not 0

  my $output;

  while(1) {
    my $data = $dbh->ora_lob_read($lobLocator, $offset, $chunkSize );
    last unless length $data;
    $output .= $data;
    $offset += $chunkSize;
  }

  return $output;
}


sub getTableSql {
  my ($self, $tableName, $isSelfReferencing, $primaryKeyColumn, $maxAlreadyLoadedPk) = @_;

  $tableName = &getTableNameFromPackageName($tableName);

  my $orderBy = "order by $primaryKeyColumn";

  if(lc($tableName) eq "sres.ontologyterm") {
    $orderBy = "order by case when ancestor_term_id = ontology_term_id then 0 else 1 end";
  }
  if(lc($tableName) eq "core.tableinfo") {
    $orderBy = "order by view_on_table_id nulls first, superclass_table_id nulls first, table_id";
  }

  if(lc($tableName) eq "study.study") {
    $orderBy = "order by investigation_id nulls first, study_id";
  }
  if(lc($tableName) eq "sres.taxon") {
    $orderBy = "order by parent_id nulls first, taxon_id";
  }


  my $where = "where $primaryKeyColumn > $maxAlreadyLoadedPk";

  my $sql = "select * from $tableName $where $orderBy";

  return $sql;
}

sub prepareTable {
  my ($self, $tableName, $isSelfReferencing, $primaryKeyColumn, $maxAlreadyLoadedPk) = @_;

  my $dbh = $self->getDatabaseHandle();

  my $sql = $self->getTableSql($tableName, $isSelfReferencing, $primaryKeyColumn, $maxAlreadyLoadedPk);

  my $sh = $dbh->prepare($sql, { ora_auto_lob => 0 } ) 
      or die "Can't prepare SQL statement: " . $dbh->errstr();
  $sh->execute();

  $self->setStatementHandle($sh);
}

sub finishTable {
  my ($self) = @_;

  my $sh = $self->getStatementHandle();
  $sh->finish();
}

sub nextRowAsHashref {
  my ($self, $tableInfo) = @_;
  my $sh = $self->getStatementHandle();

  my $hash = $sh->fetchrow_hashref();

  if($hash) {

    foreach my $lobColumn (@{$tableInfo->{lobColumns}}) {
      my $lobLoc = $hash->{lc($lobColumn)};

      if($lobLoc) {
        my $clobData = $self->readClob($lobLoc);
        $hash->{lc($lobColumn)} = $clobData;
      }
    }
  }
  return $hash;
}


sub connectDatabase {
  my ($self) = @_;

  my $database = $self->getDatabase();

  my $configFile = "$ENV{GUS_HOME}/config/gus.config";

  my $config = GUS::Supported::GusConfig->new($configFile);

  my $login       = $config->getDatabaseLogin();
  my $password    = $config->getDatabasePassword();

  my $dbh = DBI->connect("dbi:Oracle:${database}", $login, $password) or die DBI->errstr;
  $dbh->{RaiseError} = 1;
  $dbh->{AutoCommit} = 0;
  $dbh->{FetchHashKeyName} = "NAME_lc";

  $dbh->do("alter session set nls_date_format = 'yyyy-mm-dd hh24:mi:ss'") or die $dbh->errstr;

  $self->setDatabaseHandle($dbh);
}

sub disconnectDatabase {
  my ($self) = @_;
  my $dbh = $self->getDatabaseHandle();

  $dbh->disconnect();
}


sub isRowGlobal {
  my ($self, $row) = @_;

  if(!$self->{_global_row_alg_invocation_ids}) {
    my $dbh = $self->getDatabaseHandle();
    my $sql = "select w.ALGORITHM_INVOCATION_ID
from APIDB.WORKFLOWSTEPALGINVOCATION w
    ,APIDB.WORKFLOWSTEP ws
where w.workflow_step_id = ws.workflow_step_id
and (ws.name like 'global.%'
  or ws.name = 'EcNumberGenus_RSRC.runPlugin'
  or ws.name = 'metadata.ontologySynonyms.Ontology_Synonyms_genbankIsolates_RSRC.runPlugin'
)
UNION
select row_alg_invocation_id from core.algorithm where name = 'SQL*PLUS'
";

    my $sh = $dbh->prepare($sql);
    $sh->execute();

    while( my ($id) = $sh->fetchrow_array()) {
      $self->{_global_row_alg_invocation_ids}->{$id} = 1;
    }
    $sh->finish();
  }

  my $rowAlgInvocationId = $row->{row_alg_invocation_id};

  if($self->{_global_row_alg_invocation_ids}->{$rowAlgInvocationId}) {
    return 1;
  }
  return 0;
}


sub skipRow {
  my ($self, $row) = @_;

  if(!$self->{_skip_row_alg_invocation_ids}) {
    my $dbh = $self->getDatabaseHandle();
    my $sql = "select w.ALGORITHM_INVOCATION_ID
from APIDB.WORKFLOWSTEPALGINVOCATION w
    ,APIDB.WORKFLOWSTEP ws
where w.workflow_step_id = ws.workflow_step_id
and (ws.name like 'metadata.ISA%'
  or ws.name like 'ReactionsXRefs_%'
  or ws.name like 'Pathways_%')
";

    my $sh = $dbh->prepare($sql);
    $sh->execute();

    while( my ($id) = $sh->fetchrow_array()) {
      $self->{_skip_row_alg_invocation_ids}->{$id} = 1;
    }
    $sh->finish();
  }

  my $rowAlgInvocationId = $row->{row_alg_invocation_id};

  if($self->{_skip_row_alg_invocation_ids}->{$rowAlgInvocationId}) {
    return 1;
  }
  return 0;
}

sub getDistinctTablesForTableIdField {
  my ($self, $field, $table) = @_;

    my $dbh = $self->getDatabaseHandle();

  my $sql = "select distinct nvl(v.name, t.name) as table_name
                           , t.table_id as table_id
                           , nvl(vd.name, d.name) as database_name
from core.tableinfo t
   , core.tableinfo v
   , core.databaseinfo d
   , core.databaseinfo vd
   , $table s
where s.$field = t.table_id
and t.view_on_table_id = v.table_id (+)
and v.database_id = vd.database_id (+)
and d.database_id = t.database_id
";

  my $sh = $dbh->prepare($sql);
  $sh->execute();

  my %rv;

  while(my ($t, $id, $d) = $sh->fetchrow_array()) {
    $rv{$id} = "GUS::Model::${d}::${t}";
  }

  $sh->finish();

  return \%rv;
}



sub getDistinctValuesForTableFields {
  my ($self, $fullTableName, $fields, $onlyGlobalRows) = @_;

  my $tableName = &getTableNameFromPackageName($fullTableName);

  my $addRowAlgInvocationId = "";
  if($onlyGlobalRows) {
    $addRowAlgInvocationId = ",row_alg_invocation_id";
  }

  my %rv;
  my $dbh = $self->getDatabaseHandle();

  my $fieldsString = join(",", @$fields);

  my $sql = "select distinct $fieldsString $addRowAlgInvocationId from $tableName";
  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my $row = $sh->fetchrow_hashref()) {
    my @values = map { $row->{lc($_)} } @$fields;

    my $key = join("_", @values);

    if($onlyGlobalRows && $self->isRowGlobal($row)) {
      $rv{$key} = 1;
    }
    else {
      $rv{$key} = 1;
    }
  }
  $sh->finish();

  return \%rv;
}


1;
