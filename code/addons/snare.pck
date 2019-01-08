create or replace package method5.snare authid current_user is
/*
 *  Purpose: Configuration comparison program.
 *
 *  Copyright (C) 2018 Jon Heller and Ventech Solutions.  This program is licensed under the LGPLv3.
 *  See https://method5.github.io/ for more information.
 *
 */
	procedure create_snapshot(p_snapshot_name varchar2, p_targets varchar2, p_configs method5.string_table default null);
	procedure delete_snapshot(p_snapshot_name varchar2);
	function compare_details(p_snapshot_before varchar2, p_snapshot_after varchar2) return config_nt;
	function compare_summary(p_snapshot_before varchar2, p_snapshot_after varchar2) return clob;
end;
/
create or replace package body method5.snare is

	-------------------------------------------------------------------------------
	procedure raise_error_if_does_not_exist(p_snapshot_name varchar2) is
		v_count number;
	begin
		--Check if the snapshot exists.
		select count(*)
		into v_count
		from method5.snapshots
		where snapshot_name = trim(upper(p_snapshot_name));

		--Raise error if there are no snapshots.
		if v_count = 0 then
			raise_application_error(-20000, 'This snapshot name could not be found: ' || p_snapshot_name);
		end if;
	end raise_error_if_does_not_exist;


	-------------------------------------------------------------------------------
	procedure create_snapshot(
		p_snapshot_name varchar2,
		p_targets       varchar2,
		p_configs       method5.string_table default null
	) is
		v_clean_snapshot_name varchar2(128) := trim(upper(p_snapshot_name));

		type string_nt is table of varchar2(32767);
		v_missing_configs string_nt := string_nt();
		v_target_string varchar2(32767);
		v_database_or_host_name varchar2(100);
		v_db_or_host varchar2(100);
	begin
		--Validate the selected configs, if they were chosen.
		if p_configs is not null then
			--Requested configurations that don't exist.
			select requested_config.config_type
			bulk collect into v_missing_configs
			from
			(
				select lower(trim(column_value)) config_type
				from table(p_configs)
			) requested_config
			left join method5.configs
				on requested_config.config_type = lower(trim(configs.config_type))
			where configs.config_type is null
			order by requested_config.config_type;

			--Stop processing if a bad config was requested.
			if v_missing_configs.count <> 0 then
				raise_application_error(-20000, 'You requested a config that does not exist in METHOD5.CONFIG: ' ||
					v_missing_configs(1));
			end if;
		end if;

		--Create new snapshot.
		insert into method5.snapshots(snapshot_name, the_date, target_string) values (v_clean_snapshot_name, sysdate, p_targets);
		commit;

		--Don't display the Method5 help information.
		dbms_output.disable;

		--Loop through the CONFIGURATIONs and gather SNAPSHOT_RESULTS.
		for configs in
		(
			--Either all configurations or only the configurations chosen.
			select config_type, gather_code, table_name, config_name_column, config_value_column, config_value_data_type, static_targets
			from method5.configs
			where
			(
				--Select everything if nothing was specified.
				p_configs is null
				or
				--Select specific configuration.
				lower(trim(config_type)) in
				(
					select lower(trim(column_value))
					from table(p_configs)
					union all
					--Always select the pings.
					select lower('Ping database') from dual
					union all
					select lower('Ping host') from dual
				)
			)
			order by config_type
		) loop
			begin
				--Reset the target string if this config has a static target string.
				--For example, if reading from M5_DATABASE, that table is only on one database.
				if configs.static_targets is null then
					v_target_string := p_targets;
				else
					v_target_string := configs.static_targets;
				end if;

				--Gather data.
				m5_proc(
					p_code =>                   configs.gather_code,
					p_targets =>                v_target_string,
					p_table_name =>             configs.table_name,
					p_table_exists_action =>    'drop',
					p_asynchronous =>           false
				);

				--Is the target DATABASE_NAME or HOST_NAME?
				select column_name target_type
				into v_database_or_host_name
				from user_tab_columns
				where table_name = upper(configs.table_name)
					and column_id = 1;

				--Set the column name prefix for the _ERR table, based on the result type.
				if v_database_or_host_name = 'DATABASE_NAME' then
					v_db_or_host := 'DB';
				else
					v_db_or_host := 'HOST';
				end if;

				--Store the results, depending on the target type.
				execute immediate replace(replace(replace(replace(replace(replace(replace(
				q'[
					insert into method5.snapshot_results(snapshot_name, config_type, target, config_name, #CONFIG_VALUE_DATA_TYPE#_value)
					select '#SNAPSHOT_NAME#', '#CONFIG_TYPE#', #DATABASE_OR_HOST_NAME#, #CONFIG_NAME_COLUMN#, #CONFIG_VALUE_COLUMN#
					from #TABLE_NAME#
					--Order results to help index compression efficiency.
					order by 1,2,3,4
				]',
				'#SNAPSHOT_NAME#', v_clean_snapshot_name),
				'#CONFIG_VALUE_DATA_TYPE#', configs.config_value_data_type),
				'#CONFIG_TYPE#', configs.config_type),
				'#DATABASE_OR_HOST_NAME#', v_database_or_host_name),
				'#CONFIG_NAME_COLUMN#', configs.config_name_column),
				'#CONFIG_VALUE_COLUMN#', configs.config_value_column),
				'#TABLE_NAME#', configs.table_name);

				--Store metadata.
				execute immediate replace(replace(replace(
				q'[
					insert into method5.snapshot_metadata(snapshot_name, config_type, date_started, date_updated, username, is_complete,
						targets_expected, targets_completed, targets_with_errors, num_rows)
					select '#SNAPSHOT_NAME#', '#CONFIG_TYPE#', date_started, date_updated, username, is_complete,
						targets_expected, targets_completed, targets_with_errors, num_rows
					from #TABLE_NAME#_meta
				]',
				'#SNAPSHOT_NAME#', v_clean_snapshot_name),
				'#CONFIG_TYPE#', configs.config_type),
				'#TABLE_NAME#', configs.table_name);

				--Store errors.
				execute immediate replace(replace(replace(replace(replace(
				q'[
					insert into method5.snapshot_errors(snapshot_name, config_type, target, link_name, date_error, error_stack_and_backtrace)
					select '#SNAPSHOT_NAME#', '#CONFIG_TYPE#', #DATABASE_OR_HOST_NAME#, #HOST_OR_DB#_link_name, date_error, error_stack_and_backtrace
					from #TABLE_NAME#_err
				]',
				'#SNAPSHOT_NAME#', v_clean_snapshot_name),
				'#CONFIG_TYPE#', configs.config_type),
				'#DATABASE_OR_HOST_NAME#', v_database_or_host_name),
				'#HOST_OR_DB#', v_db_or_host),
				'#TABLE_NAME#', configs.table_name);

				commit;
			exception when others then
				raise_application_error(-20000, 'Error processing this config: '||configs.config_type||'.'||chr(10)||
					sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
			end;
		end loop;
	end create_snapshot;


	-------------------------------------------------------------------------------
	procedure delete_snapshot(p_snapshot_name varchar2) is
	begin
		raise_error_if_does_not_exist(p_snapshot_name);

		delete from method5.snapshot_errors where snapshot_name = trim(upper(p_snapshot_name));
		delete from method5.snapshot_metadata where snapshot_name = trim(upper(p_snapshot_name));
		delete from method5.snapshot_results where snapshot_name = trim(upper(p_snapshot_name));
		delete from method5.snapshots where snapshot_name = trim(upper(p_snapshot_name));
		commit;
	end delete_snapshot;


	-------------------------------------------------------------------------------
	function compare_details(p_snapshot_before varchar2, p_snapshot_after varchar2) return config_nt is
		v_differences config_nt;
	begin
		--Check that snapshot names exist.
		raise_error_if_does_not_exist(p_snapshot_before);
		raise_error_if_does_not_exist(p_snapshot_after);

		--All differences.
		--
		with configurations as
		(
			--Configurations and if they were gathered in both or only one snapshot.
			select
				config_type,
				max(error_message) error_message,
				count(*) missing_1_ok_2
			from
			(
				--Get all BEFORE and AFTER configurations.
				select config_type, 'Cannot compare - not gathered in AFTER' error_message
				from method5.snapshot_metadata
				where snapshot_name = trim(upper(p_snapshot_before))
				union all
				select config_type, 'Cannot compare - not gathered in BEFORE' error_message
				from method5.snapshot_metadata
				where snapshot_name = trim(upper(p_snapshot_after))
			)
			group by config_type
		),
		errors as
		(
			--Errors before and after
			select config_type, target, 'Cannot compare - error gathering data from BEFORE' error_message
			from method5.snapshot_errors
			where snapshot_name = trim(upper(p_snapshot_before))
			union all
			select config_type, target, 'Cannot compare - error gathering data from AFTER' error_message
			from method5.snapshot_errors
			where snapshot_name = trim(upper(p_snapshot_after))
		),
		different_targets as
		(
			--Targets only gathered in one snapshot.
			select nvl(ping_before.target, ping_after.target) target
				,'Cannot compare - target was gathered in '||nvl(ping_before.is_in, ping_after.is_in)||
				' but not in '||nvl(ping_before.is_not_in, ping_after.is_not_in) error_message
			from
			(
				select target, 'BEFORE' is_in, 'AFTER' is_not_in
				from method5.snapshot_results
				where config_type in ('Ping database', 'Ping host')
					and snapshot_name = trim(upper(p_snapshot_before))
			) ping_before
			full outer join
			(
				select target, 'AFTER' is_in, 'BEFORE' is_not_in
				from method5.snapshot_results
				where config_type in ('Ping database', 'Ping host')
					and snapshot_name = trim(upper(p_snapshot_after))
			) ping_after
				on ping_before.target = ping_after.target
			where ping_before.target is null
				or ping_after.target is null
			order by target
		),
		before_run as
		(
			select configs.config_type, target, config_name, string_value, number_value, date_value
			from configs
			left join
			(
				select *
				from method5.snapshot_results
				where snapshot_name = trim(upper(p_snapshot_before))
					and config_type in (select config_type from configurations where missing_1_ok_2 = 2)
					and (config_type, target) not in (select config_type, target from errors)
					and target not in (select target from different_targets)
			) results
				on configs.config_type = results.config_type
		),
		after_run as
		(
			select configs.config_type, target, config_name, string_value, number_value, date_value
			from method5.configs
			left join
			(
				select *
				from method5.snapshot_results
				where snapshot_name = trim(upper(p_snapshot_after))
					and config_type in (select config_type from configurations where missing_1_ok_2 = 2)
					and (config_type, target) not in (select config_type, target from errors)
					and target not in (select target from different_targets)
			) results
				on configs.config_type = results.config_type
		)
		select method5.config_rec(before_or_after, config_type, target, config_name, string_value, number_value, date_value)
		bulk collect into v_differences
		from
		(
			--Differences:
			select *
			from
			(
				select 'before' before_or_after, before_run.* from before_run
				minus
				select 'before' before_or_after, after_run.* from after_run
			)
			union all
			(
				select 'after' before_or_after, after_run.* from after_run
				minus
				select 'after'  before_or_after, before_run.* from before_run
			)
			union all
			--Problems because the snapshots gathered different configurations.
			select 'problem' before_or_after, config_type, null target, error_message config_name, null string_value, null number_value, null date_value
			from configurations
			where config_type in (select config_type from configurations where missing_1_ok_2 = 1)
			union all
			--Problems because there was an error gathering data for a target.
			select 'problem' before_or_after, config_type, target, error_message config_name, null string_value, null number_value, null date_value
			from errors
			where target not in (select target from different_targets)
			union all
			--Problems because the targets requested were different.
			select 'problem' before_or_after, '*', target, error_message config_name, null string_value, null number_value, null date_value
			from different_targets
			order by 2,3,4,1 desc
		);

		return v_differences;
	end compare_details;


	-------------------------------------------------------------------------------
	function compare_summary(p_snapshot_before varchar2, p_snapshot_after varchar2) return clob is
		v_snapshot_before varchar2(4000) := trim(upper(p_snapshot_before));
		v_snapshot_after  varchar2(4000) := trim(upper(p_snapshot_after));

		v_configs_with_no_diff_msg varchar2(32767);
		v_configs_with_diff_msg    varchar2(32767);
		v_configs_with_error_msg   varchar2(32767);
		v_output                   varchar2(32767);
	begin
		--Check that snapshot names exist.
		raise_error_if_does_not_exist(p_snapshot_before);
		raise_error_if_does_not_exist(p_snapshot_after);

		--Populate no-differences and differences sections.
		for differences in
		(
			--Configuration differences.
			--
			with different_targets as
			(
				--Targets only gathered in one snapshot.
				select nvl(ping_before.target, ping_after.target) target
				from
				(
					select target
					from method5.snapshot_results
					where config_type in ('Ping database', 'Ping host')
						and snapshot_name = trim(upper(p_snapshot_before))
				) ping_before
				full outer join
				(
					select target
					from method5.snapshot_results
					where config_type in ('Ping database', 'Ping host')
						and snapshot_name = trim(upper(p_snapshot_after))
				) ping_after
					on ping_before.target = ping_after.target
				where ping_before.target is null
					or ping_after.target is null
				order by target
			),
			before_run as
			(
				--Before data.
				select configs.config_type, target, config_name, string_value, number_value, date_value
				from configs
				left join
				(
					select *
					from method5.snapshot_results
					where snapshot_name = v_snapshot_before
						and target not in (select target from different_targets)
				) results
					on configs.config_type = results.config_type
				where configs.config_type not in ('Ping database', 'Ping host')
			),
			after_run as
			(
				--After data.
				select configs.config_type, target, config_name, string_value, number_value, date_value
				from configs
				left join
				(
					select *
					from method5.snapshot_results
					where snapshot_name = v_snapshot_after
						and target not in (select target from different_targets)
				) results
					on configs.config_type = results.config_type
				where configs.config_type not in ('Ping database', 'Ping host')
			),
			differences as
			(
				--Differences between before and after data.
				select *
				from
				(
					select *
					from
					(
						select 'before' before_or_after, before_run.* from before_run
						minus
						select 'before' before_or_after, after_run.* from after_run
					)
					union all
					(
						select 'after' before_or_after, after_run.* from after_run
						minus
						select 'after'  before_or_after, before_run.* from before_run
					)
					order by 2,3,4,1 desc
				)
			)
			--All configuration types with different counts.
			--V$PARAMETER: X targets, Y values
			--
			select
				all_config_types.config_type,
				nvl(max(case when target_or_config_count = 'target_count' then the_count else null end), 0) diffs_target_count,
				nvl(max(case when target_or_config_count = 'config_count' then the_count else null end), 0) diffs_config_count,
				max(target_count) no_diffs_target_count,
				max(value_count) no_diffs_value_count
			from
			(
				--All possible config types and the number of targets and values.
				select target_counts.config_type, nvl(target_count, 0) target_count, nvl(value_count, 0) value_count
				from
				(
					select distinct config_type, targets_expected target_count
					from method5.snapshot_metadata
					where snapshot_name in (v_snapshot_before, v_snapshot_after)
						and config_type not in ('Ping database', 'Ping host')
				) target_counts
				left join
				(
					select config_type, count(*) value_count
					from before_run
					group by config_type
				) value_counts
					on target_counts.config_type = value_counts.config_type
			) all_config_types
			left join
			(
				--Target counts
				select 'target_count' target_or_config_count, config_type, count(distinct target) the_count
				from differences
				group by config_type
				union all
				--Configuration name counts
				select 'config_count' target_or_config_count, config_type, count(*)
				from
				(
					select distinct config_type, config_name, target
					from differences
				)
				group by config_type
			) differences
				on all_config_types.config_type = differences.config_type
			group by all_config_types.config_type
			order by all_config_types.config_type
		) loop
			if differences.diffs_target_count = 0 and differences.diffs_config_count = 0 then
				v_configs_with_no_diff_msg := v_configs_with_no_diff_msg||chr(10)||
					differences.config_type||': '||differences.no_diffs_target_count||' targets, '||differences.no_diffs_value_count||' values';
			else
				v_configs_with_diff_msg := v_configs_with_diff_msg||chr(10)||
					differences.config_type||': '||differences.diffs_target_count||' targets different, '||differences.diffs_config_count||' values different';
			end if;
		end loop;

		--Populate error messages.
		for errors in
		(
			--Configuration types with missing results or errors:
			select config_type
			from method5.snapshot_metadata
			where snapshot_name in (v_snapshot_before, v_snapshot_after)
				and targets_expected <> targets_completed
			union
			select distinct config_type
			from method5.snapshot_errors
			where snapshot_name in (v_snapshot_before, v_snapshot_after)
		) loop
			v_configs_with_error_msg := v_configs_with_error_msg||chr(10)||errors.config_type;
		end loop;

		--Print summary.
		v_output := v_output || 'Comparison summary between '||v_snapshot_before||' and '||v_snapshot_after || chr(10);
		v_output := v_output || lpad('=', length(v_snapshot_before) + length(v_snapshot_after) + 40, '=') || chr(10) || chr(10);
		declare
			v_string varchar2(32767);
		begin
			select
				'Before snapshot: ' || max(case when snapshot_name = v_snapshot_before then
					v_snapshot_before ||', gathered on: ' || to_char(the_date, 'YYYY-MM-DD HH24:MI') || ', for targets: ' || target_string
					end)
				|| chr(10) ||
				'After snapshot:  ' || max(case when snapshot_name = v_snapshot_after then
					v_snapshot_after ||', gathered on: ' || to_char(the_date, 'YYYY-MM-DD HH24:MI') || ', for targets: ' || target_string
					end)
			into v_string
			from snapshots;

			v_output := v_output || v_string || chr(10) || chr(10) || chr(10) || chr(10);
		end;

		--Print configurations with no differences:
		v_output := v_output || 'Configurations with no errors and no differences:' || chr(10);
		v_output := v_output || '-------------------------------------------------' || chr(10);
		if v_configs_with_no_diff_msg is not null then
			v_output := v_output || chr(9)||replace(substr(v_configs_with_no_diff_msg, 2), chr(10), chr(10)||chr(9)) || chr(10) || chr(10);
		else
			v_output := v_output || '	None' || chr(10) || chr(10);
		end if;

		--Print configurations with differences:
		v_output := v_output || 'Configurations with differences:' || chr(10);
		v_output := v_output || '--------------------------------' || chr(10);
		if v_configs_with_diff_msg is not null then
			v_output := v_output || chr(9)||replace(substr(v_configs_with_diff_msg, 2), chr(10), chr(10)||chr(9)) || chr(10) || chr(10);
		else
			v_output := v_output || '	None' || chr(10) || chr(10);
		end if;

		--Print configurations with errors:
		v_output := v_output || 'Configurations with errors:' || chr(10);
		v_output := v_output || '---------------------------' || chr(10);
		if v_configs_with_error_msg is not null then
			v_output := v_output || chr(9)||replace(substr(v_configs_with_error_msg, 2), chr(10), chr(10)||chr(9)) || chr(10) || chr(10);
		else
			v_output := v_output || '	None' || chr(10)|| chr(10) || chr(10) || chr(10);
		end if;

		--Print directions to find more results.
		v_output := v_output || 'To find more details:' || chr(10);
		v_output := v_output || '---------------------' || chr(10) || chr(10);

		v_output := v_output || '--Run this query to sell all the detailed differences:' || chr(10);
		v_output := v_output || 'select * from table(snare.compare_details('             || chr(10);
		v_output := v_output || '	p_snapshot_before => '''||v_snapshot_before||''','   || chr(10);
		v_output := v_output || '	p_snapshot_after  => '''||v_snapshot_after||''''     || chr(10);
		v_output := v_output || '));' || chr(10)                                         || chr(10);

		v_output := v_output || '--Run this query to compare detailed metadata:'                                   || chr(10);
		v_output := v_output || 'select *'                                                                         || chr(10);
		v_output := v_output || 'from snapshot_metadata'                                                           || chr(10);
		v_output := v_output || 'where snapshot_name in ('''||v_snapshot_before||''', '''||v_snapshot_after||''')' || chr(10);
		v_output := v_output || 'order by config_type, snapshot_name;' || chr(10)                                  || chr(10);

		v_output := v_output || '--Run this query to compare detailed errors:'                                     || chr(10);
		v_output := v_output || 'select *'                                                                         || chr(10);
		v_output := v_output || 'from snapshot_errors'                                                             || chr(10);
		v_output := v_output || 'where snapshot_name in ('''||v_snapshot_before||''', '''||v_snapshot_after||''')' || chr(10);
		v_output := v_output || 'order by config_type, snapshot_name, target;'                                     || chr(10);

		return v_output;

	end compare_summary;

end snare;
/
