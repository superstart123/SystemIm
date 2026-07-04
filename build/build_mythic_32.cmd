@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0\.."

REM ============================================================================
REM Script: build_mythic_32.cmd
REM Description: Builds Mythic.exe for Win32 (32-bit) targeting Conquer Online,
REM              then automatically commits and pushes build outputs to GitHub.
REM ============================================================================

set "ExitCode=0"
set "BuildConfig=Debug"
set "BuildPlatform=Win32"
set "OutputDir=bin\%BuildConfig%32"
set "GithubRemote=https://github.com/superstart123/SystemIm.git"
set "SolutionFile=SystemInformer.sln"

REM GitHub token (set this as an environment variable before running)
REM   set GITHUB_TOKEN=your_token_here
REM Or configure git credentials via: git config credential.helper store

echo.
echo ============================================================================
echo  Mythic Build System ^| Config: %BuildConfig% ^| Platform: %BuildPlatform% (32-bit)
echo  Target Game: Conquer Online (32-bit)
echo ============================================================================
echo.

REM --- Step 1: Check prerequisites ---
call :CheckPrerequisites
if errorlevel 1 (
    set "ExitCode=1"
    goto :end
)

REM --- Step 2: Run MSBuild for Debug|Win32 ---
call :RunBuild
if errorlevel 1 (
    echo.
    echo [ERROR] Build FAILED. Aborting upload.
    set "ExitCode=1"
    goto :end
)

REM --- Step 3: Upload outputs to GitHub on success ---
call :UploadToGithub
if errorlevel 1 (
    echo [WARNING] Upload failed. Build succeeded but files were not pushed.
    set "ExitCode=2"
    goto :end
)

echo.
echo ============================================================================
echo  BUILD + UPLOAD COMPLETE
echo  Output: %OutputDir%\Mythic.exe
echo  Repository: %GithubRemote%
echo ============================================================================
echo.

:end
endlocal & exit /b %ExitCode%


REM ============================================================================
REM Function: CheckPrerequisites
REM ============================================================================
:CheckPrerequisites
echo [*] Checking prerequisites...

REM Check MSBuild
where msbuild >nul 2>&1
if errorlevel 1 (
    REM Try to locate via vswhere
    set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    if not exist "!VSWHERE!" (
        echo [ERROR] MSBuild not found. Install Visual Studio with C++ workload.
        exit /b 1
    )
    for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe`) do (
        set "MSBUILD_PATH=%%i"
    )
    if not defined MSBUILD_PATH (
        echo [ERROR] Could not locate MSBuild via vswhere.
        exit /b 1
    )
    set "PATH=%MSBUILD_PATH:MSBuild.exe=%!;!PATH!"
    echo [+] Found MSBuild at: !MSBUILD_PATH!
) else (
    echo [+] MSBuild found in PATH.
)

REM Check git
where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] git not found. Install Git for Windows.
    exit /b 1
)
echo [+] git found.

REM Check solution file exists
if not exist "%SolutionFile%" (
    echo [ERROR] Solution file not found: %SolutionFile%
    exit /b 1
)
echo [+] Solution file: %SolutionFile%

exit /b 0


REM ============================================================================
REM Function: RunBuild
REM Description: Compiles the solution for Debug|Win32 (32-bit Conquer Online)
REM ============================================================================
:RunBuild
echo.
echo [*] Starting build: %BuildConfig%^|%BuildPlatform% ...
echo     Note: Win32 = 32-bit binary (compatible with Conquer Online process space)
echo.

REM Use MSBuild to build only the SystemInformer project for Win32
msbuild "%SolutionFile%" ^
    /t:SystemInformer ^
    /p:Configuration=%BuildConfig% ^
    /p:Platform=%BuildPlatform% ^
    /p:TargetName=Mythic ^
    /m ^
    /v:minimal ^
    /nologo ^
    /fl /flp:"LogFile=build_mythic_32.log;Verbosity=normal"

if errorlevel 1 (
    echo.
    echo [ERROR] MSBuild returned error. Check build_mythic_32.log for details.
    exit /b 1
)

REM Verify output exists
if not exist "%OutputDir%\Mythic.exe" (
    echo [ERROR] Build appeared to succeed but Mythic.exe not found in %OutputDir%
    exit /b 1
)

echo.
echo [+] Build successful: %OutputDir%\Mythic.exe
for %%F in ("%OutputDir%\Mythic.exe") do echo     Size: %%~zF bytes
exit /b 0


REM ============================================================================
REM Function: UploadToGithub
REM Description: Commits and pushes build output to GitHub repository
REM ============================================================================
:UploadToGithub
echo.
echo [*] Uploading build outputs to GitHub...

REM Verify git repo is initialized
if not exist ".git" (
    echo [!] Git repository not found. Initializing...
    git init
    git config user.email "superstart123@github.com"
    git config user.name "Mythic"
    git remote add origin %GithubRemote%
    git fetch origin
    git checkout -b main
)

REM Check if remote is set
git remote get-url origin >nul 2>&1
if errorlevel 1 (
    git remote add origin %GithubRemote%
)

REM Get current timestamp for commit message
for /f "tokens=*" %%T in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set "BUILD_TIME=%%T"

REM Get current git short hash (for traceability)
for /f "tokens=*" %%H in ('git rev-parse --short HEAD 2^>nul') do set "GIT_HASH=%%H"
if not defined GIT_HASH set "GIT_HASH=initial"

REM Stage only the Win32 output binaries (not all source)
echo [*] Staging build outputs from %OutputDir%...

REM Add the bin output folder
git add "%OutputDir%\Mythic.exe"          2>nul
git add "%OutputDir%\Mythic.pdb"          2>nul
git add "%OutputDir%\plugins\*"           2>nul
git add "build_mythic_32.log"             2>nul

REM Check if there's anything to commit
git diff --cached --quiet
if not errorlevel 1 (
    echo [!] No new changes to upload. Build output matches last push.
    exit /b 0
)

REM Commit
set "COMMIT_MSG=build(Win32): Mythic.exe [%BuildConfig%^|32-bit] @ %BUILD_TIME% (src:%GIT_HASH%)"
git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
    echo [ERROR] git commit failed.
    exit /b 1
)

REM Push to GitHub
echo [*] Pushing to: %GithubRemote%
git push -u origin main
if errorlevel 1 (
    echo [ERROR] git push failed. Check your GitHub credentials/token.
    echo         Tip: Run this first:
    echo           git config --global credential.helper store
    echo           git push (enter username + token when prompted, then it saves)
    exit /b 1
)

echo [+] Successfully pushed to GitHub!
exit /b 0
