CREATE OR REPLACE TYPE METHOD5.method4_m5_poll_table_ot AUTHID CURRENT_USER AS OBJECT
--See Method4 package specification for details.
(
  atype ANYTYPE --<-- transient record type

, STATIC FUNCTION ODCITableDescribe(
                  rtype                 OUT ANYTYPE,
                  p_code                IN clob,
                  p_targets             IN varchar2 default null,
                  p_run_as_sys          IN varchar2 default 'NO'
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITablePrepare(
                  sctx                  OUT method4_m5_poll_table_ot,
                  tf_info               IN  sys.ODCITabFuncInfo,
                  p_code                IN clob,
                  p_targets             IN varchar2 default null,
                  p_run_as_sys          IN varchar2 default 'NO'
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITableStart(
                  sctx                  IN OUT method4_m5_poll_table_ot,
                  p_code                IN clob,
                  p_targets             IN varchar2 default null,
                  p_run_as_sys          IN varchar2 default 'NO'
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableFetch(
                  SELF  IN OUT method4_m5_poll_table_ot,
                  nrows IN     NUMBER,
                  rws   OUT    anydataset
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableClose(
                  SELF IN method4_m5_poll_table_ot
                  ) RETURN NUMBER

) NOT FINAL INSTANTIABLE;
/
CREATE OR REPLACE TYPE BODY METHOD5.method4_m5_poll_table_ot AS
--See Method4 package specification for details on Method4 (how to return anything from a query).
--See Method5 package specification for details on Method5 (how to run a query anywhere)
--
--Many methods in this type are almost identical to those in METHOD4_OT.
--Inheritence could simplify the code but causes unsolvable OCI errors in 11g.

--------------------------------------------------------------------------------
static function ODCITableDescribe(
	rtype                 out anytype,
	p_code                IN clob,
	p_targets             IN varchar2 default null,
	p_run_as_sys          IN varchar2 default 'NO'
/*
	p_table_name              in varchar2,
	p_sql_statement_condition in varchar2,
	p_refresh_seconds         in number default 3
*/
) return number is

v_table_name varchar2(100);

--Template for the type.
v_type_template varchar2(32767) := '
create or replace type m4_temp_type_#ID is object(
	--This temporary type is used for a single call to M5.
	--It is safe to drop this object as long as that statement has completed.
	--Normally these object should be automatically dropped, but it is possible
	--for them to not get dropped if the SQL statement was cancelled.
'||/*prevent SQL*Plus parse error*/''||'#COLUMNS
)';

v_type_table_template varchar2(32767) := '
create or replace type m4_temp_table_#ID
is table of m4_temp_type_#ID
--This temporary type is used for a single call to M5.
--It is safe to drop this object as long as that statement has completed.
--Normally these object should be automatically dropped, but it is possible
--for them to not get dropped if the SQL statement was cancelled.';

v_function_template varchar2(32767) := q'[
create or replace function m4_temp_function_#ID return m4_temp_table_#ID pipelined authid current_user is
	v_cursor sys_refcursor;
	v_rows m4_temp_table_#ID;
	v_condition number;
	v_target_names sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll();

	pragma autonomous_transaction;
begin
	--Continually poll table.
	loop
		--Open cursor to retrieve all new rows - those with a new target name.
		open v_cursor for q'`
			select m4_temp_type_#ID(#COLUMNS) v_result
			from #OWNER.#TABLE_NAME
			where #DATABASE_OR_HOST_NAME# not member of :target_names`'
		using v_target_names;

		--Fetch and process data.
		loop
			--Dynamic SQL is used to simplify privileges.
			fetch v_cursor
			bulk collect into v_rows
			limit 100;

			exit when v_rows.count = 0;

			--Save any new targets and pipe the output.
			for i in 1 .. v_rows.count loop
				--Save new target names.
				if v_rows(i).#DATABASE_OR_HOST_NAME# not member of v_target_names then
					v_target_names.extend;
					v_target_names(v_target_names.count) := v_rows(i).#DATABASE_OR_HOST_NAME#;
				end if;

				--Output the row.
				pipe row(v_rows(i));
			end loop;

		end loop;

		--Check the condition flag *before* the condition SQL.
		--This forces the FETCH to run one extra time, which will pick up
		--any rows inserted in the fraction of a second between the FETCH
		--and the condition SQL.
		if v_condition = 1 then
			exit;
		end if;

		--Exit when condition is met.
		execute immediate
		q'!
			select case when is_complete = 'Yes' then 1 else 0 end condition
			from #OWNER.#TABLE_NAME_meta
			where date_started = (select max(date_started) from #OWNER.#TABLE_NAME_meta)
		!'
		into v_condition;

		--Wait 1 second.  Use execute immediate to simplify privilege requirements.
		if v_condition = 0 then
			execute immediate 'begin method5.m5_sleep(1); end;';
		end if;
	end loop;
end;
]';

	---------------------------------------------------------------------------
	--Get a sequence value to help ensure uniqueness.
	function get_sequence_nextval return number is
		v_sequence_nextval number;
	begin
		execute immediate 'select method5.m5_generic_sequence.nextval from sys.dual'
		into v_sequence_nextval;

		return v_sequence_nextval;
	end get_sequence_nextval;


	---------------------------------------------------------------------------
	--Set the table_name if it is NULL.
	function get_table_name return varchar2 is
	begin
		return 'm5_temp_'||get_sequence_nextval();
	end get_table_name;

	---------------------------------------
	--Purpose: Set common variables used in other methods.
	procedure set_context_attributes(p_table_name varchar2) is
	begin
		--Create random id number to name the temporary objects.
		method4.set_temp_object_id(lpad(round(dbms_random.value * 1000000000), 9, '0'));

		--Get the owner and tablename.
		--
		--Split the value if there's a ".".
		if instr(p_table_name, '.') > 0 then
			method4.set_owner(upper(trim(substr(p_table_name, 1, instr(p_table_name, '.') - 1))));
			method4.set_table_name(upper(trim(substr(p_table_name, instr(p_table_name, '.') + 1))));
		--Assume the owner is the current_schema
		else
			method4.set_owner(sys_context('userenv', 'current_schema'));
			method4.set_table_name(upper(trim(p_table_name)));
		end if;
	end set_context_attributes;

	---------------------------------------
	--Purpose: Create the base type and the nested table type to hold results from the polling table.
	procedure create_temp_types is
		v_column_list varchar2(32767);
	begin
		--Add columns.
		--This is used instead of DBMS_METADATA because DBMS_METADATA is often too slow.
		for cols in
		(
			select *
			from all_tab_columns
			where owner = sys_context('method4_context', 'owner')
				and table_name = sys_context('method4_context', 'table_name')
			order by column_id
		) loop
			v_column_list := v_column_list || ',' || chr(10) || '	"'||cols.column_name||'" '||
				case
					when cols.data_type in ('NUMBER', 'FLOAT') then
						case
							when cols.data_precision is null and cols.data_scale is null then cols.data_type
							--For tables this could be "*", but "*" does not work with types.
							when cols.data_precision is null and cols.data_scale is not null then cols.data_type||'(38,'||cols.data_scale||')'
							when cols.data_precision is not null and cols.data_scale is null then cols.data_type||'('||cols.data_precision||')'
							when cols.data_precision is not null and cols.data_scale is not null then cols.data_type||'('||cols.data_precision||','||cols.data_scale||')'
						end
					when cols.data_type in ('CHAR', 'NCHAR', 'VARCHAR2', 'NVARCHAR2') then cols.data_type||'('||cols.data_length||' '||
						case cols.char_used when 'B' then 'byte' when 'C' then 'char' end || ')'
					when cols.data_type in ('RAW') then cols.data_type||'('||cols.data_length||')'
					else
						--DATE, TIMESTAMP, INTERVAL, many other types.
						cols.data_type
				end;
		end loop;

		--Create the type after replacing the columns and temp ID.
		execute immediate replace(replace(v_type_template, '#COLUMNS', substr(v_column_list, 3)), '#ID', sys_context('method4_context', 'temp_object_id'));

		--Create the nested table type after replacing the temp ID.
		execute immediate replace(v_type_table_template, '#ID', sys_context('method4_context', 'temp_object_id'));
	end create_temp_types;

	---------------------------------------
	--Purpose: Create the function that returns results from the table.
	procedure create_temp_function is
		v_first_column_name varchar2(128);
		v_column_list       varchar2(32767);
	begin
		--Create comma-separated list of columns in the table.
		select
			min(case when column_id = 1 then column_name else null end) first_column,
			listagg('"'||column_name||'"', ',') within group (order by column_id) column_list
		into v_first_column_name, v_column_list
		from all_tab_columns
		where owner = sys_context('method4_context', 'owner')
			and table_name = sys_context('method4_context', 'table_name');

		--Create the function
		execute immediate replace(replace(replace(replace(replace(v_function_template,
			'#ID', sys_context('method4_context', 'temp_object_id')),
			'#OWNER', sys_context('method4_context', 'owner')),
			'#TABLE_NAME', sys_context('method4_context', 'table_name')),
			'#COLUMNS', v_column_list),
			'#DATABASE_OR_HOST_NAME#', v_first_column_name);
	end;

	pragma autonomous_transaction;

begin
	v_table_name := get_table_name;

	m5_pkg.run(
		p_code => p_code,
		p_targets => p_targets,
		p_table_name => v_table_name,
		p_run_as_sys => case when trim(upper(p_run_as_sys)) in ('YES', '1') then true else false end
	);

	set_context_attributes(v_table_name);
	create_temp_types;
	create_temp_function;
	--Yes, this commit is really necessary.
	--I don't know why, but without it the CREATE statements above don't work.
	commit;
	return method4_ot.odcitabledescribe(rtype, 'select * from table(M4_TEMP_FUNCTION_'||sys_context('method4_context', 'temp_object_id')||')');
end ODCITableDescribe;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITablePrepare(
                   sctx    OUT method4_m5_poll_table_ot,
                   tf_info IN  sys.ODCITabFuncInfo,
                   p_code                IN clob,
                   p_targets             IN varchar2 default null,
                   p_run_as_sys          IN varchar2 default 'NO'
                   ) RETURN NUMBER IS

      r_meta method4.rt_anytype_metadata;

  BEGIN

      /*
      || We prepare the dataset that our pipelined function will return by
      || describing the ANYTYPE that contains the transient record structure...
      */
      r_meta.typecode := tf_info.rettype.GetAttrElemInfo(
                            1, r_meta.precision, r_meta.scale, r_meta.length,
                            r_meta.csid, r_meta.csfrm, r_meta.type, r_meta.name
                            );

      /*
      || Using this, we initialise the scan context for use in this and
      || subsequent executions of the same dynamic SQL cursor...
      */
      sctx := method4_m5_poll_table_ot(r_meta.type);

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITableStart(
                   sctx                      IN OUT method4_m5_poll_table_ot,
                   p_code                IN clob,
                   p_targets             IN varchar2 default null,
                   p_run_as_sys          IN varchar2 default 'NO'
                   ) RETURN NUMBER IS

      r_meta method4.rt_anytype_metadata;
      v_new_stmt VARCHAR2(32767);

	procedure force_hard_parsing is
	begin
		--Create scheduler job to run queries.
		--This asynchronous job will improve Method4 run time.
		--And it's fine that it's asynchronous - the hard parsing will only affect
		--the *next* execution of the query anyway.
		sys.dbms_scheduler.create_job
		(
			job_name   => 'm4_purge_pool_'||sys_context('method4_context', 'temp_object_id'),
			job_type   => 'PLSQL_BLOCK',
			job_action => replace(q'<
				declare
	    		  type string_table is table of varchar2(32767);
    			  v_sql_ids string_table;
				begin
					--Find SQL_IDs of the SQL statements used to call Method5.
					--Use dynamic SQL to enable roles to select from GV$SQL.
					execute immediate q'!
						select 'begin sys.dbms_shared_pool.purge('''||address||' '||hash_value||''', ''C''); end;' v_sql
						from sys.gv_$sql
						where
							parsing_schema_name = :parsing_schema_name
							and command_type = 3
							and lower(sql_text) like '%table%(%m5%(%'
							and lower(sql_text) not like '%quine%'
					!'
					bulk collect into v_sql_ids
					using '#OWNER#';

					--Purge each SQL_ID to force hard-parsing each time.
					--This cannot be done in the earlier Describe or Prepare phase or it will generate errors.
					for i in 1 .. v_sql_ids.count loop
						execute immediate v_sql_ids(i);
					end loop;
				end;
			>', '#OWNER#', sys_context('method4_context', 'owner')),
			start_date => systimestamp,
			enabled    => true
		);
	end;

	pragma autonomous_transaction;

  BEGIN
      force_hard_parsing;

      v_new_stmt := 'select * from table(M4_TEMP_FUNCTION_'||sys_context('method4_context', 'temp_object_id')||')';

      /*
      || We now describe the cursor again and use this and the described
      || ANYTYPE structure to define and execute the SQL statement...
      */
      method4.r_sql.cursor := DBMS_SQL.OPEN_CURSOR;
      DBMS_SQL.PARSE( method4.r_sql.cursor, v_new_stmt, DBMS_SQL.NATIVE );
      DBMS_SQL.DESCRIBE_COLUMNS2( method4.r_sql.cursor,
                                  method4.r_sql.column_cnt,
                                  method4.r_sql.description );

      --Remove statement from the cache.
      method4.r_statement_cache.delete(v_new_stmt);

      FOR i IN 1 .. method4.r_sql.column_cnt LOOP

         /*
         || Get the ANYTYPE attribute at this position...
         */
         r_meta.typecode := sctx.atype.GetAttrElemInfo(
                               i, r_meta.precision, r_meta.scale, r_meta.length,
                               r_meta.csid, r_meta.csfrm, r_meta.type, r_meta.name
                               );

         CASE r_meta.typecode
            --<>--
            WHEN DBMS_TYPES.TYPECODE_VARCHAR2
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, '', 32767
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_NVARCHAR2
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, '', 32767
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_NUMBER
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS NUMBER)
                  );
            --<FLOAT - convert to NUMBER.>--
            WHEN 4
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS NUMBER)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_BFLOAT
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS BINARY_FLOAT)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_BDOUBLE
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS BINARY_DOUBLE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_BLOB
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS BLOB)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_DATE
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS DATE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_RAW
            THEN
               DBMS_SQL.DEFINE_COLUMN_RAW(
                  method4.r_sql.cursor, i, CAST(NULL AS RAW), r_meta.length
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_TIMESTAMP
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS TIMESTAMP)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_TZ
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS TIMESTAMP WITH TIME ZONE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_LTZ
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS TIMESTAMP WITH LOCAL TIME ZONE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_INTERVAL_YM
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS INTERVAL YEAR TO MONTH)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_INTERVAL_DS
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS INTERVAL DAY TO SECOND)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_CLOB
            THEN
               --<>--
               CASE method4.r_sql.description(i).col_type
                  WHEN 8
                  THEN
                     DBMS_SQL.DEFINE_COLUMN_LONG(
                        method4.r_sql.cursor, i
                        );
                  ELSE
                     DBMS_SQL.DEFINE_COLUMN(
                        method4.r_sql.cursor, i, CAST(NULL AS CLOB)
                        );
               END CASE;
         END CASE;
      END LOOP;

      /*
      || The cursor is prepared according to the structure of the type we wish
      || to fetch it into. We can now execute it and we are done for this method...
      */
      method4.r_sql.execute := DBMS_SQL.EXECUTE( method4.r_sql.cursor );

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   MEMBER FUNCTION ODCITableFetch(
                   SELF   IN OUT method4_m5_poll_table_ot,
                   nrows  IN     NUMBER,
                   rws    OUT    ANYDATASET
                   ) RETURN NUMBER IS

      TYPE rt_fetch_attributes IS RECORD
      ( v2_column      VARCHAR2(32767)
      , num_column     NUMBER
      , bfloat_column  BINARY_FLOAT
      , bdouble_column BINARY_DOUBLE
      , date_column    DATE
      , clob_column    CLOB
      , blob_column    BLOB
      , raw_column     RAW(32767)
      , raw_error      NUMBER
      , raw_length     INTEGER
      , ids_column     INTERVAL DAY TO SECOND
      , iym_column     INTERVAL YEAR TO MONTH
      , ts_column      TIMESTAMP(9)
      , tstz_column    TIMESTAMP(9) WITH TIME ZONE
      , tsltz_column   TIMESTAMP(9) WITH LOCAL TIME ZONE
      , cvl_offset     INTEGER := 0
      , cvl_length     INTEGER
      );
      r_fetch rt_fetch_attributes;
      r_meta  method4.rt_anytype_metadata;


   BEGIN

      IF DBMS_SQL.FETCH_ROWS( method4.r_sql.cursor ) > 0 THEN

         /*
         || First we describe our current ANYTYPE instance (SELF.A) to determine
         || the number and types of the attributes...
         */
         r_meta.typecode := SELF.atype.GetInfo(
                               r_meta.precision, r_meta.scale, r_meta.length,
                               r_meta.csid, r_meta.csfrm, r_meta.schema,
                               r_meta.name, r_meta.version, r_meta.attr_cnt
                               );

         /*
         || We can now begin to piece together our returning dataset. We create an
         || instance of ANYDATASET and then fetch the attributes off the DBMS_SQL
         || cursor using the metadata from the ANYTYPE. LONGs are converted to CLOBs...
         */
         ANYDATASET.BeginCreate( DBMS_TYPES.TYPECODE_OBJECT, SELF.atype, rws );
         rws.AddInstance();
         rws.PieceWise();

         FOR i IN 1 .. method4.r_sql.column_cnt LOOP

            r_meta.typecode := SELF.atype.GetAttrElemInfo(
                                  i, r_meta.precision, r_meta.scale, r_meta.length,
                                  r_meta.csid, r_meta.csfrm, r_meta.attr_type,
                                  r_meta.attr_name
                                  );

            CASE r_meta.typecode
               --<>--
               WHEN DBMS_TYPES.TYPECODE_VARCHAR2
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.v2_column
                     );
                  rws.SetVarchar2( r_fetch.v2_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_NVARCHAR2
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.v2_column
                     );
                  rws.SetNVarchar2( r_fetch.v2_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_NUMBER
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.num_column
                     );
                  rws.SetNumber( r_fetch.num_column );
               --<FLOAT - convert to NUMBER.>--
               WHEN 4
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.num_column
                     );
                  rws.SetNumber( r_fetch.num_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_BFLOAT
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.bfloat_column
                     );
                  rws.SetBFloat( r_fetch.bfloat_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_BDOUBLE
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.bdouble_column
                     );
                  rws.SetBDouble( r_fetch.bdouble_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_BLOB
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.blob_column
                     );
                  rws.SetBlob( r_fetch.blob_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_DATE
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.date_column
                     );
                  rws.SetDate( r_fetch.date_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_RAW
               THEN
                  DBMS_SQL.COLUMN_VALUE_RAW(
                     method4.r_sql.cursor, i, r_fetch.raw_column,
                     r_fetch.raw_error, r_fetch.raw_length
                     );
                  rws.SetRaw( r_fetch.raw_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_INTERVAL_DS
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.ids_column
                     );
                  rws.SetIntervalDS( r_fetch.ids_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_INTERVAL_YM
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.iym_column
                     );
                  rws.SetIntervalYM( r_fetch.iym_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_TIMESTAMP
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.ts_column
                     );
                  rws.SetTimestamp( r_fetch.ts_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_TZ
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.tstz_column
                     );
                  rws.SetTimestampTZ( r_fetch.tstz_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_LTZ
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.tsltz_column
                     );
                  rws.SetTimestamplTZ( r_fetch.tsltz_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_CLOB
               THEN
                  --<>--
                  CASE method4.r_sql.description(i).col_type
                     WHEN 8
                     THEN
                        LOOP
                           DBMS_SQL.COLUMN_VALUE_LONG(
                              method4.r_sql.cursor, i, 32767, r_fetch.cvl_offset,
                              r_fetch.v2_column, r_fetch.cvl_length
                              );
                           r_fetch.clob_column := r_fetch.clob_column ||
                                                  r_fetch.v2_column;
                           r_fetch.cvl_offset := r_fetch.cvl_offset + 32767;
                           EXIT WHEN r_fetch.cvl_length < 32767;
                        END LOOP;
                     ELSE
                        DBMS_SQL.COLUMN_VALUE(
                           method4.r_sql.cursor, i, r_fetch.clob_column
                           );
                     END CASE;
                     rws.SetClob( r_fetch.clob_column );
               --<>--
            END CASE;
         END LOOP;

         /*
         || Our ANYDATASET instance is complete. We end our create session...
         */
         rws.EndCreate();

      END IF;

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   MEMBER FUNCTION ODCITableClose(
                   SELF IN method4_m5_poll_table_ot
                   ) RETURN NUMBER IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN

      --Drop temporary types and functions.
      execute immediate 'drop function m4_temp_function_'||sys_context('method4_context', 'temp_object_id');
      execute immediate 'drop type m4_temp_table_'||sys_context('method4_context', 'temp_object_id');
      execute immediate 'drop type m4_temp_type_'||sys_context('method4_context', 'temp_object_id');

      DBMS_SQL.CLOSE_CURSOR( method4.r_sql.cursor );
      method4.r_sql := NULL;

      RETURN ODCIConst.Success;

   END;

END;
/
