%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 DGIOT Technologies Co., Ltd. All Rights Reserved.
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

-module(dgiot_tdengine).
-author("kenneth").
-include("dgiot_tdengine.hrl").
-include_lib("dgiot/include/logger.hrl").

%% API
-export([create_database/3, create_schemas/2, create_object/3, create_user/3, alter_user/3, delete_user/2, query_object/3, batch/2]).
-export([create_database/2, create_schemas/1, create_object/2, create_user/2, alter_user/2, delete_user/1, query_object/2, batch/1, parse_batch/1]).
-export([transaction/2, format_data/4]).
-export([get_reportdata/3]).

transaction(Channel, Fun) ->
    case dgiot_channelx:call(?TYPE, Channel, config) of
        {ok, Context} ->
            Fun(Context);
        {error, Reason} ->
            {error, Reason}
    end.

create_database(DataBase, Keep) ->
    create_database(?DEFAULT, DataBase, Keep).

create_database(Channel, DataBase, Keep) ->
    transaction(Channel,
        fun(Context) ->
            Sql = dgiot_tdengine_schema:create_database(#{<<"db">> => DataBase, <<"keep">> => Keep}),
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, Sql)
        end).


create_schemas(Schema) ->
    create_schemas(?DEFAULT, Schema).

%% 如果里面有using，则为使用了超级表创建子表
create_schemas(Channel, #{<<"using">> := _STbName} = Query) ->
    transaction(Channel,
        fun(Context) ->
            Sql = dgiot_tdengine_schema:create_table(Query, Context#{<<"channel">> => Channel}),
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, Sql)
        end);

%% 如果schema里面带有tags则为超级表，没有则为普通表
create_schemas(Channel, Query) ->
    transaction(Channel,
        fun(Context) ->
            Sql = dgiot_tdengine_schema:create_table(Query, Context#{<<"channel">> => Channel}),
            R = dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, Sql),
            dgiot_tdengine_schema:alter_table(Query, Context#{<<"channel">> => Channel}),
            R
        end).

%% 插入
create_object(TableName, Object) ->
    create_object(?DEFAULT, TableName, Object).
create_object(Channel, TableName, #{<<"values">> := Values0} = Object) ->
    transaction(Channel,
        fun(Context) ->
            Values = dgiot_tdengine_select:format_batch(Object#{<<"tableName">> => TableName, <<"values">> => [Values0]}),
            Sql = <<"INSERT INTO ", Values/binary, ";">>,
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, Sql)
        end).

%% 查询
query_object(TableName, Query) ->
    query_object(?DEFAULT, TableName, Query).
query_object(Channel, TableName, Query) ->
    transaction(Channel,
        fun(Context) ->
            Sql = dgiot_tdengine_select:select(TableName, Query),
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_query, Sql)
        end).

%% 批处理
batch(Batch) ->
    batch(?DEFAULT, Batch).
batch(Channel, Requests) when is_list(Requests) ->
    case dgiot_data:get({tdengine_os, Channel}) of
        <<"windows">> ->
            parse_batch(Requests);
        _ ->
            transaction(Channel,
                fun(Context) ->
                    Request1 = list_to_binary(dgiot_utils:join(" ", [dgiot_tdengine_select:format_batch(Request) || Request <- Requests])),
                    Sql = <<"INSERT INTO ", Request1/binary, ";">>,
                    dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, Sql)
                end)
    end;
batch(Channel, Batch) ->
    case dgiot_data:get({tdengine_os, Channel}) of
        <<"windows">> ->
            parse_batch(Batch);
        _ ->
            transaction(Channel,
                fun(Context) ->
                    Values = dgiot_tdengine_select:format_batch(Batch),
                    Sql = <<"INSERT INTO ", Values/binary, ";">>,
                    dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, Sql)
                end)
    end.

parse_batch(Requests) when is_list(Requests), length(Requests) < 5 ->
    NewRequests =
        lists:foldl(fun(X, Acc) ->
            Acc ++ lists:foldl(fun(Y, Acc1) ->
                Values = maps:from_list(lists:zip(maps:get(<<"fields">>, X), Y)),
                Tags = maps:from_list(lists:zip([<<"devaddr">>], maps:get(<<"tags">>, X))),
                <<"_", ProductId/binary>> = maps:get(<<"db">>, X),
                <<"_", DeviceId/binary>> = maps:get(<<"tableName">>, X),
                Acc1 ++ [#{
                    <<"method">> => <<"POST">>,
                    <<"path">> => <<"/classes/Timescale">>,
                    <<"body">> => #{
                        <<"product">> => #{
                            <<"className">> => <<"Product">>,
                            <<"objectId">> => ProductId,
                            <<"__type">> => <<"Pointer">>
                        },
                        <<"device">> => #{
                            <<"className">> => <<"Device">>,
                            <<"objectId">> => DeviceId,
                            <<"__type">> => <<"Pointer">>
                        },
                        <<"values">> => Values#{<<"createdat">> => dgiot_datetime:nowstamp()},
                        <<"tags">> => Tags
                    }
                }]
                               end, Acc, maps:get(<<"values">>, X))
                    end, [], Requests),
    dgiot_parse:batch(NewRequests);

parse_batch(_Requests) ->
    {ok, _Requests}.

create_user(UserName, Password) ->
    create_user(?DEFAULT, UserName, Password).
create_user(Channel, UserName, Password) ->
    transaction(Channel,
        fun(Context) ->
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, <<"CREATE USER ", UserName/binary, " PASS ‘", Password/binary, "’">>)
        end).


delete_user(UserName) ->
    delete_user(?DEFAULT, UserName).
delete_user(Channel, UserName) ->
    transaction(Channel,
        fun(Context) ->
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, <<"DROP USER ", UserName/binary>>)
        end).

alter_user(UserName, NewPassword) ->
    alter_user(?DEFAULT, UserName, NewPassword).
alter_user(Channel, UserName, NewPassword) ->
    transaction(Channel,
        fun(Context) ->
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_update, <<"ALTER USER ", UserName/binary, " PASS ‘", NewPassword/binary, "’">>)
        end).

%% select flow, head, effect, power from _09d0bbcf44._47d9172bf1 where createdat >= 1635581932000 AND createdat <= 1638260333000 order by createdat asc;
get_reportdata(Channel, TableName, Query) ->
    dgiot_tdengine:transaction(Channel,
        fun(Context) ->
            Database = maps:get(<<"db">>, Query),
            Keys = maps:get(<<"keys">>, Query),
            Starttime = maps:get(<<"starttime">>, Query),
            Endtime = maps:get(<<"endtime">>, Query),
            DB = dgiot_tdengine_select:format_db(?Database(Database)),
            Tail = <<" where createdat >= ", Starttime/binary, " AND createdat <= ", Endtime/binary, " order by createdat asc;">>,
            Sql = <<"SELECT ", Keys/binary, " FROM ", DB/binary, TableName/binary, Tail/binary>>,
            ?LOG(error, "Sql ~s", [Sql]),
            dgiot_tdengine_pool:run_sql(Context#{<<"channel">> => Channel}, execute_query, Sql)
        end).

%% 产品，设备地址与数据分离，推荐
format_data(ProductId, DevAddr, Properties, Data) ->
    DeviceId = dgiot_parse_id:get_deviceid(ProductId, DevAddr),
    Values = dgiot_tdengine_field:check_fields(Data, Properties),
    Fields = get_fields(ProductId),

    dgiot_data:insert({td, ProductId, DeviceId}, Values#{<<"createdat">> => dgiot_datetime:nowstamp()}),
    Now = maps:get(<<"createdat">>, Data, now),
    NewValues = get_values(ProductId, Values, Now),
    dgiot_data:insert(?DGIOT_TD_THING_ETS, DeviceId, Values),
    #{
        <<"db">> => ?Database(ProductId),
        <<"tableName">> => ?Table(DeviceId),
        <<"using">> => ?Table(ProductId),
        <<"tags">> => [?Table(DevAddr)],
        <<"fields">> => Fields,
        <<"values">> => NewValues
    }.


%% INSERT INTO _173acf2f85._af6d16f9ba using _173acf2f85._173acf2f85 TAGS ('_KOHbyuiJilnsdD') VALUES (now,null,null,null,null);
get_values(Table, Values, Now) ->
    Values0 =
        case dgiot_data:get({Table, ?TABLEDESCRIBE}) of
            Results when length(Results) > 0 ->
                lists:foldl(fun(Column, Acc) ->
                    case Column of
                        #{<<"Note">> := <<"TAG">>} ->
                            Acc;
                        #{<<"Field">> := <<"createdat">>} ->
                            Acc ++ dgiot_utils:to_list(Now);
                        #{<<"Field">> := Field} ->
                            Value = maps:get(Field, Values, null),
                            case Value of
                                {NewValue, text} ->
                                    Acc ++ ",\'" ++ dgiot_utils:to_list(NewValue) ++ "\'";
                                _ ->
                                    Acc ++ "," ++ dgiot_utils:to_list(Value)
                            end;
                        _ ->
                            Acc
                    end
                            end, " (", Results);
            _ ->
                " "
        end,
    list_to_binary(Values0 ++ ")").

get_fields(Table) ->
    case dgiot_data:get({Table, ?TABLEDESCRIBE}) of
        Results when length(Results) > 0 ->
            lists:foldl(fun(Column, Acc) ->
                case Column of
                    #{<<"Field">> := Field} ->
                        Acc ++ [Field];
                    _ ->
                        Acc
                end
                        end, [], Results);
        _ ->
            []
    end.
