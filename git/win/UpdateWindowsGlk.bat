@echo off

xcopy /y ..\..\Glk\Executables\Release\Glk*.dll WindowsGlk
xcopy /y ..\..\Glk\Executables\Release\Glk.lib WindowsGlk
xcopy /y /s ..\..\Glk\Include\*.h WindowsGlk\Include\
xcopy /y ..\..\Glk\Glk.c WindowsGlk
