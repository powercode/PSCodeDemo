
function git {
    Write-Verbose "git $args"
    git.exe $args
    if ($LASTEXITCODE){
        throw "git $args failed with exit code $LASTEXITCODE"
    }
}


class GitLogEntry {
    [string] $Commit
    [string] $Title
    [string] $Author
    [string] $AuthorEmail
    [string] $Date
    [string] $FullMessage

    [string] ToString(){
        return "$($this.Commit.Substring(0, 7)) - `"$($this.Title)`""
    }

    static [GitLogEntry[]] GetLogEntries([string] $Path){
        $entries = @(
            foreach ($line in git -C $path log --format='%H%x00%s%x00%f%x00%an%x00%ae%x00%aI'){
                $local:commit, $local:title, $local:fullMessage, $local:author, $local:authorEmail, $local:date = $line -split '\x00'
                [GitLogEntry] @{
                    Title = $title
                    Commit = $commit
                    Author = $author
                    AuthorEmail = $authorEmail
                    Date = $date
                    FullMessage = $fullMessage
                }
            }
        )
        return $entries
    }

    static [int] IndexOf([GitLogEntry[]] $Entries, [string] $Commit){
        for($i = 0; $i -lt $Entries.Count; $i++){
            if ($Entries[$i].Commit -eq $Commit){
                return $i
            }
        }
        return -1
    }
}

class GitTagEntry{
    [string] $Commit
    [string] $Name

    static [GitTagEntry[]] GetTagEntries([string] $Path){
        $entries = @(
            foreach ($line in git -C $path tag --format='%(objectname)%00%(refname:lstrip=2)'){
                $local:commit, $local:name = $line -split '\0'
                [GitTagEntry] @{
                    Commit = $commit
                    Name = $name
                }
            }
        )
        return $entries
    }
}

class PSCodeDemo {
    [string] $RepositoryPath
    [string] $WorkTree
    [GitLogEntry[]] $DemoCommits
    [int] $CurrentCommitIndex
    [string] $OriginalBranch

    [void] CreateDemoBranch() {
        git -C $this.RepositoryPath switch -C demo
    }

    [GitLogEntry] GetCurrentCommit(){
        return $this.DemoCommits[$this.CurrentCommitIndex]
    }

    [void] SwitchToDemoBranch() {
        git -C $this.RepositoryPath --work-tree=$($this.WorkTree) switch -C demo
    }

    [GitLogEntry] CheckoutCurrentCommit(){
        $currentObject = $this.GetCurrentCommit()
        $output = git --work-tree=$($this.WorkTree) -C $this.RepositoryPath checkout -f $currentObject.Commit
        return $currentObject
    }

    [GitLogEntry] Next() {
        if ($this.CurrentCommitIndex -lt ($this.DemoCommits.Count - 1)){
            $this.CurrentCommitIndex++
             $this.CheckoutCurrentCommit()
        }
        return $this.GetCurrentCommit()
    }

    [GitLogEntry] Previous(){
        if ($this.CurrentCommitIndex -gt 0){
            $this.CurrentCommitIndex--
            $this.CheckoutCurrentCommit()
        }

        return $this.GetCurrentCommit()
    }

    [string] ToString() {
        $current = $this.GetCurrentCommit()
        return "Demo on $($current.ToString())"
    }
}

[PSCodeDemo] $script:DemoState

function New-DemoState{
    param(
        [string] $RepositoryPath,
        [string] $WorkTree,
        [string] $FromCommit,
        [string] $ToCommit
    )

    $tags = [GitTagEntry]::GetTagEntries($RepositoryPath)
    $log = [GitLogEntry]::GetLogEntries($RepositoryPath)
    $currentBranch = git rev-parse --abbrev-ref HEAD
    if ($log.Count -lt 2){
        Write-Error "The repository must have at least two commits to start a demo."
        return
    }
    if (!$FromCommit){
        $fromTag = $tags | Where-Object {$_.Name -eq 'demo-start'}
        $FromCommit = ${fromTag}?.Commit ?? $log[-1].Commit
    }
    if (!$ToCommit){
        $toTag = $tags | Where-Object {$_.Name -eq 'demo-end'}
        $ToCommit = ${toTag}?.Commit ?? $log[0].Commit
    }

    $fromIndex = [GitLogEntry]::IndexOf($log, $FromCommit)
    $toIndex = [GitLogEntry]::IndexOf($log, $ToCommit)

    $demoLog = $log[$fromIndex..$toIndex]

    $local:demoState = [PSCodeDemo] @{
        RepositoryPath = $RepositoryPath
        WorkTree = $WorkTree
        DemoCommits = $demoLog
        CurrentCommitIndex = 0
        OriginalBranch = $currentBranch
    }

    $demoState
}


<#
.SYNOPSIS
    Start a code demo in a git repository
.DESCRIPTION
    Starts a demo in a git repository by remembering the current state of the repository and checking out the specified commit.
.PARAMETER Path
    The path to the git repository to start the demo in.
.PARAMETER FromCommit
    An optional commit to start the demo from. If not specified, the first commit in the history will be used, unless a tag 'demo-start' exists, in which case the commit the tag points to will be used.
.PARAMETER ToCommit
    An optional commit to end the demo at. If not specified, the current commit will be used, unless a tag 'demo-end' exists, in which case the commit the tag points to will be used.
.PARAMETER Force
    If a demo is already in progress, this switch will force a reset of the demo state and start a new demo.
#>
function Start-CodeDemo {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $RepositoryPath,
        [string] $WorkTree = $PWD,
        [string] $FromCommit,
        [string] $ToCommit,
        [switch] $Force
    )

    $workTree = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($WorkTree)
    $RepositoryPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepositoryPath)
    if (-not (Test-Path -PathType:Container -LiteralPath:$workTree)){
        Write-Error "The specified work tree path '$workTree' does not exist."
        return
    }
    if ($null -ne $script:DemoState) {
        if ($Force) {
            Write-Warning "A demo is already in progress. Forcing a new demo will reset the demo state."
            $script:DemoState = $null
        }
        else {
            Write-Error "A demo is already in progress. Use -Force to reset the demo state."
            return
        }
    }

    $demoState = New-DemoState -RepositoryPath:$RepositoryPath -WorkTree:$WorkTree -FromCommit:$FromCommit -ToCommit:$ToCommit
    $demoState.SwitchToDemoBranch()
    $demoState.CheckoutCurrentCommit()
    $script:DemoState = $demoState
}

function Update-CodeDemo {
    param(
        [switch] $PreviousCommit
    )

    $local:state = $script:DemoState

    if ($PreviousCommit){
        $state.Previous()
    }
    else {
        $state.Next()
    }
}

function Stop-CodeDemo {
    $state = $script:DemoState
    git -C $state.RepositoryPath switch -f $state.OriginalBranch
}