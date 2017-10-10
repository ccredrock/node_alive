%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright (C) 2017, <free>
%%% @doc
%%%
%%% @end
%%% Created : 2017年07月05日19:11:34
%%%-------------------------------------------------------------------
-module(node_alive).

-export([start/0, stop/0]).

-export([start_link/0]).

-export([get_ref/0,
         get_nodes/0,
         node_type/0,
         node_id/0]).

%% callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%%------------------------------------------------------------------------------
-behaviour(gen_server).

-define(TIMEOUT, 500).
-define(HEARTBEAT_TIMEOUT, 5). %% 5秒

-define(REDIS_HEARTBEAT(T), iolist_to_binary([<<"${node_alive}_heartbeat_">>, T])).
-define(REDIS_REF(T),       iolist_to_binary([<<"${node_alive}_ref_">>, T])).

-define(REM_LUA(Table, NodeRef, DeadNode),
        [<<"EVAL">>,
         iolist_to_binary(["if redis.pcall('ZREM', KEYS[1], ARGV[1]) ~= 0 then
                            return redis.pcall('INCR', KEYS[2])
                          else
                            return 'SKIP'
                          end"]),
         2,
         Table, NodeRef, DeadNode]).

-define(CATCH_RUN(X),
        case catch X of
            {'EXIT', Reason} -> {error, Reason};
            Result -> Result
        end).

-record(state, {ref = <<>>, node = {}, heartbeat_time = 0}).

%%------------------------------------------------------------------------------
start() ->
    application:start(?MODULE).

stop() ->
    application:stop(?MODULE).

%%------------------------------------------------------------------------------
start_link() ->
    ?CATCH_RUN(gen_server:start_link({local, ?MODULE}, ?MODULE, [], [])).

-spec get_ref() -> any().
get_ref() ->
    ?CATCH_RUN(gen_server:call(?MODULE, get_ref)).

-spec get_nodes() -> [binary()].
get_nodes() ->
    ?CATCH_RUN(gen_server:call(?MODULE, get_nodes)).

node_type() ->
    {ok, NodeType} = application:get_env(?MODULE, node_type), to_binary(NodeType).

node_id() ->
    {ok, HostName} = inet:gethostname(),
    to_binary(application:get_env(?MODULE, node_id, HostName)).

%%------------------------------------------------------------------------------
%%------------------------------------------------------------------------------
init([]) ->
    State = #state{node = {node_type(), node_id()},
                   heartbeat_time = application:get_env(?MODULE, heartbeat_time, ?HEARTBEAT_TIMEOUT)},
    do_init(State),
    {ok, State, 0}.

handle_call(get_ref, _From, State) ->
    {reply, {ok, State#state.ref}, State};
handle_call(get_nodes, _From, State) ->
    {reply, catch do_get_nodes(State), State};
handle_call(_Call, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

handle_info(timeout, State) ->
    State1 = do_timeout(State),
    erlang:send_after(?TIMEOUT, self(), timeout),
    {noreply, State1};

handle_info(_Info, State) ->
    {noreply, State}.

%%------------------------------------------------------------------------------
to_binary(X) when is_list(X)    -> list_to_binary(X);
to_binary(X) when is_atom(X)    -> list_to_binary(atom_to_list(X));
to_binary(X) when is_integer(X) -> integer_to_binary(X);
to_binary(X) when is_binary(X)  -> X.

%%------------------------------------------------------------------------------
do_init(#state{node = {NodeType, NodeID}} = State) ->
    Now = erlang:system_time(seconds),
    Table = ?REDIS_HEARTBEAT(NodeType),
    {ok, [_, Ref]} = eredis_cluster:transaction([[<<"ZADD">>, Table, to_binary(Now), NodeID],
                                                 [<<"INCR">>, ?REDIS_REF(NodeType)]]),
    State#state{ref = Ref}.

%%------------------------------------------------------------------------------
do_timeout(State) ->
    try
        Now = erlang:system_time(seconds),
        State1 = do_heartbeat(Now, State),
        do_check_dead(Now, State1), State1
    catch
        _:R -> error_logger:error_msg("node_alive error ~p~n", [{R, erlang:get_stacktrace()}]), State
    end.

do_heartbeat(Now, #state{node = {NodeType, NodeID}} = State) ->
    Table = ?REDIS_HEARTBEAT(NodeType),
    {ok, _} = eredis_cluster:q([<<"ZADD">>, Table, to_binary(Now), NodeID]),
    case eredis_cluster:q([<<"GET">>, ?REDIS_REF(NodeType)]) of
        {ok, Ref} when is_binary(Ref) -> State#state{ref = Ref};
        _ -> State
    end.

do_check_dead(Now, #state{node = {NodeType, _NodeID}, heartbeat_time = HTime}) ->
    Table = ?REDIS_HEARTBEAT(NodeType),
    case eredis_cluster:q([<<"ZRANGEBYSCORE">>, Table, <<"0">>, to_binary(Now - HTime)]) of
        {ok, [DeadNode | _]} ->
            eredis_cluster:q(?REM_LUA(Table, ?REDIS_REF(NodeType), DeadNode));
        _ ->
            skip
    end.

%%------------------------------------------------------------------------------
do_get_nodes(#state{node = {NodeType, _NodeID}}) ->
    Table = ?REDIS_HEARTBEAT(NodeType),
    {ok, List} = eredis_cluster:q([<<"ZRANGE">>, Table, <<"0">>, <<"-1">>]), {ok, List}.

