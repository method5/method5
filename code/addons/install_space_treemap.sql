prompt Installing Space Treemap...

--------------------------------------------------------------------------------
--#1: Check the user.
--------------------------------------------------------------------------------
@code/check_user must_not_run_as_sys_and_has_dba



--------------------------------------------------------------------------------
--#2: Create function to build the treemap.
--------------------------------------------------------------------------------
create or replace function method5.get_space_treemap
(
	p_value_title varchar2,
	p_value_select_list varchar2
) return clob authid current_user
is
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



prompt Finished installing Space Treemap.
