--
-- these look like tuning tables (their names end in four digits) but no synonym points at them.
--

set pagesize 50000 linesize 100

SELECT 'drop table ' || owner || '.' || table_name || ';'
       AS "-- orphaned tuning tables"
FROM all_tables
WHERE table_name IN (SELECT table_name
                     FROM all_tables
                    MINUS
                     SELECT table_name
                     FROM all_synonyms
                    MINUS
                     SELECT mview_name
                     FROM all_mviews)
  AND REGEXP_REPLACE(table_name, '[0-9][0-9][0-9][0-9]$', 'fournumbers')
      LIKE '%fournumbers'
  AND table_name NOT LIKE 'QUERY_RESULT_%'
  AND owner != 'SYS'
  AND owner != 'APEX_030200'
  AND owner != 'CTXSYS'
  AND owner != 'EXFSYS'
  AND owner != 'SYSMAN'
  AND owner != 'WMSYS'
ORDER BY owner, table_name;

-- exit
