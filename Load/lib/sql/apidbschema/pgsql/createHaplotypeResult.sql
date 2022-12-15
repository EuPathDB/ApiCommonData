CREATE TABLE apidb.HaplotypeResult (
 haplotype_result_id         NUMERIC(12) NOT NULL,
 na_feature_id               NUMERIC(12) NOT NULL, -- na_feature id for the haploblock
 protocol_app_node_id         NUMERIC(10) NOT NULL,
 value                        varchar(5),
 modification_date            TIMESTAMP NOT NULL,
 user_read                    NUMERIC(1) NOT NULL,
 user_write                   NUMERIC(1) NOT NULL,
 group_read                   NUMERIC(1) NOT NULL,
 group_write                  NUMERIC(1) NOT NULL,
 other_read                   NUMERIC(1) NOT NULL,
 other_write                  NUMERIC(1) NOT NULL,
 row_user_id                  NUMERIC(12) NOT NULL,
 row_group_id                 NUMERIC(3) NOT NULL,
 row_project_id               NUMERIC(4) NOT NULL,
 row_alg_invocation_id        NUMERIC(12) NOT NULL,
 FOREIGN KEY (na_feature_id) REFERENCES Dots.NAFeatureImp,
 FOREIGN KEY (protocol_app_node_id) REFERENCES Study.ProtocolAppNode,
 PRIMARY KEY (haplotype_result_id)
);

GRANT INSERT, SELECT, UPDATE, DELETE ON apidb.HaplotypeResult TO gus_w;
GRANT SELECT ON apidb.HaplotypeResult TO gus_r;

CREATE INDEX haprslt_revix0 ON apidb.HaplotypeResult (na_feature_id, haplotype_result_id) TABLESPACE indx;
CREATE INDEX haprslt_revix1 ON apidb.HaplotypeResult (protocol_app_node_id, haplotype_result_id) TABLESPACE indx;

------------------------------------------------------------------------------

CREATE SEQUENCE apidb.haplotyperesult_sq;

GRANT SELECT ON apidb.haplotyperesult_sq TO gus_r;
GRANT SELECT ON apidb.haplotyperesult_sq TO gus_w;

------------------------------------------------------------------------------

INSERT INTO core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable, 
     modification_date, user_read, user_write, group_read, group_write, 
     other_read, other_write, row_user_id, row_group_id, row_project_id, 
     row_alg_invocation_id)
SELECT NEXTVAL('core.tableinfo_sq'), 'HaplotypeResult',
       'Standard', 'haplotype_result_id',
       d.database_id, 0, 0, NULL, NULL, 1, localtimestamp, 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE lower(name) = 'apidb') d
WHERE 'haplotyperesult' NOT IN (SELECT lower(name) FROM core.TableInfo
                                    WHERE database_id = d.database_id);
