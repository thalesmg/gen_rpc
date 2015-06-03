%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_server_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%%% Supervisor functions
-export([start_link/0, start_child/1, stop_child/1]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% Launch a local receiver and return the port
start_child(Node) ->
    ?debug("Starting new listener for remote node [~s]", [Node]),
    {ok, Pid} = supervisor:start_child(?MODULE, [Node]),
    {ok, Port} = gen_rpc_server:get_port(Pid),
    {ok, Port}.

%% Terminate and unregister a child server
stop_child(Pid) ->
    ?debug("Terminating and unregistering server with PID [~p]", [Pid]),
    supervisor:terminate_child(?MODULE, Pid).

%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_server, {gen_rpc_server,start_link,[]}, transient, 5000, worker, [gen_rpc_server]}
    ]}}.