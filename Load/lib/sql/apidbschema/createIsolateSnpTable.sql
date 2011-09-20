drop table Apidb.IsolateSNPs;

create table Apidb.IsolateSNPs as
select s.na_sequence_id as is_na_sequence_id,atr.source_id as is_source_id, s.name,s.isolate, 
f.allele,snpf.source_id as snp_source_id,d.name as snp_db_name,snpf.na_sequence_id as snp_na_sequence_id,snpl.start_min as snp_start_min
from dots.ISOLATEFEATURE f, dots.ISOLATESOURCE s, dots.NALOCATION il, dots.SNPFEATURE snpf, 
dots.NALOCATION snpl,Apidb.IsolateAttributes atr, sres.externaldatabaserelease rel, sres.externaldatabase d
where s.na_feature_id = f.parent_id
and s.na_sequence_id = atr.NA_SEQUENCE_ID
and il.na_feature_id = f.na_feature_id
and snpf.na_sequence_id = f.na_sequence_id
and snpl.na_feature_id = snpf.na_feature_id
and snpl.start_min = il.start_min
and snpf.external_database_release_id = rel.external_database_release_id
and rel.external_database_id = d.external_database_id
and d.name in ('PlasmoDB combined SNPs','Broad SNPs','Sanger falciparum SNPs','Su SNPs');

commit;

GRANT SELECT ON Apidb.IsolateSNPs TO gus_r;
GRANT SELECT ON Apidb.IsolateSNPs TO gus_w;

create index Apidb.IsolateSNPs_is_sid_idx on Apidb.IsolateSNPs (is_source_id);
create index Apidb.IsolateSNPs_snp_db_id_idx on Apidb.IsolateSNPs (snp_db_name,snp_source_id,allele);
create index Apidb.IsolateSNPs_snp_id_idx on Apidb.IsolateSNPs (snp_source_id);
create index Apidb.IsolateSNPs_snp_seq_start_idx on Apidb.IsolateSNPs (snp_na_sequence_id,snp_start_min);

commit;

quit;
