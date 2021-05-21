package ApiCommonData::Load::DeseqAnalysis;
use base qw(CBIL::TranscriptExpression::DataMunger::Loadable);
use CBIL::Util::Utils;
use strict;
use Data::Dumper;
#uses DESeq.r script 

sub getSampleName {$_[0]->{sampleName}}
sub getSamplesHash {$_[0]->{samplesHash}}
sub getSuffix {$_[0]->{suffix}}
sub getMainDirectory {$_[0]->{mainDirectory}}
sub getReference {$_[0]->{reference}}
sub getComparator {$_[0]->{comparator}}
sub getRefCheck {$_[0]->{referenceCheck}}
sub getCompCheck {$_[0]->{comparatorCheck}}

sub new {
    my ($class, $args) = @_;
    
    my $requiredParams = [
	'sampleName',
	'samplesHash',
	'mainDirectory'
	];
    my $self = $class->SUPER::new($args, $requiredParams);
    
    
    my $cleanSampleName = $self->getSampleName();
    $cleanSampleName =~ s/ /_/g;
    my $suffix = $self->getSuffix();
    $self->setOutputFile($cleanSampleName.$suffix);
    
    
    return $self;
}

sub munge {
    my ($self) = @_;
    my $samplesHashref = $self->getSamplesHash();
    my $suffix = $self->getSuffix();
    my $sampleName = $self->getSampleName();
    $sampleName =~ s/_vs_/ vs /;
    my $mainDirectory=$self->getMainDirectory();
    my $outputFile = $self->getOutputFile();
    my $reference = $self->getReference();
    my $comparator = $self->getComparator();
    my $refCheck = $self->getRefCheck();
    my $compCheck = $self->getCompCheck();
    $self->setNames([$sampleName]);
    my $fileName = $outputFile."_formatted";
    $fileName =~ s/ /_/g;
    $self->setFileNames([$fileName]);    
    my @inputs;
    
    my %samplesHash = %{$samplesHashref};
    
#    print Dumper %samplesHash;
    
    opendir(DIR, $mainDirectory);
    my @ds = readdir(DIR);
    my %ref;
    my %comp;
    my $append;
    if ($suffix =~ /Firststrand/) {
	$append = ".firststrand";
    }
    elsif ($suffix =~ /Secondstrand/) {
	$append = ".secondstrand";
    }
    else {
	$append = ".unstranded";
    } 
    my $dataframeFile = $sampleName.$append."_dataframe.txt";
    $dataframeFile =~ s/ /_/g;
    open(my $dataframe, ">$mainDirectory/$dataframeFile");
    print $dataframe "sample\tfile\tcondition\n";
    foreach my $d (sort @ds) {
	next unless $d =~ /(\S+)\.genes\.htseq-union${append}\.counts/;
	next unless $d !~ /combined/;
	my $sample = $1;
#	print  "sample (deseqanalysis.pm) is ${sample}";
#	my $refKey = $reference;
#	$refKey =~ s/ /_/g;
#	print "ref to check is ${refCheck}";
#	my $compKey = $comparator;
#	$compKey =~ s/ /_/g;
#	print " comp to check is ${compCheck}";
#	print "reference is $reference";
#	print "comparator is $comparator";
	
	my @referenceArray = @{$samplesHash{$reference}};
	my @comparatorArray= @{$samplesHash{$comparator}};
	
	foreach my $element(@referenceArray) {
	    if ($sample eq $element) {
		$ref{$sample} = $d;
		push @inputs, $sample;
		print  "putting $d as the reference with $sample as reference\n";
	    }
	    else {
		next;
	    }
	}
	foreach my $element(@comparatorArray) {
	    if ($sample eq $element) {
		$comp{$sample} = $d;
		push @inputs, $sample;
		print  "putting $d as the comparator with $sample as comparator\n";
	    }
	    else {
		next;
	    }
	}
	

	
# 	if (($refCheck =~ /$compCheck/) || ($compCheck =~ /$refCheck/)) { 
# 	    if ($refCheck eq $compCheck) {
	
# 		die "WARNING reference and comparator matched strings are the same\n";
# 	    }
# 	    else {
# 		if ($refCheck =~ /$compCheck/) {
# 		    #ref is longer 
# 		    if ($sample =~ /^$refCheck/) {
# 			$ref{$sample} = $d;
# 			push @inputs, $sample;
# #			print  "putting $d as the reference with $sample as reference\n";
			
# 		    }
# 		    elsif (($sample =~ /^$compCheck/) && ($sample !~ /^$refCheck/)) {
# 			$comp{$sample} = $d;
# 			push @inputs, $sample;
# #			print  "putting $d as the comparator with $sample as comparator\n";
# 		    }
# 		    else {
# 			print "sample:: $sample ::  in deseqanalysis.pm sub munge creating ref and comp hashes doesnt match the reference or the comparator\n";
# 		    }
# 		}
# 		elsif ($compCheck =~ /$refCheck/) {
# 		    #comp is longer 
		   
#                     if ($sample =~ /^$compCheck/) {
#                         $comp{$sample} = $d;
#                         push @inputs, $sample;
# #                        print  "putting $d as the comparator with $sample as comparator\n";
			
#                     }
#                     elsif (($sample =~ /^$refCheck/) && ($sample !~ /^$compCheck/)) {
#                         $ref{$sample} = $d;
#                         push @inputs, $sample;
# #                        print  "putting $d as the reference  with $sample as reference\n";
#                     }
#                     else {
#                         print "sample:: $sample ::  in deseqanalysis.pm sub munge creating ref and comp hashes doesnt match the reference or the compara\
# tor\n";
#                     }
# 		}
# 		else {
# 		    print "Something is wrong, the reference and comparator are not being determined. look at DeseqAnalysis.pm line 116";
# 		}
# 	    }
# 	}
# 	else {
# 	    if ($sample =~ /^$refCheck/) {
# 		$ref{$sample} = $d;
# 		push @inputs, $sample;
# #		print  "putting $d as the reference with $sample as reference\n";
		
# 	    }
# 	    elsif ($sample =~ /^$compCheck/) {
# 		$comp{$sample} = $d;
# 		push @inputs, $sample;
# #		print  "putting $d as the comparator with $sample as comparator\n";
# 	    }
# 	    else {
# 		print "sample:: $sample ::  in deseqanalysis.pm sub munge creating ref and comp hashes doesnt match the reference or the comparator\n";
# 	    }
# 	}
    }	
    foreach my $rep (keys %ref) {
	print $dataframe $rep."\t".$ref{$rep}."\treference\n";
    }
    foreach my $rep (keys %comp) {
	print $dataframe $rep."\t".$comp{$rep}."\tcomparator\n";
    }
	
    
	
	
	close($dataframe);
	
	$outputFile =~ s/ /_/g;
    eval { &runCmd("DESeq.r $dataframeFile $mainDirectory $mainDirectory $outputFile") };
    if ($@) {
        print "Coverage is no deep enough to run DESeq2. Differential expression will not be loaded for this contrast.\n";
    }
    else {
        open(my $OUT, ">$mainDirectory\/$fileName");
        print $OUT "ID\tfold_change\tp_value\tadj_p_value\n";
        open( my $IN, "$mainDirectory\/$outputFile");

        while (my $line = <$IN>) {
        chomp $line;
    #	print "gettting to the printing of the formatted file\n\n\n\n\n ";
        if ($line =~/baseMean/) {
            #skip header
            next;
        }
        else {
            my @temps = split ",", $line;
            my $reportedFC;
            my $id = $temps[0];
            $id =~ s/"//g;
            my $log2fc = $temps[2];
            my $foldchange = 2**$log2fc;
            if ($foldchange >1 ) {
            #its ok leave it alone
                $reportedFC = $foldchange;
            }
            else {
            $reportedFC = (1/$foldchange)*(-1);
            }
            my $pval = $temps[5];
            my $adjp = $temps[6];
            print $OUT $id."\t".$reportedFC."\t".$pval."\t".$adjp."\n";
        }
       }

        close ($IN);
        close($OUT);

        ####################################################################################################
        my $input_list = \@inputs;
        $self->setSourceIdType('gene');
        $self->setInputProtocolAppNodesHash({$sampleName => $input_list});
        $self->getProtocolParamsHash();
        $self->addProtocolParamValue('reference',$reference);
        $self->addProtocolParamValue('comparator',$comparator);
        $self->createConfigFile();
    }
}


1;
