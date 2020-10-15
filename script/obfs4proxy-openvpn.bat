@echo off

rem ## We should absolutely not use EnableDelayedExpansion globally as it
rem ## will mess up correctly importing conf file and working with paths with
rem ## weird characters in them. I learned that the hard way.
setlocal

rem # We enable utf-8 mode to ensure proper handling of non-ascii paths.
rem # This, combined with using shortcut approach to change the default font
rem # to Lucida Console which is UTF8-capabale, should be enough to handle
rem # all cases
rem # https://ss64.com/nt/chcp.html
rem # https://docs.microsoft.com/en-gb/windows/win32/intl/code-page-identifiers
chcp 65001 > nul || call :fatalError "Could not enable UTF-8 mode"

rem # Setting SCRIPT_ROOT
set "SCRIPT_ROOT=%CD%"

set "SCRIPT_CONFIG_FILE=%SCRIPT_ROOT%\config\obfs4proxy-openvpn.conf"

rem ###### Defaults ######
set "MODE="
set "TRANSPORT=obfs4"
set "IAT_MODE=0"
set "CLIENT_UPSTREAM_PROXY="
set "CLIENT_REMOTE_CERT="
set "CLIENT_REMOTE_NODE_ID="
set "CLIENT_REMOTE_PUBLIC_KEY="
set "SERVER_OBFS4_BIND_ADDR=0.0.0.0"
set "SERVER_OBFS4_BIND_PORT=1516"
set "SERVER_OPENVPN_BIND_ADDR=127.0.0.1"
set "SERVER_OPENVPN_BIND_PORT=1515"
set "OPENVPN_BINARY=%ProgramFiles%\OpenVPN\bin\openvpn.exe"
set "OPENVPN_RELATIVE_PATH=%SCRIPT_ROOT%"
set "OPENVPN_CONFIG_FILE=config\openvpn-%MODE%.conf"
set "OPENVPN_CONFIG_WARN_INLINE=true"
set "OPENVPN_GUI_HOOK=true"
set "SCRIPT_ID="
set "OPENVPN_GUI_BINARY=%ProgramFiles%\OpenVPN\bin\openvpn-gui.exe"
set "OBFS4PROXY_BINARY=%SCRIPT_ROOT%\bin\obfs4proxy.exe"
set "OBFS4PROXY_WORKING_DIR=%SCRIPT_ROOT%\data"
set "OBFS4PROXY_LOG_LEVEL=error"
set "OBFS4PROXY_LOG_IP=false"

set "SCRIPT_VERSION=0.1.0"
set "_CONF_VALID="
set "_STRING="
set "_STRING_LEN="
set "_OPENVPN_INLINE_WARN_SHOWN=0"
set "CLIENT_REMOTE_CREDENTIALS="
set "CLIENT_OBFS4_SOCKS5_PORT="
set "OPENVPN_CONFIG_FILE_PATH="



call :startup

call :import_conf

call :validate_env

call :initiate_obfs4proxy

call :initiate_openvpn

call :final_message



:startup
title obfs4proxy-openvpn

echo/
echo ###############################################################################
echo #                                                                             #
echo #                             obfs4proxy-openvpn                              #
echo #                                   v%SCRIPT_VERSION%                                    #
echo #                                                                             #
echo #                               https://hamy.io                               #
echo #                                                                             #
echo ###############################################################################
echo/
timeout /t 1 > nul

if not "%_RAN_VIA_LNK%"=="1" (
    call :fatalError "Please run this script through the provided shortcut in the script root"
)

exit /b


rem ## Importing configuration and initial validation
:import_conf
echo * Importing config file...

if not exist "%SCRIPT_CONFIG_FILE%" (
    call :fatalError "Could not find the config file: %SCRIPT_CONFIG_FILE%"
)


rem To make 'echo', correctly output escape characters to be piped to 'findstr',
rem the variable must be quoted. That would however result in ehcoing the quoted
rem string, so we need to match quoted strings in findstr
for /f "usebackq eol=# tokens=1*" %%i in ("%SCRIPT_CONFIG_FILE%") DO (

    set "_CONF_VALID="

    if "%%i"=="MODE" (
        echo "%%~j"| findstr /r "^\""server\""$ ^\""client\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid MODE: %%~j"
        set "_CONF_VALID=1" 
    )

    if "%%i"=="TRANSPORT" (
        echo "%%~j"| findstr /r "^\""obfs[2-4]\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid TRANSPORT: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="IAT_MODE" (
        echo "%%~j"| findstr /r "^\""[0-2]\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid IAT_MODE: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="CLIENT_UPSTREAM_PROXY" (
        echo "%%~j"| findstr /r "^\""http:// ^\""socks4a:// ^\""socks5://" > nul
        call :errorCheck "Parsing config file failed: Invalid CLIENT_UPSTREAM_PROXY: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="CLIENT_REMOTE_CERT" (
        echo "%%~j"| findstr /r "^\""[a-zA-Z0-9/+]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid CLIENT_REMOTE_CERT: %%~j"
        set "_STRING=%%~j"
        call :strlenCheck _STRING 70 70 "Invalid CLIENT_REMOTE_CERT string length (must be exactly 70)"
        set "_CONF_VALID=1"
    )

    if "%%i"=="CLIENT_REMOTE_NODE_ID" (
        echo "%%~j"| findstr /r "^\""[0-9a-f]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid CLIENT_REMOTE_NODE_ID: %%~j"
        set "_STRING=%%~j"
        call :strlenCheck _STRING 40 40 "Invalid CLIENT_REMOTE_NODE_ID string length (must be exactly 40)"
        set "_CONF_VALID=1"
    )

    if "%%i"=="CLIENT_REMOTE_PUBLIC_KEY" (
        echo "%%~j"| findstr /r "^\""[0-9a-f]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid CLIENT_REMOTE_PUBLIC_KEY: %%~j"
        set "_STRING=%%~j"
        call :strlenCheck _STRING 64 64 "Invalid CLIENT_REMOTE_PUBLIC_KEY string length (must be exactly 64)"
        set "_CONF_VALID=1"
    )

    if "%%i"=="SERVER_OBFS4_BIND_ADDR" (
        echo "%%~j"| findstr /r "^\""[a-zA-Z0-9:.]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid SERVER_OBFS4_BIND_ADDR: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="SERVER_OBFS4_BIND_PORT" (
        echo "%%~j"| findstr /r "^\""[0-9]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid SERVER_OBFS4_BIND_PORT: %%~j"
        if %%~j gtr 65535 (
            call :fatalError "Parsing config file failed: Invalid SERVER_OBFS4_BIND_PORT number: %%~j"
        )
        set "_CONF_VALID=1"
    )

    if "%%i"=="SERVER_OPENVPN_BIND_ADDR" (
        echo "%%~j"| findstr /r "^\""[a-zA-Z0-9:.]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid SERVER_OPENVPN_BIND_ADDR: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="SERVER_OPENVPN_BIND_PORT" (
        echo "%%~j"| findstr /r "^\""[0-9]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid SERVER_OPENVPN_BIND_PORT: %%~j"
        if %%~j gtr 65535 (
            call :fatalError "Parsing config file failed: Invalid SERVER_OPENVPN_BIND_PORT number: %%~j"
        )
        set "_CONF_VALID=1"
    )

    rem ## Futher checks will be done later but for now, we check to ensure
    rem ## no illegal chacters are in the path
    if "%%i"=="OPENVPN_BINARY" (
        echo "%%~j"| findstr /r "^\""[^/*\""<>|?]*\.exe\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OPENVPN_BINARY: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="OPENVPN_RELATIVE_PATH" (
        echo "%%~j"| findstr /r "^\""[^/*\""<>|?]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OPENVPN_RELATIVE_PATH: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="OPENVPN_CONFIG_FILE" (
        echo "%%~j"| findstr /r "^\""[^/*\""<>|?]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OPENVPN_CONFIG_FILE: %%~j"
        set "_CONF_VALID=1"
    )
    
    if "%%i"=="OPENVPN_CONFIG_WARN_INLINE" (
        echo "%%~j"| findstr /r "^\""true\""$ ^\""false\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OPENVPN_CONFIG_WARN_INLINE: %%~j"
        set "_CONF_VALID=1"
    )
    
    if "%%i"=="OPENVPN_GUI_HOOK" (
        echo "%%~j"| findstr /r "^\""true\""$ ^\""false\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OPENVPN_GUI_HOOK: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="SCRIPT_ID" (
        echo "%%~j"| findstr /r "^\""[1-9][0-9]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid SCRIPT_ID: %%~j"
        if %%~j gtr 9999 (
            call :fatalError "Maximum value for SCRIPT_ID is 9999: %%~j"
        )
        set "_CONF_VALID=1"
    )

    if "%%i"=="OPENVPN_GUI_BINARY" (
        echo "%%~j"| findstr /r "^\""[^/*\""<>|?]*\.exe\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OPENVPN_GUI_BINARY: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="OBFS4PROXY_BINARY" (
        echo "%%~j"| findstr /r "^\""[^/*\""<>|?]*\.exe\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OBFS4PROXY_BINARY: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="OBFS4PROXY_WORKING_DIR" (
        echo "%%~j"| findstr /r "^\""[^/*\""<>|?]*\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OBFS4PROXY_WORKING_DIR: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="OBFS4PROXY_LOG_LEVEL" (
        echo "%%~j"| findstr /r "^\""none\""$ ^\""error\""$ ^\""warn\""$ ^\""info\""$ ^\""debug\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OBFS4PROXY_LOG_LEVEL: %%~j"
        set "_CONF_VALID=1"
    )

    if "%%i"=="OBFS4PROXY_LOG_IP" (
        echo "%%~j"| findstr /r "^\""true\""$ ^\""false\""$" > nul
        call :errorCheck "Parsing config file failed: Invalid OBFS4PROXY_LOG_IP: %%~j"
        set "_CONF_VALID=1"
    )

    if defined _CONF_VALID (
        rem ## The call method is used, so we could also expand variables
        rem ## inside variables ^(like %ProgramFiles%^)
        call set "%%i=%%~j"
    ) else (
        call :fatalError "Parsing conf file failed: Invalid config: %%i"
    )
)

exit /b



:validate_env
echo * Validating settings...

if "%MODE%"=="" (
    call :fatalError "No known MODE of operation!"
)

rem # Paths tests are being done here ^(after initial variable expansion^)
if "%OPENVPN_GUI_HOOK%"=="true" (
    if not exist "%OPENVPN_GUI_BINARY%" (
        call :fatalError "OPENVPN_GUI_HOOK is set but could not find OpenVPN GUI binary. You either need to disable OPENVPN_GUI_HOOK or install OpenVPN GUI. If you believe OpenVPN GUI is already installed on the system, then adjust its path in obfs4proxy-openvpn.conf."
    )
    if "%SCRIPT_ID%"=="" (
        call :fatalError "OPENVPN_GUI_HOOK is set but SCRIPT_ID is not. SCRIPT_ID must be set and it should be a unique ID accross all obfs4proxy-openvpn instances running on this host."
    )
) else (
    if not exist "%OPENVPN_BINARY%" (
        call :fatalError "Could not find OpenVPN binary. You need to install OpenVPN first. If you believe OpenVPN is already installed on the system, then adjust its path in obfs4proxy-openvpn.conf."
    )
)

rem Check whether OPENVPN_CONFIG_FILE is a relative path or not.
rem A relative path, should not have ":" in it
echo "%OPENVPN_CONFIG_FILE%" | findstr /r "^[^:]*$" > nul
if %ERRORLEVEL% equ 0 (
    rem # A trailing '\' seems to be enough to check for a directory existence
    if not "%OPENVPN_RELATIVE_PATH%"=="" (
        rem # A trailing '\' seems to be enough to check for a directory existence
        if not exist "%OPENVPN_RELATIVE_PATH%\" (
            call :fatalError "Could not find OPENVPN_RELATIVE_PATH: %OPENVPN_RELATIVE_PATH%"
        )
        if not exist "%OPENVPN_RELATIVE_PATH%\%OPENVPN_CONFIG_FILE%" (
            call :fatalError "Could not find OPENVPN_CONFIG_FILE: %OPENVPN_RELATIVE_PATH%\%OPENVPN_CONFIG_FILE%"
        )
        set "OPENVPN_CONFIG_FILE_PATH=%OPENVPN_RELATIVE_PATH%\%OPENVPN_CONFIG_FILE%"
    ) else (
        call :fatalError "%OPENVPN_CONFIG_FILE% is a relative path but OPENVPN_RELATIVE_PATH is not specified."
    )
) else (
    if not exist "%OPENVPN_CONFIG_FILE%" (
        call :fatalError "Could not find OPENVPN_CONFIG_FILE: %OPENVPN_CONFIG_FILE%"
    )
    set "OPENVPN_CONFIG_FILE_PATH=%OPENVPN_CONFIG_FILE%"
)


rem # openvpn conf file comments do not need processing
for /f "usebackq eol=#" %%i in ("%OPENVPN_CONFIG_FILE_PATH%") DO (
    echo "%%i"| findstr /r "^\""config\""$ ^\""--config\""$" > nul && echo * WARNING: Nested openvpn "%%i" detected. Not going to validate those.
    echo "%%i"| findstr /r "^\""cd\""$ ^\""--cd\""$" > nul && call :fatalError "'cd' directive in openvpn conf file detected. Please adjust OPENVPN_RELATIVE_PATH instead."
    echo "%%i"| findstr /r "^\""proto\""$ ^\""--proto\""$" > nul && call :fatalError "Do not specify 'proto' in openvpn conf file. This will be done by the script and its always going to be TCP."
    echo "%%i"| findstr /r "^\""<key>\""$ ^\""<pkcs12>\""$ ^\""<secret>\""$ ^\""<tls-auth>\""$ ^\""<tls-crypt>\""$" > nul && (
        if "%OPENVPN_GUI_HOOK%"=="true" (
            if not "%OPENVPN_CONFIG_WARN_INLINE%"=="false" (
            
                setlocal EnableDelayedExpansion
                
                if !_OPENVPN_INLINE_WARN_SHOWN! equ 0 (
                    echo/
                    echo       ####################################################################
                    echo       #                                                                  #
                    echo       #                             WARNING                              #
                    echo       #                                                                  #
                    echo       # Potentially Sensitive inline file^(s^) in OpenVPN config detected. #
                    echo       # This is not recommanded when OPENVPN_GUI_HOOK is active.         #
                    echo       #                                                                  #
                    echo       # The reason being is that a stripped-down copy of the config file #
                    echo       # will be placed  in the  OpenVPN GUI  config directory.  So it is #
                    echo       # advised not to include any sensitive content in the OpenVPN conf #
                    echo       # file. Please note  that most of  the times, you don't need to do #
                    echo       # that anyways as by default, obfs4proxy-openvpn supports relative #
                    echo       # path,  allowing all  related OpenVPN  files to be  placed in one #
                    echo       # location while preserving portability.                           #
                    echo       #                                                                  #
                    echo       # NOTE: If you're  sure what  you're doing,  you can  disable this #
                    echo       # warning   by  adjusting   OPENVPN_CONFIG_WARN_INLINE   value  in #
                    echo       # obfs4proxy-openvpn.conf file.                                    #
                    echo       #                                                                  #
                    echo       ####################################################################
                )
                
                echo/
                echo * Potentially sensitive "%%i" inline directive detected.
                choice /m "# Are you sure that you want to continue %%i"
                if !ERRORLEVEL! neq 1 (
                    endlocal
                    call :fatalError "Please remove the %%i sensitve inline file in your openvpn config and try again"
                ) else (
                    endlocal & set "_OPENVPN_INLINE_WARN_SHOWN=1"
                )
                
            ) else (
                echo * OpenVPN config inline warning for %%i skipped...
            )
        )
    )
    if "%MODE%"=="client" (
        echo "%%i"| findstr /r "^\""http-proxy\""$ ^\""--http-proxy\""$ ^\""socks-proxy\""$ ^\""--socks-proxy\""$" > nul && call :fatalError "setting '%%i' is not supported in the openvpn conf file in client mode. If your host requires a proxy server to connect to the Internet, You need to set that as CLIENT_UPSTREAM_PROXY in the obfs4proxy-openvpn.conf file."
    ) else (
        echo "%%i"| findstr /r "^\""local\""$ ^\""--local\""$ ^\""port\""$ ^\""--port\""$ ^\""lport\""$ ^\""--lport\""$" > nul && call :fatalError "directly specifying '%%i' in openvpn conf file in server mode is not supported. This will be set by the script."
    )
)

if not exist "%OBFS4PROXY_BINARY%" (
    call :fatalError "Could not find OBFS4PROXY_BINARY: %OBFS4PROXY_BINARY%"
)

if not exist "%OBFS4PROXY_WORKING_DIR%\" (
    call :fatalError "Could not find OBFS4PROXY_WORKING_DIR: %OBFS4PROXY_WORKING_DIR%"
)

if "%TRANSPORT%"=="obfs4" (
    if "%MODE%"=="client" (
        if not "%CLIENT_REMOTE_CERT%"=="" (
            if not "%CLIENT_REMOTE_NODE_ID%"=="" (
                call :fatalError "You can not specify both CLIENT_REMOTE_CERT and CLIENT_REMOTE_NODE_ID"
            )
            if not "%CLIENT_REMOTE_PUBLIC_KEY%"=="" (
                call :fatalError "You can not specify both CLIENT_REMOTE_CERT and CLIENT_REMOTE_PUBLIC_KEY"
            )
            set "CLIENT_REMOTE_CREDENTIALS=cert=%CLIENT_REMOTE_CERT%"
        ) else (
            if "%CLIENT_REMOTE_NODE_ID%"=="" (
                call :fatalError "You must specify either CLIENT_REMOTE_CERT or both CLIENT_REMOTE_NODE_ID and CLIENT_REMOTE_PUBLIC_KEY"
            )
            if "%CLIENT_REMOTE_PUBLIC_KEY%"=="" (
                call :fatalError "You must specify either CLIENT_REMOTE_CERT or both CLIENT_REMOTE_NODE_ID and CLIENT_REMOTE_PUBLIC_KEY"
            )
            set "CLIENT_REMOTE_CREDENTIALS=node-id=%CLIENT_REMOTE_NODE_ID%;public-key=%CLIENT_REMOTE_PUBLIC_KEY%"
        )
    )
)

exit /b


rem ###########################################################
:initiate_obfs4proxy
echo * Initializing obfs4proxy...

setlocal

set "TOR_PT_MANAGED_TRANSPORT_VER=1"
set "TOR_PT_STATE_LOCATION=%OBFS4PROXY_WORKING_DIR%\%TRANSPORT%"
set "TOR_PT_CLIENT_TRANSPORTS="
set "TOR_PT_PROXY="
set "TOR_PT_SERVER_TRANSPORTS="
set "TOR_PT_SERVER_BINDADDR="
set "TOR_PT_ORPORT="
set "TOR_PT_SERVER_TRANSPORT_OPTIONS="
set "OBFS4PROXY_OUTPUT=%TOR_PT_STATE_LOCATION%\obfs4proxy_stdout.txt"
set "OBFS4PROXY_VERSION="
set "OBFS4PROXY_ARGS="
set "_SERVER_OBFS4_BIND_ADDR_REAL="
set "_SERVER_OBFS4_CERT="
set "_SERVER_OBFS4_CERT_FILE=%TOR_PT_STATE_LOCATION%\cert.txt"
set "_METHODS_DONE=0"

if not exist "%TOR_PT_STATE_LOCATION%\" (
    mkdir "%TOR_PT_STATE_LOCATION%"
    call :errorCheck "Could not create %TOR_PT_STATE_LOCATION%\"
)

if "%MODE%"=="client" (
    set "TOR_PT_CLIENT_TRANSPORTS=%TRANSPORT%"
    set "TOR_PT_PROXY=%CLIENT_UPSTREAM_PROXY%"
) else (
    set "TOR_PT_SERVER_TRANSPORTS=%TRANSPORT%"
    set "TOR_PT_SERVER_BINDADDR=%TRANSPORT%-%SERVER_OBFS4_BIND_ADDR%:%SERVER_OBFS4_BIND_PORT%"
    set "TOR_PT_ORPORT=%SERVER_OPENVPN_BIND_ADDR%:%SERVER_OPENVPN_BIND_PORT%"
    if "%TRANSPORT%"=="obfs4" (
        if not "%IAT_MODE%"=="0" (
            set "TOR_PT_SERVER_TRANSPORT_OPTIONS=%TRANSPORT%:iat-mode=%IAT_MODE%"
        )
    )
)

setlocal EnableDelayedExpansion
if not "%OBFS4PROXY_LOG_LEVEL%"=="none" (
    set "OBFS4PROXY_ARGS=-enableLogging -logLevel %OBFS4PROXY_LOG_LEVEL%"
    if "%OBFS4PROXY_LOG_IP%"=="true" (
        set "OBFS4PROXY_ARGS=!OBFS4PROXY_ARGS! -unsafeLogging"
    )
)
endlocal & set "OBFS4PROXY_ARGS=%OBFS4PROXY_ARGS%"

rem ## We use this method to retrieve the obfs4proxy version number,
rem    as if we directly use for /f to run obfs4proxy executable,
rem    it'll fail if the path has paranthesis in it. However, it
rem    does not fail if you use 'type' command in for /f. Beats me why.
> "%OBFS4PROXY_OUTPUT%" (
    "%OBFS4PROXY_BINARY%" --version
    for /f "delims=" %%i in ('type "%OBFS4PROXY_OUTPUT%"') do (
        set "OBFS4PROXY_VERSION=%%i"
    )
) || call :fatalError "could not extract ofbs4proxy version number. (maybe another instance of the script is running?)"
echo "%OBFS4PROXY_VERSION%"| findstr /r "^\""obfs4proxy-" > nul || call :fatalError "Parsing obfs4proxy version number failed: '%OBFS4PROXY_VERSION%'"
echo * obf4proxy v%OBFS4PROXY_VERSION:~11% detected

rem ## https://stackoverflow.com/a/10358437
> "%OBFS4PROXY_OUTPUT%" start /b "" "%OBFS4PROXY_BINARY%" %OBFS4PROXY_ARGS% || call :fatalError "could not start ofbs4proxy (maybe another instance of the script is running?)"


rem ## Since the obfs4proxy output file is locked while it's running,
rem ## 'type' method is used to read the file. We can't really break output
rem ## of the for loop, without making to run in the end, so I've used this
rem ## cleaner method.
for /l %%i IN (1,1,10) DO (
    timeout /t 1 /nobreak > nul
    if "%MODE%"=="client" (
        for /f "tokens=1* delims=:" %%j in ('type "%OBFS4PROXY_OUTPUT%"') DO (
            if "%%j"=="CMETHOD %TRANSPORT% socks5 127.0.0.1" (
                echo "%%k"| findstr /r "^\""[0-9]*\""$" > nul
                call :errorCheck "obfs4proxy invalid port number: %%k"
                set "CLIENT_OBFS4_SOCKS5_PORT=%%k"
            )
            if "%%j"=="CMETHODS DONE" (
                set "_METHODS_DONE=1"
                rem ## This method is used to break out of the for loop when we're done
                goto :initiate_obfs4proxy_internal
            )
        )
    ) else (
        for /f "tokens=1-5 delims=,= " %%j in ('type "%OBFS4PROXY_OUTPUT%"') DO (
            if "%%j"=="SMETHOD" (
                if "%%k"=="%TRANSPORT%" (
                    set "_SERVER_OBFS4_BIND_ADDR_REAL=%%l"
                    if "%%m"=="ARGS:cert" (
                        set "_SERVER_OBFS4_CERT=%%n"
                    )
                )
            )
            if "%%j"=="SMETHODS" (
                if "%%k"=="DONE" (
                    set "_METHODS_DONE=1"
                    rem ## This method is used to break out of the for loop when we're done
                    goto :initiate_obfs4proxy_internal
                )
            )
        )
    )
)

rem ## Called from :initiate_obfs4proxy. This is for loop breakout
:initiate_obfs4proxy_internal

if %_METHODS_DONE% equ 0 (
    call :fatalError "obfs4proxy initialization timeout"
)

if "%MODE%"=="client" (
    if "%CLIENT_OBFS4_SOCKS5_PORT%"=="" (
        call :fatalError "Could extract obfs4proxy port number"
    )
    echo * Client %TRANSPORT% initialization successful
    echo * OpenVPN will be using the SOCKS5 proxy running on 127.0.0.1:%CLIENT_OBFS4_SOCKS5_PORT%
    rem ## Ending local of :initiate_obfs4proxy ^(for client^)
    endlocal & set "CLIENT_OBFS4_SOCKS5_PORT=%CLIENT_OBFS4_SOCKS5_PORT%"
) else (
    if "%_SERVER_OBFS4_BIND_ADDR_REAL%"=="" (
        call :fatalError "Could extract obfs4proxy bind addr/port"
    )
    if "%TRANSPORT%"=="obfs4" (
        if "%_SERVER_OBFS4_CERT%"=="" (
            call :fatalError "Could extract obfs4proxy cert"
        ) else (
            call :strlenCheck _SERVER_OBFS4_CERT 70 70 "Parsing obfs4 server cert failed (Invalid length)"
            rem https://stackoverflow.com/a/23530712
            if not exist "%_SERVER_OBFS4_CERT_FILE%" (
                (
                    echo *** Set following value as CLIENT_REMOTE_CERT, in your clients obfs4proxy-openvpn.conf file ***
                    echo/
                    echo %_SERVER_OBFS4_CERT%
                ) > "%_SERVER_OBFS4_CERT_FILE%" || call :fatalError "Creating cert.txt file failed."
                
                echo/
                echo       ####################################################################
                echo       #                                                                  #
                echo       # It looks like you are running obfs4 in server mode for the first #
                echo       # time. For this to work, a certificate is generated that you'd    #
                echo       # need to import to the clients conf file later on.                #
                echo       #                                                                  #
                echo       # A file called "cert.txt" is created for you for this purpose.    #
                echo       # This file is located in the obfs4 data directory ^(by default in  #
                echo       # "data\obfs4\"^) and contains the require certificate that needs   #
                echo       # to be imported to the clients.                                   #
                echo       #                                                                  #
                echo       ####################################################################
                echo/
                
                setlocal EnableDelayedExpansion
                choice /m "# Do you want to open the cert.txt file in your text editor right now"
                if !ERRORLEVEL! equ 1 (
                    endlocal
                    echo * Opening the cert.txt file in your default text editor...
                    echo/
                    start "" "%_SERVER_OBFS4_CERT_FILE%" || call :fatalError "Could not open the cert.txt file"
                    pause
                ) else (
                    endlocal
                    echo * Opening cert.txt file skipped.
                )
            )
        )
    )
    echo/
    echo * Server %TRANSPORT% initialization successful
    echo * Reverse proxy is listening on %_SERVER_OBFS4_BIND_ADDR_REAL%
    rem ## Ending local of :initiate_obfs4proxy
    endlocal
)



rem ## Return to the :initiate_obfs4proxy caller
exit /b

rem ###########################################################



:initiate_openvpn
setlocal

set "SOCKS5_AUTH=%OBFS4PROXY_WORKING_DIR%\%TRANSPORT%\socks5_auth"

if "%MODE%"=="client" (
    if "%TRANSPORT%"=="obfs4" (
        rem ## https://stackoverflow.com/a/7225821
        rem ## https://stackoverflow.com/a/10358437
        rem ## https://stackoverflow.com/a/23530712
        > "%SOCKS5_AUTH%" (
            echo %CLIENT_REMOTE_CREDENTIALS%;iat-mode=
            echo %IAT_MODE%
        ) || call :fatalError "Could not write to socks5_auth file"
    )
)

if "%OPENVPN_GUI_HOOK%"=="true" (
    call :initiate_openvpn_gui
) else (
    call :initiate_openvpn_cli
)

endlocal

exit /b



:initiate_openvpn_gui
setlocal

set "OPENVPN_GUI_OVPN_DIR=%USERPROFILE%\OpenVPN\config"
set "OPENVPN_GUI_LOG_DIR=%USERPROFILE%\OpenVPN\log"
set "OPENVPN_GUI_OVPN_FILENAME=obfs4proxy-openvpn-%SCRIPT_ID%"
set "OPENVPN_GUI_OVPN_EXT=ovpn"
set "OPENVPN_GUI_LOCK_EXT=lock"
set "OPENVPN_GUI_OVPN_PATH="
set "OPENVPN_GUI_LOCK_PATH="
set "OPENVPN_GUI_LOG_PATH="
set "OPENVPN_GUI_MANUAL_RIGHTCLICK=0"
set "OPENVPN_GUI_RUNNING="
set "OPENVPN_GUI_BINARY_NAME="


for /f "tokens=2* skip=2" %%i in ('reg query "HKCU\Software\OpenVPN-GUI" /v config_dir 2^> nul') do (
    if "%%i"=="REG_SZ" (
        if not "%OPENVPN_GUI_OVPN_DIR%"=="%%j" (
            echo * Note: Customized OpenVPN GUI config directory detected
            set "OPENVPN_GUI_OVPN_DIR=%%j"
        )
    )
)
for /f "tokens=2* skip=2" %%i in ('reg query "HKCU\Software\OpenVPN-GUI" /v config_ext 2^> nul') do (
    if "%%i"=="REG_SZ" (
        if not "%OPENVPN_GUI_OVPN_EXT%"=="%%j" (
            echo * Note: Customized OpenVPN GUI openvpn extension detected
            set "OPENVPN_GUI_OVPN_EXT=%%j"
        )
    )
)
for /f "tokens=2* skip=2" %%i in ('reg query "HKCU\Software\OpenVPN-GUI" /v log_dir 2^> nul') do (
    if "%%i"=="REG_SZ" (
        if not "%OPENVPN_GUI_LOG_DIR%"=="%%j" (
            echo * Note: Customized OpenVPN GUI log directory detected
            set "OPENVPN_GUI_LOG_DIR=%%j"
        )
    )
)
if "%MODE%"=="client" (
    for /f "tokens=2* skip=2" %%i in ('reg query "HKCU\Software\OpenVPN-GUI\proxy" /v proxy_source 2^> nul') do (
        if "%%i"=="REG_SZ" (
            if not "%%j"=="0" (
                call :fatalError "OpenVPN GUI Proxy setting is set. This is not supported. If your host requires a proxy server to connect to the Internet, You need to set that as CLIENT_UPSTREAM_PROXY in the obfs4proxy-openvpn.conf file."
            )
        )
    )
)
set "OPENVPN_GUI_OVPN_PATH=%OPENVPN_GUI_OVPN_DIR%\%OPENVPN_GUI_OVPN_FILENAME%.%OPENVPN_GUI_OVPN_EXT%"
set "OPENVPN_GUI_LOCK_PATH=%OPENVPN_GUI_OVPN_DIR%\%OPENVPN_GUI_OVPN_FILENAME%.%OPENVPN_GUI_LOCK_EXT%"
set "OPENVPN_GUI_LOG_PATH=%OPENVPN_GUI_LOG_DIR%\%OPENVPN_GUI_OVPN_FILENAME%.log"

if not exist "%OPENVPN_GUI_OVPN_DIR%\" (
    call :fatalError "Could not find OpenVPN GUI config folder. (Re)starting the OpenVPN GUI program might fix it: %OPENVPN_GUI_OVPN_DIR%"
)
if /i "%OPENVPN_GUI_OVPN_EXT%"=="%OPENVPN_GUI_LOCK_EXT%" (
    call :fatalError "Seriously?! Of all the extensions in the world, you went with .%OPENVPN_GUI_LOCK_EXT% for your openvpn files?"
)

for /f "delims=" %%i in ("%OPENVPN_GUI_BINARY%") do (
    set "OPENVPN_GUI_BINARY_NAME=%%~nxi"    
)

call :OpenvpnGuiStatusUpdate

if not exist "%OPENVPN_GUI_OVPN_PATH%" (
    if %OPENVPN_GUI_RUNNING% equ 1 (
        echo/
        echo       ####################################################################
        echo       #                                                                  #
        echo       # It looks like you are running this script for the first time in  #
        echo       # OpenVPN GUI mode.                                                #
        echo       #                                                                  #
        echo       # A running instance of OpenVPN GUI, cannot detect new files in    #
        echo       # its config directory automaticaly. The easiest way to fix this,  #
        echo       # is by restarting OpenVPN GUI. The script can do that for you.    #
        echo       #                                                                  #
        echo       # NOTE: if you have any active OpenVPN connections, they will be   #
        echo       # terminated ^(a confirmation dialog will be displayed^)             #
        echo       #                                                                  #
        echo       ####################################################################
        echo/
        
        setlocal EnableDelayedExpansion
        choice /m "# Do you want this script to restart OpenVPN GUI"
        
        rem # echo does not set/clear the errorlevel, so we're fine
        echo/
        
        if !ERRORLEVEL! equ 1 (
            endlocal
            
            start "" "%OPENVPN_GUI_BINARY%" --command exit || call :fatalError "Could not invoke OpenVPN GUI exit command"
            call :OpenvpnGuiStatusChange
            echo * OpenVPN GUI terminated successfully
            
        ) else (
            endlocal
            
            echo/
            echo       ####################################################################
            echo       #                                                                  #
            echo       # Another way to make OpenVPN GUI refresh its config directory, is #
            echo       # by simply right clicking on the OpenVPN GUI tray icon once.      #
            echo       # However, please keep in mind that there is no way for the script #
            echo       # to verify whether you've actually done it or not. So unless you  #
            echo       # you do it, the script will not work correctly.                   #
            echo       #                                                                  #
            echo       # NOTE: You will be prompted later on when you need to manually    #
            echo       # right click on the OpenVPN GUI tray icon.                        #
            echo       #                                                                  #
            echo       ####################################################################
            echo/
            
            setlocal EnableDelayedExpansion
            choice /m "# Do you want to continue"
            if !ERRORLEVEL! equ 1 (
                endlocal & set "OPENVPN_GUI_MANUAL_RIGHTCLICK=1"
            ) else (
                endlocal
                call :fatalError "Given the circumstances, the script cannot gaurantee reliable execution"
            )
        )
    )
    
    rem # We put this after the confirmation dialog so even if the user closes the script
    rem # on that dialog, the next time it shows up again ^(as it should ^)
    rem # We should also always use the lock file before writing to the ovpn file
    2> "%OPENVPN_GUI_LOCK_PATH%" (
        rem # https://stackoverflow.com/a/295214/892099
        rem # We use double 'greater than' sign here just to be super sure
        rem # we wouldn't mistakenly rewriting anything
        type nul >> "%OPENVPN_GUI_OVPN_PATH%" || call :fatalError "Could not create the ovpn file"
    ) || call :fatalError "Could not accquire exclusive lock (is another instance with the same SCRIPT_ID is running?)."
    
    setlocal EnableDelayedExpansion
    if !OPENVPN_GUI_MANUAL_RIGHTCLICK! equ 1 (
        echo/
        echo       ####################################################################
        echo       #                                                                  #
        echo       # Please right click on the OpenVPN GUI icon once to open up its   #
        echo       # menu. After that, you may click anywhere else on the screen to   #
        echo       # close the said menu. Once you're done, press any key to continue #
        echo       #                                                                  #
        echo       ####################################################################
        echo/
        pause
    )
    endlocal
    
)


if %OPENVPN_GUI_RUNNING% equ 0 (
    start "" "%OPENVPN_GUI_BINARY%" || call :fatalError "Could not start OpenVPN GUI"
    call :OpenvpnGuiStatusChange
    echo * OpenVPN GUI started successfully
)

rem we use this method to accquire a lock: https://stackoverflow.com/a/25131361
rem This however has the small side effect of any potential stderr, going to the lock file
2> "%OPENVPN_GUI_LOCK_PATH%" (
    > "%OPENVPN_GUI_OVPN_PATH%" (
        echo # This file is automatically generated by obfs4proxy-openvpn with SCRIPT_ID of "%SCRIPT_ID%"
        echo # Do NOT edit this file directly.
        echo/
        if not "%OPENVPN_RELATIVE_PATH%"=="" (
            echo cd "%OPENVPN_RELATIVE_PATH:\=\\%"
        )
        if "%MODE%"=="client" (
            echo proto tcp-client
            if "%TRANSPORT%"=="obfs4" (
                echo socks-proxy 127.0.0.1 %CLIENT_OBFS4_SOCKS5_PORT% "%SOCKS5_AUTH:\=\\%"
            ) else (
                echo socks-proxy 127.0.0.1 %CLIENT_OBFS4_SOCKS5_PORT%
            )
        ) else (
            echo proto tcp-server
            echo local %SERVER_OPENVPN_BIND_ADDR%
            echo lport %SERVER_OPENVPN_BIND_PORT%
        )
        rem # removing potential openvpn conf file comments
        for /f "usebackq eol=# delims=" %%i in ("%OPENVPN_CONFIG_FILE_PATH%") DO (
            rem # openvpn also accepts ';' for comments at the begining of the line
            rem # we're not going to use echo ^| findstr here, as piping alone,
            rem # could potentially screw up the strings.
            for /f "usebackq eol=; delims=" %%j in ('%%i') DO (
                echo %%j
            )
        )
    ) || call :fatalError "Could not write to the ovpn file"
    
    call :doNotCloseMessage
    echo       #                                                                  #
    echo       # If OpenVPN execution fails, remember to look at the OpenVPN log  #
    echo       # file by right clicking on OpenVPN GUI tray icon and selecting    #
    echo       # "View Log".                                                      #
    echo       #                                                                  #
    echo       # NOTE: Internal "reconnect" functionality of the OpenVPN GUI,     #
    echo       # might malfunction. This is a bug in the OpenVPN GUI program.     #
    echo       #                                                                  #
    echo       #                                                                  #
    echo       ####################################################################
    
    call :openvpnGuiControl restart 1
    
) || call :fatalError "Could not accquire exclusive lock (is another instance with the same SCRIPT_ID is running?)."

echo * Giving the process some time to release the lock file...
timeout /t 2 /nobreak > nul
del "%OPENVPN_GUI_LOCK_PATH%"

endlocal

exit /b


:initiate_openvpn_cli
echo * Starting OpenVPN in terminal mode...
call :doNotCloseMessage
echo/

rem ## I still have to find a way to set the openvpn arguments in a variable, that would be
rem ## correctly quoted when passed to openvpn executable. Otherwise, all included paths with
rem ## special characters in them, will fail. Untill then, full arguments are specified for each
rem ## conditions. 
if not "%OPENVPN_RELATIVE_PATH%"=="" (
    if "%MODE%"=="client" (
        if "%TRANSPORT%"=="obfs4" (
            "%OPENVPN_BINARY%" --cd "%OPENVPN_RELATIVE_PATH:\=\\%" --config "%OPENVPN_CONFIG_FILE%" --proto tcp-client --socks-proxy 127.0.0.1 %CLIENT_OBFS4_SOCKS5_PORT% "%SOCKS5_AUTH:\=\\%"
        ) else (
            "%OPENVPN_BINARY%" --cd "%OPENVPN_RELATIVE_PATH:\=\\%" --config "%OPENVPN_CONFIG_FILE%" --proto tcp-client --socks-proxy 127.0.0.1 %CLIENT_OBFS4_SOCKS5_PORT%
        )
    ) else (
        "%OPENVPN_BINARY%" --cd "%OPENVPN_RELATIVE_PATH:\=\\%" --config "%OPENVPN_CONFIG_FILE%" --proto tcp-server --local %SERVER_OPENVPN_BIND_ADDR% --lport %SERVER_OPENVPN_BIND_PORT%
    )
) else (
    if "%MODE%"=="client" (
        if "%TRANSPORT%"=="obfs4" (
            "%OPENVPN_BINARY%" --config "%OPENVPN_CONFIG_FILE%" --proto tcp-client --socks-proxy 127.0.0.1 %CLIENT_OBFS4_SOCKS5_PORT% "%SOCKS5_AUTH:\=\\%"
        ) else (
            "%OPENVPN_BINARY%" --config "%OPENVPN_CONFIG_FILE%" --proto tcp-client --socks-proxy 127.0.0.1 %CLIENT_OBFS4_SOCKS5_PORT%
        )
    ) else (
        "%OPENVPN_BINARY%" --config "%OPENVPN_CONFIG_FILE%" --proto tcp-server --local %SERVER_OPENVPN_BIND_ADDR% --lport %SERVER_OPENVPN_BIND_PORT%
    )
)
call :errorCheck "Could not start openvpn"

exit /b


:OpenvpnGuiStatusUpdate
rem # we use qprocess to see if openvpn gui is already running for
rem # currect session. current session in qprocess, starts with a
rem # 'greater than' sign.
set "OPENVPN_GUI_RUNNING=0"
for /f "skip=1" %%i in ('qprocess "%OPENVPN_GUI_BINARY_NAME%" 2^> nul') do (
    echo "%%i"| findstr /r "^\"">" > nul && set "OPENVPN_GUI_RUNNING=1"
)
exit /b


:OpenvpnGuiStatusChange
for /l %%i IN (1,1,10) DO (

    timeout /t 1 /nobreak > nul
    
    set "OPENVPN_GUI_RUNNING=0"
    for /f "skip=1" %%i in ('qprocess "%OPENVPN_GUI_BINARY_NAME%" 2^> nul') do (
        echo "%%i"| findstr /r "^\"">" > nul && set "OPENVPN_GUI_RUNNING=1"
    )
    
    setlocal EnableDelayedExpansion
    if not "!OPENVPN_GUI_RUNNING!"=="%OPENVPN_GUI_RUNNING%" (
        goto :OpenvpnGuiStatusChangeInt
    ) else (
        endlocal
    )
    
)
call :fatalError "OpenVPN GUI status change timed out."
:OpenvpnGuiStatusChangeInt
endlocal
exit /b


:OpenvpnGuiStatusCheck
call :OpenvpnGuiStatusUpdate
if %OPENVPN_GUI_RUNNING% equ 0 (
    call :fatalError "OpenVPN GUI is not running anymore"
)
exit /b


rem # this is a quite ugly solution. But the only way
rem # that we can keep the current lock file, is by calling
rem # other routines rather than goto. calling back to itself
rem # will cause slight increase in the memory footprint each time,
rem # but its negligible. And also, the user is not expected to
rem # use this functionaity too many times.
rem #
rem # we also must make sure openvpn gui is running beforehand. Otherwise, it will be started
rem # inside the lock procedure which causes the lock to not release even after the script
rem # is closed and only be released after openvpn gui process is ended.
rem #
rem # for some reason, the internal openvpn gui reconnect command, fails.
rem # This seems to be a bug in openpvn gui when the ovpn file contains 'cd'.
rem # so we first try disconnecting the profile if its potentially running from
rem # the previous run, etc. we need to give it some time to ensure full
rem # execution and cleanup, in case the profile was infact running.
:openvpnGuiControl <command> <showLegend>
echo/
if "%1"=="restart" (
    call :OpenvpnGuiStatusCheck
    start "" "%OPENVPN_GUI_BINARY%" --command disconnect "%OPENVPN_GUI_OVPN_FILENAME%" || call :fatalError "Could not invoke OpenVPN GUI disconnect command"
    echo * Starting OpenVPN GUI "%OPENVPN_GUI_OVPN_FILENAME%" profile in 3 seconds...
    timeout /t 3 /nobreak > nul
    start "" "%OPENVPN_GUI_BINARY%" --command connect "%OPENVPN_GUI_OVPN_FILENAME%" || call :fatalError "Could not invoke OpenVPN GUI connect command"
) else (
    if "%1"=="status" (
        call :OpenvpnGuiStatusCheck
        echo * Calling OpenVPN GUI status windows...
        start "" "%OPENVPN_GUI_BINARY%" --command status "%OPENVPN_GUI_OVPN_FILENAME%" || call :fatalError "Could not invoke OpenVPN GUI status command"
    ) else (
        call :OpenvpnGuiStatusCheck
        echo * Disconnecting "%OPENVPN_GUI_OVPN_FILENAME%" profile...
        start "" "%OPENVPN_GUI_BINARY%" --command disconnect "%OPENVPN_GUI_OVPN_FILENAME%" || call :fatalError "Could not invoke OpenVPN GUI disconnect command"
        exit /b
    )
)
echo/

if "%2"=="1" (
    echo [1] Reconnect
    echo [2] Show Status
    echo [3] Disconnect ^& Exit
    echo [0] Disconnect ^& Cleanup ^& Exit
    echo/
)

choice /c 1230 /n /m "# You may select an option:"
if %ERRORLEVEL% equ 1 (
    call :openvpnGuiControl restart
) else (
    if %ERRORLEVEL% equ 2 (
        call :openvpnGuiControl status
    ) else (
        if %ERRORLEVEL% equ 3 (
            call :openvpnGuiControl disconnect
        ) else (
            echo/
            echo * NOTE: After disconneting, the sript will try to delete the following files:
            echo * "%OPENVPN_GUI_OVPN_PATH%"
            echo * "%OPENVPN_GUI_LOG_PATH%"
            echo/
            setlocal EnableDelayedExpansion
            choice /m "# Are you sure you want to deleted these files"
            if !ERRORLEVEL! equ 1 (
                endlocal
                
                call :openvpnGuiControl disconnect
                
                echo * Giving the OpenVPN GUI some time to release the files...
                timeout /t 2 /nobreak > nul
                del "%OPENVPN_GUI_OVPN_PATH%"
                del "%OPENVPN_GUI_LOG_PATH%"
                
            ) else (
                endlocal
                echo * Cleanup skipped by the user
                call :openvpnGuiControl disconnect
            )
        )
    )
)

exit /b


:doNotCloseMessage
    echo/
    echo       ####################################################################
    echo       #                                                                  #
    echo       #   Do NOT Close This Window While The OpenVPN Session is Active   #
    echo       #                                                                  #
    echo       ####################################################################
exit /b


rem ## https://stackoverflow.com/a/5841587
rem ## Our biggest valid string is going to be 70 characters long.
rem ## So unrequired extra irritatoins are removed. This function
rem ## is capable of counting strings length upto 128 charactres long.
:strlenCheck <stringVar> <minLength> <maxLength> <errorMessage>
(
    setlocal EnableDelayedExpansion
    (set^ tmp=!%~1!)
    if defined tmp (
        set "len=1"
        for %%P in (64 32 16 8 4 2 1) do (
            if "!tmp:~%%P,1!" NEQ "" ( 
                set /a "len+=%%P"
                set "tmp=!tmp:~%%P!"
            )
        )
    ) ELSE (
        set len=0
    )
)
(
    endlocal
    if %len% lss %2 (
        call :fatalError %4
    )
    if %len% gtr %3 (
        call :fatalError %4
    )
    exit /b
)


rem ## mostly used inside 'for' loops ^(so we wouldn't need to enable delayed expansion^)
:errorCheck <errorMessage>
if %ERRORLEVEL% neq 0 (
    call :fatalError %*
)
exit /b


:fatalError <errorMessage>
color 47
echo/
echo ************** ERROR **************
echo %*
echo Last Error Code: %ERRORLEVEL%
echo ***********************************
pause > nul
exit 1


:final_message
color 07
echo/
echo/
echo ###############################################################################
echo #                                                                             #
echo #        Script execution is complete. You may close this windows now.        #
echo #                                                                             #
echo ###############################################################################
exit
