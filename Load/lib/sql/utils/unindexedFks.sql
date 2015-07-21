
-- This query finds columns on which foreign-key constraints are defined but no index exists.

-- This is a potential performance problem. Consider, for example, the table SEQUENCE
-- whose column TAXON_ID references the TAXON_ID column of the TAXON table. Whenever
-- an update or delete causes a value to removed from TAXON.TAXON_ID, the TAXON_ID
-- field of every record in SEQUENCE must be checked to ensure that the change will
-- not violate the foreign-key constraint. If no index is defined on
-- SEQUENCE.TAXON_ID, then a full table scan must be performed.

-- The output of this query is in the form of the needed CREATE INDEX statement.

select distinct create_index
from (select 'create index ' || acc.owner || '.' || substr(acc.table_name, 1, 23)
             || '_revix' || mod(rownum, 10) ||' on ' || acc.owner || '.'
             || acc.table_name || ' (' || acc.column_name || ', '
             || nvl(pks.column_name, '??PK??') || ') tablespace indx; -- constraint '
             || ac.owner || '.' || ac.constraint_name
             as create_index
      from all_cons_columns acc, all_constraints ac,
           (select accp.owner || '.' || accp.table_name as tab, accp.column_name
            from all_constraints acp, all_cons_columns accp
            where acp.constraint_name = accp.constraint_name
              and constraint_type = 'P') pks
      where ac.constraint_name = acc.constraint_name
        and ac.owner = acc.owner
        and ac.constraint_type = 'R'
        and acc.position = 1
        and acc.owner || '.' || acc.table_name = pks.tab(+)
        and acc.owner in (select upper(name) from core.DatabaseInfo)
        and acc.owner || '.' || acc.table_name || '.' || acc.column_name
            not in (select table_owner || '.' || table_name || '.' || column_name
                    from all_ind_columns
                    where column_position = 1)
     )
order by create_index;
