%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright (C) 2017, <meituan>
%%% @doc
%%%
%%% @end
%%% Created : 2017年07月05日19:11:34
%%%-------------------------------------------------------------------
-module(node_alive).

-export([start/0, stop/0]).

-export([start_link/1]).

%% callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%%------------------------------------------------------------------------------
-callback handle_dead(DeadNode::binary()) -> ok | {error, Reason::term()}.
-callback handle_over(DeadNode::binary()) -> ok | {error, Reason::term()}.

%%------------------------------------------------------------------------------
-behaviour(gen_server).

-define(TIMEOUT, 1000).

-define(HEARTBEAT_TIMEOUT, 20). %% 15秒
-define(MASTER_TIMEOUT,    10). %% 10秒

-define(REDIS_HEARTBEAT(T), iolist_to_binary([<<"$node_alive_heartbeat_">>, T])).
-define(REDIS_MASTER(T),    iolist_to_binary([<<"$node_alive_master_">>, T])).
-define(REDIS_OVER(T),      iolist_to_binary([<<"$node_alive_over_">>, T])).

-record(state, {node_type = null, node_id = 0,
                heartbeat_time = 0, master_time = 0,
                callback_mod = null}).

%%------------------------------------------------------------------------------
start() ->
    application:start(?MODULE).

stop() ->
    application:stop(?MODULE).

%%------------------------------------------------------------------------------
start_link(Props) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Props], []).

%%------------------------------------------------------------------------------
init([Props]) ->
    {ok, #state{node_type      = to_binary(proplists:get_value(node_type, Props)),
                node_id        = to_binary(proplists:get_value(node_id, Props)),
                heartbeat_time = proplists:get_value(heartbeat_time, Props, ?HEARTBEAT_TIMEOUT),
                master_time    = proplists:get_value(master_time, Props, ?MASTER_TIMEOUT),
                callback_mod   = proplists:get_value(callback_mod, Props)}, 0}.

handle_call(_Call, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

handle_info(timeout, State) ->
    do_timeout(State),
    erlang:send_after(?TIMEOUT, self(), timeout),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%%------------------------------------------------------------------------------
to_binary(X) when is_list(X)    -> list_to_binary(X);
to_binary(X) when is_atom(X)    -> list_to_binary(atom_to_list(X));
to_binary(X) when is_integer(X) -> integer_to_binary(X);
to_binary(X) when is_binary(X)  -> X.

timepiece(T) ->
    Now = erlang:system_time(seconds),
    Now - (Now rem T).

%%------------------------------------------------------------------------------
do_timeout(State) ->
    try
        Now = erlang:system_time(seconds),
        do_heartbeat(Now, State),
        do_check_dead(Now, State),
        do_check_over(State)
    catch
        E:R -> error_logger:error_msg("node_alive error ~p~n", [{E, R, erlang:get_stacktrace()}])
    end.

do_heartbeat(Now, #state{node_type = NodeType, node_id = NodeID}) ->
    HeartbeatTable = ?REDIS_HEARTBEAT(NodeType),
    {ok, _} = eredis_pool:q([<<"ZADD">>, HeartbeatTable, to_binary(Now), NodeID]).

do_check_dead(Now, #state{node_type = NodeType,
                          heartbeat_time = HTime, master_time = MTime,
                          callback_mod = Mod}) ->
    HeartbeatTable = ?REDIS_HEARTBEAT(NodeType),
    {ok, List} = eredis_pool:q([<<"ZRANGE">>, HeartbeatTable, <<"0">>, <<"-1">>, <<"WITHSCORES">>]),
    case do_split_nodes(integer_to_binary(Now - HTime), List, {[], []}) of
        {[], _} -> skip;
        {[DeadNode | _], Lives} ->
            MasterTable = ?REDIS_MASTER(NodeType),
            TimePiece = integer_to_binary(timepiece(MTime)),
            case eredis_pool:transaction([[<<"ZREMRANGEBYSCORE">>, MasterTable, <<"0">>, <<"0">>],
                                          [<<"ZADD">>, MasterTable, TimePiece, TimePiece]]) of
                {ok, [_, <<"1">>]} ->
                    ok = Mod:handle_dead(DeadNode),
                    LList = [[<<"LPUSH">>, ?REDIS_OVER([NodeType, "_", X]), DeadNode] || X <- Lives],
                    {ok, _} = eredis_pool:transaction([[<<"ZREM">>, HeartbeatTable, DeadNode] | LList]);
                {ok, [_, <<"0">>]} ->
                    skip
            end
    end.

do_split_nodes(DeadTime, [Node, Time | T], {Deads, Lives}) ->
    case Time =< DeadTime of
        true -> do_split_nodes(DeadTime, T, {[Node | Deads], Lives});
        false -> do_split_nodes(DeadTime, T, {Deads, [Node | Lives]})
    end;
do_split_nodes(_DeadTime, [], Acc) -> Acc.

do_check_over(#state{node_type = NodeType, node_id = NodeID, callback_mod = Mod}) ->
    OverTable = ?REDIS_OVER([NodeType, "_", NodeID]),
    case eredis_pool:q([<<"LRANGE">>, OverTable, <<"-1">>, <<"-1">>]) of
        {ok, []} -> skip;
        {ok, [DeadNode]} ->
            ok = Mod:handle_dead(DeadNode),
            {ok, _} = eredis_pool:q([<<"LPOP">>, OverTable])
    end.

