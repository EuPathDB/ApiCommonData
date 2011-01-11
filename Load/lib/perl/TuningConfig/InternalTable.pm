package ApiCommonData::Load::TuningConfig::InternalTable;

use ApiCommonData::Load::TuningConfig::TableSuffix;
use ApiCommonData::Load::TuningConfig::Utils;

# @ISA = qw( ApiCommonData::Load::TuningConfig::Table );


use strict;
use Data::Dumper;
my $maxRebuildMinutes;

sub new {
    my ($class, $name, $internalDependencyNames, $externalDependencyNames,
        $externalTuningTableDependencyNames, $intermediateTables, $ancillaryTables, $sqls,
        $perls, $unionizations, $programs, $dbh, $debug, $dblinkSuffix,
        $alwaysUpdate, $maxRebuildMinutesParam, $instance, $propfile, $password)
	= @_;

    my $self = {};
    $maxRebuildMinutes = $maxRebuildMinutesParam;

    bless($self, $class);
    $self->{name} = $name;
    $self->{internalDependencyNames} = $internalDependencyNames;
    $self->{externalDependencyNames} = $externalDependencyNames;
    $self->{externalTuningTableDependencyNames} = $externalTuningTableDependencyNames;
    $self->{intermediateTables} = $intermediateTables;
    $self->{ancillaryTables} = $ancillaryTables;
    $self->{sqls} = $sqls;
    $self->{perls} = $perls;
    $self->{unionizations} = $unionizations;
    $self->{programs} = $programs;
    $self->{debug} = $debug;
    $self->{dblinkSuffix} = $dblinkSuffix;
    $self->{internalDependencies} = [];
    $self->{externalDependencies} = [];
    $self->{externalTuningTableDependencies} = [];
    $self->{debug} = $debug;
    $self->{alwaysUpdate} = $alwaysUpdate;
    $self->{instance} = $instance;
    $self->{propfile} = $propfile;
    $self->{password} = $password;

    # get timestamp and definition from database
    my $sql = <<SQL;
       select to_char(timestamp, 'yyyy-mm-dd hh24:mi:ss') as timestamp, definition
       from apidb.TuningTable
       where name = '$self->{name}'
SQL

    my $stmt = $dbh->prepare($sql);
    $stmt->execute()
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
    my ($timestamp, $dbDef) = $stmt->fetchrow_array();
    $stmt->finish();
    $self->{timestamp} = $timestamp;
    $self->{dbDef} = $dbDef;

    return $self;
  }

sub getSqls {
  my ($self) = @_;

  return $self->{sqls};
}

sub getPerls {
  my ($self) = @_;

  return $self->{perls};
}

sub getUnionizations {
  my ($self) = @_;

  return $self->{unionizations};
}

sub getPrograms {
  my ($self) = @_;

  return $self->{programs};
}

sub getInternalDependencyNames {
  my ($self) = @_;

  return $self->{internalDependencyNames};
}

sub getExternalDependencyNames {
  my ($self) = @_;

  return $self->{externalDependencyNames};
}

sub getExternalTuningTableDependencyNames {
  my ($self) = @_;

  return $self->{externalTuningTableDependencyNames};
}

sub getInternalDependencies {
  my ($self) = @_;

  return $self->{internalDependencies};
}

sub getExternalDependencies {
  my ($self) = @_;

  return $self->{externalDependencies};
}

sub getExternalTuningTableDependencies {
  my ($self) = @_;

  return $self->{externalTuningTableDependencies};
}

sub getTimestamp {
  my ($self) = @_;

  return $self->{timestamp};
}

sub getState {
  my ($self, $doUpdate, $dbh, $purgeObsoletes, $registry) = @_;

  return $self->{state} if defined $self->{state};

  ApiCommonData::Load::TuningConfig::Log::addLog("checking $self->{name}");

  my $needUpdate;
  my $broken;

  # check if the definition is different (or none is stored)
  if (!$self->{dbDef}) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    no TuningTable record exists in database for $self->{name} -- update needed.");
    $needUpdate = 1;
  } elsif ($self->{dbDef} ne $self->getDefString()) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    stored TuningTable record differs from current definition for $self->{name} -- update needed.");
    $needUpdate = 1;
    ApiCommonData::Load::TuningConfig::Log::addLog("stored:\n-------\n" . $self->{dbDef} . "\n-------")
	if $self->{debug};
    ApiCommonData::Load::TuningConfig::Log::addLog("current:\n-------\n" . $self->getDefString() . "\n-------")
	if $self->{debug};
  }

  # check internal dependencies
  foreach my $dependency (@{$self->getInternalDependencies()}) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    depends on tuning table " . $dependency->getName());

    # increase log-file indentation for recursive call
    ApiCommonData::Load::TuningConfig::Log::increaseIndent();
    my $childState = $dependency->getState($doUpdate, $dbh, $purgeObsoletes, $registry);
    ApiCommonData::Load::TuningConfig::Log::decreaseIndent();

    if ($childState eq "neededUpdate" || $dependency->getTimestamp() gt $self->getTimestamp()) {
      $needUpdate = 1;
      ApiCommonData::Load::TuningConfig::Log::addLog("    $self->{name} needs update because it depends on " . $dependency->getName() . ", which was found to be out of date (or is simply newer).");
    } elsif ($childState eq "broken") {
      $broken = 1;
      ApiCommonData::Load::TuningConfig::Log::addLog("    $self->{name} is broken because it depends on " . $dependency->getName() . ", which is broken.");
    }
  }

  # check external dependencies
  foreach my $dependency (@{$self->getExternalDependencies()}) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    depends on external table " . $dependency->getName());
    if ($dependency->getTimestamp() gt $self->{timestamp}) {
      $needUpdate = 1;
      ApiCommonData::Load::TuningConfig::Log::addLog("    creation timestamp of $self->{name} ($self->{timestamp}) is older than observation timestamp of " . $dependency->getName() . " (" . $dependency->getTimestamp() . ") -- update needed.");
    }
  }

  # check external tuning-table dependencies
  if ($self->getExternalTuningTableDependencies()) {
    foreach my $dependency (@{$self->getExternalTuningTableDependencies()}) {
      ApiCommonData::Load::TuningConfig::Log::addLog("    depends on external tuning table " . $dependency->getName());
      if ($dependency->getTimestamp() gt $self->{timestamp}) {
	$needUpdate = 1;
	ApiCommonData::Load::TuningConfig::Log::addLog("    creation timestamp of $self->{name} ($self->{timestamp}) is older than creation timestamp of " . $dependency->getName() . " (" . $dependency->getTimestamp() . ") -- update needed.");
      }
    }
  }


  if ($self->{alwaysUpdate}) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    " . $self->{name} . " has alwaysUpdate attribute.");
  }

  if ( ($doUpdate and $needUpdate) or $self->{alwaysUpdate}) {
    my $updateResult = $self->update($dbh, $purgeObsoletes, $registry);
    $broken = 1 if $updateResult eq "broken";
  }

  ApiCommonData::Load::TuningConfig::Log::setUpdateNeededFlag()
      if $needUpdate and !$self->{alwaysUpdate};  # don't set the update flag for alwaysUpdate tables

  if ($broken) {
    $self->{state} = "broken";
    ApiCommonData::Load::TuningConfig::Log::setErrorsEncounteredFlag();
  } elsif ($needUpdate) {
    $self->{state} = "neededUpdate";
  } else {
    $self->{state} = "up-to-date";
  }

  ApiCommonData::Load::TuningConfig::Log::addLog("    $self->{name} found to be \"$self->{state}\"");

  return $self->{state};
}

sub update {
  my ($self, $dbh, $purgeObsoletes, $registry) = @_;

  my $startTime = time;

  ApiCommonData::Load::TuningConfig::Log::setUpdatePerformedFlag()
      unless $self->{alwaysUpdate};

  my $suffix = ApiCommonData::Load::TuningConfig::TableSuffix::getSuffix($dbh);

  my $dateString = `date`;
  chomp($dateString);
  ApiCommonData::Load::TuningConfig::Log::addLog("    Rebuilding tuning table " . $self->{name} . " on $dateString");

  $self->dropIntermediateTables($dbh);

  my $updateError;

  foreach my $unionization (@{$self->{unionizations}}) {

    last if $updateError;

    ApiCommonData::Load::TuningConfig::Log::addLog("running unionization to build $self->{name}\n")
	if $self->{debug};

    $self->unionize($unionization, $dbh);
  }

  foreach my $sql (@{$self->{sqls}}) {

    last if $updateError;

    my $sqlCopy = $sql;

    # change, for example, "@toxo" to "@toxobuild"
    my $dblinkSuffix = $self->{dblinkSuffix};
    $sqlCopy =~ s/@(\w*)\b/\@$1$dblinkSuffix/g;

    # use numeric suffix to make db object names unique
    $sqlCopy =~ s/&1/$suffix/g;

    ApiCommonData::Load::TuningConfig::Log::addLog("vvvvvv sql string changed: vvvvvv\nbefore: \"$sql\"\nafter: \"$sqlCopy\"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^")
	if $self->{debug} && $sqlCopy ne $sql;

    ApiCommonData::Load::TuningConfig::Log::addLog("running sql of length "
						   . length($sqlCopy)
						   . " to build $self->{name}:\n$sqlCopy")
	if $self->{debug};

    $updateError = 1 if !ApiCommonData::Load::TuningConfig::Utils::sqlBugWorkaroundDo($dbh, $sqlCopy);;

    if ($dbh->errstr =~ /ORA-01652/) {
    ApiCommonData::Load::TuningConfig::Log::addLog("Setting out-of-space flag, so notification email is sent.");
      ApiCommonData::Load::TuningConfig::Log::setOutOfSpaceMessage($dbh->errstr);
    }

  }

  foreach my $perl (@{$self->{perls}}) {
    last if $updateError;

    my $perlCopy = $perl;
    $perlCopy =~ s/&1/$suffix/g;  # use suffix to make db object names unique

    ApiCommonData::Load::TuningConfig::Log::addLog("running perl of length " . length($perlCopy) . " to build $self->{name}::\n$perlCopy")
	if $self->{debug};
    eval $perlCopy;

    if ($@) {
      $updateError = 1;
      ApiCommonData::Load::TuningConfig::Log::addErrorLog("Error \"$@\" encountered executing Perl statement beginning:\n" . substr($perlCopy, 1, 100) );
    }
  }

  foreach my $program (@{$self->{programs}}) {
    last if $updateError;

    my $commandLine = $program->{commandLine}
                      . " -instance '" . $self->{instance} . "'"
                      . " -propfile '" . $self->{propfile} . "'"
                      . " -password '" . $self->{password} . "'"
                      . " -logfile '" . ApiCommonData::Load::TuningConfig::Log::getLogfile() . "'"
                      . " -suffix '" . $suffix . "'";

    ApiCommonData::Load::TuningConfig::Log::addLog("running program with command line \"" . $commandLine . "\" to build $self->{name}");

    my $returnCode = system("$commandLine");

    ApiCommonData::Load::TuningConfig::Log::addLog("finished running program, with exit code $returnCode");

    if ($returnCode) {
      $updateError = 1;
    }
  }

  return "broken" if $updateError;

  $self->dropIntermediateTables($dbh, 'warn on nonexistence');

  # publish main table
  $self->publish($self->{name}, $suffix, $dbh, $purgeObsoletes) or return "broken";

  # publish ancillary tables
  foreach my $ancillary (@{$self->{ancillaryTables}}) {
      ApiCommonData::Load::TuningConfig::Log::addLog("publishing ancillary table " . $ancillary->{name});
      $self->publish($ancillary->{name}, $suffix, $dbh, $purgeObsoletes) or return "broken";
  }

  # store definition
  ApiCommonData::Load::TuningConfig::Log::addErrorLog("unable to store table definition")
      if $self->storeDefinition($dbh);

  my $buildDuration = time - $startTime;
  ApiCommonData::Load::TuningConfig::Log::addLog("    $buildDuration seconds to rebuild tuning table "
                                                 . $self->{name});

  if ($maxRebuildMinutes) {
    ApiCommonData::Load::TuningConfig::Log::addErrorLog("table rebuild took longer than $maxRebuildMinutes minute maximum.")
      if ($buildDuration > $maxRebuildMinutes * 60)
  }

  ApiCommonData::Load::TuningConfig::Log::logRebuild($dbh, $self->{name}, $buildDuration, $registry->getInstanceName(), $registry->getDblink());

  return "neededUpdate"
}

sub storeDefinition {
  my ($self, $dbh) = @_;

  my $sql = <<SQL;
       delete from apidb.TuningTable
       where name = '$self->{name}'
SQL

  my $stmt = $dbh->prepare($sql);
  $stmt->execute()
    or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
  $stmt->finish();

  my $sql = <<SQL;
       insert into apidb.TuningTable
          (name, timestamp, definition) values (?, sysdate, ?)
SQL

  my $stmt = $dbh->prepare($sql);

  if (!$stmt->execute($self->{name}, $self->getDefString())) {
    ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
    return "fail";
  }

  $stmt->finish();

  return;
}

sub getDefString {
  my ($self) = @_;

  return $self->{defString} if $self->{defString};

  my $defString;

  my $sqls = $self->getSqls();
  $defString = join(" ", @{$sqls}) if $sqls;

  my $perls = $self->getPerls();
  $defString .= join(" ", @{$perls}) if $perls;

  my $unionizations = $self->getUnionizations();
  $defString .= join(" ", @{$unionizations}) if $unionizations;

  my $programs = $self->getPrograms();
  $defString .= join(" ", @{$programs}) if $programs;

  $self->{defString} = $defString;

  return $defString;
}

sub getName {
  my ($self) = @_;

  return $self->{name};
}

sub addExternalDependency {
    my ($self, $dependency) = @_;

    push(@{$self->{externalDependencies}}, $dependency);
}

sub addExternalTuningTableDependency {
    my ($self, $dependency) = @_;

    push(@{$self->{externalTuningTableDependencies}}, $dependency);
}

sub addInternalDependency {
    my ($self, $dependency) = @_;

    push(@{$self->{internalDependencies}}, $dependency);
}

sub hasDependencyCycle {
    my ($self, $ancestorsRef) = @_;

    my $cycleFound;

    # log error if $self is earliest ancestor
    if ($ancestorsRef->[0] eq $self->{name}) {
      ApiCommonData::Load::TuningConfig::Log::addErrorLog("ERROR: cycle of dependencies: " .
						     join(" -> ", @{$ancestorsRef}) .
						    " -> " . $self->{name});
      return 1;
    }

    # stop recursing if $self is ANY ancestor
    foreach my $ancestor (@{$ancestorsRef}) {
      return 1 if $ancestor eq $self->{name};
    }

    push(@{$ancestorsRef}, $self->{name});
    foreach my $child (@{$self->getInternalDependencies()}) {
      $cycleFound = 1
	if $child->hasDependencyCycle($ancestorsRef);
    }

    pop(@{$ancestorsRef});
    return $cycleFound;
}

sub dropIntermediateTables {
  my ($self, $dbh, $warningFlag) = @_;

  foreach my $intermediate (@{$self->{intermediateTables}}) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    must drop intermediate table $intermediate->{name}");

    my $sql = <<SQL;
       drop table $intermediate->{name}
SQL

    $dbh->{PrintError} = 0;
    my $stmt = $dbh->prepare($sql);
    my $sqlReturn = $stmt->execute();
    $stmt->finish();
    $dbh->{PrintError} = 1;

    ApiCommonData::Load::TuningConfig::Log::addLog("WARNING: intermediateTable"
						   . $intermediate->{name}
						   . " was not created during the update of "
						   . $self->{name})
	if ($warningFlag and !defined $sqlReturn);
  }

}

sub publish {
  my ($self, $tuningTableName, $suffix, $dbh, $purgeObsoletes) = @_;

  # grant select privilege on new table
    my $sql = <<SQL;
      grant select on $tuningTableName$suffix to gus_r
SQL

    my $stmt = $dbh->prepare($sql);
    $stmt->execute()
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
    $stmt->finish();

  # get name of old table (for subsequenct purging). . .
  my $oldTable;
  my ($schema, $table) = split(/\./, $tuningTableName);
  if ($purgeObsoletes) {
    my $sql = <<SQL;
      select table_owner || '.' || table_name
      from all_synonyms
      where owner = upper(?)
        and synonym_name = upper(?)
SQL

    my $stmt = $dbh->prepare($sql);
    $stmt->execute("$schema", "$table")
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
    ($oldTable) = $stmt->fetchrow_array();
    $stmt->finish();
  } else {
    # . . . or just mark it obsolete
    my $sql = <<SQL;
      insert into apidb.ObsoleteTuningTable (name, timestamp)
      select table_owner || '.' || table_name, sysdate
      from all_synonyms
      where owner = upper(?)
        and synonym_name = upper(?)
SQL

    my $stmt = $dbh->prepare($sql);
    $stmt->execute("$schema", "$table")
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
    $stmt->finish();
  }

  # update synonym
  my $sql = <<SQL;
    create or replace synonym $tuningTableName for $tuningTableName$suffix
SQL
  my $synonymRtn = $dbh->do($sql);

  if (!defined $synonymRtn) {
    ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
  }

  # drop obsolete table, if we're doing that (and it exists)
  if (defined $synonymRtn && $purgeObsoletes && $oldTable) {
    ApiCommonData::Load::TuningConfig::Log::addLog("    purging obsolete table " . $oldTable);    
    $dbh->do("drop table " . $oldTable)
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
  }

  # Run stored procedure to analye any apidb tables that need it
  $dbh->do("BEGIN apidb.apidb_unanalyzed_stats; END;")
    or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");

  return $synonymRtn
}

sub unionize {
  my ($self, $union, $dbh) = @_;

  $union->{name} = $self->{name}
    if !$union->{name};

  my ($coltypeRef, $columnsRef, $columnSetRef, $sourceNumber, $fromsRef)
    = $self->getColumnInfo($dbh, $union);

  my %coltype = %{$coltypeRef};
  my %columnSet = %{$columnSetRef};
  my @columns = @{$columnsRef};
  my @froms = @{$fromsRef};

  # build create table
  my @unionMembers; # array of query statements to be UNIONed
  $sourceNumber = 0;

  foreach my $source (@{$union->{source}}) {

    $sourceNumber++;

    my @selectees;  # array of terms for the SELECT clause
    my $notAllNulls = 0; # TRUE if at least one column is really there (else skip the whole unionMember)

    foreach my $column (@columns) {

      if ($columnSet{$sourceNumber}->{$column}) {
	$notAllNulls = 1;
	push(@selectees, $column);
      } else {
	push(@selectees, 'cast (null as ' . $coltype{$column} . ') as ' . $column);
      }
    }
    push(@unionMembers, 'select ' . join(', ', @selectees) . "\nfrom ". $froms[$sourceNumber])
      if $notAllNulls;
  }

  my $suffix = ApiCommonData::Load::TuningConfig::TableSuffix::getSuffix($dbh);

  my $createTable = "create table $union->{name}$suffix as\n"
    . join("\nunion\n", @unionMembers);

  ApiCommonData::Load::TuningConfig::Log::addLog("creating union table with following statement:\n$createTable") if $self->{debug};
  runSql($dbh, $createTable);
}

sub getColumnInfo {
  my ($self, $dbh, $union) = @_;

    my %coltype;
    my @columns;
    my %columnSet;
    my $sourceNumber;
    my @froms;

  my $dblinkSuffix = $self->{dblinkSuffix};
    foreach my $source (@{$union->{source}}) {

      $sourceNumber++;

      my $dblink = $source->{dblink};
      $dblink = "@" . $dblink . $dblinkSuffix
	if $dblink;
      my $table = $source->{name};

      my $tempTable;

      if ($source->{query}) {
	my $queryString = $source->{query}[0];
	$tempTable = 'apidb.UnionizerTemp';
	$table = $tempTable;
	# do dblink-suffix transformation on $queryString
	$queryString =~ s/@(\w*)\b/\@$1$dblinkSuffix/g;
	runSql($dbh, 'create table ' . $tempTable . ' as ' . $queryString);
	$froms[$sourceNumber] = '(' . $queryString . ')';
      } else {
	$table = $union->{name} if !$table;
	$froms[$sourceNumber] = "$table$dblink";
      }

      my ($owner, $simpleTable) = split(/\./, $table);


      my $sql = <<SQL;
         select column_name, data_type, char_col_decl_length, column_id
         from all_tab_columns$dblink
         where owner=upper('$owner')
           and table_name=upper('$simpleTable')
         union
         select tab.column_name, tab.data_type, tab.char_col_decl_length,
                tab.column_id
         from all_synonyms$dblink syn, all_tab_columns$dblink tab
         where syn.table_owner = tab.owner
           and syn.table_name = tab.table_name
           and syn.owner=upper('$owner')
           and syn.synonym_name=upper('$simpleTable')
         order by column_id
SQL
      print "$sql\n\n" if $self->{debug};

      my $stmt = $dbh->prepare($sql);
      $stmt->execute();

      while (my ($columnName, $dataType, $charLen, $column_id) = $stmt->fetchrow_array()) {

	# add this to the list of columns and store its datatype declaration
	if (! $coltype{$columnName}) {
	  push(@columns, $columnName);
	  if ($dataType eq "VARCHAR2") {
	    $coltype{$columnName} = 'VARCHAR2('.$charLen.')';
	  } else {
	    $coltype{$columnName} = $dataType;
	  }
	}

	# note that this table has this column
	$columnSet{$sourceNumber}->{$columnName} = 1;
      }
      $stmt->finish();

      runSql($dbh, 'drop table ' . $tempTable) if ($tempTable);
    }

  return (\%coltype, \@columns, \%columnSet, $sourceNumber, \@froms);

}

sub runSql {

  my ($dbh, $sql) = @_;

  my $stmt = $dbh->prepare($sql);
  $stmt->execute() or die "failed executing SQL statement \"$sql\"\n";
  $stmt->finish();
}

1;
