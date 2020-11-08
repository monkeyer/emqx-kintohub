#!/bin/sh
## EMQ docker image start script
# Huang Rui <vowstar@gmail.com>
# EMQ X Team <support@emqx.io>

## Shell setting
if [[ ! -z "$DEBUG" ]]; then
    set -ex
else
    set -e
fi

## Local IP address setting

LOCAL_IP=$(hostname -i |grep -E -oh '((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])'|head -n 1)

## EMQ Base settings and plugins setting
# Base settings in /opt/emqx/etc/emqx.conf
# Plugin settings in /opt/emqx/etc/plugins

_EMQX_HOME="/opt/emqx"

if [[ -z "$PLATFORM_ETC_DIR" ]]; then
    export PLATFORM_ETC_DIR="$_EMQX_HOME/etc"
fi

if [[ -z "$PLATFORM_LOG_DIR" ]]; then
    export PLATFORM_LOG_DIR="$_EMQX_HOME/log"
fi

if [[ -z "$EMQX_NAME" ]]; then
    export EMQX_NAME="$(hostname)"
fi

if [[ -z "$EMQX_HOST" ]]; then
    if [[ "$EMQX_CLUSTER__K8S__ADDRESS_TYPE" == "dns" ]] && [[ ! -z "$EMQX_CLUSTER__K8S__NAMESPACE" ]];then
        EMQX_CLUSTER__K8S__SUFFIX=${EMQX_CLUSTER__K8S__SUFFIX:-"pod.cluster.local"}
        DNSAddress="${LOCAL_IP//./-}.${EMQX_CLUSTER__K8S__NAMESPACE}.${EMQX_CLUSTER__K8S__SUFFIX}"
        export EMQX_HOST="$DNSAddress"
    elif [[ "$EMQX_CLUSTER__K8S__ADDRESS_TYPE" == "hostname" ]] && [[ ! -z "$EMQX_CLUSTER__K8S__NAMESPACE" ]]; then
        EMQX_CLUSTER__K8S__SUFFIX=${EMQX_CLUSTER__K8S__SUFFIX:-"svc.cluster.local"}
        HostAddress=$(sed -n "/^${LOCAL_IP}/"p /etc/hosts | grep -e "$(hostname).*.${EMQX_CLUSTER__K8S__NAMESPACE}.${EMQX_CLUSTER__K8S__SUFFIX}" -o)
        export EMQX_HOST="$HostAddress"
    else
        export EMQX_HOST="$LOCAL_IP"
    fi
fi

if [[ -z "$EMQX_WAIT_TIME" ]]; then
    export EMQX_WAIT_TIME=5
fi

if [[ -z "$EMQX_NODE_NAME" ]]; then
    export EMQX_NODE_NAME="$EMQX_NAME@$EMQX_HOST"
fi

# Set hosts to prevent cluster mode failed

# unset EMQX_NAME
# unset EMQX_HOST

if [[ -z "$EMQX_NODE__PROCESS_LIMIT" ]]; then
    export EMQX_NODE__PROCESS_LIMIT=2097152
fi

if [[ -z "$EMQX_NODE__MAX_PORTS" ]]; then
    export EMQX_NODE__MAX_PORTS=1048576
fi

if [[ -z "$EMQX_NODE__MAX_ETS_TABLES" ]]; then
    export EMQX_NODE__MAX_ETS_TABLES=2097152
fi

if [[ -z "$EMQX__LOG_CONSOLE" ]]; then
    export EMQX__LOG_CONSOLE="console"
fi

if [[ -z "$EMQX_LISTENER__TCP__EXTERNAL__ACCEPTORS" ]]; then
    export EMQX_LISTENER__TCP__EXTERNAL__ACCEPTORS=64
fi

if [[ -z "$EMQX_LISTENER__TCP__EXTERNAL__MAX_CLIENTS" ]]; then
    export EMQX_LISTENER__TCP__EXTERNAL__MAX_CLIENTS=1000000
fi

if [[ -z "$EMQX_LISTENER__SSL__EXTERNAL__ACCEPTORS" ]]; then
    export EMQX_LISTENER__SSL__EXTERNAL__ACCEPTORS=32
fi

if [[ -z "$EMQX_LISTENER__SSL__EXTERNAL__MAX_CLIENTS" ]]; then
    export EMQX_LISTENER__SSL__EXTERNAL__MAX_CLIENTS=500000
fi

if [[ -z "$EMQX_LISTENER__WS__EXTERNAL__ACCEPTORS" ]]; then
    export EMQX_LISTENER__WS__EXTERNAL__ACCEPTORS=16
fi

if [[ -z "$EMQX_LISTENER__WS__EXTERNAL__MAX_CLIENTS" ]]; then
    export EMQX_LISTENER__WS__EXTERNAL__MAX_CLIENTS=250000
fi

# Fix issue #42 - export env EMQX_DASHBOARD__DEFAULT_USER__PASSWORD to configure
# 'dashboard.default_user.password' in etc/plugins/emqx_dashboard.conf
if [[ ! -z "$EMQX_ADMIN_PASSWORD" ]]; then
    export EMQX_DASHBOARD__DEFAULT_USER__PASSWORD=$EMQX_ADMIN_PASSWORD
fi

# echo value of $VAR_FULL_NAME hiding secrets if any
echo_value () {
    # get MASK_CONFIG
    MASK_CONFIG_FILTER="$MASK_CONFIG_FILTER|password|passwd|key|token|secret"
    FORMAT_MASK_CONFIG_FILTER=$(echo $MASK_CONFIG_FILTER |sed -e "s/^[^A-Za-z0-9_]\{1,\}//g"|sed -e "s/[^A-Za-z0-9_]\{1,\}/\|/g")

    # check if contains sensitive value
    if [ ! -z $(echo $(echo $VAR_NAME | tr '.' ' ') |grep -w -o -E "$FORMAT_MASK_CONFIG_FILTER") ]; then
        echo "$VAR_NAME=***secret***"
    else
        echo "$VAR_NAME=$(eval echo \$$VAR_FULL_NAME)"
    fi
}

# Catch all EMQX_ prefix environment variable and match it in configure file
CONFIG="${_EMQX_HOME}/etc/emqx.conf"
CONFIG_PLUGINS="${_EMQX_HOME}/etc/plugins"
for VAR in $(env)
do
    # Config normal keys such like node.name = emqx@127.0.0.1
    if [[ ! -z "$(echo $VAR | grep -E '^EMQX_')" ]]; then
        VAR_NAME=$(echo "$VAR" | sed -r "s/EMQX_([^=]*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | sed -r "s/__/\./g")
        VAR_FULL_NAME=$(echo "$VAR" | sed -r "s/([^=]*)=.*/\1/g")
        # Config in emq.conf
        if [[ ! -z "$(cat $CONFIG |grep -E "^(^|^#*|^#*\s*)$VAR_NAME")" ]]; then
            echo_value
            if [[ -z "$(eval echo \$$VAR_FULL_NAME)" ]]; then
                echo "$(sed -r "s/(^\s*)($VAR_NAME\s*=\s*.*)/#\2/g" $CONFIG)" > $CONFIG
            else
                echo "$(sed -r "s/(^#*\s*)($VAR_NAME)\s*=\s*(.*)/\2 = $(eval echo \$$VAR_FULL_NAME|sed -e 's/\//\\\//g')/g" $CONFIG)" > $CONFIG
            fi
        fi
        # Config in plugins/*
        for CONFIG_PLUGINS_FILE in $(ls $CONFIG_PLUGINS); do
            if [[ ! -z "$(cat $CONFIG_PLUGINS/$CONFIG_PLUGINS_FILE |grep -E "^(^|^#*|^#*\s*)$VAR_NAME")" ]]; then
                echo_value
                if [[ -z "$(eval echo \$$VAR_FULL_NAME)" ]]; then
                    echo "$(sed -r "s/(^\s*)($VAR_NAME\s*=\s*.*)/#\2/g" $CONFIG_PLUGINS/$CONFIG_PLUGINS_FILE)" > $CONFIG_PLUGINS/$CONFIG_PLUGINS_FILE
                else
                    echo "$(sed -r "s/(^#*\s*)($VAR_NAME)\s*=\s*(.*)/\2 = $(eval echo \$$VAR_FULL_NAME|sed -e 's/\//\\\//g')/g" $CONFIG_PLUGINS/$CONFIG_PLUGINS_FILE)" > $CONFIG_PLUGINS/$CONFIG_PLUGINS_FILE
                fi
            fi 
        done
    fi
    # Config template such like {{ platform_etc_dir }}
    if [[ ! -z "$(echo $VAR | grep -E '^PLATFORM_')" ]]; then
        VAR_NAME=$(echo "$VAR" | sed -r "s/([^=]*)=.*/\1/g"| tr '[:upper:]' '[:lower:]')
        VAR_FULL_NAME=$(echo "$VAR" | sed -r "s/([^=]*)=.*/\1/g")
        echo "$(sed -r "s@\{\{\s*$VAR_NAME\s*\}\}@$(eval echo \$$VAR_FULL_NAME|sed -e 's/\//\\\//g')@g" $CONFIG)" > $CONFIG
    fi
done

## EMQX Plugin load settings
# Plugins loaded by default

if [[ ! -z "$EMQX_LOADED_PLUGINS" ]]; then
    echo "EMQX_LOADED_PLUGINS=$EMQX_LOADED_PLUGINS"
    # Parse plugin names and place `{plugin_name, true}.` tuples in `loaded_plugins`.
    for var in $(echo "$EMQX_LOADED_PLUGINS"|sed -e "s/^[^A-Za-z0-9_]\{1,\}//g"|sed -e "s/[^A-Za-z0-9_]\{1,\}/\ /g"); do
        if [ ! -z "$(grep -oE "\{($var),[ ]*(true|false)\}" ${_EMQX_HOME}/data/loaded_plugins)" ]; then
            echo "$(sed -r "s/\{($var),[ ]*(true|false)\}./\{\1, true\}./1" ${_EMQX_HOME}/data/loaded_plugins)" > ${_EMQX_HOME}/data/loaded_plugins
        elif [ ! -z $(grep -o "$var\." ${_EMQX_HOME}/data/loaded_plugins) ]; then
            # backward compatible.
            echo "$(sed -r "s/($var)./\{\1, true\}./1" ${_EMQX_HOME}/data/loaded_plugins)" > ${_EMQX_HOME}/data/loaded_plugins
        else
            echo "{$var, true}." >> ${_EMQX_HOME}/data/loaded_plugins
        fi
    done
fi

## EMQX Modules load settings
# Modules loaded by default

if [[ ! -z "$EMQX_LOADED_MODULES" ]]; then
    echo "EMQX_LOADED_MODULES=$EMQX_LOADED_MODULES"
    # Parse module names and place `{module_name, true}.` tuples in `loaded_modules`.
    for var in $(echo "$EMQX_LOADED_MODULES"|sed -e "s/^[^A-Za-z0-9_]\{1,\}//g"|sed -e "s/[^A-Za-z0-9_]\{1,\}/\ /g"); do
        if [ ! -z "$(grep -oE "\{($var),[ ]*(true|false)\}" ${_EMQX_HOME}/data/loaded_modules)" ]; then
            echo "$(sed -r "s/\{($var),[ ]*(true|false)\}./\{\1, true\}./1" ${_EMQX_HOME}/data/loaded_modules)" > ${_EMQX_HOME}/data/loaded_modules
        elif [ ! -z $(grep -o "$var\." ${_EMQX_HOME}/data/loaded_modules) ]; then
            # backward compatible.
            echo "$(sed -r "s/($var)./\{\1, true\}./1" ${_EMQX_HOME}/data/loaded_modules)" > ${_EMQX_HOME}/data/loaded_modules
        else
            echo "{$var, true}." >> ${_EMQX_HOME}/data/loaded_modules
        fi
    done
fi

exec "$@"