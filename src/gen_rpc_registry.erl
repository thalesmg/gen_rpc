-module(gen_rpc_registry).

-behaviour(gen_server).

%% API
-export([ start_link/0
        , nodes/0
        ]).

%% via callbacks
-export([ register_name/2
        , unregister_name/1
        , whereis_name/1
        , send/2
        ]).

-export_type([ name/0
             ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("stdlib/include/ms_transform.hrl").

-define(SERVER, ?MODULE).

-define(TAB, ?MODULE).

-type name() :: term().

-type state() :: #{ rlookup := ets:tid()
                  }.

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec nodes() -> [node()].
nodes() ->
    ThisNode = node(),
    lists:usort(
      ets:select(?TAB,
                 ets:fun2ms(fun({{client, {Node, _}}, _}) when Node =/= ThisNode -> Node;
                               ({{client, Node}, _})      when Node =/= ThisNode -> Node
                            end))).

-spec register_name(term(), pid()) -> yes | no.
register_name(Name, Pid) ->
    gen_server:call(?SERVER, {register, Name, Pid}, infinity).

-spec unregister_name(term()) -> ok.
unregister_name(Name) ->
    gen_server:call(?SERVER, {unregister, Name}, infinity).

-spec whereis_name(term()) -> pid() | undefined.
whereis_name(Name) ->
    case ets:lookup(?TAB, Name) of
        [{_Name, Pid}] ->
            Pid;
        [] ->
            undefined
    end.

-spec send(name(), term()) -> pid().
send(Name, Msg) ->
    case whereis_name(Name) of
        undefined ->
            exit({badarg, {Name, Msg}});
        Pid ->
            Pid ! Msg
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

-spec init([]) -> {ok, state()}.
init([]) ->
    ets:new(?TAB, [ named_table
                  , protected
                  , set
                  , {read_concurrency, true}
                  , {write_concurrency, false}
                  ]),
    RLookup = ets:new(rlookup, [ set
                               , private
                               , {read_concurrency, false}
                               , {write_concurrency, false}
                               ]),
    {ok, #{rlookup => RLookup}}.

handle_call({register, Name, Pid}, _From, State = #{rlookup := RLookup}) ->
    %% Optimized for the happy case
    Reply =
        case ets:insert_new(?TAB, {Name, Pid}) of
            true ->
                MRef = monitor(process, Pid),
                case ets:insert_new(RLookup, {Pid, MRef, Name}) of
                    true ->
                        yes;
                    false ->
                        %% The pid has been already registered with a
                        %% different name. This is invalid, so
                        %% rollback the changes:
                        ets:delete(?TAB, Name),
                        demonitor(MRef, [flush]),
                        no
                end;
            false ->
                no
        end,
    {reply, Reply, State};
handle_call({unregister, Name}, _From, State = #{rlookup := RLookup}) ->
    case whereis_name(Name) of
        undefined ->
            ok;
        Pid ->
            [{Pid, MRef, Name}] = ets:lookup(RLookup, Pid),
            demonitor(MRef, [flush]),
            ets:delete(?TAB, Name),
            ets:delete(RLookup, Pid)
    end,
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'DOWN', _MonitorRef, _Type, Pid, _Info}, State = #{rlookup := RLookup}) ->
    case ets:lookup(RLookup, Pid) of
        [{Pid, _MRef, Name}] ->
            ets:delete(?TAB, Name),
            ets:delete(RLookup, Pid);
        [] ->
            ok
    end,
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
