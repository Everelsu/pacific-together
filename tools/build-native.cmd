@echo off
rem Builds native/ (UE4SS + PacificTogetherNative); the DLL lands in mod/PacificTogetherNative/dlls/main.dll.
rem First run: git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive
setlocal
set "VS="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`call "%VSWHERE%" -latest -products * -property installationPath`) do set "VS=%%i"
echo Visual Studio: %VS%
if not defined VS (echo Visual Studio Build Tools not found & exit /b 1)
rem vcvars64 looks for vswhere on PATH
set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%"
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set PATH=%USERPROFILE%\.cargo\bin;%PATH%
cd /d "%~dp0..\native"
if not exist build\build.ninja cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Game__Shipping__Win64 || exit /b 1
rem MSVC sometimes fails with C1041 (shared .pdb) under heavy parallel load; a second pass resumes where it stopped
cmake --build build --target PacificTogetherNative || cmake --build build --target PacificTogetherNative
