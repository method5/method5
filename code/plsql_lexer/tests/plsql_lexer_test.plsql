create or replace package plsql_lexer_test authid current_user is
/*
== Purpose ==

Unit tests for PLSQL_LEXER.


== Example ==

begin
	plsql_lexer_test.run;
	plsql_lexer_test.run(plsql_lexer_test.c_dynamic_tests);
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_test_whitespace              constant number := power(2, 1);
c_test_comment                 constant number := power(2, 2);
c_test_text                    constant number := power(2, 3);
c_test_numeric                 constant number := power(2, 4);
c_test_word                    constant number := power(2, 5);
c_test_inquiry_directive       constant number := power(2, 6);
c_test_preproc_control_token   constant number := power(2, 7);
c_test_3_character_punctuation constant number := power(2, 9);
c_test_2_character_punctuation constant number := power(2, 10);
c_test_1_character_punctuation constant number := power(2, 11);
c_test_unexpected              constant number := power(2, 12);
c_test_utf8                    constant number := power(2, 13);
c_test_row_pattern_matching    constant number := power(2, 14);
c_test_other                   constant number := power(2, 15);
c_test_line_col_start_end_pos  constant number := power(2, 16);

c_test_convert_to_text         constant number := power(2, 17);
c_test_get_varchar2_table      constant number := power(2, 18);

c_dynamic_tests                constant number := power(2, 30);

--Default option is to run all static test suites.
c_static_tests                 constant number := c_test_whitespace+c_test_comment+
	c_test_text+c_test_numeric+c_test_word+c_test_inquiry_directive+
	c_test_preproc_control_token+c_test_3_character_punctuation+c_test_2_character_punctuation+
	c_test_1_character_punctuation+c_test_unexpected+c_test_utf8+c_test_row_pattern_matching+
	c_test_other+c_test_line_col_start_end_pos+c_test_convert_to_text+c_test_get_varchar2_table;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_static_tests);

end;
/
create or replace package body plsql_lexer_test is
pragma serially_reusable;

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;

--Global characters for testing.
g_4_byte_utf8 varchar2(1 char) := unistr('\d841\df79');  --The "cut" character in Cantonese.  Looks like a guy with a sword.
g_2_byte_utf8 varchar2(1 char) := unistr('\00d0');       --The "eth" character, an upper case D with a line.

--Helper procedures.


--------------------------------------------------------------------------------
procedure assert_equals(p_test varchar2, p_expected varchar2, p_actual varchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with: '||p_test);
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


--------------------------------------------------------------------------------
function get_value_n(p_source clob, n number) return varchar2 is
	v_tokens token_table;
begin
	v_tokens := plsql_lexer.lex(p_source);
	return v_tokens(n).value;
end get_value_n;


--------------------------------------------------------------------------------
function get_sqlcode_n(p_source clob, n number) return varchar2 is
	v_tokens token_table;
begin
	v_tokens := plsql_lexer.lex(p_source);
	return v_tokens(n).sqlcode;
end get_sqlcode_n;


--------------------------------------------------------------------------------
function get_sqlerrm_n(p_source clob, n number) return varchar2 is
	v_tokens token_table;
begin
	v_tokens := plsql_lexer.lex(p_source);
	return v_tokens(n).sqlerrm;
end get_sqlerrm_n;


--------------------------------------------------------------------------------
--Simplifies calls to lex and print_tokens.
function lex(p_source clob) return clob is
begin
	return plsql_lexer.print_tokens(plsql_lexer.lex(p_source));
end lex;


--------------------------------------------------------------------------------
--Test Suites
procedure test_whitespace is
begin
	assert_equals('whitespace: 1a', 'whitespace EOF', lex(unistr('\3000')));
	assert_equals('whitespace: 1b', unistr('\3000'), get_value_n(unistr('\3000'), 1));
	assert_equals('whitespace: 2a', 'whitespace EOF', lex(chr(0)||chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||unistr('\3000')));
	--The chr(0) may prevent the string from being displayed properly.
	assert_equals('whitespace: 2b', chr(0)||chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||unistr('\3000'), get_value_n(chr(0)||chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||unistr('\3000'), 1));
	assert_equals('whitespace: 3', 'whitespace EOF', lex('	'));
	assert_equals('whitespace: 4', 'whitespace word whitespace word EOF', lex(' a a'));
end test_whitespace;


--------------------------------------------------------------------------------
procedure test_comment is
	v_clob clob;
begin
	assert_equals('comment: 1a', 'whitespace comment EOF', lex('  --asdf'));
	assert_equals('comment: 1b', '--asdf', get_value_n('  --asdf', 2));
	assert_equals('comment: 2a', 'whitespace comment EOF', lex('  --asdf'||chr(13)||'asdf'));
	assert_equals('comment: 2b', '--asdf'||chr(13)||'asdf', get_value_n('  --asdf'||chr(13)||'asdf', 2));
	assert_equals('comment: 3', 'whitespace comment whitespace word EOF', lex('  --asdf'||chr(13)||chr(10)||'asdf'));
	assert_equals('comment: 4', 'whitespace comment whitespace word EOF', lex('  --asdf'||chr(10)||'asdf'));
	assert_equals('comment: 5', 'comment EOF', lex('--'));
	assert_equals('comment: 6', 'comment EOF', lex('/**/'));
	assert_equals('comment: 7', 'comment EOF', lex('--/*'));
	assert_equals('comment: 8', 'word comment word EOF', lex(q'<asdf/*asdfq'!!'q!'' -- */asdf>'));
	assert_equals('comment: 9a', 'comment EOF', lex('/*'));
	assert_equals('comment: 9b', '-1742', to_char(get_sqlcode_n('/*', 1)));
	assert_equals('comment: 9c', 'comment not terminated properly', get_sqlerrm_n('/*', 1));
	--Comments may be larger than 32767.
	assert_equals('comment: 10', 'whitespace comment EOF', lex(' /*'||lpad('A', 32767, 'A')||'*/'));
end test_comment;


--------------------------------------------------------------------------------
procedure test_text is
begin
	--Simple strings.
	assert_equals('text: simple string 1a', 'whitespace text whitespace EOF', lex(q'! ' ' !'));
	assert_equals('text: simple string 1b', q'!' '!', get_value_n(q'! ' ' !', 2));
	--Simple N strings.
	assert_equals('text: n string 1a', 'whitespace text whitespace EOF', lex(q'! n' ' !'));
	assert_equals('text: n string 1b', q'!n' '!', get_value_n(q'! n' ' !', 2));
	assert_equals('text: n string 2a', 'whitespace text whitespace EOF', lex(q'! N' ' !'));
	assert_equals('text: n string 2b', q'!N' '!', get_value_n(q'! N' ' !', 2));

	--Escaped strings.
	assert_equals('text: escaped string 1', 'text whitespace EOF', lex(q'!'''' !'));
	assert_equals('text: escaped string 2', 'text whitespace EOF', lex(q'!'a ''' !'));
	assert_equals('text: escaped string 3', 'text whitespace EOF', lex(q'!''' ' !'));

	--Escaped N strings.
	assert_equals('text: escaped N string 1', 'text whitespace EOF', lex(q'!n'''' !'));
	assert_equals('text: escaped N string 2', 'text whitespace EOF', lex(q'!n'a ''' !'));
	assert_equals('text: escaped N string 3', 'text whitespace EOF', lex(q'!n''' ' !'));

	--Escaped alternative quote strings (not really escaped, but looks that way).
	assert_equals('text: escaped aq string 1', 'text whitespace EOF', lex(q'[q'!'!' ]'));
	assert_equals('text: escaped aq string 2', 'text whitespace EOF', lex(q'[q'!''!' ]'));

	--Escaped alternative quote N strings (not really escaped, but looks that way).
	assert_equals('text: escaped aq N string 1', 'text whitespace EOF', lex(q'[nq'!'!' ]'));
	assert_equals('text: escaped aq N string 2', 'text whitespace EOF', lex(q'[nq'!''!' ]'));

	--Alternative quoting mechanism closing delimiters: [, {, <, (
	assert_equals('text: alternative quote 1a', 'text EOF', lex(q'!q'[a]'!'));
	assert_equals('text: alternative quote 1b', q'!q'[a]'!', get_value_n(q'!q'[a]'!', 1));
	assert_equals('text: alternative quote 2a', 'text EOF', lex(q'!q'{a}'!'));
	assert_equals('text: alternative quote 2b', q'!q'{a}'!', get_value_n(q'!q'{a}'!', 1));
	assert_equals('text: alternative quote 3a', 'text EOF', lex(q'!q'<a>'!'));
	assert_equals('text: alternative quote 3b', q'!q'<a>'!', get_value_n(q'!q'<a>'!', 1));
	assert_equals('text: alternative quote 4a', 'text EOF', lex(q'!q'(a)'!'));
	assert_equals('text: alternative quote 4b', q'!q'(a)'!', get_value_n(q'!q'(a)'!', 1));
	--Alternative quoting mechanism matching delimiters.
	assert_equals('text: alternative quote ', 'text EOF', lex(q'!q'# ''' #'!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: alternative quote 5b', q'!q'# ''' #'!', get_value_n(q'!q'# ''' #'!', 1)); --'--Fix highlighting on some IDEs.

	--Same as above 2, but for n and N alternative quoting mechanisms.
	assert_equals('text: alternative n quote 1a', 'text EOF', lex(q'!nq'[a]'!'));
	assert_equals('text: alternative n quote 1b', q'!nq'[a]'!', get_value_n(q'!nq'[a]'!', 1));
	assert_equals('text: alternative n quote 2a', 'text EOF', lex(q'!nq'{a}'!'));
	assert_equals('text: alternative n quote 2b', q'!nq'{a}'!', get_value_n(q'!nq'{a}'!', 1));
	assert_equals('text: alternative n quote 3a', 'text EOF', lex(q'!Nq'<a>'!'));
	assert_equals('text: alternative n quote 3b', q'!Nq'<a>'!', get_value_n(q'!Nq'<a>'!', 1));
	assert_equals('text: alternative n quote 4a', 'text EOF', lex(q'!Nq'(a)'!'));
	assert_equals('text: alternative n quote 4b', q'!Nq'(a)'!', get_value_n(q'!Nq'(a)'!', 1));
	assert_equals('text: alternative n quote ', 'text EOF', lex(q'!Nq'# ''' #'!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: alternative n quote 5b', q'!Nq'# ''' #'!', get_value_n(q'!Nq'# ''' #'!', 1)); --'--Fix highlighting on some IDEs.

	--Test string not terminated.
	assert_equals('text: string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer '!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: string not terminated 2', q'!'!', get_value_n(q'!asdf qwer '!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer '!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer '!', 5)); --'--Fix highlighting on some IDEs.
	--Same as above, but for N, alternative quote, and N alternative quote.
	assert_equals('text: n string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer n'!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: n string not terminated 2', q'!n'!', get_value_n(q'!asdf qwer n'!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: n string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer n'!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: n string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer n'!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer Q'<asdf)'''!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 2', q'!Q'<asdf)'''!', get_value_n(q'!asdf qwer Q'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer q'<asdf)'''!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer Q'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer nQ'<asdf)'''!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 2', q'!NQ'<asdf)'''!', get_value_n(q'!asdf qwer NQ'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer nq'<asdf)'''!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer NQ'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.

	--Alternative quoting invalid delimiters - they may parse but throw errors.
	--Per my testing, only characters 9, 10, and 32 are problems.  I'm not testing 10 - the quotes are too ugly.
	assert_equals('text: AQ bad delimiter space 1', 'whitespace text whitespace EOF', lex(q'! q'  ' !'));
	assert_equals('text: AQ bad delimiter space 2', q'!q'  '!', get_value_n(q'! q'  ' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter space 3', '-911', to_char(get_sqlcode_n(q'! q'  ' !', 2))); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter space 4', 'invalid character', get_sqlerrm_n(q'! q'  ' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter tab 1', 'whitespace text whitespace EOF', lex(q'! Q'		' !'));
	assert_equals('text: AQ bad delimiter tab 2', q'!Q'		'!', get_value_n(q'! Q'		' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter tab 3', '-911', to_char(get_sqlcode_n(q'! Q'		' !', 2))); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter tab 4', 'invalid character', get_sqlerrm_n(q'! Q'		' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ bad delimiter space 1', 'whitespace text whitespace EOF', lex(q'! Nq'  ' !'));
	assert_equals('text: NAQ bad delimiter space 2', q'!Nq'  '!', get_value_n(q'! Nq'  ' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ bad delimiter space 3', '-911', to_char(get_sqlcode_n(q'! nq'  ' !', 2))); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ bad delimiter space 4', 'invalid character', get_sqlerrm_n(q'! nq'  ' !', 2)); --'--Fix highlighting on some IDEs.
end test_text;


--------------------------------------------------------------------------------
procedure test_numeric is
begin
	assert_equals('numeric: + not part of number', '+ numeric EOF', lex('+1234'));
	assert_equals('numeric: - not part of number', '+ numeric EOF', lex('+1234'));

	assert_equals('numeric: simple integer 1', 'numeric EOF', lex('1234'));
	assert_equals('numeric: simple integer 2', '1234', get_value_n('1234', 1));

	assert_equals('numeric: simple decimal 1', 'numeric EOF', lex('12.34'));
	assert_equals('numeric: simple decimal 2', '12.34', get_value_n('12.34', 1));

	assert_equals('numeric: start with . 1', 'numeric EOF', lex('.1234'));
	assert_equals('numeric: start with . 2', '.1234', get_value_n('.1234', 1));

	assert_equals('numeric: long number 1', 'numeric EOF', lex('1234567890123456789012345678901234567890.1234567890123456789012345678901234567890'));
	assert_equals('numeric: long number 2', '1234567890123456789012345678901234567890.1234567890123456789012345678901234567890', get_value_n('1234567890123456789012345678901234567890.1234567890123456789012345678901234567890', 1));

	assert_equals('numeric: E 1a', 'numeric EOF', lex('1.1e5'));
	assert_equals('numeric: E 1b', '1.1e5', get_value_n('1.1e5', 1));
	assert_equals('numeric: E 2a', 'numeric EOF', lex('1.1e+5'));
	assert_equals('numeric: E 2b', '1.1e+5', get_value_n('1.1e+5', 1));
	assert_equals('numeric: E 3a', 'numeric EOF', lex('1.1e-5'));
	assert_equals('numeric: E 3b', '1.1e-5', get_value_n('1.1e-5', 1));
	--Same as above, but with capital E
	assert_equals('numeric: E 4a', 'numeric EOF', lex('1.1E5'));
	assert_equals('numeric: E 4b', '1.1E5', get_value_n('1.1E5', 1));
	assert_equals('numeric: E 5a', 'numeric EOF', lex('1.1E+5'));
	assert_equals('numeric: E 5b', '1.1E+5', get_value_n('1.1E+5', 1));
	assert_equals('numeric: E 6a', 'numeric EOF', lex('1.1E-5'));
	assert_equals('numeric: E 6b', '1.1E-5', get_value_n('1.1E-5', 1));

	assert_equals('numeric: combine e and d/f 1a', 'numeric EOF', lex('.10e+5d'));
	assert_equals('numeric: combine e and d/f 1b', '.10e+5d', get_value_n('.10e+5d', 1));
	assert_equals('numeric: combine e and d/f 2a', 'numeric EOF', lex('.10E+5D'));
	assert_equals('numeric: combine e and d/f 2b', '.10E+5D', get_value_n('.10E+5D', 1));
	assert_equals('numeric: combine e and d/f 3a', 'numeric EOF', lex('.10E+5f'));
	assert_equals('numeric: combine e and d/f 3b', '.10E+5f', get_value_n('.10E+5f', 1));
	assert_equals('numeric: combine e and d/f 4a', 'numeric EOF', lex('.10e+5F'));
	assert_equals('numeric: combine e and d/f 4b', '.10e+5F', get_value_n('.10e+5F', 1));
	assert_equals('numeric: combine e and d/f 5a', 'numeric EOF', lex('.10e5'));
	assert_equals('numeric: combine e and d/f 5b', '.10e5', get_value_n('.10e5', 1));

	assert_equals('numeric: random 1', 'text numeric EOF', lex(q'[''4]'));
	assert_equals('numeric: random 2', 'numeric + numeric + numeric EOF', lex(q'[4+4+4]'));
	assert_equals('numeric: random 3', 'numeric word EOF', lex(q'[1.2ee]'));
	assert_equals('numeric: random 4', 'numeric word numeric word EOF', lex(q'[1.2ee1.2ff]'));
end test_numeric;


--------------------------------------------------------------------------------
procedure test_word is
begin
	assert_equals('word: simple name', 'word whitespace word EOF', lex('asdf asdf'));

	--Names can include numbers, #, $, and _, but not at the beginning.
	assert_equals('word: identifier 1', 'word EOF', lex('asdfQWER1234#$_asdf'));
	assert_equals('word: identifier 2', 'unexpected word EOF', lex('#a'));
	assert_equals('word: identifier 3', 'preprocessor_control_token EOF', lex('$a'));
	assert_equals('word: identifier 4', 'unexpected word EOF', lex('_a'));
	assert_equals('word: identifier 5', 'numeric word EOF', lex('1a'));
	assert_equals('word: identifier 6', '+ word + EOF', lex('+a1#$_+'));

	--4 byte supplementary character for "cut".
	assert_equals('word: utf8 identifier 1', 'word EOF', lex(g_4_byte_utf8));
	--2 byte D - Latin Capital Letter ETH.
	assert_equals('word: utf8 identifier 2', 'word EOF', lex(g_2_byte_utf8));
	--Putting different letters together.
	assert_equals('word: utf8 identifier 3', 'word + EOF', lex(g_2_byte_utf8||g_2_byte_utf8||g_4_byte_utf8||'A+'));
	assert_equals('word: utf8 identifier 4', g_2_byte_utf8||g_2_byte_utf8||g_4_byte_utf8||'A', get_value_n(g_2_byte_utf8||g_2_byte_utf8||g_4_byte_utf8||'A+', 1));

	assert_equals('word: double quote 1', 'word word EOF', lex('"asdf"a'));
	assert_equals('word: double quote 2', 'word word EOF', lex('"!@#$%^&*()"a'));
	assert_equals('word: double quote 3', '"!@#$%^&*()"', get_value_n('"!@#$%^&*()"a', 1));
	assert_equals('word: double quote 4', 'word numeric word EOF', lex('"a"4"b"'));

	assert_equals('word: missing double quote 1a', 'word EOF', lex('"!@#$%^&*()'));
	assert_equals('word: missing double quote 1b', '-1740', get_sqlcode_n('"!@#$%^&*()', 1));
	assert_equals('word: missing double quote 1c', 'missing double quote in identifier', get_sqlerrm_n('"!@#$%^&*()', 1));

	--This should be an error, but must be enforced later by the parser.
	assert_equals('word: zero-length identifier 1a', 'numeric word EOF', lex('1""'));
	assert_equals('word: zero-length identifier 1b', '""', get_value_n('1""', 2));
	assert_equals('word: zero-length identifier 1c', null, get_sqlcode_n('1""', 2));
	assert_equals('word: zero-length identifier 1d', null, get_sqlerrm_n('1""', 2));

	assert_equals('word: identifier is too long 30 bytes 1a', 'word EOF', lex('abcdefghijabcdefghijabcdefghij'));
	assert_equals('word: identifier is too long 30 bytes 1b', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghij', 1));
	assert_equals('word: identifier is too long 30 bytes 1c', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghij', 1));
	assert_equals('word: identifier is too long 30 bytes 2a', 'word EOF', lex('"abcdefghijabcdefghijabcdefghij"'));
	assert_equals('word: identifier is too long 30 bytes 2b', null, get_sqlcode_n('"abcdefghijabcdefghijabcdefghij"', 1));
	assert_equals('word: identifier is too long 30 bytes 2c', null, get_sqlerrm_n('"abcdefghijabcdefghijabcdefghij"', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('word: identifier is too long 31 bytes 1a', 'word EOF', lex('abcdefghijabcdefghijabcdefghijK'));
	assert_equals('word: identifier is too long 31 bytes 1b', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghijK', 1));
	assert_equals('word: identifier is too long 31 bytes 1c', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghijK', 1));
	assert_equals('word: identifier is too long 31 bytes 2a', 'word EOF', lex('"abcdefghijabcdefghijabcdefghijK"'));
	assert_equals('word: identifier is too long 31 bytes 2b', null, get_sqlcode_n('"abcdefghijabcdefghijabcdefghijK"', 1));
	assert_equals('word: identifier is too long 31 bytes 2c', null, get_sqlerrm_n('"abcdefghijabcdefghijabcdefghijK"', 1));

	assert_equals('word: identifier is too long 29 chars 31 bytes 1a', 'word EOF', lex('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8));
	assert_equals('word: identifier is too long 29 chars 31 bytes 1b', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));
	assert_equals('word: identifier is too long 29 chars 31 bytes 1c', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));

	--Database links can have 128 bytes.  This example is valid.
	assert_equals('word: database link 1', 'word whitespace * whitespace word whitespace word @ word . word @ word EOF', lex('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij.abcdefghijabcdefghijabcdefghijabcdefghij@abcdefghijabcdefghijabcdefghijabcdefghij'));
	assert_equals('word: database link 2', '@', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 8));
	assert_equals('word: database link 3', 'abcdefghijabcdefghijabcdefghijabcdefghij1', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 9));
	assert_equals('word: database link 4', '.', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 10));
	assert_equals('word: database link 5', 'abcdefghijabcdefghijabcdefghijabcdefghij2', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 11));
	assert_equals('word: database link 6', '@', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 12));
	assert_equals('word: database link 7', 'abcdefghijabcdefghijabcdefghijabcdefghij3', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 13));
	assert_equals('word: database link 8', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));
	assert_equals('word: database link 9', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));
end test_word;


--------------------------------------------------------------------------------
procedure test_inquiry_directive is
begin
	assert_equals('inquiry directive: simple 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$asdf); end;'));
	assert_equals('inquiry directive: simple 2', '$$asdf', get_value_n('begin dbms_output.put_line($$asdf); end;', 7));

	assert_equals('inquiry directive: name characters 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$asdf$_#1); end;'));
	assert_equals('inquiry directive: name characters 2', '$$asdf$_#1', get_value_n('begin dbms_output.put_line($$asdf$_#1); end;', 7));

	assert_equals('inquiry directive: unexpected (empty name)', 'word whitespace word . word ( unexpected unexpected ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$); end;'));

	assert_equals('inquiry directive: 30 characters 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghij); end;'));
	assert_equals('inquiry directive: 30 characters 2', '$$abcdefghijabcdefghijabcdefghij', get_value_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghij); end;', 7));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('inquiry directive: 31 characters 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghijK); end;'));
	assert_equals('inquiry directive: 31 characters 2', null, get_sqlcode_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghijK); end;', 1));
	assert_equals('inquiry directive: 31 characters 3', null, get_sqlerrm_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghijK); end;', 1));

	--PL/SQL Bug(?): Inquiry directive can be over 31 bytes if the last character starts before byte 30.
	assert_equals('inquiry directive: 30 characters 31 bytes 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('inquiry directive: 30 characters 31 bytes 2', '$$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, get_value_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 7));
	assert_equals('inquiry directive: 30 characters 31 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('inquiry directive: 30 characters 31 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('inquiry directive: 30 characters 33 bytes 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;'));
	assert_equals('inquiry directive: 30 characters 33 bytes 2', '$$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8, get_value_n('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 7));
	assert_equals('inquiry directive: 30 characters 33 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));
	assert_equals('inquiry directive: 30 characters 33 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('inquiry directive: 30 characters 31 bytes 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('inquiry directive: 30 characters 31 bytes2', null, get_sqlcode_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('inquiry directive: 30 characters 31 bytes3', null, get_sqlerrm_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
end test_inquiry_directive;


--------------------------------------------------------------------------------
procedure test_preproc_control_token is
begin
	assert_equals('preprocessor control token: valid example 1', 'word whitespace preprocessor_control_token whitespace numeric = numeric whitespace preprocessor_control_token whitespace word ; whitespace preprocessor_control_token whitespace word ; EOF', lex('begin $if 1=1 $then null; $end end;'));
	assert_equals('preprocessor control token: valid example 2', 'begin', get_value_n('begin $if 1=1 $then null; $end end;', 1));
	assert_equals('preprocessor control token: valid example 3', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 2));
	assert_equals('preprocessor control token: valid example 4', '$if', get_value_n('begin $if 1=1 $then null; $end end;', 3));
	assert_equals('preprocessor control token: valid example 5', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 4));
	assert_equals('preprocessor control token: valid example 6', '1', get_value_n('begin $if 1=1 $then null; $end end;', 5));
	assert_equals('preprocessor control token: valid example 7', '=', get_value_n('begin $if 1=1 $then null; $end end;', 6));
	assert_equals('preprocessor control token: valid example 8', '1', get_value_n('begin $if 1=1 $then null; $end end;', 7));
	assert_equals('preprocessor control token: valid example 9', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 8));
	assert_equals('preprocessor control token: valid example 10', '$then', get_value_n('begin $if 1=1 $then null; $end end;', 9));
	assert_equals('preprocessor control token: valid example 11', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 10));
	assert_equals('preprocessor control token: valid example 12', 'null', get_value_n('begin $if 1=1 $then null; $end end;', 11));
	assert_equals('preprocessor control token: valid example 13', ';', get_value_n('begin $if 1=1 $then null; $end end;', 12));
	assert_equals('preprocessor control token: valid example 14', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 13));
	assert_equals('preprocessor control token: valid example 15', '$end', get_value_n('begin $if 1=1 $then null; $end end;', 14));
	assert_equals('preprocessor control token: valid example 16', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 15));
	assert_equals('preprocessor control token: valid example 17', 'end', get_value_n('begin $if 1=1 $then null; $end end;', 16));
	assert_equals('preprocessor control token: valid example 18', ';', get_value_n('begin $if 1=1 $then null; $end end;', 17));
	assert_equals('preprocessor control token: valid example 19', '', get_value_n('begin $if 1=1 $then null; $end end;', 18));

	assert_equals('preprocessor control token: name characters 1', 'word whitespace preprocessor_control_token whitespace numeric = numeric whitespace preprocessor_control_token whitespace word ; whitespace preprocessor_control_token whitespace word ; EOF', lex('begin $if_#$1 1=1 $then null; $end end;'));
	assert_equals('preprocessor control token: name characters 2', '$if_#$1', get_value_n('begin $if_#$1 1=1 $then null; $end end;', 3));

	assert_equals('preprocessor control token: unexpected (empty name)', 'word whitespace word . word ( unexpected ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($); end;'));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('preprocessor control token: 31 characters 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghijK); end;'));
	assert_equals('preprocessor control token: 31 characters 2', null, get_sqlcode_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghijK); end;', 1));
	assert_equals('preprocessor control token: 31 characters 3', null, get_sqlerrm_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghijK); end;', 1));

	--PL/SQL Bug(?): Preprocessor control tokens can be over 31 bytes if the last character starts before byte 30.
	--Although all preprocessor control tokens are predefined.  Using anything else will throw an additional error.
	--It may not be worth catching this second error.
	assert_equals('preprocessor control token: 30 characters 31 bytes 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('preprocessor control token: 30 characters 31 bytes 2', '$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, get_value_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 7));
	assert_equals('preprocessor control token: 30 characters 31 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('preprocessor control token: 30 characters 31 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('preprocessor control token: 30 characters 33 bytes 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;'));
	assert_equals('preprocessor control token: 30 characters 33 bytes 2', '$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8, get_value_n('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 7));
	assert_equals('preprocessor control token: 30 characters 33 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));
	assert_equals('preprocessor control token: 30 characters 33 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('preprocessor control token: 30 characters 31 bytes 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('preprocessor control token: 30 characters 31 bytes2', null, get_sqlcode_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('preprocessor control token: 30 characters 31 bytes3', null, get_sqlerrm_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
end test_preproc_control_token;


--------------------------------------------------------------------------------
procedure test_3_character_punctuation is
begin
	assert_equals('3-char punctuation: 01', ', , ,}? , , EOF', lex(q'[,,,}?,,]'));

	assert_equals('3-char punctuation: 02', ',', get_value_n(q'[,,,}?,,]', 1));
	assert_equals('2-char punctuation: 03', ',', get_value_n(q'[,,,}?,,]', 2));
	assert_equals('2-char punctuation: 04', ',}?', get_value_n(q'[,,,}?,,]', 3));
	assert_equals('2-char punctuation: 05', ',', get_value_n(q'[,,,}?,,]', 4));
	assert_equals('2-char punctuation: 06', ',', get_value_n(q'[,,,}?,,]', 5));
end test_3_character_punctuation;


--------------------------------------------------------------------------------
procedure test_2_character_punctuation is
begin
	assert_equals('2-char punctuation: 01', '~= != ^= <> := => >= <= ** || << >> {- -} *? +? ?? ,} }? {, .. EOF', lex(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]'));

	assert_equals('2-char punctuation: 02', '~=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 1));
	assert_equals('2-char punctuation: 03', '!=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 2));
	assert_equals('2-char punctuation: 04', '^=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 3));
	assert_equals('2-char punctuation: 05', '<>', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 4));
	assert_equals('2-char punctuation: 06', ':=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 5));
	assert_equals('2-char punctuation: 07', '=>', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 6));
	assert_equals('2-char punctuation: 08', '>=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 7));
	assert_equals('2-char punctuation: 09', '<=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 8));
	assert_equals('2-char punctuation: 10', '**', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 9));
	assert_equals('2-char punctuation: 11', '||', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 10));
	assert_equals('2-char punctuation: 12', '<<', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 11));
	assert_equals('2-char punctuation: 13', '>>', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 12));
	assert_equals('2-char punctuation: 14', '{-', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 13));
	assert_equals('2-char punctuation: 15', '-}', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 14));
	assert_equals('2-char punctuation: 16', '*?', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 15));
	assert_equals('2-char punctuation: 17', '+?', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 16));
	assert_equals('2-char punctuation: 18', '??', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 17));
	assert_equals('2-char punctuation: 19', ',}', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 18));
	assert_equals('2-char punctuation: 20', '}?', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 19));
	assert_equals('2-char punctuation: 21', '{,', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 20));
	assert_equals('2-char punctuation: 22', '..', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 21));
	assert_equals('2-char punctuation: 22', null, get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>{--}*?+???,}}?{,..]', 22));
end test_2_character_punctuation;


--------------------------------------------------------------------------------
procedure test_1_character_punctuation is
begin
	--Note that "$" is not included here.  "$" is only a token in a row pattern
	--matching context.  See the separate unit tests for row pattern matching.
	assert_equals('1-char punctuation: 01', '! @ % ^ * ( ) - + = [ ] { } | : ; < , > . / ? EOF', lex(q'[!@%^*()-+=[]{}|:;<,>./?]'));
	assert_equals('1-char punctuation: 02', '!',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 1));
	assert_equals('1-char punctuation: 03', '@',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 2));
	assert_equals('1-char punctuation: 04', '%',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 3));
	assert_equals('1-char punctuation: 05', '^',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 4));
	assert_equals('1-char punctuation: 06', '*',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 5));
	assert_equals('1-char punctuation: 07', '(',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 6));
	assert_equals('1-char punctuation: 08', ')',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 7));
	assert_equals('1-char punctuation: 09', '-',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 8));
	assert_equals('1-char punctuation: 10', '+',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 9));
	assert_equals('1-char punctuation: 11', '=',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 10));
	assert_equals('1-char punctuation: 12', '[',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 11));
	assert_equals('1-char punctuation: 13', ']',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 12));
	assert_equals('1-char punctuation: 14', '{',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 13));
	assert_equals('1-char punctuation: 15', '}',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 14));
	assert_equals('1-char punctuation: 16', '|',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 15));
	assert_equals('1-char punctuation: 17', ':',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 16));
	assert_equals('1-char punctuation: 18', ';',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 17));
	assert_equals('1-char punctuation: 19', '<',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 18));
	assert_equals('1-char punctuation: 20', ',',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 19));
	assert_equals('1-char punctuation: 21', '>',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 20));
	assert_equals('1-char punctuation: 22', '.',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 21));
	assert_equals('1-char punctuation: 23', '/',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 22));
	assert_equals('1-char punctuation: 24', '?',  get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 23));
	assert_equals('1-char punctuation: 25', null, get_value_n(q'[!@%^*()-+=[]{}|:;<,>./?]', 24));

	assert_equals('1-char punctuation: realistic example',
		'<< word >> word whitespace word whitespace word := numeric ; whitespace word whitespace word ; whitespace word ; EOF',
		lex(q'[<<my_label>>declare v_test number:=1; begin null; end;]'));

	assert_equals('@!= ambiguity',
		'word whitespace * whitespace word whitespace word whitespace word whitespace word @ ! = word whitespace word whitespace numeric != numeric EOF',
		lex(q'[select * from dual where sysdate@!=sysdate and 1!=2]'));
end test_1_character_punctuation;


--------------------------------------------------------------------------------
procedure test_unexpected is
begin
	assert_equals('unexpected: 01', 'unexpected EOF', lex('_'));
	assert_equals('unexpected: 02', '_', get_value_n('_', 1));
	assert_equals('unexpected: 03', 'word unexpected EOF', lex('abcd&'));
	assert_equals('unexpected: 04', '&', get_value_n('abcd&', 2));
end test_unexpected;


--------------------------------------------------------------------------------
procedure test_utf8 is
begin
	--Try to trip-up substrings with multiples of that character.
	assert_equals('utf8: 4-byte 1', 'word EOF', lex(g_4_byte_utf8));
	assert_equals('utf8: 4-byte 2', 'word whitespace word EOF', lex(g_4_byte_utf8 || ' ' || g_4_byte_utf8));
	assert_equals('utf8: 4-byte 4', 'word whitespace word EOF', lex(g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||' a'));
	assert_equals('utf8: 4-byte 3', 'word whitespace word EOF', lex(g_4_byte_utf8||g_4_byte_utf8||'asdf'||g_4_byte_utf8||' a'));
end test_utf8;


--------------------------------------------------------------------------------
--Row pattern matching in 12c adds complexity because of operator ambiguity.
procedure test_row_pattern_matching is
begin
	--Inquiry directives and preprocessor control tokens still work in row pattern matching.
	--'$' matches the single character, it is not allowed as part of a name inside row pattern matching.
	--This is valid code that should run on 12c+.
	assert_equals(
		'Row pattern matching: valid PL/SQL 1',
		/*declare                                */ 'whitespace word ' ||
		/*	v_test number;                       */ 'whitespace word whitespace word ; ' ||
		/*begin                                  */ 'whitespace word ' ||
		/*	select $$inq_dir_test inq_dir_test$$ */ 'whitespace word whitespace inquiry_directive whitespace word ' ||
		/*	into v_test                          */ 'whitespace word whitespace word ' ||
		/*	from dual                            */ 'whitespace word whitespace word ' ||
		/*	match_recognize(                     */ 'whitespace word ( ' ||
		/*		measures x.dummy dummy           */ 'whitespace word whitespace word . word whitespace word ' ||
		/*		pattern(                         */ 'whitespace word ( ' ||
		/*			^x$$|                        */ 'whitespace ^ word $ $ | ' ||
		/*			x{$$inq_dir_test}|           */ 'whitespace word { inquiry_directive } | ' ||
		/*			x{$IF 1=1 $THEN 1 $END}      */ 'whitespace word { preprocessor_control_token whitespace numeric = numeric whitespace preprocessor_control_token whitespace numeric whitespace preprocessor_control_token } ' ||
		/*		)                                */ 'whitespace ) ' ||
		/*		define x as (1=1)                */ 'whitespace word whitespace word whitespace word whitespace ( numeric = numeric ) ' ||
		/*	);                                   */ 'whitespace ) ; ' ||
		/*end;                                   */ 'whitespace word ; whitespace EOF'
		,
		--To work correctly in the real world, execute this alter first:
		--alter session set plsql_ccflags = 'inq_dir_test:1';
		lex('
			declare
				v_test number;
			begin
				select $$inq_dir_test inq_dir_test$$
				into v_test
				from dual
				match_recognize(
					measures x.dummy dummy
					pattern(
						^x$$|
						x{$$inq_dir_test}|
						x{$IF 1=1 $THEN 1 $END}
					)
					define x as (1=1)
				);
			end;
		')
	);

	--Valid code that returns 'X'.
	assert_equals(
		'Row pattern matching: valid SQL 1',
		/*select *                 */ 'whitespace word whitespace * ' ||
		/*from dual                */ 'whitespace word whitespace word ' ||
		/*match_recognize(         */ 'whitespace word ( ' ||
		/*	measures x.dummy dummy */ 'whitespace word whitespace word . word whitespace word ' ||
		/*	pattern(^x$)           */ 'whitespace word ( ^ word $ ) ' ||
		/*	define x as (1=1)      */ 'whitespace word whitespace word whitespace word whitespace ( numeric = numeric ) ' ||
		/*)                        */ 'whitespace ) whitespace EOF',
		lex('
			select *
			from dual
			match_recognize(
				measures x.dummy dummy
				pattern(^x$)
				define x as (1=1)
			)
		'));

	--Although "**" and "||" are invalid, they are lexed differently in pattern matching.
	--This may matter for error handling.
	assert_equals(
		'Row pattern matching: invalid SQL 2',
		/*select *                 */ 'whitespace word whitespace * ' ||
		/*from dual                */ 'whitespace word whitespace word ' ||
		/*match_recognize(         */ 'whitespace word ( ' ||
		/*	measures x.dummy dummy */ 'whitespace word whitespace word . word whitespace word ' ||
		/*	pattern(^x**||$)       */ 'whitespace word ( ^ word * * | | $ ) ' ||
		/*	define x as (1=1)      */ 'whitespace word whitespace word whitespace word whitespace ( numeric = numeric ) ' ||
		/*)                        */ 'whitespace ) whitespace EOF',
		lex('
			select *
			from dual
			match_recognize(
				measures x.dummy dummy
				pattern(^x**||$)
				define x as (1=1)
			)
		'));

	--Lexer bug, although it's astronomically unlikely to happen.
	--Creating functions with these specific names, calling them in this order, and
	--using "$", "**", and "||" may lex incorrectly because it looks like it's
	--part of pattern matching.
	assert_equals(
		'Row pattern matching: Bug 1',
		/*begin                                           */ 'whitespace word ' ||
		/*	match_recognize(pattern(p_name$ => 2**2||1)); */ 'whitespace word ( word ( word $ whitespace => whitespace numeric * * numeric | | numeric ) ) ; ' ||
		/*end;                                            */ 'whitespace word ; whitespace EOF',
		lex('
			begin
				match_recognize(pattern(p_name$ => 2**2||1));
			end;
		'));

	assert_equals('Row pattern matching: Paren-counting 1','word ( word ( ( ) word $ ) ) EOF',lex('match_recognize(pattern(()x$))'));
	assert_equals('Row pattern matching: Paren-counting 2','word ( word ( ( ( ) ) word $ ) ) EOF',lex('match_recognize(pattern((())x$))'));
	assert_equals('Row pattern matching: Paren-counting 3','word ( word ( ( word ( word ) ) word $ ) ) EOF',lex('match_recognize(pattern((x(y))x$))'));

	assert_equals('Row pattern matching: Value 1' ,'pattern',get_value_n('match_recognize(pattern((x(y))x$))', 3));
	assert_equals('Row pattern matching: Value 2' ,'x'      ,get_value_n('match_recognize(pattern((x(y))x$))', 6));
	assert_equals('Row pattern matching: Value 3' ,'('      ,get_value_n('match_recognize(pattern((x(y))x$))', 7));
	assert_equals('Row pattern matching: Value 4' ,')'      ,get_value_n('match_recognize(pattern((x(y))x$))', 10));
	assert_equals('Row pattern matching: Value 5' ,'x'      ,get_value_n('match_recognize(pattern((x(y))x$))', 11));
	assert_equals('Row pattern matching: Value 6' ,'$'      ,get_value_n('match_recognize(pattern((x(y))x$))', 12));
	assert_equals('Row pattern matching: Value 7' ,')'      ,get_value_n('match_recognize(pattern((x(y))x$))', 13));

	assert_equals('Row pattern matching: Value 8' ,'('      ,get_value_n('match_recognize(pattern(**||)||', 4));
	assert_equals('Row pattern matching: Value 9' ,'*'      ,get_value_n('match_recognize(pattern(**||)||', 5));
	assert_equals('Row pattern matching: Value 10','*'      ,get_value_n('match_recognize(pattern(**||)||', 6));
	assert_equals('Row pattern matching: Value 11','|'      ,get_value_n('match_recognize(pattern(**||)||', 7));
	assert_equals('Row pattern matching: Value 12','|'      ,get_value_n('match_recognize(pattern(**||)||', 8));
	assert_equals('Row pattern matching: Value 13','||'     ,get_value_n('match_recognize(pattern(**||)||', 10));
end test_row_pattern_matching;


--------------------------------------------------------------------------------
procedure test_other is
begin
	assert_equals('Other: Null only returns EOF', 'EOF', lex(null));
	assert_equals('Other: EOF value is NULL', null, get_value_n(null, 1));
	assert_equals('Other: Random', 'word whitespace - numeric + numeric whitespace word whitespace word ; EOF', lex('select -1+1e2d from dual;'));
end test_other;


--------------------------------------------------------------------------------
procedure test_line_col_start_end_pos is
	v_tokens token_table;

	function concat_token(p_token token) return varchar2 is
	begin
		return
			p_token.line_number||'-'||
			p_token.column_number||'-'||
			p_token.first_char_position||'-'||
			p_token.last_char_position;
	end concat_token;
begin
	--Simple strings.
	v_tokens := plsql_lexer.lex('A C');
	assert_equals('Line Number Simple 1.', '1-1-1-1', concat_token(v_tokens(1)));
	assert_equals('Line Number Simple 2.', '1-2-2-2', concat_token(v_tokens(2)));
	assert_equals('Line Number Simple 3.', '1-3-3-3', concat_token(v_tokens(3)));
	assert_equals('Line Number Simple 4.', '1-4-4-4', concat_token(v_tokens(4)));

	--Smallest possible string.
	v_tokens := plsql_lexer.lex('A');
	assert_equals('Line Number Simple 5.', '1-1-1-1', concat_token(v_tokens(1)));
	assert_equals('Line Number Simple 6.', '1-2-2-2', concat_token(v_tokens(2)));

	--Empty, just EOF.
	v_tokens := plsql_lexer.lex('');
	assert_equals('Line Number EOF 1.', '1-1-1-1', concat_token(v_tokens(1)));

	--Test values with all different types.
	v_tokens := plsql_lexer.lex(q'[
		/*comment*/ 'text1' nq'!text2!' 1.2d asdf "asdf" $$asdf $asdf *.`]'
	);

	assert_equals('Line Number 01.', '1-1-1-3', concat_token(v_tokens(1)));     --whitespace at beginning
	assert_equals('Line Number 02.', '2-3-4-14', concat_token(v_tokens(2)));    --comment
	assert_equals('Line Number 03.', '2-14-15-15', concat_token(v_tokens(3)));  --whitespace
	assert_equals('Line Number 04.', '2-15-16-22', concat_token(v_tokens(4)));  --text
	assert_equals('Line Number 05.', '2-22-23-23', concat_token(v_tokens(5)));  --whitespace
	assert_equals('Line Number 06.', '2-23-24-34', concat_token(v_tokens(6)));  --nq text
	assert_equals('Line Number 07.', '2-34-35-35', concat_token(v_tokens(7)));  --whitespace
	assert_equals('Line Number 08.', '2-35-36-39', concat_token(v_tokens(8)));  --number
	assert_equals('Line Number 09.', '2-39-40-40', concat_token(v_tokens(9)));  --whitespace
	assert_equals('Line Number 10.', '2-40-41-44', concat_token(v_tokens(10))); --word
	assert_equals('Line Number 11.', '2-44-45-45', concat_token(v_tokens(11))); --whitespace
	assert_equals('Line Number 12.', '2-45-46-51', concat_token(v_tokens(12))); --word (in quotes)
	assert_equals('Line Number 13.', '2-51-52-52', concat_token(v_tokens(13))); --whitespace
	assert_equals('Line Number 14.', '2-52-53-58', concat_token(v_tokens(14))); --Inquiry directive
	assert_equals('Line Number 15.', '2-58-59-59', concat_token(v_tokens(15))); --whitespace
	assert_equals('Line Number 16.', '2-59-60-64', concat_token(v_tokens(16))); --preprocessor control token
	assert_equals('Line Number 17.', '2-64-65-65', concat_token(v_tokens(17))); --whitespace
	assert_equals('Line Number 18.', '2-65-66-66', concat_token(v_tokens(18))); --*
	assert_equals('Line Number 19.', '2-66-67-67', concat_token(v_tokens(19))); --.
	assert_equals('Line Number 20.', '2-67-68-68', concat_token(v_tokens(20))); --EOF

	--Test multiple new lines.
	v_tokens := plsql_lexer.lex(q'[
a


b



c]'
	);

	assert_equals('Line Number - Many Lines 01.', '1-1-1-1', concat_token(v_tokens(1)));   --whitespace.
	assert_equals('Line Number - Many Lines 02.', '2-1-2-2', concat_token(v_tokens(2)));   --a
	assert_equals('Line Number - Many Lines 03.', '2-2-3-5', concat_token(v_tokens(3)));   --whitespace
	assert_equals('Line Number - Many Lines 04.', '5-1-6-6', concat_token(v_tokens(4)));   --b
	assert_equals('Line Number - Many Lines 05.', '5-2-7-10', concat_token(v_tokens(5)));  --whitespace
	assert_equals('Line Number - Many Lines 06.', '9-1-11-11', concat_token(v_tokens(6))); --c
	assert_equals('Line Number - Many Lines 07.', '9-2-12-12', concat_token(v_tokens(7))); --eof

	--TODO: Multi-byte character test.

end test_line_col_start_end_pos;


--------------------------------------------------------------------------------
procedure test_convert_to_text is
begin
	assert_equals('Convert To Text 1' ,'select * from dual', plsql_lexer.concatenate(plsql_lexer.lex('select * from dual')));
	--TODO: Test multi-byte characters and large strings.
end test_convert_to_text;


--------------------------------------------------------------------------------
procedure test_get_varchar2_table is
begin
	--TODO: Test multi-byte characters and large strings.
	null;
end test_get_varchar2_table;


--------------------------------------------------------------------------------
procedure dynamic_tests is
	type clob_table is table of clob;
	type string_table is table of varchar2(100);
	v_sql_fulltexts clob_table;
	v_sql_ids string_table;
	sql_cursor sys_refcursor;
	v_tokens token_table;
begin
	--This tests that everything can be lexed.
	--There should not be any unexpected tokens for valid code.

	--Use dynamic SQL so the package doesn't need direct grants on GV$SQL.
	open sql_cursor for '
		--Select distinct SQL statements.
		select sql_fulltext, sql_id
		from
		(
			select sql_fulltext, sql_id, row_number() over (partition by sql_id order by 1) rownumber
			from gv$sql
		)
		where rownumber = 1
		--TODO: Add PL/SQL code.
		order by sql_id
	';
	loop
		fetch sql_cursor bulk collect into v_sql_fulltexts, v_sql_ids limit 100;
		exit when v_sql_fulltexts.count = 0;

		--Go through each SQL text.
		for i in 1 .. v_sql_fulltexts.count loop
			--Lex.
			v_tokens := plsql_lexer.lex(v_sql_fulltexts(i));

			--Loop through the tokens.
			for j in 1 .. v_tokens.count loop
				--Fail if an unexpected is found.
				if v_tokens(j).type = plsql_lexer.c_unexpected then
					assert_equals('Dynamic test on '||v_sql_ids(i)||': ', '0 unexpected found', '>=1 unexpected found');
					exit;
				--Pass if last token and no unexpected are found.
				elsif j = v_tokens.count then
					assert_equals('Dynamic test on '||v_sql_ids(i)||': ', '0 unexpected found', '0 unexpected found');
				end if;
			end loop;
		end loop;
	end loop;
end dynamic_tests;


--------------------------------------------------------------------------------
procedure run(p_tests number default c_static_tests) is
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Print header.
	dbms_output.put_line(null);
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('PL/SQL Lexer Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the chosen tests.
	if bitand(p_tests, c_test_whitespace)              > 0 then test_whitespace; end if;
	if bitand(p_tests, c_test_comment)                 > 0 then test_comment; end if;
	if bitand(p_tests, c_test_text)                    > 0 then test_text; end if;
	if bitand(p_tests, c_test_numeric)                 > 0 then test_numeric; end if;
	if bitand(p_tests, c_test_word)                    > 0 then test_word; end if;
	if bitand(p_tests, c_test_inquiry_directive)       > 0 then test_inquiry_directive; end if;
	if bitand(p_tests, c_test_preproc_control_token)   > 0 then test_preproc_control_token; end if;
	if bitand(p_tests, c_test_3_character_punctuation) > 0 then test_3_character_punctuation; end if;
	if bitand(p_tests, c_test_2_character_punctuation) > 0 then test_2_character_punctuation; end if;
	if bitand(p_tests, c_test_1_character_punctuation) > 0 then test_1_character_punctuation; end if;
	if bitand(p_tests, c_test_unexpected)              > 0 then test_unexpected; end if;
	if bitand(p_tests, c_test_utf8)                    > 0 then test_utf8; end if;
	if bitand(p_tests, c_test_row_pattern_matching)    > 0 then test_row_pattern_matching; end if;
	if bitand(p_tests, c_test_other)                   > 0 then test_other; end if;
	if bitand(p_tests, c_test_line_col_start_end_pos)  > 0 then test_line_col_start_end_pos; end if;

	if bitand(p_tests, c_test_convert_to_text)         > 0 then test_convert_to_text; end if;
	if bitand(p_tests, c_test_get_varchar2_table)      > 0 then test_get_varchar2_table; end if;

	if bitand(p_tests, c_dynamic_tests)                > 0 then dynamic_tests; end if;

	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line(unit_tests.C_PASS_MESSAGE);
	else
		dbms_output.put_line(unit_tests.C_FAIL_MESSAGE);
	end if;
end run;

end;
/
