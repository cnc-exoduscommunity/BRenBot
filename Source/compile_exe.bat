REM Requires PAR::Packer (pp) to be installed

SETLOCAL

REM Configure additional modules and libraries to be included in the compiled executable
REM Some of the required libraries may differ depending on your Perl distribution
SET PPModules= -M POE/Filter.pm -M POE/Filter/Stream.pm -M XML/LibXML/Sax.pm
SET PPLibraries= -l libexpat-1_.dll -l libxml2-2_.dll -l libiconv-2_.dll -l liblzma-5_.dll -l zlib1_.dll

REM Compile the executable file
pp -o brenbot.exe %PPModules% %PPLibraries% brenbot.pl

ENDLOCAL