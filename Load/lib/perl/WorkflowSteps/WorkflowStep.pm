package ApiCommonData::Load::WorkflowSteps::WorkflowStep;

########################################
## Super class for ApiDB workflow steps
########################################

@ISA = (GUS::Workflow::WorkflowStepInvoker);

use strict;

use GUS::Workflow::WorkflowStepInvoker;

sub getLocalDataDir {
    my ($self) = @_;
    my $workflowHome = $self->getWorkflowHomeDir();
    return "$workflowHome/data";
}

sub getComputeClusterHomeDir {
    my ($self) = @_;
    my $clusterBase = $self->getGlobalConfig('clusterBaseDir');
    my $projectName = $self->getWorkflowConfig('name');
    my $projectVersion = $self->getWorkflowConfig('version');
    return "$clusterBase/$projectName/$projectVersion";
}

sub getComputeClusterDataDir {
    my ($self) = @_;
    my $home = $self->getComputeClusterHomeDir();
    return "$home/data";
}

sub makeControllerPropFile {
  my ($self, $taskInputDir, $slotsPerNode, $taskSize, $taskClass) = @_;

  my $nodePath = $self->getGlobalConfig('nodePath');
  my $nodeClass = $self->getGlobalConfig('nodeClass');

  # tweak inputs
  my $masterDir = $taskInputDir;
  $masterDir =~ s/master/input/;
  $nodeClass = 'DJob::DistribJob::BprocNode' unless $nodeClass;
  
  # get configuration values
  my $nodePath = $self->getConfig('nodePath');
  my $nodeClass = $self->getConfig('nodeClass');

  # construct dir paths
  my $localDataDir = $self->getLocalDataDir();
  my $computeClusterDataDir = $self->getComputeClusterDataDir();

  # print out the file
  my $controllerPropFile = "$localDataDir/$taskInputDir/controller.prop";
  open(F, $controllerPropFile) 
      || die "Can't open controller prop file '$controllerPropFile' for writing";
  print F 
"masterdir=$computeClusterDataDir/$masterDir
inputdir=$computeClusterDataDir/$taskInputDir
nodedir=$nodePath
slotspernode=$slotsPerNode
subtasksize=$taskSize
taskclass=$taskClass
nodeclass=$nodeClass
restart=no
";
    close(F);
}

sub runCmdOnCluster {
  my ($self, $test, $cmd) = @_;
}

# avoid using this subroutine!
# it is provided for backward compatibility.  plugins and commands that
# are called from the workflow should take an extDbRlsSpec as an argument,
# not an internal id
sub getExtDbRlsId {
  my ($self, $extDbRlsSpec) = @_;

  my ($extDbName, $extDbRlsVer) = $self->getExtDbInfo($extDbRlsSpec);

  my $sql = "select external_database_release_id from sres.externaldatabaserelease d, sres.externaldatabase x where x.name = '${extDbName}' and x.external_database_id = d.external_database_id and d.version = '${extDbRlsVer}'";

  my $cmd = "getValueFromTable --idSQL \"$sql\"";
  my $extDbRlsId = $self->runCmd(0, $cmd);

  return  $extDbRlsId;
}

sub getExtDbInfo {
    my ($self, $extDbRlsSpec) = @_;

    if ($extDbRlsSpec =~ /(.+)\|(.+)/) {
      my $extDbName = $1;
      my $extDbRlsVer = $2;
      return ($extDbName, $extDbRlsVer);
    } else {
      die "Database specifier '$extDbRlsSpec' is not in 'name|version' format";
    }
}

sub getTableId {
  my ($self, $tableName) = @_;
  my $sql = "select table_id from core.tableinfo where name = '$tableName'";

  my $cmd = "getValueFromTable --idSQL \"$sql\"";
  my $tableId = $self->runCmd(0, $cmd);
  return  $tableId;
}

sub getTaxonId {
  my ($self,$taxId) = @_;

  my $sql = "select taxon_id from sres.taxon where ncbi_tax_id = $taxId";

  my $cmd = "getValueFromTable --idSQL \"$sql\"";

  my $taxonId = $self->runCmd(0, $cmd);

  return $taxonId;
}

sub getTaxonIdList {
  my ($self, $taxonId, $hierarchy) = @_;

  if ($hierarchy) {
    return chomp($self->runCmd(0, "getSubTaxaList --taxon_id $taxonId"));
  } else {
    return $taxonId;
  }
}

sub copyToCluster {
  my ($self, $fromDir, $fromFile, $toDir) = @_;
}

sub copyFromCluster {
  my ($self, $fromDir, $fromFile, $toDir) = @_;
}

1;

