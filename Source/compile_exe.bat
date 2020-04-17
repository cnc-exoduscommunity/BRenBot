REM Requires PAR::Packer (pp) to be installed

SETLOCAL

REM Configure additional modules and libraries to be included in the compiled executable
REM Some of the required libraries may differ depending on your Perl distribution
SET PPModules= -M XML/SAX/Expat.pm
SET PPLibraries= 

REM Compile the executable file
pp -o brenbot.exe %PPModules% %PPLibraries% brenbot.pl

ENDLOCAL