package ApiCommonData::Load::gencodeGFF2BioperlTree;

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
# (4) create transcript
# (5) add to gene
# (6) create exons from sublocations
# (7) add to transcript



sub preprocess {
    my ($bioperlSeq, $plugin) = @_;

    my ($geneFeature, $source);
    my  $primerPair = '';

#    my $unflattener = Bio::SeqFeature::Tools::Unflattener->new;
#    $unflattener->unflatten_seq(-seq=>$bioperlSeq,-use_magic=>1);

    my @topSeqFeatures = $bioperlSeq->remove_SeqFeatures;

    foreach my $bioperlFeatureTree (@topSeqFeatures) {
        my $type = $bioperlFeatureTree->primary_tag();
        # print STDERR "Feature type is: $type\n";
        
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

            if($geneFeature->has_tag("gene_type")){
                my($geneType) = $geneFeature->get_tag_values("gene_type");

                if($geneType =~ /pseudogene/i){
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

            my ($geneArrayRef,$UTRArrayRef) = &traverseSeqFeatures($geneFeature, $bioperlSeq);

            my @genes = @{$geneArrayRef};
            foreach my $gene (@genes) {
                $bioperlSeq->add_SeqFeature($gene);
            }
            
            my @UTRs = @{$UTRArrayRef};
            foreach my $UTR (@UTRs){
                #print STDERR Dumper $UTR;
                $bioperlSeq->add_SeqFeature($UTR);
            }
        
        }else{

            if($type eq 'gap' || $type eq 'direct_repeat' || $type eq 'three_prime_utr' 
                            || $type eq 'five_prime_utr' || $type eq 'splice_acceptor_site' || $type eq 'UTR'){
                $bioperlSeq->add_SeqFeature($bioperlFeatureTree);
            }
        }

    }
}

sub traverseSeqFeatures {
    my ($geneFeature, $bioperlSeq) = @_;
    
    my (@genes, $gene, @UTRs);

    my @RNAs = $geneFeature->get_SeqFeatures;

    my $transcriptCount = scalar @RNAs;
    my $ctr = 1;

    # This will accept genes of type misc_feature (e.g. cgd4_1050 of GI:46229367)
    # because it will have a geneFeature but not standalone misc_feature 
    # as found in GI:32456060.
    # And will accept transcripts that do not have 'gene' parents (e.g. tRNA
    # in GI:32456060)

    foreach my $RNA ( sort {$a->location->start <=> $b->location->start || $a->location->end <=> $b->location->end} @RNAs){ 
    my $type = $RNA->primary_tag;

        if (grep {$type eq $_} (
             'transcript',
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

        
       #print STDERR "-----------------$type----------------------\n";

        if($type eq 'transcript'){
#            $type = 'coding';
            my ($geneType) = $RNA->get_tag_values("gene_type") if ($RNA->has_tag("gene_type"));
            my ($transType) = $RNA->get_tag_values("transcript_type") if ($RNA->has_tag("transcript_type"));
            $type = &getTypeOfGene($geneType, $transType) if ($geneType);
        }

        if($type eq 'ncRNA'){
            if($RNA->has_tag('ncRNA_class')){
                ($type) = $RNA->get_tag_values('ncRNA_class');
                $RNA->remove_tag('ncRNA_class');
            }
        }


        $gene = &makeBioperlFeature("${type}_gene", $geneFeature->location, $bioperlSeq);
        my($geneID) = $geneFeature->get_tag_values('ID');

        if($transcriptCount > 1){
            $geneID = $geneID."\.$ctr";
            $ctr++;
        }

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

        my (@exons, @codingStart, @codingEnd);
        
        my $CDSctr =0;

        my $prevPhase =0;
        
        my($codingStart,$codingEnd);

        foreach my $subFeature (sort {$a->location->start <=> $b->location->start} @containedSubFeatures){

            $codonStart = $subFeature->frame();

            if($subFeature->primary_tag eq 'exon'){
                my $exon = &makeBioperlFeature($subFeature->primary_tag,$subFeature->location,$bioperlSeq);
                push(@exons,$exon);
            }

            if($subFeature->primary_tag eq 'CDS'){

                if($subFeature->location->strand == -1){
                    $codingStart = $subFeature->location->end;
                    $codingEnd = $subFeature->location->start;
                    $codingStart -= $subFeature->frame() if ($subFeature->frame() > 0);

                }else{
                    $codingStart = $subFeature->location->start;
                    $codingEnd = $subFeature->location->end;
                    $codingStart += $subFeature->frame() if ($subFeature->frame() > 0);

                }
                push(@codingStart,$codingStart);
                push(@codingEnd,$codingEnd);

                $CDSctr++;
            }

            if ($subFeature->primary_tag eq 'five_prime_utr' || $subFeature->primary_tag eq 'three_prime_utr' 
                    || $subFeature->primary_tag eq 'splice_acceptor_site' || $subFeature->primary_tag eq 'UTR'){
                
                my $UTR = &makeBioperlFeature($subFeature->primary_tag,$subFeature->location,$bioperlSeq);

                $UTR = &copyQualifiers($subFeature,$UTR);

                push(@UTRs,$UTR);
            }
        }

        
        $codingStart = shift(@codingStart);
        $codingEnd = shift(@codingEnd);
        foreach my $exon (@exons){
            if($codingStart <= $exon->location->end && $codingStart >= $exon->location->start){
                $exon->add_tag_value('CodingStart',$codingStart);
                $exon->add_tag_value('CodingEnd',$codingEnd);

                $codingStart = shift(@codingStart);
                $codingEnd = shift(@codingEnd);
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
        push(@genes, $gene);

    }
    }
    return (\@genes ,\@UTRs);
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


sub getTypeOfGene {
    my ($geneType, $transType) = @_;

    my $returnType = 'just testing';

    my %geneTypes = (
        protein_coding => 'coding',
        IG_C_gene => 'coding',
        IG_D_gene => 'coding',
        IG_J_gene => 'coding',
        IG_V_gene => 'coding',
        TR_C_gene => 'coding',
        TR_D_gene => 'coding',
        TR_J_gene => 'coding',
        TR_V_gene => 'coding',
        IG_C_pseudogene => 'coding',
        IG_J_pseudogene => 'coding',
        IG_V_pseudogene => 'coding',
        TR_J_pseudogene => 'coding',
        TR_V_pseudogene => 'coding',
        Mt_rRNA => 'rRNA',
        rRNA => 'rRNA',
        Mt_tRNA => 'tRNA',
        tRNA => 'tRNA',
        snRNA => 'snRNA',
        snoRNA => 'snoRNA',
        miRNA => 'miRNA',
        lincRNA => 'ncRNA',
#        3prime_overlapping_ncrna => 'ncRNA',
        non_coding => 'ncRNA',
        misc_RNA => 'misc_RNA',
        antisense => 'misc_RNA',
        sense_intronic => 'misc_RNA',
        sense_overlapping => 'misc_RNA',
    );

    if ($geneTypes{$geneType} ) {
        $returnType = $geneTypes{$geneType};
    } else {
        if ($geneType =~ /pseudogene/ ) {
            if ($transType eq 'protein_coding') {
                $returnType = "coding";
            } else {
                $returnType = "tRNA";
            }
        } elsif ($geneType =~ /3prime_overlapping_ncrna/ ) {
            $returnType = "ncRNA";
        } else {
            $returnType = "misc_RNA";
        }
    }
    return $returnType;
}

1;
