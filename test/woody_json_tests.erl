-module(woody_json_tests).

-include_lib("eunit/include/eunit.hrl").

-record(testStruct, {
    tp :: red | black | indeterminate,
    name :: binary(),
    parent :: {link, #testStruct{}} | {tag, binary()} | undefined
}).

-export([struct_info/1]).
-export([enum_info/1]).
-export([record_name/1]).

-spec test() -> _.

-spec json_term_test_() -> _.

json_term_test_() ->
    [
        ?_assertEqual(woorl_json:json_to_term([], test_schema()), #{}),
        ?_assertEqual(woorl_json:term_to_json(#{}, test_schema()), []),
        ?_assertEqual(
            test_term_1(),
            woorl_json:json_to_term(test_json_1(), test_schema())
        ),
        ?_assertEqual(
            test_json_1(),
            woorl_json:term_to_json(test_term_1(), test_schema())
        ),
        ?_assertEqual(
            test_term_1(),
            woorl_json:json_to_term(woorl_json:term_to_json(test_term_1(), test_schema()), test_schema())
        )
    ].

-spec non_printable_test_() -> _.
non_printable_test_() ->
    T1 = <<"Hello there!">>,
    J1 = T1,
    T2 = term_to_binary("Hello there!"),
    J2 = [{<<"content_type">>, <<"base64">>}, {<<"content">>, base64:encode(T2)}],
    [
        ?_assertEqual(J1, woorl_json:term_to_json(T1, string)),
        ?_assertEqual(J2, woorl_json:term_to_json(T2, string)),
        ?_assertEqual(T2, woorl_json:json_to_term(woorl_json:term_to_json(T2, string), string))
    ].

-spec enum_map_test_() -> _.
enum_map_test_() ->
    T = {map, {enum, {?MODULE, testEnum}}, i32},
    V = #{red => 42, indeterminate => 43},
    %% TODO/FIXME Map order is different in Erlang 27
    J = [{<<"red">>, 42}, {<<"indeterminate">>, 43}],
    [
        ?_assertEqual(J, woorl_json:term_to_json(V, T)),
        ?_assertEqual(V, woorl_json:json_to_term(J, T)),
        ?_assertEqual(V, woorl_json:json_to_term(woorl_json:term_to_json(V, T), T))
    ].

%%

test_json_1() ->
    [
        [
            {<<"key">>, [[42.42], []]},
            {<<"value">>, [
                {<<"127">>, [
                    %% TODO/FIXME Since 1.7 testcases for json_to_term
                    %% and term_to_json are broken.
                    %% For some reason after migration to jsone
                    %% atom_to_binary calls were removed and
                    %% term-encoded json with enums and structs now
                    %% contains atoms (!). Which in result breaks
                    %% json-encoding of that kind of a term, since it
                    %% does attempt to get value from json data with
                    %% atom_to_binary, like so:
                    %%
                    %%    FJson = getv(atom_to_binary(Fn, utf8), Json, Def),
                    %%
                    %% It is necessary to figure out the correct
                    %% approach, considering the existing usage of
                    %% this utility in production. Then, adjust or
                    %% replace the tests.
                    {<<"tp">>, <<"black">>},
                    {<<"name">>, <<"magic">>},
                    {<<"parent">>, [
                        {<<"link">>, [
                            {<<"tp">>, <<"red">>},
                            {<<"name">>, <<"herring">>}
                        ]}
                    ]}
                ]}
            ]}
        ]
    ].

test_term_1() ->
    #{
        [[42.42], []] => #{
            127 => #testStruct{
                tp = black,
                name = <<"magic">>,
                parent = {link, #testStruct{tp = red, name = <<"herring">>}}
            }
        }
    }.

test_schema() ->
    {map, {list, {set, double}}, {map, i8, {struct, struct, {?MODULE, testStruct}}}}.

-spec struct_info(atom()) ->
    {struct, struct | union | exception, [
        {pos_integer(), required | optional | undefined, woorl_thrift:type(), atom(), term() | undefined}
    ]}.
struct_info(testStruct) ->
    {struct, struct, [
        {1, required, {enum, {?MODULE, testEnum}}, 'tp', undefined},
        {2, optional, string, 'name', <<>>},
        {3, optional, {struct, union, {?MODULE, testUnion}}, 'parent', undefined}
    ]};
struct_info(testUnion) ->
    {struct, union, [
        {1, undefined, string, 'tag', undefined},
        {2, undefined, {struct, struct, {?MODULE, testStruct}}, 'link', undefined}
    ]};
struct_info(_) ->
    error(badarg).

-spec enum_info(atom()) -> {enum, [{atom(), integer()}]}.
enum_info(testEnum) ->
    {enum, [
        {red, 1},
        {black, 2},
        {indeterminate, 4}
    ]};
enum_info(_) ->
    error(badarg).

-spec record_name(atom()) -> atom() | no_return().
record_name(testStruct) ->
    'testStruct';
record_name(_) ->
    error(badarg).
