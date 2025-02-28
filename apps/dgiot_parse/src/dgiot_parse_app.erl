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

-module(dgiot_parse_app).
-behaviour(application).

-emqx_plugin(?MODULE).

-include("dgiot_parse.hrl").
-include_lib("dgiot/include/logger.hrl").
%% Application callbacks
-export([start/2, stop/1]).


start(_StartType, _StartArgs) ->
    dgiot_metrics:start(dgiot_parse),
    {ok, Sup} = dgiot_parse_sup:start_link(),
    dgiot_parse_channel:start(),
    dgiot_hook:add(one_for_one, {'dgiot','load_cache_classes'}, fun dgiot_parse_cache:start_cache/1),
    {ok, Sup}.

stop(_State) ->
    dgiot_hook:remove({'dgiot','load_cache_classes'}),
    ok.