drop index dots.AaSeq_source_ix;
drop index dots.NaFeat_alleles_ix;
drop index dots.AaSequenceImp_string2_ix;
drop index dots.nasequenceimp_string1_seq_ix;
drop index dots.nasequenceimp_string1_ix;
drop index dots.ExonOrder_ix;
drop index dots.SeqvarStrain_ix;

alter table dots.sequencePiece DROP ( start_position, end_position );

exit
