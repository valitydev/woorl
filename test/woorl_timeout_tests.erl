-module(woorl_timeout_tests).

-include_lib("eunit/include/eunit.hrl").

-spec test() -> _.

%% TEST-NET-1 (RFC 5737): guaranteed non-routable, so a TCP connect gets no
%% response and blocks until the connect timeout fires. A faithful stand-in for
%% a service ClusterIP with no healthy backend (SYN silently dropped), which is
%% what the reported `woorl --deadline=1m` call actually hit.
-define(BLACKHOLE_URL, "http://192.0.2.1:8022/v1/test").

-spec deadline_timeout_test_() -> _.
deadline_timeout_test_() ->
    {setup,
        fun() ->
            {ok, Apps} = application:ensure_all_started(woorl),
            Apps
        end,
        fun(_Apps) -> ok end, [
            fun parse_yields_full_minute/0,
            fun make_transport_opts_no_deadline/0,
            fun make_transport_opts_follows_deadline/0,
            {timeout, 30, fun default_opts_cap_connect_below_deadline/0},
            {timeout, 30, fun fix_opts_follow_deadline/0}
        ]}.

%%
%% The deadline value is NOT the reason for a sub-second failure: `1m` parses to
%% a full minute.
%%
-spec parse_yields_full_minute() -> _.
parse_yields_full_minute() ->
    {ok, Deadline} = woorl_deadline:parse_pretty(<<"1m">>),
    Timeout = woody_deadline:to_timeout(Deadline),
    ?assert(Timeout > 58000),
    ?assert(Timeout =< 60000).

%%
%% The fix: with a deadline set, connect/send timeouts follow the deadline
%% instead of woody's 1000ms cap; with no deadline nothing is overridden.
%%
-spec make_transport_opts_no_deadline() -> _.
make_transport_opts_no_deadline() ->
    ?assertEqual(#{}, woorl:make_transport_opts(woody_context:new())).

-spec make_transport_opts_follows_deadline() -> _.
make_transport_opts_follows_deadline() ->
    Ctx = ctx_with_deadline(<<"1m">>),
    #{connect_timeout := Connect, send_timeout := Send} = woorl:make_transport_opts(Ctx),
    %% ~60000ms (the full deadline) -- crucially NOT the 1000ms cap
    ?assert(Connect > 58000),
    ?assert(Send > 58000).

%%
%% End-to-end reproduction through woody's real transport against a black-hole
%% endpoint, with the SAME 4s deadline in both cases:
%%   - default transport opts -> connect capped at 1000ms -> fails at ~1s
%%   - the fix's transport opts -> connect follows the deadline -> fails at ~4s
%% This is the direct proof that the sub-second failure was the connect/send cap,
%% not the parsed deadline.
%%
-spec default_opts_cap_connect_below_deadline() -> _.
default_opts_cap_connect_below_deadline() ->
    Elapsed = time_flush(ctx_with_deadline(<<"4s">>), #{}),
    %% woody caps connect_timeout at 1000ms regardless of the 4s deadline
    ?assert(Elapsed > 700),
    ?assert(Elapsed < 2500).

-spec fix_opts_follow_deadline() -> _.
fix_opts_follow_deadline() ->
    Ctx = ctx_with_deadline(<<"4s">>),
    Elapsed = time_flush(Ctx, woorl:make_transport_opts(Ctx)),
    %% connect now runs up to the ~4s deadline instead of the 1s cap
    ?assert(Elapsed > 3000),
    ?assert(Elapsed < 6000).

%%
%% helpers
%%

-spec ctx_with_deadline(binary()) -> woody_context:ctx().
ctx_with_deadline(Bin) ->
    {ok, Deadline} = woorl_deadline:parse_pretty(Bin),
    woody_context:set_deadline(Deadline, woody_context:new()).

-spec time_flush(woody_context:ctx(), map()) -> integer().
time_flush(Ctx, TransportOpts) ->
    WoodyState = woody_state:new(client, Ctx, woody_event_handler_default),
    Transport0 = woody_client_thrift_http_transport:new(?BLACKHOLE_URL, TransportOpts, #{}, WoodyState),
    {Transport1, ok} = thrift_transport:write(Transport0, <<"ping">>),
    Started = erlang:monotonic_time(millisecond),
    {_Transport2, Result} = thrift_transport:flush(Transport1),
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    ?assertMatch({error, _}, Result),
    Elapsed.
