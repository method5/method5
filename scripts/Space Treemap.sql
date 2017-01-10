--Purpose: Create a treemap visualization of space usage.
--How to use:
--	Run #1 to gather data, it may take a few minutes.
--	Run #2 to check that lifecycles and LOBs are correct.
--	Run #3 to create a function.
--	Run #4 to call the function with different group settings.
--Version: 1.0.3



--------------------------------------------------------------------------------
--#1: Gather data.  This step can take a few minutes.
--------------------------------------------------------------------------------

--Start gathering.
begin
	m5_proc(
		p_code                => q'<select owner, sum(bytes) bytes from dba_segments group by owner>',
		p_table_name          => 'space_treemap',
		p_table_exists_action => 'DROP'
	);
end;
/


--Check results.  Resolve any errors and re-run if necessary.
select * from space_treemap order by 1, 2;
select * from space_treemap_meta;
select * from space_treemap_err order by 1;
--Jobs that have not finished yet.
select * from sys.dba_scheduler_running_jobs where owner = user;



--------------------------------------------------------------------------------
--#2: Check metadata.  There should not be any relevant databases without a
--	lifecycle or line of business.  Fix any missing values before proceeding.
--------------------------------------------------------------------------------
select *
from m5_database
where lifecycle_status is null
	or line_of_business is null;



--------------------------------------------------------------------------------
--#3: Create function to build the treemap.
--------------------------------------------------------------------------------
create or replace function get_space_treemap(p_value_title varchar2, p_value_select_list varchar2) return clob is
	type string_table is table of varchar2(32767);
	v_strings string_table;
	v_clob clob;
begin
	--Using LOB locators is *much* faster than using simple || operators.
	dbms_lob.createtemporary(v_clob, true);

	--Gather HTML lines.
	execute immediate replace(replace(q'<

		--Header HTML.
		select replace(q'[
		<html>
			<head>
				<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
				<script type="text/javascript">
					google.charts.load('current', {'packages':['treemap']})#SEMICOLON#
					google.charts.setOnLoadCallback(drawChart)#SEMICOLON#
					function drawChart() {
					var data = google.visualization.arrayToDataTable([

		['ID', 'Parent', 'Segment Size in GB'],]', '#SEMICOLON#', ';') html_line
		from dual
		union all
		--HTML for data.
		select json_value html_line
		from
		(
			--Ordered JSON data, to know when to not put a comma at the end.
			select
				'[{v:'''||id||''',f:'''||formatted_id||'''},'||
				case when parent_id = 'null' then 'null,' else ''''||parent_id||''',' end ||
				gb||']'||
				case when rownumber = 1 then null else ',' end
				json_value
			from
			(
				--Create ID, PARENT_ID, VALUE.
				select
					value1||'|'||value2||'|'||value3||'|'||value4 id,
					coalesce(value4, value3, value2, value1, 'Global') || ' ('||trim(to_char(gb, '999,999,999.0'))||')' formatted_id,
					case
						when value4 is not null then value1||'|'||value2||'|'||value3||'|'
						when value3 is not null then value1||'|'||value2||'|'||'|'
						when value2 is not null then value1||'|'||'|'||'|'
						when value1 is not null then '|||'
						else 'null'
					end parent_id,
					gb,
					row_number() over (order by 1) rownumber
				from
				(
					--Rollups with distinct (in case one of the ROLLUPS was null and doubled things).
					select distinct rollups.*
					from
					(
						--Rollups.
						select value1, value2, value3, value4, round(sum(bytes)/1024/1024/1024, 1) gb
						from
						(
							--Basic space data.
							select
								'$$TITLE$$' title, $$SELECT_LIST$$
								space_treemap.bytes
							from space_treemap
							left join
							(
								select distinct lower(database_name) database_name, lifecycle_status, line_of_business
								from m5_database
							) metadata
								on space_treemap.database_name = metadata.database_name
							order by 1,2,3,4
						) space_data
						group by rollup(title, value1, value2, value3, value4)
					) rollups
				) rollups_distinct
				order by 1
			) table_data
			order by rownumber desc
		)
		union all
		--Footer HTML.
		select replace(q'[
					])#SEMICOLON#

					tree = new google.visualization.TreeMap(document.getElementById('chart_div'))#SEMICOLON#

					tree.draw(data, {
						minColor: '#0d0',
						midColor: '#0d0',
						maxColor: '#0d0',
						headerHeight: 15,
						fontColor: 'black',
						title: "Segment sizes in GB, grouped by: $$TITLE$$"
					})#SEMICOLON#
				  }
				</script>
			</head>
			<body>
				<div id="chart_div" style="width: 100%#SEMICOLON# height: 100%#SEMICOLON#"></div>
			</body>
		</html>
		]', '#SEMICOLON#', ';') html_line
		from dual


	>', '$$SELECT_LIST$$', p_value_select_list), '$$TITLE$$', p_value_title) --'--PL/SQL Developer parser bug.
	bulk collect into v_strings;

	--Convert lines into single CLOB
	for i in 1 .. v_strings.count loop
		dbms_lob.append(v_clob, v_strings(i)|| chr(10));
	end loop;

	return v_clob;
end;
/



--------------------------------------------------------------------------------
--#4: Build HTML files to contain the visualization.
--------------------------------------------------------------------------------

--#4a: Change the order of the 4 values to genearate different charts.
select get_space_treemap('Owner, Lifecycle, LOB, DB', 'lifecycle_status value2, line_of_business value3, space_treemap.database_name value4, owner value1,') from dual;
select get_space_treemap('Lifecycle, LOB, DB, owner', 'lifecycle_status value1, line_of_business value2, space_treemap.database_name value3, owner value4,') from dual;
select get_space_treemap('Lifecycle, DB, owner', 'lifecycle_status value1, space_treemap.database_name value2, owner value3, null value4,') from dual;


--#4b: Save the CLOB as an .HTML file and open in a browser.

