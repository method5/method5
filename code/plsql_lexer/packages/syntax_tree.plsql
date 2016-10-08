create or replace package syntax_tree is
--Copyright (C) 2016 Jon Heller.  This program is licensed under the LGPLv3.

--  _____   ____    _   _  ____ _______   _    _  _____ ______  __     ________ _______ 
-- |  __ \ / __ \  | \ | |/ __ \__   __| | |  | |/ ____|  ____| \ \   / /  ____|__   __|
-- | |  | | |  | | |  \| | |  | | | |    | |  | | (___ | |__     \ \_/ /| |__     | |   
-- | |  | | |  | | | . ` | |  | | | |    | |  | |\___ \|  __|     \   / |  __|    | |   
-- | |__| | |__| | | |\  | |__| | | |    | |__| |____) | |____     | |  | |____   | |   
-- |_____/ \____/  |_| \_|\____/  |_|     \____/|_____/|______|    |_|  |______|  |_|   
-- 
--This package is experimental and does not work yet.


procedure add_child_ids(p_nodes in out node_table);
function get_child_node_by_type(p_nodes node_table, p_node_index number, p_node_type varchar2, p_occurrence number default 1) return node;
function get_children_node_by_type(p_nodes node_table, p_node_index number, p_node_type varchar2) return node_table;
function get_first_ancest_node_by_type(p_nodes node_table, p_node_index number, p_node_type varchar2) return node;

function are_names_equal(p_name1 varchar2, p_name2 varchar2) return boolean;
function get_data_dictionary_case(p_name varchar2) return varchar2;

/*

== Purpose ==

Contains functions and procedures for managing node tables - walking, converting, etc.

== Example ==

TODO


*/
end;
/
create or replace package body syntax_tree is
--Copyright (C) 2016 Jon Heller.  This program is licensed under the LGPLv3.

--  _____   ____    _   _  ____ _______   _    _  _____ ______  __     ________ _______ 
-- |  __ \ / __ \  | \ | |/ __ \__   __| | |  | |/ ____|  ____| \ \   / /  ____|__   __|
-- | |  | | |  | | |  \| | |  | | | |    | |  | | (___ | |__     \ \_/ /| |__     | |   
-- | |  | | |  | | | . ` | |  | | | |    | |  | |\___ \|  __|     \   / |  __|    | |   
-- | |__| | |__| | | |\  | |__| | | |    | |__| |____) | |____     | |  | |____   | |   
-- |_____/ \____/  |_| \_|\____/  |_|     \____/|_____/|______|    |_|  |______|  |_|   
-- 
--This package is experimental and does not work yet.

--TODO: Am I re-inventing an XML wheel here?

--Purpose: Set all the CHILD_IDs of a node_table based on the parent_id.
--ASSUMPTIONS: p_nodes is dense, all child_ids are NULL, all parent_ids are set correctly,
--  nodes are added in tree order so a child node will always have an ID after the parent.
procedure add_child_ids(p_nodes in out node_table) is
	v_child_ids number_table;
begin
	--Loop through each node, look for nodes that refer to it.	
	for i in 1 .. p_nodes.count loop
		v_child_ids := number_table();

		--Gather child nodes.
		for j in i .. p_nodes.count loop
			if p_nodes(j).parent_id = i then
				v_child_ids.extend;
				v_child_ids(v_child_ids.count) := j;
			end if;
		end loop;

		--Set it if it's not null
		if v_child_ids.count > 0 then
			p_nodes(i).child_ids := v_child_ids;
		end if;
			
	end loop;
end;


function get_child_node_by_type(p_nodes node_table, p_node_index number, p_node_type varchar2, p_occurrence number default 1) return node is
	v_counter number := 0;
begin
	--TODO: Verify p_occurance

	for i in 1 .. p_nodes(p_node_index).child_ids.count loop
		if p_nodes(p_nodes(p_node_index).child_ids(i)).type = p_node_type then
			v_counter := v_counter + 1;
			if v_counter = p_occurrence then
				return p_nodes(p_nodes(p_node_index).child_ids(i));
			end if;
		end if;
	end loop;

	return null;
end get_child_node_by_type;


function get_children_node_by_type(p_nodes node_table, p_node_index number, p_node_type varchar2) return node_table is
	v_nodes node_table := node_table();
begin
	for i in 1 .. p_nodes(p_node_index).child_ids.count loop
		if p_nodes(p_nodes(p_node_index).child_ids(i)).type = p_node_type then
			v_nodes.extend;
			v_nodes(v_nodes.count) := p_nodes(p_nodes(p_node_index).child_ids(i));
		end if;
	end loop;

	return v_nodes;
end get_children_node_by_type;


function get_first_ancest_node_by_type(p_nodes node_table, p_node_index number, p_node_type varchar2) return node is
	v_parent_id number;
begin
	--Special case if already at top, return null.
	if p_nodes(p_node_index) is null then
		return null;
	end if;

	v_parent_id := p_nodes(p_node_index).parent_id;

	--Climb up tree until correct node found.
	loop
		--Nothing left to serach for, return NULL.
		if v_parent_id is null then
			return null;
		--Node found, return it.
		elsif p_nodes(v_parent_id).type = p_node_type then
			return p_nodes(v_parent_id);
		--Nothing found, go to next parent
		else
			v_parent_id := p_nodes(v_parent_id).parent_id;
		end if;
	end loop;

end get_first_ancest_node_by_type;


--Purpose: Compare names using the Oracle double-quote rules.
--Object names are case-insensitive *unless* they use double-quotes, except that
--double-quotes with all upper-case are really case-insensitive.
--Assumes: Names do not have leading or trailing whitespace, and are real names.
function are_names_equal(p_name1 varchar2, p_name2 varchar2) return boolean is
	is_case_sensitive boolean := false;
begin
	--Comparison is case sensitive if either name is case-sensitive.
	if
	(
		(p_name1 like '"%"' and p_name1 <> upper(p_name1))
		or
		(p_name2 like '"%"' and p_name2 <> upper(p_name2))
	)
	then
		is_case_sensitive := true;
	end if;

	--Compare them as-is if case sensitive.
	if is_case_sensitive then
		return p_name1 = p_name2;
	--Trim double-quotes and compare in same case if case insensitive.
	else
		return
			upper(trim('"' from p_name1)) = upper(trim('"' from p_name2));
	end if;

	return null;
end are_names_equal;


--Convert a name string to the case needed to match the data dictionary.
--Examples:
--asdf   --> ASDF
--"asdf" --> asdf
--"ASDF" --> ASDF
function get_data_dictionary_case(p_name varchar2) return varchar2 is
begin
	if p_name like '"%"' then
		return trim('"' from p_name);
	else
		return upper(p_name);
	end if;
end get_data_dictionary_case;


end;
/
