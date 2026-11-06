# SPDX-License-Identifier: MIT
# Group boundaries are fresh Lua environments in the shared serial runner.
@{
    Name = 'behaviour.runtime-contracts'
    Files = @(
        (Join-Path $Core 'core_fixture.lua'),
        (Join-Path $Shared 'SCNamespace.lua'),
        (Join-Path $Shared 'SCCall.lua'),
        (Join-Path $Shared 'SCStableValue.lua'),
        (Join-Path $Shared 'SCConfig.lua'),
        (Join-Path $Shared 'SCDiagnostics.lua'),
        (Join-Path $Client 'SCScheduler.lua'),
        (Join-Path $Core 'core_harness.lua')
    )
}
@{ Name = 'behaviour.follow-and-access'; Files = @(Get-ScGameplayFiles) + (Join-Path $Gameplay 'gameplay_harness.lua') }
@{ Name = 'behaviour.combat-ownership'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCPZOptimizerAdapter.lua'),
    (Join-Path $Essential 'combat_harness.lua')) }
@{ Name = 'behaviour.needs-and-sleep'; Files = @(Get-ScGameplayFiles) + (Join-Path $Essential 'needs_harness.lua') }
