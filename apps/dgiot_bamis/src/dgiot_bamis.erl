%%--------------------------------------------------------------------
%% Copyright (c) 2020 DGIOT Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% @doc dgiot_bamis Protocol
-module(dgiot_bamis).
-include("dgiot_bamis.hrl").
-include_lib("dgiot/include/logger.hrl").
-dgiot_swagger(<<"amis">>).

-export([
    get/1,
    post/1,
    put/1,
    delete/1,
    format/1,
    start_http/0
]).

-define(APP, ?MODULE).
%% amis api 接口适配
%% https://aisuda.bce.baidu.com/amis/zh-CN/docs/types/api#%E6%8E%A5%E5%8F%A3%E8%BF%94%E5%9B%9E%E6%A0%BC%E5%BC%8F-%E9%87%8D%E8%A6%81-

%% @description 接口说明
%% before 请求前的接口适配器拦截
%% after 请求返回的数据适配器，目前已适配amis返回格式参数，参数如下

%% @description 参数说明
%% status: 返回 0，表示当前接口正确返回，否则按错误请求处理；
%% msg: 返回接口处理信息，主要用于表单提交或请求失败时的 toast 显示；
%% data: 必须返回一个具有 key-value 结构的对象。

%% @description 备注
%% 已实现 get post 的适配工作
get({'before', '*', Args}) ->
%%    io:format("~s ~p Data: ~p ~n", [?FILE, ?LINE, Data]),
    NewData = maps:fold(fun(K, V, Acc) ->
        case V of
            undefined -> Acc;
            _ -> Acc#{K => V}
        end
                        end, #{}, Args),
    Basic = format(NewData),
%%    io:format("~s ~p Basic: ~p ~n", [?FILE, ?LINE, Basic]),
    Basic;

get({'after', #{<<"results">> := Response} = _Data}) ->
%%    io:format("~s ~p ~p~n", [?FILE, ?LINE, _Data]),
    #{
        <<"status">> => 0,
        <<"msg">> => <<"数据请求成功"/utf8>>,
        <<"data">> => #{<<"items">> => Response}
    };

get({'after', #{<<"results">> := Response, <<"count">> := Count} = _Data}) ->
    #{
        <<"status">> => 0,
        <<"msg">> => <<"数据请求成功"/utf8>>,
        <<"data">> => #{
            <<"items">> => Response,
            <<"total">> => Count
        }
    };

get({'before', _Id, Args}) ->
    erlang:put(self(), Args),
%%    io:format("~s ~p ~p ~p ~n", [?FILE, ?LINE, Args, _Id]),
    maps:with([<<"id">>], Args);

%% 查询单个
get({'after', Data}) ->
    Args = erlang:get(self()),
%%    io:format("~s ~p Data ~p ~n", [?FILE, ?LINE, Data]),
    NewData =
        case Args of
            #{<<"keys">> := undefined} ->
%%                io:format("~s ~p Field ~p ~n", [?FILE, ?LINE, maps:get(Field, Data,#{})]),
                Data;
            #{<<"keys">> := Keys} ->
                NewKeys = re:split(Keys, <<",">>, [{return, binary}, trim]),
%%                io:format("~s ~p Field ~p ~n", [?FILE, ?LINE, maps:get(Field, Data,#{})]),
                dgiot_map:with(NewKeys, Data);
            _ ->
                Data
        end,
%%    io:format("~s ~p NewData ~p ~n", [?FILE, ?LINE, NewData]),
    #{
        <<"status">> => 0,
        <<"msg">> => <<"数据请求成功"/utf8>>,
        <<"data">> => NewData
    }.

post({'before', _Id, Args}) ->
%%    io:format("~s ~p ~p ~p~n", [?FILE, ?LINE, Args, Id]),
    Args;
post({'after', Data}) ->
%%    io:format("~s ~p ~p~n", [?FILE, ?LINE, Data]),
    #{
        <<"status">> => 0,
        <<"msg">> => <<"数据提交成功"/utf8>>,
        <<"data">> => Data
    }.
put({'before', _Id, Args}) ->
    erlang:put(self(), Args),
%%    io:format("~s ~p ~p ~p~n", [?FILE, ?LINE, Args, Id]),
    Args;
put({'after', Data}) ->
    Request = erlang:get(self()),
%%    io:format("~s ~p ~p~n", [?FILE, ?LINE, Data]),
    #{
        <<"status">> => 0,
        <<"msg">> => <<"修改成功"/utf8>>,
        <<"data">> => #{<<"Data">> => Data, <<"Request">> => Request}
    }.
delete({'before', _Id, Args}) ->
    erlang:put(self(), Args),
%%    io:format("~s ~p ~p ~p ~n", [?FILE, ?LINE, Args, Id]),
    Args;
delete({'after', Data}) ->
    Request = erlang:get(self()),
%%    io:format("~s ~p ~p~n", [?FILE, ?LINE, Data]),
    #{
        <<"status">> => 0,
        <<"msg">> => <<"删除成功"/utf8>>,
        <<"data">> => #{<<"Data">> => Data, <<"Request">> => Request}
    }.



%% 查询多个
%%/**
%%* https://docs.parseplatform.org/rest/guide/#query-constraints
%%* 查询条件
%%Parameter	Use
%%order	Specify a field to sort by
%%limit	Limit the number of objects returned by the query
%%skip	Use with limit to paginate through results
%%keys	Restrict the fields returned by the query
%%excludeKeys	Exclude specific fields from the returned query
%%include	Use on Pointer columns to return the full object
%%*/
format(#{<<"orderBy">> := OrderBy} = Data) ->
    NewData = maps:without([<<"orderBy">>], Data),
    format(NewData#{<<"order">> => [OrderBy]});

format(#{<<"order">> := [Order | _], <<"orderDir">> := OrderDir} = Data) ->
    NewData = maps:without([<<"orderDir">>], Data),
    NewOrder =
        case OrderDir of
            <<"desc">> ->
                <<"-", Order/binary>>;
            _ ->
                Order
        end,
    format(NewData#{<<"order">> => [NewOrder]});

format(#{<<"perPage">> := PerPage, <<"page">> := Page} = Data) ->
    NewData = maps:without([<<"perPage">>, <<"page">>], Data),
    Skip = (Page - 1) * PerPage,
    format(NewData#{<<"limit">> => PerPage, <<"skip">> => Skip});

format(#{<<"perPage">> := PerPage} = Data) ->
    NewData = maps:without([<<"perPage">>, <<"page">>], Data),
    Skip = 0,
    format(NewData#{<<"limit">> => PerPage, <<"skip">> => Skip});

format(#{<<"page">> := Page} = Data) ->
    NewData = maps:without([<<"perPage">>, <<"page">>], Data),
    Skip = (Page - 1) * 10,
    format(NewData#{<<"limit">> => 10, <<"skip">> => Skip});

format(Data) ->
    Where = maps:without([<<"limit">>, <<"skip">>, <<"order">>, <<"count">>, <<"limit">>, <<"keys">>, <<"excludeKeys">>, <<"include">>, <<"where">>, <<"perPage">>, <<"page">>, <<"orderBy">>, <<"orderDir">>], Data),
    NewData = maps:without(maps:keys(Where) ++ [<<"perPage">>, <<"page">>, <<"orderBy">>, <<"orderDir">>], Data),
    case Data of
        #{<<"where">> := ParesWhere} when is_map(ParesWhere) ->
            NewData#{<<"where">> => maps:merge(ParesWhere, Where)};
        _ ->
            case length(maps:to_list(Where)) of
                0 ->
                    NewData;
                _ ->
                    NewData#{<<"where">> => Where}
            end
    end.

start_http() ->
    Port = 9089,
    {file, Here} = code:is_loaded(?MODULE),
    Dir = filename:dirname(filename:dirname(Here)),
    Root = dgiot_httpc:url_join([Dir, "/priv/"]),
    DocRoot = Root ++ "www",
    dgiot_http_server:start_http(?MODULE, Port, DocRoot).
