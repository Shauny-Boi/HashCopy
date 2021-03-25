# HashCopy Powershell script written by Shaun Curtis, 2021
# https://github.com/Shauny-Boi/HashCopy
# Licensed under GNU General Public License v3.0
# For more information on this, and how to apply and follow the GNU GPL, see https://www.gnu.org/licenses/

#	Initialise Windows Forms
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

#	Defines the function that writes various milestones/decisions to a perpetual "SysLog" file
Function SysLogWrite{
	Param ([string]$SysLogString)
	$TDStamp = Get-Date -Format yyyy/MM/dd-HH:mm:ss.fffffff
	$SysLogEntry = $($TDStamp + " - " + $SysLogString)
	Add-content $SysLog -Value $SysLogEntry 
	}

#	Defines the function that writes various milestones/decisions and the actual hash comparison results to a per-job "JobLog" file	
Function JobLogWrite{
	Param ([string]$JobLogString)
	$TDStamp = Get-Date -Format yyyy/MM/dd-HH:mm:ss.fffffff
	$JobLogEntry = $($TDStamp + " - " + $JobLogString)
	Add-Content $JobLog -Value $JobLogEntry
	}

#	Defines the function that resets the GUI to default state	
Function ResetForm{
	$Form.Dispose()
	SysLogWrite "******** Form reset - new session commencing ********"
	MakeForm
	}

#	Defines the function that calls "FolderBrowserDialog" to allow user to select Source and Destination folders via a GUI
Function Get-Folder{
		param(
		[string]$TitleText = '',
		[string]$InitialDirectory = '',
		[string]$LocationType = ''
	)
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")|Out-Null

    $FolderName = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderName.Description = $TitleText
    $FolderName.RootFolder = "MyComputer"
    $FolderName.SelectedPath = $InitialDirectory

#	Logic added depending on whether it's the Source or Destination folder (parameter passed from the relevant button click)
    if($FolderName.ShowDialog() -eq "OK"){
		if($LocationType -eq "Source"){
			$Script:SourceFolder += $FolderName.SelectedPath
			$SourcePath.Visible = $True
			}
		elseif($LocationType -eq "Dest"){
			$Script:DestFolder += $FolderName.SelectedPath
			$DestPath.Visible = $True
			}
		}
	}

#	Defines the function that ensures an empty folder exists and is empty for Robocopy to use to remove any existing contents in the Destination directory
Function Nuke{
	if(Test-Path -LiteralPath $Nuke){
		if((Get-ChildItem $Script:Nuke | Measure-Object).Count -eq 0){
			SysLogWrite $("Utility folder " + $Nuke + " exists and is empty")
			}
		else{
			SysLogWrite $("Utility folder " + $Nuke + " exists but contains data; Terminating script")
			$NukeNotEmpty=[System.Windows.Forms.MessageBox]::Show("Folder $Nuke is required to be empty for this script to function`n`nPlease review the contents and delete/move as appropriate." , "Review contents of specified folder" , 0)
			Explorer $Nuke	# Opens the Nuke folder for the user to view the contents
			[environment]::exit(0)
			}
		}
	else{
		SysLogWrite $("Utility folder " + $Nuke + " does not exist; re-creating")
		New-Item -ItemType Directory -Path $Nuke
		}
	}

#	Defines the function that performs some validation and pre-copy actions
Function Validate{
#	Start with a try/catch Get-ChildItem to ensure the user has access to all files, but should catch other errors.
	try{
		Get-ChildItem $Script:SourceFolder -Recurse -Force -ErrorAction Stop
		}
	catch{
		SysLogWrite "$Error"
		SysLogWrite "Terminating script"
		[System.Windows.Forms.MessageBox]::Show("$Error" , "An error has occurred" , 0)
		[environment]::exit(0)
		}
	if($Script:SourceFolder -eq '' -or $Script:DestFolder -eq ''){	# if one or both paths not provided when user clicks the "Copy" button
		[System.Windows.Forms.MessageBox]::Show("You must select both a Source and Destination folder." , "One or more paths required" , 0)
		}
	elseif($Script:SourceFolder -eq $Script:DestFolder){
		[System.Windows.Forms.MessageBox]::Show("Source and Destination folder cannot be the same." , "Invalid folder selections" , 0)
		}
	elseif((Get-ChildItem $Script:DestFolder -Force | Measure-Object).Count -ne 0) {	# if the Destination folder has anything in it, let the user decide to remove contents
		$DestNotEmpty=[System.Windows.Forms.MessageBox]::Show("The destination folder already contains data.`n`nDo you wish to delete the contents? `n`nThis cannot be undone!" , "Destination conains data" , 4)
		switch ($DestNotEmpty) {
			'Yes'{	# This block is where the first part of the local JobLog is created and logged - a folder and the JobLog file are created using the date/timestamp at this point (to the second)
				Nuke	# Calls the Nuke function
				$Script:JobFolderName = Get-Date -Format yyyyMMdd_HHmmss
				$Script:JobFolder = New-Item -ItemType Directory -Path $($LogRoot + $Script:JobFolderName)
				$Script:JobLog = New-Item -ItemType File -Path $Script:JobFolder\$Script:JobFolderName.txt
				JobLogWrite "******** Commencing Purge of Destination Directory ********"
#	Robocopy is used to remove any contents of the destination folder
				Robocopy $Nuke $Script:DestFolder /MIR /V /LOG+:$Script:JobLog
				if($LastExitCode -ge 8){	# Checks the Robocopy Exit code for a decision to continue - https://docs.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility
					[System.Windows.Forms.MessageBox]::Show("Purge of destination folder failed. `n`n Please investigate and then try again. `n`n Resetting the tool" , "Destination purge failed" , 0)
					SysLogWrite $("Destination folder " + $Script:DestFolder + " already contains data. Content deletion failed. Job aborted and tool reset")
					JobLogWrite "******** Purge of Destination Directory Failed - Job aborted ********"
					ResetForm
					}
				else{
					SysLogWrite $("Destination folder " + $Script:DestFolder + " contained data; contents deleted")
					JobLogWrite "******** Purge of Destination Directory Complete ********"
					SpaceCheck
					}
				}
			'No'{
				SysLogWrite $("Destination folder " + $Script:DestFolder + " already contains data. Copy aborted")
				}
			}
		}
	else{
		SpaceCheck
		}
	}

#	Defines the function that ensures there is enough free space on the destination drive
Function SpaceCheck{
	SysLogWrite "Determining space requirements"
	$SourceTotal = Get-ChildItem $Script:SourceFolder -Recurse -Force | Measure-Object -Sum Length | Select -Expand Sum
	$DestDrive = $Script:DestFolder.SubString(0,1)
	$DestFree = Get-PSDrive $DestDrive | Select -Expand Free
	$SourceTotalMB = [math]::Round($SourceTotal / 1024 / 1024)
	$DestFreeMB = [math]::Round($DestFree / 1024 / 1024)
	if($DestFree -gt $SourceTotal){
		SysLogWrite $("Source total " + $SourceTotalMB + "MB is smaller than Destination free space " + $DestFreeMB + "MB. Proceeding with copy.")
		FinalCheck
		}
	else{
		$SpaceNeeded = $SourceTotalMB - $DestFreeMB
		SysLogWrite $("Source total " + $SourceTotalMB + "MB is larger than Destination free space " + $DestFreeMB + "MB. User to remediate.")
		[System.Windows.Forms.MessageBox]::Show("Insufficient free space in destination directory. `n`n $SpaceNeeded MB required `n`n Please remediate and then try again." , "Insufficient Free Space" , 0)
		}
	}
	
#	Defines the function that gives the user a final chance to back out of the copy. It also copies over the empty directory structure prior to the files being hashed and copied.
Function FinalCheck{
	$LastChanceToAbort=[System.Windows.Forms.MessageBox]::Show("You wish to copy`n`n $Script:SourceFolder`n`nto`n`n$Script:DestFolder" , "Ready To Copy" , 4)
	switch ($LastChanceToAbort) {	# If we get to this point, all criteria have been satisfied and we can now copy as intended
		'Yes'{
			if(! $JobFolderName){	# If the Destination was new or empty, then the Job folder and Log aren't created until this point.
				$Script:JobFolderName = Get-Date -Format yyyyMMdd_HHmmss
				$Script:JobFolder = New-Item -ItemType Directory -Path $($LogRoot + $Script:JobFolderName)
				$Script:JobLog = New-Item -ItemType File -Path $Script:JobFolder\$Script:JobFolderName.txt
				}
			SysLogWrite $("Copy from " + $Script:SourceFolder + " to " + $Script:DestFolder + " authorised - beginning copy")
			SysLogWrite "Copying over empty folder structure"
			JobLogWrite "******** Copying over empty folder structure ********"
#	The copy starts with copying across the empty Directory structure. The below copying code only processes files, and therefore only creates the structure for where those files reside.			
			if($Script:SourceFolder.Length -eq 3){
				$SVI = $Script:SourceFolder + "System Volume Information"
				robocopy $Script:SourceFolder $Script:DestFolder /E /XF *.* /XD $SVI /DCOPY:DAT /LOG+:$Script:JobLog
				}
			else{
				robocopy $Script:SourceFolder $Script:DestFolder /E /XF *.* /DCOPY:DAT /LOG+:$Script:JobLog
				}
			if($LastExitCode -ge 8){	# Checks the Robocopy Exit code for a decision to continue - https://docs.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility
				[System.Windows.Forms.MessageBox]::Show("Copying over empty folder structure failed. `n`n Please investigate and then try again. `n`n Resetting the tool" , "Empty folder structure copy failed" , 0)
				SysLogWrite "Empty folder structure copy failed. Job aborted and tool reset"
				JobLogWrite "******** Empty folder structure copy failed - Job aborted ********"
				ResetForm
				}
			else{
				SysLogWrite "Empty folder structure copy completed successfully"
				JobLogWrite "******** Empty folder structure copy completed successfully ********"
				ExecuteCopy
				}
			}
		'No'{
			SysLogWrite $("Copy from " + $Script:SourceFolder + " to " + $Script:DestFolder + " aborted")
			}
		}
	}

#	Defines the function that loads the ProgressBar showing the progress as the script runs
Function ExecuteCopy{
	$WaitForm = New-Object System.Windows.Forms.Form
	$WaitForm.Size= New-Object System.Drawing.Size(1500,250)
	$WaitForm.StartPosition = "CenterScreen"
	$WaitForm.Text = "Copying, Please Wait...."
	$WaitForm.Visible = $False
	$WaitForm.Enabled = $True
	$WaitForm.AutoSize = $True
	$WaitForm.Controlbox = $False
	$WaitForm.AutoSizeMode = "GrowAndShrink"
	$WaitForm.Add_Shown({$WaitForm.Activate()})

	[reflection.assembly]::LoadWithPartialName("System.Windows.Forms")
	$File = (Get-Item 'C:\Users\Shaun\Desktop\Copy.gif')	# The script should function without the gif being present
	$Img = [System.Drawing.Image]::Fromfile($File);

	[System.Windows.Forms.Application]::EnableVisualStyles()

	$PictureBox = New-Object Windows.Forms.PictureBox
	$PictureBox.SizeMode = "AutoSize"
	$PictureBox.Image = $Img
	$WaitForm.Controls.Add($PictureBox)
#	$WaitForm.Topmost = $True

    $ProgressLabel = New-Object System.Windows.Forms.Label
    $ProgressLabel.Text = ""
    $ProgressLabel.AutoSize = $True
    $ProgressLabel.Width = 1490
    $ProgressLabel.Height = 10
    $ProgressLabel.Location = New-Object System.Drawing.Point(5,165)
    $ProgressLabel.Font = [System.Drawing.Font]::new("Arial Black", 8, [System.Drawing.FontStyle]::Regular)
	$ProgressLabel.Visible = $True
    $WaitForm.Controls.Add($ProgressLabel)

	$ProgressBar = New-Object System.Windows.Forms.ProgressBar
	$ProgressBar.Value = 0
	$ProgressBar.Style="Continuous"
	$ProgressBar.Location = New-Object System.Drawing.Point(5,190)
	$ProgressBar.Size = New-Object System.Drawing.Size(1490,20)
	$WaitForm.Controls.Add($ProgressBar)

#	The next block displays the progress bar and animated gif. A separate Runspace is required to do this at the same time.
	$RS = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
	$RS.Open()
	$RS.SessionStateProxy.SetVariable("WaitForm", $WaitForm)
	$Data = [hashtable]::Synchronized(@{text=""})
	$RS.SessionStateProxy.SetVariable("data", $Data)
	$P = $RS.CreatePipeline({ [void] $WaitForm.ShowDialog()})
	$P.Input.Close()
	$P.InvokeAsync()
	
	$SourceFiles = Get-ChildItem $Script:SourceFolder -Recurse -File -Force | Where-Object FullName -notmatch '[A-Z]:\\System Volume Information.*'
	$SourceFileTotal = $SourceFiles.Count
	$Increment = 0
	
	SysLogWrite "Starting Copy"
	JobLogWrite "******** Starting copy ********"
	
	$SourceFiles | foreach{
		$SourceHash = ''
		$DestHash = ''
		$Increment++
		[int]$PCT= ($Increment/$SourceFileTotal)*100
		$ProgressBar.Value = $PCT
		$ProgressLabel.Text="Current File: $($_.FullName)"
		$WaitForm.Refresh()
		try{
			$SourceHash = Get-Filehash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop | Select -Expand hash
			}
		catch{
			JobLogWrite "$Error"
			SysLogWrite "Terminating script"
			SysLogWrite "$Error"
			SysLogWrite "Terminating script"
			[System.Windows.Forms.MessageBox]::Show("$Error" , "An error has occurred" , 0)
			[environment]::exit(0)
			}
		if($Script:SourceFolder.Length -eq 3){
			$TargetFile = $Script:DestFolder + $_.FullName.SubString(2)
			}
		else{$TargetFile = $Script:DestFolder + $_.FullName.SubString($Script:SourceFolder.Length)
			}
		New-Item -ItemType File -Path $TargetFile -Force
		Copy-Item -LiteralPath $_.FullName -Destination $TargetFile
		$DestHash = Get-Filehash -LiteralPath $TargetFile -Algorithm SHA256 | Select -Expand hash
		if ($SourceHash -eq $DestHash -and $SourceHash -ne '' -and $DestHash -ne ''){
			JobLogwrite $("SUCCESS - Source file " + $_.FullName +" SHA1 hash "+ $SourceHash + " matches destination file " + $TargetFile +" SHA1 hash "+ $DestHash)
			}
		elseif($SourceHash -eq '' -and $DestHash -eq ''){
			JobLogwrite $("FAILURE - Source file " + $_.FullName +" SHA1 hash "+ $SourceHash + " and destination file " + $TargetFile +" SHA1 hash "+ $DestHash + "are empty - file likely did not copy properly either")
			$Script:Mismatch++
			}
		else{
			JobLogwrite $("FAILURE - Source file " + $_.FullName +" SHA1 hash "+ $SourceHash + " does not match destination file " + $TargetFile +" SHA1 hash "+ $DestHash)
			$Script:Mismatch++
			}
		}
#	Count files and folders in the source and destination paths to ensure all files were copied
	$DestFileTotal = (Get-ChildItem $Script:DestFolder -Recurse -Force -File | Where-Object FullName -notmatch '[A-Z]:\\System Volume Information.*').Count
	$SourceFolderTotal = (Get-ChildItem $Script:SourceFolder -Recurse -Force -Directory | Where-Object FullName -notmatch '[A-Z]:\\System Volume Information.*').Count
	$DestFolderTotal = (Get-ChildItem $Script:DestFolder -Recurse -Force -Directory | Where-Object FullName -notmatch '[A-Z]:\\System Volume Information.*').Count
	
	if($SourceFileTotal -eq $DestFileTotal -and $SourceFolderTotal -eq $DestFolderTotal){
		if($Script:Mismatch -eq 0){
			SysLogWrite $("All files and folders copied and verified successfully. Source files total: " + $SourceFileTotal + ". Destination files total: " + $DestFileTotal + ". Source folders total: " + $SourceFolderTotal + ". Destination folders total: " + $DestFolderTotal + ". Errors: " + $Script:Mismatch +".")
			JobLogWrite "****** All files and folders copied and verified successfully ******"
			JobLogWrite $("Source files total: " + $SourceFileTotal + ". Destination files total: " + $DestFileTotal + ". Source folders total: " + $SourceFolderTotal + ". Destination folders total: " + $DestFolderTotal + ". Errors: " + $Script:Mismatch +".")
			$ResultsLabel.Text = "All files and folders copied and verified successfully"
			}
		else{
			SysLogWrite $("All files and folders copied, however there are " + $Script:Mismatch + " errors to review in the JobLog")
			JobLogWrite $("All files and folders copied, however there are " + $Script:Mismatch + " errors to review")
			JobLogWrite $("Source files total: " + $SourceFileTotal + ". Destination files total: " + $DestFileTotal + ". Source folders total: " + $SourceFolderTotal + ". Destination folders total: " + $DestFolderTotal + ". Errors: " + $Script:Mismatch +".")
			$ResultsLabel.Text = "There are " + $Script:Mismatch + " errors to review in the JobLog"
			}
		}
	else{
		SysLogWrite $("Not all files and folders were copied and verified successfully. Review the JobLog for details " + $JobLog)
		JobLogWrite "****** Not all files and folders were copied and verified successfully ******"
		JobLogWrite $("Source files total: " + $SourceFileTotal + ". Destination files total: " + $DestFileTotal + ". Source folders total: " + $SourceFolderTotal + ". Destination folders total: " + $DestFolderTotal + ". Errors: " + $Script:Mismatch +".")
		$ResultsLabel.Text = "Not all files and folders were copied and verified successfully. Review the JobLog for details"
		}
	
#	Replaces the "Copy" Button with the "JobLog" Button - this also forces the user to reset the form to perform another copy, ensuring all the variables get reset properly.
	$CopyButton.Visible = $False
	$JobLogButton.Visible = $True
	
	$WaitForm.close()
	$RS.close()
	$Form.Refresh()
	}

#	Defines the function that creates the base form for the user to input the source and destination.
Function Makeform{
	$Script:Mismatch = 0
	$Script:SourceFolder = ''
	$Script:DestFolder = ''
	$Script:JobFolderName = ''
	$Script:JobFolder = ''
	$Script:JobLog = ''

    $Form = New-Object System.Windows.Forms.Form
    $Form.ClientSize = New-Object System.Drawing.Size(1500,200)
    $Form.Text = "File Copy with SHA1 hash verification"
    $Form.AcceptButton = $CopyButton
    $Form.StartPosition = "CenterScreen"
    $Form.KeyPreview = $True
    $Form.Add_Closing({SysLogWrite "User quit program"})
    $Form.Add_KeyDown({if ($_.KeyCode -eq "Enter")         # If Enter key pressed
        {
        $CopyButton.PerformClick()	# Perform click of the "CopyButton"
        }
    })
    $Form.Add_KeyDown({if ($_.KeyCode -eq "Escape")	# If Escape key pressed
        {
        $Form.Close()	# Exit
        }
    })

    $FolderLabel = New-Object System.Windows.Forms.Label
    $FolderLabel.Text = "Select source and destination folders"
    $FolderLabel.AutoSize = $True
	$FolderLabel.Size = New-Object System.Drawing.Size(25,10)
    $FolderLabel.Location = New-Object System.Drawing.Point(5,5)
    $FolderLabel.Font = [System.Drawing.Font]::new("Arial Black", 12, [System.Drawing.FontStyle]::Regular)
	$FolderLabel.Visible = $True
    $Form.Controls.Add($FolderLabel)

    $SourcePath = New-Object System.Windows.Forms.Label
    $SourcePath.Text = $Script:SourceFolder
	$SourcePath.Size = New-Object System.Drawing.Size(1250,30)
    $SourcePath.Location = New-Object System.Drawing.Point(270,40)
    $SourcePath.Font = [System.Drawing.Font]::new("Arial", 12, [System.Drawing.FontStyle]::Regular)
    $SourcePath.Visible = $False
    $Form.Controls.Add($SourcePath)
	
	$SourceLabel = New-Object System.Windows.Forms.Label
	$SourceLabel.Location = New-Object System.Drawing.Point(5,40)
	$SourceLabel.Size = New-Object System.Drawing.Size(145,30)
	$SourceLabel.Visible = $True
	$SourceLabel.Text = "Source Folder"
	$SourceLabel.Font = [System.Drawing.Font]::new("Arial", 12, [System.Drawing.FontStyle]::Regular)
	$Form.Controls.Add($SourceLabel)

    $SourceButton = New-Object System.Windows.Forms.Button
    $SourceButton.Location = New-Object System.Drawing.Point(150,35)
    $SourceButton.Size = New-Object System.Drawing.Size(110,30)
    $SourceButton.Parent = $Form
    $SourceButton.Text = "Select"
    $SourceButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
    $SourceButton.Visible = $True
    $SourceButton.Add_Click({
		$Script:SourceFolder = ''	# Clears the variable out in case the user made an incorrect selection previously
	    Get-Folder -TitleText "Select Source Folder" -LocationType "Source"
		$SourcePath.Text = $Script:SourceFolder	# This is where the result of the Get-Folder function is returned
	    })
    $Form.Controls.Add($SourceButton)

    $DestPath = New-Object System.Windows.Forms.Label
    $DestPath.Text = $Script:DestFolder
	$DestPath.Size = New-Object System.Drawing.Size(1250,30)
    $DestPath.Location = New-Object System.Drawing.Point(270,80)
    $DestPath.Font = [System.Drawing.Font]::new("Arial", 12, [System.Drawing.FontStyle]::Regular)
    $DestPath.Visible = $False
    $Form.Controls.Add($DestPath)
	
	$DestLabel = New-Object System.Windows.Forms.Label
	$DestLabel.Location = New-Object System.Drawing.Point(5,80)
	$DestLabel.Size = New-Object System.Drawing.Size(145,30)
	$DestLabel.Visible = $True
	$DestLabel.Text = "Destination Folder"
	$DestLabel.Font = [System.Drawing.Font]::new("Arial", 12, [System.Drawing.FontStyle]::Regular)
	$Form.Controls.Add($DestLabel)

    $DestButton = New-Object System.Windows.Forms.Button
    $DestButton.Location = New-Object System.Drawing.Point(150,75)
    $DestButton.Size = New-Object System.Drawing.Size(110,30)
    $DestButton.Parent = $Form
    $DestButton.Text = "Select"
    $DestButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
    $DestButton.Visible = $True
    $DestButton.Add_Click({
		$Script:DestFolder = ''	# Clears the variable out in case the user made an incorrect selection previously
	    Get-Folder -TitleText "Select Destination Folder" -LocationType "Dest"
		$DestPath.Text = $Script:DestFolder	# This is where the result of the Get-Folder function is returned
	    })
    $Form.Controls.Add($DestButton)	

	$SysLogButton = New-Object System.Windows.Forms.Button
    $SysLogButton.Location = New-Object System.Drawing.Point(860,140)
    $SysLogButton.Size = New-Object System.Drawing.Size(150,50)
    $SysLogButton.Parent = $Form
    $SysLogButton.Anchor = "Bottom,Right"
    $SysLogButton.Text = "Open SysLog"
	$SysLogButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
	$SysLogButton.Backcolor = [System.Drawing.Color]::OldLace
    $SysLogButton.Visible = $True
    $SysLogButton.Add_Click({
	    Notepad $SysLog
	    })
    $Form.Controls.Add($SysLogButton)

	$ResetButton = New-Object System.Windows.Forms.Button
    $ResetButton.Location = New-Object System.Drawing.Point(1020,140)
    $ResetButton.Size = New-Object System.Drawing.Size(150,50)
    $ResetButton.Parent = $Form
    $ResetButton.Anchor = "Bottom,Right"
    $ResetButton.Text = "Reset"
	$ResetButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
	$ResetButton.Backcolor = [System.Drawing.Color]::MediumOrchid
    $ResetButton.Visible = $True
    $ResetButton.Add_Click({
	    ResetForm
	    })
    $Form.Controls.Add($ResetButton)

    $CopyButton = New-Object System.Windows.Forms.Button
    $CopyButton.Location = New-Object System.Drawing.Point(1180,140)
    $CopyButton.Size = New-Object System.Drawing.Size(150,50)
    $CopyButton.Parent = $Form
    $CopyButton.Anchor = "Bottom,Right"
    $CopyButton.Text = "Copy"
	$CopyButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
    $CopyButton.Visible = $True
	$CopyButton.Backcolor = [System.Drawing.Color]::LightGreen
    $CopyButton.Add_Click({
	    Validate
	    })
    $Form.Controls.Add($CopyButton)
	
	$JobLogButton = New-Object System.Windows.Forms.Button
    $JobLogButton.Location = New-Object System.Drawing.Point(1180,140)
    $JobLogButton.Size = New-Object System.Drawing.Size(150,50)
    $JobLogButton.Parent = $Form
    $JobLogButton.Anchor = "Bottom,Right"
    $JobLogButton.Text = "Open JobLog"
	$JobLogButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
	$JobLogButton.Backcolor = [System.Drawing.Color]::LightSteelBlue
    $JobLogButton.Visible = $False
    $JobLogButton.Add_Click({
	    Notepad $JobLog
	    })
    $Form.Controls.Add($JobLogButton)
	
    $ExitButton = New-Object System.Windows.Forms.Button
    $ExitButton.Location = New-Object System.Drawing.Point(1340,140)
    $ExitButton.Size = New-Object System.Drawing.Size(150,50)
    $ExitButton.Parent = $Form
    $ExitButton.Anchor = "Bottom,Right"
    $ExitButton.Text = "Exit"
	$ExitButton.Font = [System.Drawing.Font]::new("Arial Black", 10, [System.Drawing.FontStyle]::Regular)
	$ExitButton.Backcolor = [System.Drawing.Color]::IndianRed
    $ExitButton.Visible = $True
    $ExitButton.Add_Click({
        $Form.Close()
	    })
    $Form.Controls.Add($ExitButton)

    $ResultsLabel = New-Object System.Windows.Forms.Label
    $ResultsLabel.Text = ''
    $ResultsLabel.Parent = $Form
    $ResultsLabel.Anchor = "Left,Bottom"
    $ResultsLabel.Size = New-Object System.Drawing.Size(1040,30)
    $ResultsLabel.Location = New-Object System.Drawing.Point(5,140)
    $ResultsLabel.Font = [System.Drawing.Font]::new("Arial Black", 12, [System.Drawing.FontStyle]::Regular)
    $ResultsLabel.Visible = $True
    $Form.Controls.Add($ResultsLabel)

    [void]$Form.Showdialog()
    }

# 	This is where the script actually "Starts"; the above code is all functions.
# 	This will need to be updated once the NAS is online.
$SourceFolder = ''
$DestFolder = ''
$Mismatch = 0
$DestRoot = "C:\Temp"
$LogRoot = $DestRoot + "\SHA1CopyReports\"
$SysLog = $LogRoot + "SysLog.txt"
$Nuke = "C:\Temp\Nuke"
$JobFolderName = ''
$JobFolder = ''
$JobLog = ''
if(Test-Path -LiteralPath $SysLog){
	SysLogWrite "******** Starting a new session ********"
	Makeform
	}
else{
	$MissingSysLogFile=[System.Windows.Forms.MessageBox]::Show("Unable to find $SysLog`n`nDo you wish to create it now?" , "Unable To Find SysLog file" , 4)
	switch ($MissingSysLogFile) {
		'Yes'{
			New-Item -ItemType File -Path $SysLog -Force
			SysLogWrite "******** Starting a new session ********"
			SysLogWrite $("SysLog file: " + $SysLog + " was missing. User elected to re-create")
			Makeform
			}
		'No'{
			[System.Windows.Forms.MessageBox]::Show("Cannot function without SysLog file - Exiting program." , "Unable To Find SysLog file" , 0)
			Exit
			}
		}
	}