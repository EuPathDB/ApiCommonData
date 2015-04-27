package ApiCommonData::Load::GenemRNACDSexonUTR2BioperlTree;

# Remove existing gene features, promote CDS, tRNA, etc to gene

use strict;
use Bio::Location::Simple;
use ApiCommonData::Load::BioperlTreeUtils qw{makeBioperlFeature};
use Data::Dumper;
use Bio::SeqFeature::Tools::Unflattener;
use Data::Dumper;

#input:
#
# gene  [folded into CDS]
# mRNA  (optional)  [discarded]
# CDS
#
#output: standard api tree: gene->transcript->exons

# (0) remove all seq features, add back the non-genes
# (1) copy old gene qualifiers to cds/rna feature
# (2) retype CDS into Gene
# (3) remember its join locations
# (4) create transcript, give it a copy of the gene's location
# (5) add to gene
# (6) create exons from sublocations
# (7) add to transcript

#Need to check if codon_start qualifier (reading frame) in Genbank files for CDS is relative to the CDS positions. This code assumes that it is
# Need extra work if the codonStart value gets from get_tag_values('codon_start') 

sub preprocess {
    my ($bioperlSeq, $plugin) = @_;

    my ($geneFeature, $source);
    my  $primerPair = '';
#    my $unflattener = Bio::SeqFeature::Tools::Unflattener->new;

	#$unflattener->unflatten_seq(-seq=>$bioperlSeq,-use_magic=>1);
	my @topSeqFeatures = $bioperlSeq->remove_SeqFeatures;



	    


	foreach my $bioperlFeatureTree (@topSeqFeatures) {
	    my $type = $bioperlFeatureTree->primary_tag();
	    
	    if($type eq 'pseudogene'){
		$bioperlFeatureTree->primary_tag('gene');
		$bioperlFeatureTree->add_tag_value("pseudo","");
		$type = "gene";
	    }


	    if($type eq 'repeat_region'){
		if($bioperlFeatureTree->has_tag("satellite")){
		    $bioperlFeatureTree->primary_tag("microsatellite");
		}
		if(!($bioperlFeatureTree->has_tag("ID"))){
		    $bioperlFeatureTree->add_tag_value("ID",$bioperlSeq->accession());
		}

		$bioperlSeq->add_SeqFeature($bioperlFeatureTree);
	    }
	    if($type eq 'STS'){
		if(!($bioperlFeatureTree->has_tag("ID"))){
		    $bioperlFeatureTree->add_tag_value("ID",$bioperlSeq->accession());
		}
		$bioperlSeq->add_SeqFeature($bioperlFeatureTree);
	    }
	    if ($type eq 'gene') {

		$geneFeature = $bioperlFeatureTree; 
		if(!($geneFeature->has_tag("ID"))){
		    $geneFeature->add_tag_value("ID",$bioperlSeq->accession());
		}      

		if (($geneFeature->has_tag("ID"))){
			my ($cID) = $geneFeature->get_tag_values("ID");
			print STDERR "processing $cID...\n";
		}

		if($geneFeature->has_tag("Note")){
		    my($note) = $geneFeature->get_tag_values("Note");

		    if($note =~ /pseudogene/i){
			$geneFeature->add_tag_value("pseudo","");
		    }
		}
		for my $tag ($geneFeature->get_all_tags) {    

		    if($tag eq 'pseudo'){

			if ($geneFeature->get_SeqFeatures){
			    next;
			}else{
			    $geneFeature->primary_tag("coding_gene");
			    my $geneLoc = $geneFeature->location();
			    my $transcript = &makeBioperlFeature("transcript", $geneLoc, $bioperlSeq);
			    my @exonLocs = $geneLoc->each_Location();
			    foreach my $exonLoc (@exonLocs){
				my $exon = &makeBioperlFeature("exon",$exonLoc,$bioperlSeq);
				$transcript->add_SeqFeature($exon);
			    }
			    $geneFeature->add_SeqFeature($transcript);
			    $bioperlSeq->add_SeqFeature($geneFeature);
			}
			
		    }
		}       
		my ($gene,$UTRArrayRef) = &traverseSeqFeatures($geneFeature, $bioperlSeq);

		my @UTRs = @{$UTRArrayRef};
		if($gene){

		    $bioperlSeq->add_SeqFeature($gene);
		}
		
		foreach my $UTR (@UTRs){


		#    print STDERR Dumper $UTR;
		    $bioperlSeq->add_SeqFeature($UTR);
		}

	    
	    }else{

		if($type eq 'gap' || $type eq 'direct_repeat' || $type eq 'three_prime_utr' || $type eq 'five_prime_utr' || $type eq 'splice_acceptor_site'){
		    $bioperlSeq->add_SeqFeature($bioperlFeatureTree);
		}

	    ## deal with tRNA that does not have 'gene' parents (e.g. tRNA in GI:32456060)
            if($type eq 'tRNA') {
                $geneFeature = $bioperlFeatureTree;

                my $geneLoc = $geneFeature->location();
                my $gene = &makeBioperlFeature("tRNA_gene", $geneLoc, $bioperlSeq);

		my ($geneID) = $geneFeature->get_tag_values('ID');
		$gene->add_tag_value("ID",$geneID);
                $gene = &copyQualifiers($geneFeature, $gene);

                my $transcript = &makeBioperlFeature("transcript", $geneLoc, $bioperlSeq);

                my @exonLocs = $geneLoc->each_Location();
                foreach my $exonLoc (@exonLocs){
                    my $exon = &makeBioperlFeature("exon",$exonLoc,$bioperlSeq);
                    $exon->add_tag_value('CodingStart', '');
                    $exon->add_tag_value('CodingEnd', '');
                    $transcript->add_SeqFeature($exon);
                }
                $gene->add_SeqFeature($transcript);
                $bioperlSeq->add_SeqFeature($gene);
            }  ## end for type eq tRNA

	    }

	}
}

sub traverseSeqFeatures {
    my ($geneFeature, $bioperlSeq) = @_;
    
    my ($gene,@UTRs);

    my @RNAs = $geneFeature->get_SeqFeatures;

    # This will accept genes of type misc_feature (e.g. cgd4_1050 of GI:46229367)
    # because it will have a geneFeature but not standalone misc_feature 
    # as found in GI:32456060.
    # And will accept transcripts that do not have 'gene' parents (e.g. tRNA
    # in GI:32456060)
    foreach my $RNA (@RNAs){ 
	my $type = $RNA->primary_tag;
        if (grep {$type eq $_} (
             'mRNA',
             'misc_RNA',
             'rRNA',
             'snRNA',
             'snoRNA',
             'tRNA',
             'ncRNA',
	     'pseudogenic_transcript',	
             'scRNA',
				
             )
        ) {



	    
	   # print STDERR "-----------------$type----------------------\n";

	    if($type eq 'ncRNA'){
		if($RNA->has_tag('ncRNA_class')){
		    ($type) = $RNA->get_tag_values('ncRNA_class');
		    $RNA->remove_tag('ncRNA_class');

		}
	    }


	    if($type eq 'mRNA'){
		$type = 'coding';

	    }
	    #$gene = &makeBioperlFeature("${type}_gene", $geneFeature->location, $bioperlSeq);
	    $gene = &makeBioperlFeature("${type}_gene", $RNA->location, $bioperlSeq);  ## for gene use transcript location instead of gene location
	    my($geneID) = $geneFeature->get_tag_values('ID');

	    #print "ID:$geneID\n";
	    $gene->add_tag_value("ID",$geneID);
	    $gene = &copyQualifiers($geneFeature, $gene);
            $gene = &copyQualifiers($RNA,$gene);
	    my $transcript = &makeBioperlFeature("transcript", $RNA->location, $bioperlSeq);
  	    #$transcript = &copyQualifiers($RNA,$transcript);

	    my @containedSubFeatures = $RNA->get_SeqFeatures;
	    
	    my $codonStart = 0;
	    
	    ($codonStart) = $gene->get_tag_values('codon_start') if $gene->has_tag('codon_start');
	    $codonStart -= 1 if $codonStart > 0;

	    if($gene->has_tag('selenocysteine')){
		$gene->remove_tag('selenocysteine');
		$gene->add_tag_value('selenocysteine','selenocysteine');
	    }

	    #my (@exons, @codingStart, @codingEnd);
	    my (@exons, @codingStartAndEndPairs);
	    
	    foreach my $subFeature (sort {$a->location->start <=> $b->location->start} @containedSubFeatures){

		if($subFeature->primary_tag eq 'exon'){
		    my $exon = &makeBioperlFeature($subFeature->primary_tag,$subFeature->location,$bioperlSeq);
		    push(@exons,$exon);
		}

		if($subFeature->primary_tag eq 'CDS'){
		    my $cdsStrand = $subFeature->location->strand;
		    my $cdsFrame = $subFeature->frame();

		    if($subFeature->location->strand == -1){
			my $cdsCodingStart = $subFeature->location->end;
			my $cdsCodingEnd = $subFeature->location->start;
			push (@codingStartAndEndPairs, "$cdsCodingStart\t$cdsCodingEnd\t$cdsStrand\t$cdsFrame");
		    }else{
			my $cdsCodingStart = $subFeature->location->start;
			my $cdsCodingEnd = $subFeature->location->end;
			push (@codingStartAndEndPairs, "$cdsCodingStart\t$cdsCodingEnd\t$cdsStrand\t$cdsFrame");
		    }
		}

		if ($subFeature->primary_tag eq 'five_prime_utr' || $subFeature->primary_tag eq 'three_prime_utr' || $subFeature->primary_tag eq 'splice_acceptor_site'){
		    
		    my $UTR = &makeBioperlFeature($subFeature->primary_tag,$subFeature->location,$bioperlSeq);
		    $UTR = &copyQualifiers($subFeature,$UTR);
		    push(@UTRs,$UTR);
		}

	    }

	    ## deal with codonStart, use the frame of the 1st CDS to assign codonStart
	    foreach my $j (0..$#codingStartAndEndPairs) {
	      my ($start, $end, $strand, $frame) = split (/\t/, $codingStartAndEndPairs[$j]);
	      if ($j == 0 && $strand ==1 && $frame > 0) {
		$start += $frame;
		$codingStartAndEndPairs[$j] = "$start\t$end\t$strand\t$frame";
	      } elsif ($j == $#codingStartAndEndPairs && $strand == -1 && $frame > 0) {
		$start -= $frame;
		$codingStartAndEndPairs[$j] = "$start\t$end\t$strand\t$frame";
	      }
	    }

	    ## add codingStart and codingEnd
	    my ($codingStart, $codingEnd) = split(/\t/, shift(@codingStartAndEndPairs) );

	    foreach my $exon (@exons){

		if($codingStart <= $exon->location->end && $codingStart >= $exon->location->start){
		    $exon->add_tag_value('CodingStart',$codingStart);
		    $exon->add_tag_value('CodingEnd',$codingEnd);
		    ($codingStart, $codingEnd) = split(/\t/, shift(@codingStartAndEndPairs) );
		} else {
		    $exon->add_tag_value('CodingStart',"");
		    $exon->add_tag_value('CodingEnd',"");
		}

		$transcript->add_SeqFeature($exon);
	    }		    
	    
  	    if(!($transcript->get_SeqFeatures())){
		my @exonLocs = $RNA->location->each_Location();
		foreach my $exonLoc (@exonLocs){
		    my $exon = &makeBioperlFeature("exon",$exonLoc,$bioperlSeq);
		    $transcript->add_SeqFeature($exon);
		    if($gene->primary_tag ne 'coding_gene' && $gene->primary_tag ne 'pseudo_gene' ){
			$exon->add_tag_value('CodingStart', '');
			$exon->add_tag_value('CodingEnd', '');	
		    }

		}
	    }

	    
	    if($gene->location->start > $transcript->location->start){
		print STDERR "The transcript for gene $geneID is not within parent boundaries.\n";
		$gene->location->start($transcript->location->start);
	    }

	    
	    if($gene->location->end < $transcript->location->end){
		print STDERR "The transcript for gene $geneID is not within parent boundaries.\n";
		$gene->location->end($transcript->location->end);
	    }

	$gene->add_SeqFeature($transcript);

	}
    }
    return ($gene,\@UTRs);
}


sub copyQualifiers {
  my ($geneFeature, $bioperlFeatureTree) = @_;
  
  for my $qualifier ($geneFeature->get_all_tags()) {

    if ($bioperlFeatureTree->has_tag($qualifier) && $qualifier ne "ID" && $qualifier ne "Parent" && $qualifier ne "Derives_from") {
      # remove tag and recreate with merged non-redundant values
      my %seen;
      my @uniqVals = grep {!$seen{$_}++} 
                       $bioperlFeatureTree->remove_tag($qualifier), 
                       $geneFeature->get_tag_values($qualifier);
                       
      $bioperlFeatureTree->add_tag_value(
                             $qualifier, 
                             @uniqVals
                           );    
    } elsif($qualifier ne "ID" && $qualifier ne "Parent" && $qualifier ne "Derives_from") {
      $bioperlFeatureTree->add_tag_value(
                             $qualifier,
                             $geneFeature->get_tag_values($qualifier)
                           );
    }
     
  }
  return $bioperlFeatureTree;
}

1;
