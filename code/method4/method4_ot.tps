CREATE OR REPLACE TYPE method4_ot AUTHID CURRENT_USER AS OBJECT
--See Method4 package specification for details.
(
  atype ANYTYPE --<-- transient record type

, STATIC FUNCTION ODCITableDescribe(
                  rtype   OUT ANYTYPE,
                  stmt    IN  VARCHAR2
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITablePrepare(
                  sctx    OUT method4_ot,
                  tf_info IN  sys.ODCITabFuncInfo,
                  stmt    IN  VARCHAR2
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITableStart(
                  sctx    IN OUT method4_ot,
                  stmt    IN     VARCHAR2
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableFetch(
                  SELF  IN OUT method4_ot,
                  nrows IN     NUMBER,
                  rws   OUT    anydataset
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableClose(
                  SELF IN method4_ot
                  ) RETURN NUMBER

) NOT FINAL INSTANTIABLE;
/
