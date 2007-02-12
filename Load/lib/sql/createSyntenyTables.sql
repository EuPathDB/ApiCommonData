GRANT references ON DoTS.NaSequenceImp TO ApiDB;
GRANT references ON SRes.ExternalDatabaseRelease TO ApiDB;

------------------------------------------------------------------------------

CREATE TABLE ApiDB.Synteny (
 synteny_id  NUMBER(10),
 external_database_release_id NUMBER(10),
 a_na_sequence_id  NUMBER(10),	
 b_na_sequence_id  NUMBER(10),	
 a_start NUMBER(8),
 a_end NUMBER(8),
 b_start NUMBER(8),
 b_end NUMBER(8),
 is_reversed NUMBER(3),
 MODIFICATION_DATE     DATE,
 USER_READ             NUMBER(1),
 USER_WRITE            NUMBER(1),
 GROUP_READ            NUMBER(1),
 GROUP_WRITE           NUMBER(1),
 OTHER_READ            NUMBER(1),
 OTHER_WRITE           NUMBER(1),
 ROW_USER_ID           NUMBER(12),
 ROW_GROUP_ID          NUMBER(3),
 ROW_PROJECT_ID        NUMBER(4),
 ROW_ALG_INVOCATION_ID NUMBER(12),
 FOREIGN KEY (a_na_sequence_id) REFERENCES DoTS.NaSequenceImp (na_sequence_id),
 FOREIGN KEY (b_na_sequence_id) REFERENCES DoTS.NaSequenceImp (na_sequence_id),
 FOREIGN KEY (external_database_release_id) REFERENCES SRes.ExternalDatabaseRelease (external_database_release_id),
 PRIMARY KEY (synteny_id)
);

CREATE SEQUENCE ApiDB.Synteny_sq;

GRANT insert, select, update, delete ON ApiDB.Synteny TO gus_w;
GRANT select ON ApiDB.Synteny TO gus_r;
GRANT select ON ApiDB.Synteny_sq TO gus_w;

INSERT INTO core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable, 
     modification_date, user_read, user_write, group_read, group_write, 
     other_read, other_write, row_user_id, row_group_id, row_project_id, 
     row_alg_invocation_id)
SELECT core.tableinfo_sq.nextval, 'Synteny',
       'Standard', 'synteny_id',
       d.database_id, 0, 0, '', '', 1,sysdate, 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM dual,
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE name = 'ApiDB') d
WHERE 'Synteny' NOT IN (SELECT name FROM core.TableInfo
                                    WHERE database_id = d.database_id);

------------------------------------------------------------------------------
exit;
