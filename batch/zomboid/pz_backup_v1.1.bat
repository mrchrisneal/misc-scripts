:: Zomboid Backup Script v1.1 (December 11, 2025)
:: Author: Chris Neal (loosely based on a script by pzfans)
:: Tested for Build 42 compatibility (user data path unchanged)
:: GitHub: https://github.com/mrchrisneal/misc-scripts/blob/main/batch/zomboid
@echo off
@echo ========================================================================
@echo                       Zomboid Backup Script v1.1                        
@echo                    by Chris Neal (December 11, 2025)                    
@echo   https://github.com/mrchrisneal/misc-scripts/blob/main/batch/zomboid   
@echo ========================================================================
@echo:

:: Get and format date/time
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YY=%dt:~2,2%" & set "YYYY=%dt:~0,4%" & set "MM=%dt:~4,2%" & set "DD=%dt:~6,2%"
set "HH=%dt:~8,2%" & set "Min=%dt:~10,2%" & set "Sec=%dt:~12,2%"
set "fullstamp=%YYYY%-%MM%-%DD%_%HH%-%Min%-%Sec%"

setlocal enabledelayedexpansion

set "file=%UserProfile%\Zomboid"
set "dest=%UserProfile%\Zomboid_Backups\PZBackup_%fullstamp%"

@echo This script will create a timestamped backup of the entire Zomboid data folder.
@echo:
@echo          Zomboid Folder: %file%
@echo      Backup Destination: %dest%
@echo:

:: ================================================================
::                   SERVER STATUS CHECK
:: ================================================================
@echo Checking server status...

:: Look for the specific Java process running the GameServer class
:: NOTE: %% is required in batch files to escape the percent sign
wmic process where "name='java.exe' and CommandLine like '%%zombie.network.GameServer%%'" get ProcessId 2>nul | findstr [0-9] >nul

if %errorlevel%==0 (
    color 0E
    @echo: 
    @echo [WARNING] SERVER IS CURRENTLY RUNNING!
    @echo: 
    @echo Backing up a live database ^(players.db/vehicles.db^) carries a risk.
    @echo If a player moves an item or enters a vehicle exactly when the
    @echo copy happens, that specific file may become corrupted in the backup.
    @echo: 
    @echo It is highly recommended to STOP the server before backing up.
    @echo: 
    set /p "run_live=Are you sure you want to proceed with a LIVE backup? (y/n): "
    if /i "!run_live!" neq "y" (
        @echo:
        @echo Backup cancelled by user.
        color 07
        goto :end
    )
    @echo:
    @echo Proceeding with live backup...
    color 07
) else (
    @echo Server is OFFLINE. Proceeding with safe backup...
)

:: ================================================================
@echo: 
@echo Additionally, a 7-zip archive containing this backup can be saved to OneDrive.
@echo Path: %UserProfile%\OneDrive\Zomboid_Backups\PZBackup_%fullstamp%.7z
@echo: 
set /p archivechoice=Compress the backup and save it to OneDrive? (y/n) 
@echo: 
@echo Starting backup...

:: Create destination directory
mkdir "%dest%" 2>nul
if not exist "%dest%" (
    color 0C
    @echo [ERROR] Failed to create backup directory: %dest%
    color 07
    goto :end
)

:: Using Robocopy for better handling of locked files and excluding Logs
:: /E = Copy subdirectories including empty ones (safer than /MIR for new destinations)
:: /XD Logs = Exclude the Logs folder (saves massive space)
:: /R:1 /W:1 = Retry locked files once, wait 1 sec (prevents hanging on live server)
:: /NFL = No File List (suppresses per-file output, still shows directories + summary)
robocopy "%file%" "%dest%" /E /XD Logs /R:1 /W:1 /NFL
set "robo_result=!errorlevel!"

:: Robocopy exit codes: 0-7 are success/info, 8+ are errors
if !robo_result! geq 8 (
    color 0C
    @echo:
    @echo [ERROR] Robocopy encountered errors during backup ^(exit code: !robo_result!^)
    color 07
) else (
    @echo:
    @echo ================================================================
    @echo:
    @echo Backup completed successfully. Files were saved in:
    @echo %dest%
)

@echo: 
if /i "%archivechoice%"=="y" (
    :: Verify 7-Zip exists
    if not exist "C:\Program Files\7-Zip\7z.exe" (
        color 0E
        @echo [WARNING] 7-Zip not found at C:\Program Files\7-Zip\7z.exe
        @echo Archive step skipped.
        color 07
        goto :end
    )
    
    :: Create OneDrive backup directory if it doesn't exist
    if not exist "%UserProfile%\OneDrive\Zomboid_Backups" (
        mkdir "%UserProfile%\OneDrive\Zomboid_Backups"
    )
    
    @echo Creating .7z archive and saving it to OneDrive...
    "C:\Program Files\7-Zip\7z.exe" a "%UserProfile%\OneDrive\Zomboid_Backups\PZBackup_%fullstamp%" "%dest%"
    set "zip_result=!errorlevel!"
    
    if !zip_result!==0 (
        @echo ================================================================
        @echo:
        @echo Archive completed. File was saved to:
        @echo %UserProfile%\OneDrive\Zomboid_Backups\PZBackup_%fullstamp%.7z
    ) else (
        color 0E
        @echo [WARNING] 7-Zip reported an error ^(exit code: !zip_result!^)
        color 07
    )
    @echo:
) else (
    @echo Archive skipped.
    @echo:
)

:end
@echo:
@echo This window will automatically close in 120 seconds.
@echo Press any key to close immediately...
timeout /t 120
