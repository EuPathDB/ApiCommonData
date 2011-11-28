/* table for SpliceSite sites */

CREATE TABLE apidb.SpliceSiteGenes (
  splice_site_feature_id        NUMERIC(10) not null,
  location                      NUMERIC(10) not null,
  strand                        CHAR(1), 
  source_id                     character varying(50),
  dist_to_cds                   NUMERIC(10) not null,
  within_cds                    NUMERIC(1),
  sample_name                   character varying(100),
  count                         NUMERIC(10),
  count_per_million             FLOAT(40), 
  avg_mismatches                FLOAT(40), 
  is_unique                     NUMERIC(1),
  type                          character varying(50),
  na_sequence_id                NUMERIC(10),
  external_database_release_id  NUMERIC(10),
  is_dominant                   NUMERIC(1), 
  percent_fraction              NUMERIC(3), 
  diff_to_next                  NUMERIC(3), 
  first_atg_location            NUMERIC(10),
  dist_to_first_atg             NUMERIC(10)
);

grant select on Apidb.SpliceSiteGenes to gus_r;
grant insert, select, update, delete on Apidb.SpliceSiteGenes to gus_w;

CREATE INDEX splicesitegenes_loc_idx
ON Apidb.SpliceSiteGenes (source_id, na_sequence_id, location, type)
tablespace indx

CREATE INDEX splicesitegenes_data_idx
ON Apidb.SpliceSiteGenes (splice_site_feature_id, count_per_million, sample_name, source_id)
tablespace indx



INSERT INTO core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable, 
     modification_date, user_read, user_write, group_read, group_write, 
     other_read, other_write, row_user_id, row_group_id, row_project_id, 
     row_alg_invocation_id)
SELECT core.tableinfo_sq.nextval, 'SpliceSiteGenes',
       'Standard', 'splice_site_feature_id',
       d.database_id, 0, 0, '', '', 1,sysdate, 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM dual,
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE name = 'ApiDB') d
WHERE 'SpliceSiteGenes' NOT IN (SELECT name FROM core.TableInfo
                                    WHERE database_id = d.database_id);

quit;
