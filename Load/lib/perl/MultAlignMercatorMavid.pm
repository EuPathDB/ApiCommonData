package ApiCommonData::Load::MultAlignMercatorMavid;

use strict;

use Bio::SeqIO;
use Bio::Seq;

#use ApiCommonWebsite::Model::ModelProp;

use CGI::Carp qw(fatalsToBrowser set_message);


# ========================================================================
# ----------------------------- BEGIN Block ------------------------------
# ========================================================================
BEGIN {
    # Carp callback for sending fatal messages to browser
    sub handle_errors {
        my ($msg) = @_;
#        print "<p><pre>$msg</pre></p>";
    }
    set_message(\&handle_errors);
}

#--------------------------------------------------------------------------------

sub new {
	 my $Class = shift;

	 my $Self = bless {}, $Class;

	 return $Self;
}

#--------------------------------------------------------------------------------

sub getAlignment {
  my($self,$contig, $start, $stop, $strand) = @_;

  my $agpDir = $self->getMercatorOutputDir();
  my $alignDir = $self->getMercatorOutputDir()."/alignments";
  my $sliceAlign = $self->getCndSrcBin()."/sliceAlignment";
  my $fa2clustal = $self->getCndSrcBin()."/fa2clustal";

  my ($genome, $assembly, $assemblyStart, $assemblyStop, $assemblyStrand) = &translateCoordinates($contig, $agpDir, $start, $stop, $strand);

  &validateMapCoordinates($genome, $alignDir, $assembly, $assemblyStart, $assemblyStop, $agpDir);

  my $multiFasta = makeAlignment($alignDir, $agpDir, $sliceAlign, $genome, $assembly, $assemblyStart, $assemblyStop, $assemblyStrand);

  return $multiFasta;
}

sub getAlignmentLocations {
  my($self,$contig, $start, $stop, $strand) = @_;

  my $agpDir = $self->getMercatorOutputDir();
  my $alignDir = $self->getMercatorOutputDir()."/alignments";
  my $sliceAlign = $self->getCndSrcBin()."/sliceAlignment";
  my $fa2clustal = $self->getCndSrcBin()."/fa2clustal";

  my ($genome, $assembly, $assemblyStart, $assemblyStop, $assemblyStrand) = &translateCoordinates($contig, $agpDir, $start, $stop, $strand);

#  &validateMapCoordinates($genome, $alignDir, $assembly, $assemblyStart, $assemblyStop, $agpDir);

  my $locations = &getLocations($alignDir, $agpDir, $sliceAlign, $genome, $assembly, $assemblyStart, $assemblyStop, '+');

  return $locations;
}

#--------------------------------------------------------------------------------
sub initialize {
  my($self,$dbh,$mod,$csb) = @_;
  $self->setCndSrcBin($csb);
  $self->setMercatorOutputDir($mod);
  $self->setDbh($dbh);
}

sub setCndSrcBin { my($self,$val) = @_; $self->{CndSrcBin} = $val; }
sub getCndSrcBin { my $self = shift; return $self->{CndSrcBin}; }

sub setDbh { my($self,$val) = @_; $self->{dbh} = $val; }
sub getDbh { my $self = shift; return $self->{dbh}; }

sub setMercatorOutputDir { my($self,$dir) = @_; $self->{MercatorOutputdir} = $dir; }
sub getMercatorOutputDir { my $self = shift; return $self->{MercatorOutputdir}; }
#--------------------------------------------------------------------------------

sub translateCoordinates {
  my ($contig, $agpDir, $start, $stop, $strand) = @_;

  opendir(DIR, $agpDir) or &error("Could not open directory $agpDir for reading:$!");

  my ($genome, $assembly);

  while (defined (my $fn = readdir DIR) ) {

    print STDERR "AGPFILE=$fn\n";
    next unless($fn =~ /([\w\d_]+)\.agp$/);

    my $thisGenome = $1;

    open(AGP, "$agpDir/$fn") or &error("Cannot open file $fn for reading: $!");

    while(<AGP>) {
      chomp;
      my @a = split(/\t/, $_);
      my $assemblyName = $a[0];
      my $assemblyStart = $a[1];
      my $assemblyStop = $a[2];
      my $contigName = $a[5];
      my $contigStart = $a[6];
      my $contigStop = $a[7];
      my $contigStrand = $a[8];

      next unless($contigName eq $contig);

      if($genome) {
        &error("Source_id $contig was found in multiple genomes: $genome and $thisGenome");
      }
      $genome = $thisGenome;
      $assembly = $assemblyName;

      if($start > $contigStop || $stop < $contigStart) {
        &userError("Please enter coordinates between $contigStart-$contigStop for $contig");
      }

      # The -1 is because sliceAlign has a 1 off error
      if($contigStrand eq '+') {
        $start = $assemblyStart + ($start - $contigStart) - 1;
        $stop = $assemblyStop - ($contigStop - $stop);
      }
      else {
        my $tmpStop = $stop;
        $stop = $assemblyStop - ($start - $contigStart);
        $start = $assemblyStart +  ($contigStop - $tmpStop) -  1;
        $strand = $strand eq '+' ? '-' : '+';
      }
    }
    close AGP;
  }
  close DIR;

  unless($genome) {
    &userError("$contig was not found in any of the genomes which were input to mercator.\n\nUse the chromosome id for scaffolds which have been assembled into chromosomes");
  }
  return($genome, $assembly, $start, $stop, $strand);
}

#--------------------------------------------------------------------------------

sub validateMapCoordinates {
  my ($genome, $alignDir, $query, $start, $stop, $agpDir) = @_;

  my $mapfile = "$alignDir/map";
  my $genomesFile = "$alignDir/genomes";

  unless(-e $mapfile) {
    &error("Map file $mapfile does not exist");
  }

  unless(-e $genomesFile) {
    &error("Genomes file $genomesFile does not exist");
  }

  my $index;
  open(GENOME, $genomesFile) or &error("Cannot open file $genomesFile for reading: $!");
  my $line = <GENOME>;
  chomp $line;
  my @genomes = split(/\t/, $line);
  for(my $i = 0; $i < scalar(@genomes); $i++) {
    $index = ($i + 1) * 4 if($genomes[$i] eq $genome);
  }

  close GENOME;

  open(MAP, $mapfile) or error("Cannot open file $mapfile for reading: $!");

  my %mapped;

  while(<MAP>) {
    chomp;

    my @a = split(/\t/, $_);

    my $contig = $a[$index - 3];
    my $mapStart = $a[$index - 2];
    my $mapStop = $a[$index - 1];

    if(my $hash = $mapped{$contig}) {
      $mapped{$contig}->{start} = $hash->{start} < $mapStart ? $hash->{start} : $mapStart;
      $mapped{$contig}->{stop} = $hash->{stop} > $mapStop ? $hash->{stop} : $mapStop;
    }
    else {
      $mapped{$contig} = {start => $mapStart, stop => $mapStop};
    }
  }
  close MAP;

  unless($mapped{$query}) {
    &userError("There is no alignment data available for this Genomic Sequence:  $query.\n\nGenomic sequences with few or no genes will not be mapped.");
  }

  my $mapStart = $mapped{$query}->{start};
  my $mapStop = $mapped{$query}->{stop};

  if($start >= $mapStop || $stop <= $mapStart) {
    my $mappedCoord = replaceAssembled($agpDir, $genome, $query, $mapStart, $mapStop, '+');
    my ($junk, $included) = split(' ', $mappedCoord);

    userError("Whoops!  Those Coordinates fall outside a mapped region!\nThe available region for this contig is:  $included");
  }
}

#--------------------------------------------------------------------------------

sub validateMacros {
  my ($cgi) = @_;

  my $project = $cgi->param('project_id');
  my $props =  ApiCommonWebsite::Model::ModelProp->new($project);
  my $mercatorOutputDir = $props->{MERCATOR_OUTPUT_DIR};
  my $cndsrcBin =  $props->{CNDSRC_BIN};

  my $alignmentsDir = "$mercatorOutputDir/alignments";
  my $sliceAlignment = "$cndsrcBin/sliceAlignment";
  my $fa2clustal = "$cndsrcBin/fa2clustal";

  unless(-e $cndsrcBin) {
    error("cndsrc Bin directory does not exist [$cndsrcBin]");
  }
  unless(-e $sliceAlignment) {
    error("sliceAlignment exe does not exist [$sliceAlignment]");
  }
  unless(-e $fa2clustal) {
    error("fa2clustal exe does not exist [$fa2clustal]");
  }

  unless(-e $alignmentsDir) {
    error("alignments directory not found");
  }

  return($mercatorOutputDir, $alignmentsDir, $sliceAlignment, $fa2clustal);
}

#--------------------------------------------------------------------------------

sub replaceAssembled {
  my ($agpDir, $genome, $input, $start, $stop, $strand) = @_;

  my $fn = "$agpDir/$genome" . ".agp";

  open(FILE, $fn) or error("Cannot open file $fn for reading:$!");

  my @v;

  while(<FILE>) {
    chomp;

    my @ar = split(/\t/, $_);

    my $assembly = $ar[0];
    my $assemblyStart = $ar[1];
    my $assemblyStop = $ar[2];
    my $type = $ar[4];

    my $contig = $ar[5];
    my $contigStart = $ar[6];
    my $contigStop = $ar[7];
    my $contigStrand = $ar[8];

    next unless($type eq 'D');
    my $shift = $assemblyStart - $contigStart;
    my $checkShift = $assemblyStop - $contigStop;

    &error("Cannot determine shift") unless($shift == $checkShift);

    if($assembly eq $input && 
       (($start >= $assemblyStart && $start <= $assemblyStop) || 
        ($stop >= $assemblyStart && $stop <= $assemblyStop) ||
        ($start < $assemblyStart && $stop > $assemblyStop ))) {
      
      my ($newStart, $newStop, $newStrand);

      # the +1 and -1 is because of a 1 off error in the sliceAlign program
      if($contigStrand eq '+') {
        $newStart = $start < $assemblyStart ? $contigStart : $start - $assemblyStart + $contigStart + 1;
        $newStop = $stop > $assemblyStop ? $contigStop : $stop - $assemblyStart + $contigStart; 
        $newStrand = $strand;
      }
      else {
        $newStart = $start < $assemblyStart ? $contigStop : $assemblyStop - $start + $contigStart - 1;
        $newStop = $stop > $assemblyStop ? $contigStart : $assemblyStop - $stop + $contigStart;  
        $newStrand = $strand eq '+' ? '-' : '+';
      }

      if($newStart <= $newStop) {
        push(@v, "$contig:$newStart-$newStop($newStrand)");
      }
      else {
        push(@v, "$contig:$newStop-$newStart($newStrand)");
      }
    }
  }
  close FILE;

  return ">$genome " . join(';', @v);
}

#--------------------------------------------------------------------------------

sub getNewLocations {
  my ($agpDir, $genome, $input, $start, $stop, $strand) = @_;

  my $fn = "$agpDir/$genome" . ".agp";

  open(FILE, $fn) or error("Cannot open file $fn for reading:$!");

  my @v;

  while(<FILE>) {
    chomp;

    my @ar = split(/\t/, $_);

    my $assembly = $ar[0];
    my $assemblyStart = $ar[1];
    my $assemblyStop = $ar[2];
    my $type = $ar[4];

    my $contig = $ar[5];
    my $contigStart = $ar[6];
    my $contigStop = $ar[7];
    my $contigStrand = $ar[8];

    next unless($type eq 'D');
    my $shift = $assemblyStart - $contigStart;
    my $checkShift = $assemblyStop - $contigStop;

    &error("Cannot determine shift") unless($shift == $checkShift);

    if($assembly eq $input && 
       (($start >= $assemblyStart && $start <= $assemblyStop) || 
        ($stop >= $assemblyStart && $stop <= $assemblyStop) ||
        ($start < $assemblyStart && $stop > $assemblyStop ))) {
      
      my ($newStart, $newStop, $newStrand);

      # the +1 and -1 is because of a 1 off error in the sliceAlign program
      if($contigStrand eq '+') {
        $newStart = $start < $assemblyStart ? $contigStart : $start - $assemblyStart + $contigStart + 1;
        $newStop = $stop > $assemblyStop ? $contigStop : $stop - $assemblyStart + $contigStart; 
        $newStrand = $strand;
      }
      else {
        $newStart = $start < $assemblyStart ? $contigStop : $assemblyStop - $start + $contigStart - 1;
        $newStop = $stop > $assemblyStop ? $contigStart : $assemblyStop - $stop + $contigStart;  
        $newStrand = $strand eq '+' ? '-' : '+';
      }

      if($newStart <= $newStop) {
        push(@v, [$contig,$newStart,$newStop,$newStrand]);
      }
      else {
        push(@v, [$contig,$newStop,$newStart,$newStrand]);
      }
    }
  }
  close FILE;

  return \@v;
}

#--------------------------------------------------------------------------------

sub makeAlignment {
  my ($alignDir, $agpDir, $sliceAlign, $referenceGenome, $queryContig, $queryStart, $queryStop, $queryStrand) = @_;

  my $command = "$sliceAlign $alignDir $referenceGenome '$queryContig' $queryStart $queryStop $queryStrand";

  my @lines = `$command`;

#  my @lines = split(/\n/, $alignments);
  for(my $i = 0; $i < scalar (@lines); $i++) {
    my $line = $lines[$i];
    my ($genome, $assembled, $start, $stop, $strand) = $line =~ />(\w+) (\w+):(\d+)-(\d+)([-+])/;
    next unless($genome);

    my $replaced = &replaceAssembled($agpDir, $genome, $assembled, $start, $stop, $strand);

    $lines[$i] = $replaced."\n";

    if($line =~ />/) {
      $lines[$i] =~ s/([+|-])$/\($1\)/;
    }
  }

  return join("", @lines) . "\n";
}

#--------------------------------------------------------------------------------
sub getLocations {  ##get the locations and identifiers of all toxo seqs
  my ($alignDir, $agpDir, $sliceAlign, $referenceGenome, $queryContig, $queryStart, $queryStop, $queryStrand) = @_;


  my $command = "$sliceAlign $alignDir $referenceGenome '$queryContig' $queryStart $queryStop $queryStrand";
 
  my @lines = `$command`;
 
 
  my @locs;

  foreach my $line (@lines) {
    my ($genome, $assembled, $start, $stop, $strand) = $line =~ />([\w_\.]+) (\S*?):(\d+)-(\d+)([-+])/;


    next unless($genome);

    my $loc = &getNewLocations($agpDir, $genome, $assembled, $start, $stop, $strand);

    push(@locs,@$loc);

  }

  return \@locs;
}  
#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------

sub error {
  my ($msg) = @_;

  print STDERR "ERROR: $msg\n\nPlease report this error.  \nMake sure to include the error message, contig_id, start and end positions.\n";
}

sub userError {
  my ($msg) = @_;

  print STDERR "$msg\n\nPlease Try again!\n";
}

1;

__DATA__
body
{
font-family: courier, 'serif'; 
font-size: 100%;
font-weight: bold;
background-color: #F8F8FF;
}
b.red
{
font-family: courier, 'serif';
font-weight: bold;
color:#FF1800; 
}
b.maroon
{
font-family: courier, 'serif';
font-weight: bold;
color:#8B0000; 
}
tr 
{
font-family: courier, 'serif';
font-weight: normal;
font-size: 80%;
}



