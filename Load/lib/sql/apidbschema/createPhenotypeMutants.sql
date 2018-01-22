create table ApiDB.PhenotypeMutants (
 phenotype_mutants_id           NUMBER(10),
 na_feature_id                  NUMBER(10),
 fgsc                           VARCHAR(50),
 pubmed                         NUMBER(10),
 mating_type                    VARCHAR(10),
 basal_hyphae_growth_rate       NUMBER(10),
 aerial_hyphae_height           NUMBER(10),
 conidia_production             VARCHAR(50),
 protoperithecia_production     VARCHAR(50),
 perithecia_production          VARCHAR(50),
 ascospore_production            VARCHAR(50),
 FOREIGN KEY (na_feature_id)    REFERENCES dots.NaFeatureImp,
 PRIMARY KEY (phenotype_mutants_id)
);

create index apidb.phenmutants_1
  on apidb.phenotypemutants (na_feature_id, phenotype_mutants_id) tablespace indx;

CREATE SEQUENCE apidb.PhenotypeMutants_sq;

GRANT INSERT, SELECT, UPDATE, DELETE ON apidb.Phenotypemutants TO gus_w;
GRANT SELECT ON apidb.Phenotypemutants TO gus_r;
GRANT SELECT ON apidb.Phenotypemutants_sq TO gus_w;

INSERT INTO core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable, 
     modification_date, user_read, user_write, group_read, group_write, 
     other_read, other_write, row_user_id, row_group_id, row_project_id, 
     row_alg_invocation_id)
SELECT core.tableinfo_sq.nextval, 'PhenotypeMutants',
       'Standard', 'phenotype_mutants_id',
       d.database_id, 0, 0, '', '', 1,sysdate, 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM dual,
     (SELECT MIN(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE name = 'ApiDB') d
WHERE 'phenotypemutants' NOT IN (SELECT LOWER(name) FROM core.TableInfo
                               WHERE database_id = d.database_id);


exit;
