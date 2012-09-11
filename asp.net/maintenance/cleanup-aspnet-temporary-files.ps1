# array of servers we want to run this command against. You can add the servers to the list here, or read them from a file, etc
$servers = @("server-01","server-02");

$machineStatusLookup = New-Object 'System.Collections.Generic.SortedDictionary[string,object]';

# run the command against all configured servers
invoke-command -cn $servers {

    function Write-Output-Message($message) {
        $output = New-Object PSObject -Property @{
            Message = $message
        };

        Write-Output $output;
    }
    
    # List of all versions of .net that have Temporary ASP.NET Files folders
    $versions = @("v2.0.50727","v4.0.30319");
    $frameworks = @("Framework","Framework64");

    # dictionary of path (key) and a boolean value of whether file exists or not to speed up processing
    # keep this global since a path will exist / not exist regardless of where we are looking at it from
    $lookup = New-Object 'System.Collections.Generic.Dictionary[string,bool]';

    # grab reference to matchine name and unicode encoding to make life easier
    $machine = $env:COMPUTERNAME;
    $unicode = [System.Text.Encoding]::Unicode;

    #regex for matching file in the __AssemblyInfo.ini__ file
    $rgx = [regex]'(?i)file:///[\w\d\._\-/\:]+';

    # counter variable to track how many deletions we have done.
    $folder_deletions = 0;

    # iterate every version specified
    $versions | %{ 
        $version = $_;

        # iterate every framework-bitness for the version
        $frameworks | %{
            $framework = $_;
            $aspnet_temp = "C:\Windows\Microsoft.NET\$framework\$version\Temporary ASP.NET Files";

            # progress variables
            $scan_position = 0;

            # recursively search for __AssemblyInfo__.ini files which contain information about cached dll
            ls $aspnet_temp -r -filter __AssemblyInfo__.ini | %{
                # capture some local values to make life easier
                $ini = $_.FullName;
                $dir = $_.DirectoryName;

                # parse source file path from __AssemblyInfo__.ini file
                $file = [string]$null;
                $contents = [System.IO.File]::ReadAllText($ini, $unicode);
                $match = $rgx.Match($contents);
                if ($match.Success -eq $true) {
                    # get the local path value from the file uri
                    $file = (new-object System.Uri($match.Value)).LocalPath.ToLower();
                }

                # if we successfully processed the info file, then process the target file
                if ($file -ne $null) {
                    # try to see if we've already checked the existance of the file
                    $file_exists = $true;
                    if ($lookup.TryGetValue($file, [ref]$file_exists) -eq $false) {
                        # check to see if the file exists
                        $file_exists = [System.IO.File]::Exists($file);

                        #add the result to the lookup table
                        $lookup.Add($file, $file_exists);
                    }

                    #if file doesn't exist, kill the current directory
                    if ($file_exists -eq $false) {
                        Remove-Item -Path $dir -Recurse -ErrorAction Continue;
                        $folder_deletions += 1;
                    }
                }

                # increment our position counter
                $scan_position += 1;

                # write some info messages every 1000 files or so
                if (($scan_position % 1000) -eq 0) {
                    $msg = "[$framework\$version] Scanned: $scan_position. Deleted: $folder_deletions.";
                    Write-Output-Message $msg;
                }
            }
        }
    }

    Write-Output-Message "Done.";
} | %{
    $source = $_.PSComputerName;
    $message = $_.Message;

    $status = $null;
    if ($machineStatusLookup.TryGetValue($source, [ref]$status) -ne $true) {
        $status = New-Object PSObject -Property @{ Server=$source; Status=$message; };

        $machineStatusLookup.Add($source, $status);
    }

    $status.Server = $source;
    $status.Status = $message;

    # clear output and re-draw
    Clear-Host;
    $machineStatusLookup | select -ExpandProperty Values | Format-Table -Property Status, Server;
};

write-output "Done";