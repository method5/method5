CREATE OR REPLACE TYPE method4_poll_table_ot AUTHID CURRENT_USER AS OBJECT
--See Method4 package specification for details.
(
  atype ANYTYPE --<-- transient record type

, STATIC FUNCTION ODCITableDescribe(
                  rtype                     OUT ANYTYPE,
                  p_table_name              IN VARCHAR2,
                  p_sql_statement_condition IN VARCHAR2,
                  p_refresh_seconds         IN NUMBER DEFAULT 3
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITablePrepare(
                  sctx                      OUT method4_poll_table_ot,
                  tf_info                   IN  sys.ODCITabFuncInfo,
                  p_table_name              IN VARCHAR2,
                  p_sql_statement_condition IN VARCHAR2,
                  p_refresh_seconds         IN NUMBER DEFAULT 3
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITableStart(
                  sctx                      IN OUT method4_poll_table_ot,
                  p_table_name              IN VARCHAR2,
                  p_sql_statement_condition IN VARCHAR2,
                  p_refresh_seconds         IN NUMBER DEFAULT 3
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableFetch(
                  SELF  IN OUT method4_poll_table_ot,
                  nrows IN     NUMBER,
                  rws   OUT    anydataset
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableClose(
                  SELF IN method4_poll_table_ot
                  ) RETURN NUMBER

) NOT FINAL INSTANTIABLE;
/
