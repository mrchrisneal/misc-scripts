:: author: Chris Neal (loosely based on a script by pzfans)
@echo off
@echo ================================================================
@echo                    Zomboid Backup Script v1.0                   
@echo                          by Chris Neal                         
@echo ================================================================
@echo:

::Get and format date/time
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YY=%dt:~2,2%" & set "YYYY=%dt:~0,4%" & set "MM=%dt:~4,2%" & set "DD=%dt:~6,2%"
set "HH=%dt:~8,2%" & set "Min=%dt:~10,2%" & set "Sec=%dt:~12,2%"
set "fullstamp=%YYYY%-%MM%-%DD%_%HH%-%Min%-%Sec%"
::set "datestamp=%YYYY%%MM%%DD%" & set "timestamp=%HH%%Min%%Sec%" & set "fullstamp=%YYYY%-%MM%-%DD%_%HH%-%Min%-%Sec%"

break

setlocal enabledelayedexpansion

set "file=%UserProfile%\Zomboid"
set "dest=%UserProfile%\Zomboid_Backups\PZBackup_%fullstamp%"

@echo This script will create a timestamped backup of the entire Zomboid data folder.
@echo:
@echo          Zomboid Folder: %file%
@echo      Backup Destination: %dest%
@echo:
@echo Cancel the backup process at any time by closing this window, or by pressing CTRL+C.
@echo: 
pause
@echo: 
@echo Additionally, a 7-zip archive containing this backup can be saved to OneDrive.
@echo Path: %UserProfile%\OneDrive\Zomboid_Backups\PZBackup_%fullstamp%.7z
@echo: 
set /p archivechoice=Compress the backup and save it to OneDrive? (y/n) 
@echo: 
@echo Starting backup...
mkdir "%dest%"
xcopy "%file%" "%dest%" /s /e /y
@echo: 
echo ================================================================
@echo: 
echo Backup completed. Files were saved in %dest%
@echo: 
if "%archivechoice%"=="y" (
	echo Creating .7z archive and saving it to OneDrive...
	"C:\Program Files\7-Zip\7z.exe" a %UserProfile%\OneDrive\Zomboid_Backups\PZBackup_%fullstamp% %dest%
	echo ================================================================
	@echo: 
	echo Archive completed. File was saved to %UserProfile%\OneDrive\Zomboid_Backups\PZBackup_%fullstamp%.7z
	@echo:
) else (
	echo Archive skipped.
	@echo:
)
pause

