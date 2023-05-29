@echo off
"%ProgramFiles(x86)%\Zip\zip" -j \Temp\wingit.zip ..\Release\Git.exe
"%ProgramFiles(x86)%\Zip\zip" -j \Temp\wingit.zip ..\Release\Git.chm
"%ProgramFiles(x86)%\Zip\zip" -j \Temp\wingit.zip ..\Release\Glk*.dll
"%ProgramFiles(x86)%\Zip\zip" -j \Temp\wingit.zip ..\README.txt
popd
