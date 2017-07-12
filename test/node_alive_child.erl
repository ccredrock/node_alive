%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright (C) 2017, <meituan>
%%% @doc
%%%
%%% @end
%%% Created : 2017年07月05日19:11:34
%%%-------------------------------------------------------------------
-module(node_alive_child).

%% callbacks
-export([handle_dead/1,
         handle_over/1]).

%%------------------------------------------------------------------------------
-behaviour(node_alive).

handle_dead(_Node) -> timer:sleep(1000).
handle_over(_Node) -> timer:sleep(1000).
