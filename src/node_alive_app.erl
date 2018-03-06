%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright 2018 redrock
%%% @doc redis node alive
%%% @end
%%%-------------------------------------------------------------------
-module(node_alive_app).

-export([start/2, stop/1]).

%%------------------------------------------------------------------------------
-behaviour(application).

%%------------------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    node_alive_sup:start_link().

stop(_State) ->
    ok.
