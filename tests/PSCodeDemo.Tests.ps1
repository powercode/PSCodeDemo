

BeforeAll {
    Import-Module -Force -Name:$PSScriptRoot\..\src\PSCodeDemo.psd1
}

Describe 'GitLog' {
    It 'CanGetLogEntries' {
        InModuleScope -ModuleName:PSCodeDemo {
            $entries = [GitLogEntry]::GetLogEntries("$psscriptroot\DemoRepo")
            $entries | Should -Not -BeNullOrEmpty
            $entries.Count | Should -be 6
            $entries[0].Title | Should -BeExactly 'Delegate DebuggerDisplay to DebuggerDisplay property'
        }
    }
}


Describe 'CodeDemo' {
    BeforeEach{
        Mkdir TestDrive:\DemoRepo | Out-Null
    }
    It 'Starts-Demo' {
        InModuleScope -ModuleName:PSCodeDemo {
            mock -CommandName:git -ParameterFilter {$args[2] -eq 'log'} -MockWith:{
                Get-Content -LiteralPath:"$psscriptroot\gitlog.txt"
            } -Verifiable
            mock -CommandName:git -ParameterFilter {$args[2] -eq 'tag'} -MockWith:{
                Get-Content -LiteralPath:"$psscriptroot\gittag.txt"
            } -Verifiable
            mock -CommandName:git -ParameterFilter {$args[3] -eq 'switch'} -MockWith {

            } -Verifiable
            mock -CommandName:git -ParameterFilter {$args[3] -eq 'checkout'} -MockWith {

            } -Verifiable
            mock -CommandName:git -MockWith {
                throw ('git command not mocked: {0}' -f $args)
            }
            Start-CodeDemo -RepositoryPath "$psscriptroot\DemoRepo" -WorkTree:TestDrive:\DemoRepo
            $demoLog = $script:DemoState.DemoCommits
            $demoLog.Count | Should -be 4
            $demoState.GetCurrentCommit() | Should -BeExactly '52273a3a57f53b3e05b47b1bf82fb9fd6ee9ca97'
            
            Should -Invoke -CommandName:git -ParameterFilter {$args[3] -eq 'switch'} -Times:1
            Should -Invoke -CommandName:git -ParameterFilter {$args[3] -eq 'checkout' -and ($args[5] -eq '52273a3a57f53b3e05b47b1bf82fb9fd6ee9ca97')} -Times:1
        }
    }
}