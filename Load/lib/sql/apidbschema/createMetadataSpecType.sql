-- override the default type (string, number[, ...?] )
--  and filter (range, membership)
--  for MetadataSpec for filter params

CREATE TABLE apidb.MetadataSpecType (
 metadata_spec_type_id      NUMBER(12) NOT NULL,
 property                   VARCHAR(100) NOT NULL,
 type                       VARCHAR(10),
 filter                     VARCHAR(10),
 modification_date          DATE NOT NULL,
 user_read                  NUMBER(1) NOT NULL,
 user_write                 NUMBER(1) NOT NULL,
 group_read                 NUMBER(1) NOT NULL,
 group_write                NUMBER(1) NOT NULL,
 other_read                 NUMBER(1) NOT NULL,
 other_write                NUMBER(1) NOT NULL,
 row_user_id                NUMBER(12) NOT NULL,
 row_group_id               NUMBER(3) NOT NULL,
 row_project_id             NUMBER(4) NOT NULL,
 row_alg_invocation_id      NUMBER(12) NOT NULL
);

ALTER TABLE apidb.MetadataSpecType
ADD CONSTRAINT metdattyp_pk PRIMARY KEY (metadata_spec_type_id);

GRANT INSERT, SELECT, UPDATE, DELETE ON apidb.MetadataSpecType TO gus_w;
GRANT SELECT ON apidb.MetadataSpecType TO gus_r;

CREATE INDEX apidb.metdattyp_idx ON apidb.MetadataSpecType (property, type, filter);

------------------------------------------------------------------------------

CREATE SEQUENCE apidb.MetadataSpecType_sq;

GRANT SELECT ON apidb.MetadataSpecType_sq TO gus_r;
GRANT SELECT ON apidb.MetadataSpecType_sq TO gus_w;

------------------------------------------------------------------------------

INSERT INTO core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable, 
     modification_date, user_read, user_write, group_read, group_write, 
     other_read, other_write, row_user_id, row_group_id, row_project_id, 
     row_alg_invocation_id)
SELECT core.tableinfo_sq.nextval, 'MetadataSpecType',
       'Standard', 'metadata_spec_type_id',
       d.database_id, 0, 0, '', '', 1,sysdate, 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM dual,
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE lower(name) = 'apidb') d
WHERE 'metadataspectype' NOT IN (SELECT lower(name) FROM core.TableInfo
                                    WHERE database_id = d.database_id);

exit;
